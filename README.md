# Company Treasury

[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-blue)](https://soliditylang.org)
[![Foundry](https://img.shields.io/badge/Foundry-latest-orange)](https://book.getfoundry.sh)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-17%2F17%20passed-brightgreen)]()

生产级链上金库系统，支持以公司/团队名义管理公共资金。基于 Solidity + Foundry，采用模块化 Hub-and-Spoke 架构，实现多签审批、时间锁、流支付、DeFi 收益管理和预算分配。

---

## 目录

- [核心功能](#核心功能)
- [架构设计](#架构设计)
- [快速开始](#快速开始)
- [合约接口](#合约接口)
- [角色与权限](#角色与权限)
- [安全设计](#安全设计)
- [测试](#测试)
- [部署](#部署)
- [运维指南](#运维指南)
- [许可证](#许可证)

---

## 核心功能

| 功能 | 描述 |
|------|------|
| **多签审批** | N/M 灵活阈值，支持 EIP-712 链下签名（gasless），Bitmap 审批记录 |
| **时间锁** | 可配置延迟执行，棘轮机制防缩短，交易自动从 Queued→Ready 转换 |
| **流支付** | Sablier 式线性释放，支持 Cliff 期，收款方主动提现（Pull over Push） |
| **收益管理** | ERC-4626 标准金库集成，Aave/Lido/Compound/Yearn 适配，策略白名单+分配上限 |
| **预算管理** | 部门/项目预算分配，冻结余额防双花，支出历史全追溯 |
| **紧急控制** | 三级应急：Pause（暂停）→ Shutdown（取消待处理）→ Recovery（48h 延迟提取） |

## 架构设计

### 总体架构：Hub-and-Spoke + UUPS 代理

```
┌──────────────────┐
│   ProxyAdmin     │
└────────┬─────────┘
         │
    ┌────┴─────┬─────────────┐
    │          │             │
┌───v──────┐ ┌─v──────────┐ ┌v──────────────┐
│Treasury  │ │YieldManager│ │StreamingManager│
│Core      │ │(UUPS Proxy)│ │(UUPS Proxy)    │
│(UUPS)    │ │            │ │                │
│          │ │策略注册    │ │流支付创建/取消  │
│持有全部   │ │存取/收割   │ │线性释放计算    │
│资产      │ │风控上限    │ │批量操作        │
│多签+时间锁│ │ERC-4626   │ │                │
│预算管理   │ │            │ │                │
│紧急控制   │ │            │ │                │
└──────────┘ └────────────┘ └────────────────┘
     │              │               │
     └──────────────┴───────────────┘
              所有资产通过 TreasuryCore 统一保管
              外围模块通过 moduleRegistry 授权调用
```

**为什么不用 Diamond（EIP-2535）**：delegatecall 风险高，storage 管理复杂。独立 UUPS 代理 + 中心金库更安全，每个模块独立升级不影响核心资产安全。

### 工作流

```
多签+时间锁:
  PROPOSE → APPROVE(N次) → 达阈值 → QUEUE(时间锁) → READY → EXECUTE
                            ↘ (无延迟) → READY → EXECUTE

流支付:
  CREATE → (Cliff) → WITHDRAW(收款方) → 流结束
                  ↘ CANCEL(退还剩余)

收益管理:
  REGISTER → DEPOSIT → (收益累计) → HARVEST → WITHDRAW
                               ↘ REBALANCE(调仓)

预算管理:
  CREATE → ACTIVATE → SPEND(多签) → CLOSE(退回剩余)
                   ↘ MODIFY
```

### 代码结构

```
contracts/
├── interfaces/          # ITreasuryEvents, ITreasuryErrors
├── libraries/           # TreasuryConstants（角色/常量）
├── treasury/            # TreasuryCore + 5个模块
│   └── modules/         # Access, MultiSig, Timelock, Budget, Emergency
├── yield/               # YieldManager（ERC-4626 策略管理）
├── streaming/           # StreamingManager（流支付）
└── factory/             # TreasuryFactory（一键部署）

test/
├── TreasuryCore.t.sol   # 17 个单元测试，全部通过
└── mocks/               # MockERC20, MockERC4626

scripts/
└── Deploy.s.sol         # 部署脚本
```

## 快速开始

### 环境要求

- [Foundry](https://book.getfoundry.sh/getting-started/installation) >= 1.0
- Git

### 安装

```bash
git clone https://github.com/1952154539/Company-Treasury.git
cd Company-Treasury
forge install
```

### 编译

```bash
forge build
```

### 测试

```bash
forge test -vvv
```

### Gas 报告

```bash
forge test --gas-report
```

## 合约接口

### TreasuryCore（核心金库）

```solidity
// 多签交易
function proposeTransaction(
    address target, uint256 value, bytes calldata data,
    uint256 minDelay, uint256 approvalThreshold,
    string calldata description, bytes32 salt
) external returns (uint256 txId);

function approveTransaction(uint256 txId) external;
function approveBySignature(uint256 txId, uint256 deadline, uint8 v, bytes32 r, bytes32 s) external;
function executeTransaction(uint256 txId) external payable;
function cancelTransaction(uint256 txId) external;

// 签名者管理
function addSigner(address account) external;
function removeSigner(address account) external;
function setGlobalThreshold(uint256 newThreshold) external;

// 预算
function createBudget(...) external returns (bytes32 budgetId);
function getBudgetAvailable(bytes32 budgetId) external view returns (uint256);

// 紧急控制
function pause() external;
function triggerEmergencyShutdown() external;
function executeEmergencyRecovery(address token, address to, uint256 amount) external;

// 查询
function getTransaction(uint256 txId) external view returns (MultiSigTransaction memory);
function getSignerList() external view returns (address[] memory);
function getETHBalance() external view returns (uint256);
function getERC20Balance(address token) external view returns (uint256);
```

### StreamingManager（流支付）

```solidity
function createStream(
    address recipient, address token, uint256 amount,
    uint64 startTime, uint64 cliffDuration, uint64 endTime,
    bool cancelable, bytes32 budgetId
) external returns (uint256 streamId);

function withdrawFromStream(uint256 streamId) external returns (uint256 amount);
function cancelStream(uint256 streamId) external;
function vestedAmount(uint256 streamId) external view returns (uint256);
function releasableAmount(uint256 streamId) external view returns (uint256);
```

### YieldManager（收益管理）

```solidity
function addStrategy(
    string calldata name, address vault, address asset,
    uint256 allocationCap, uint8 riskLevel
) external returns (bytes32 strategyId);

function depositToStrategy(
    bytes32 strategyId, uint256 amount, uint256 minSharesOut
) external returns (bytes32 positionId, uint256 shares);

function withdrawFromStrategy(
    bytes32 positionId, uint256 shares, uint256 minAssetsOut
) external returns (uint256 assets);

function harvestYield(bytes32 strategyId) external returns (uint256 harvestedAmount);
function rebalance(bytes32 fromStrategyId, bytes32 toStrategyId, uint256 shares, uint256 minAssetsOut) external;
function emergencyWithdrawAll(bytes32 strategyId) external;
```

## 角色与权限

| 角色 | 说明 |
|------|------|
| `DEFAULT_ADMIN_ROLE` | 超级管理员，管理其他角色、升级合约 |
| `TREASURY_CONTROLLER_ROLE` | 运营管理，管理签名者/阈值/模块 |
| `SIGNER_ROLE` | 多签成员，审批/拒绝交易 |
| `PROPOSER_ROLE` | 提案人（通常为预算负责人） |
| `EXECUTOR_ROLE` | 执行人（可自动化 keeper bot） |
| `CANCELLER_ROLE` | 取消待处理交易的权限 |
| `STRATEGIST_ROLE` | 策略师，管理 DeFi 投资策略 |
| `BUDGET_MANAGER_ROLE` | 预算管理员，创建/修改/关闭预算 |
| `RECOVERY_ROLE` | 紧急恢复，48 小时延迟才能转出资产 |

### 签名者阈值配置示例

| 团队规模 | 推荐阈值 | 配置 |
|----------|----------|------|
| 3 人团队 | 2/3 | `threshold=2, signers=3` |
| 5 人团队 | 3/5 | `threshold=3, signers=5` |
| 7 人团队 | 4/7 | `threshold=4, signers=7` |
| 大型 DAO | 可更高 | 最大支持 256 签名者 |

## 安全设计

| 层次 | 措施 |
|------|------|
| **重入保护** | ReentrancyGuardTransient（EIP-1153 Cancun），Checks-Effects-Interactions |
| **访问控制** | OpenZeppelin AccessControlEnumerable，细粒度角色隔离 |
| **时间锁** | 棘轮机制（只能增加，不可减少），参数变更也过时间锁 |
| **升级安全** | UUPS 模式，`_disableInitializers()` 防实现劫持，ERC-7201 命名空间存储 |
| **签名安全** | EIP-712 类型化结构化数据，Nonce 防重放，Deadline 过期 |
| **经济安全** | 滑点保护、策略分配上限、单笔最大支出、预算周期限制 |
| **紧急系统** | Tier 1 Pause → Tier 2 Shutdown → Tier 3 Recovery（48h 延迟） |

### ERC-7201 存储

所有合约使用 ERC-7201 命名空间存储防止升级碰撞：

```solidity
// keccak256(abi.encode(uint256(keccak256("treasury.core.storage")) - 1)) & ~bytes32(uint256(0xff))
bytes32 private constant STORAGE_SLOT = 0x78b80d75e1e78a0e3b63f253e108249e7b250f3e2a1b471a5c631e75a2b40900;
```

## 测试

全面覆盖各模块核心功能，17 个测试全部通过：

| 测试类别 | 用例数 | 覆盖内容 |
|----------|--------|----------|
| 多签流程 | 3 | 提案→审批→执行、EIP-712 签名、拒绝 |
| 时间锁 | 2 | 延迟执行、棘轮机制 |
| 签名者管理 | 2 | 增删、阈值边界 |
| 流支付 | 1 | 创建→线性释放→提现 |
| 收益管理 | 2 | 策略注册、存款 |
| 预算管理 | 1 | 创建→记录支出→可用额度 |
| 紧急控制 | 2 | 暂停/恢复、紧急关闭 |
| 资产托管 | 2 | ETH 收款、ERC20 收款 |
| 交易生命周期 | 2 | 取消、基础提案 |

```bash
forge test -vvv
# Suite result: ok. 17 passed; 0 failed; 0 skipped
```

## 部署

### 1. 配置环境变量

```bash
cp .env.example .env
# 编辑 .env，填入部署者私钥、管理员地址、签名者列表等
```

### 2. 执行部署

```bash
# 本地测试网
forge script scripts/Deploy.s.sol --rpc-url http://localhost:8545 --broadcast

# Sepolia 测试网
forge script scripts/Deploy.s.sol --rpc-url $SEPOLIA_RPC --broadcast --verify

# Ethereum 主网
forge script scripts/Deploy.s.sol --rpc-url $MAINNET_RPC --broadcast --verify
```

### 3. 部署后步骤

1. **授予角色**：为团队成员分配合适的角色
2. **注册模块**：YieldManager 和 StreamingManager 已在工厂中注册
3. **添加 DeFi 策略**：通过 `YieldManager.addStrategy()` 注册 ERC-4626 金库
4. **创建预算**：通过 `TreasuryCore.createBudget()` 为各部门创建预算
5. **转移所有权**：将 DEFAULT_ADMIN_ROLE 转移给 DAO 治理合约或多签钱包

## 运维指南

### 日常操作

| 场景 | 操作 | 所需角色 |
|------|------|----------|
| 支付供应商 | `propose → approve ×N → execute` | PROPOSER + SIGNERS + EXECUTOR |
| 创建流支付 | `streaming.createStream()` | STREAM_CREATOR |
| 存入 DeFi | `yield.depositToStrategy()` | STRATEGIST |
| 收割收益 | `yield.harvestYield()` | STRATEGIST |
| 创建预算 | `createBudget()` | BUDGET_MANAGER |
| 修改阈值 | `setGlobalThreshold()` | TREASURY_CONTROLLER |
| 添加签名者 | `addSigner()` | TREASURY_CONTROLLER |

### 紧急操作

| 场景 | 操作 | 延迟 |
|------|------|------|
| 暂停所有操作 | `pause()` | 即时 |
| 恢复操作 | `unpause()` | 即时 |
| 完全关闭 | `triggerEmergencyShutdown()` | 即时 |
| 紧急提取资产 | `executeEmergencyRecovery()` | 48 小时延迟 |

## 技术栈

- **Solidity 0.8.24**（via IR，Cancun EVM）
- **OpenZeppelin Contracts v5.6.1**（AccessControl, UUPS, ReentrancyGuardTransient, ERC-4626）
- **Foundry**（编译/测试/部署/验证/fuzz）
- **ERC-7201**（命名空间存储）
- **EIP-712**（链下签名审批）
- **EIP-1153**（瞬态存储防重入）

## 审计建议

在部署到主网前，建议完成：

- [ ] 第三方安全审计（推荐 Trail of Bits / OpenZeppelin / Certora）
- [ ] 不变量测试（Echidna / Medusa fuzzing）
- [ ] 形式化验证（Certora 规则）
- [ ] 多签操作演练（测试网完整流程）
- [ ] 紧急恢复演练
- [ ] Gas 优化审查

## 许可证

MIT License - 详见 [LICENSE](LICENSE)
