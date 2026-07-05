# Company Treasury — 链上企业金库系统

[![Solidity](https://img.shields.io/badge/Solidity-0.8.24-blue)](https://soliditylang.org)
[![Foundry](https://img.shields.io/badge/Foundry-latest-orange)](https://book.getfoundry.sh)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Tests](https://img.shields.io/badge/tests-66%2F66%20passed-brightgreen)]()
[![Next.js](https://img.shields.io/badge/Next.js-16-black)](https://nextjs.org)

生产级链上企业金库系统。采用 **UUPS 可升级代理 + ERC-7201 命名空间存储** 的 Hub-and-Spoke 模块化架构，集成 N/M 多签治理（EIP-712 链下签名 + Bitmap 位图追踪）、棘轮时间锁、Sablier 式流支付、ERC-4626 DeFi 收益策略管理、部门预算分配，以及三级应急控制系统。

---

## 目录

- [系统架构](#系统架构)
- [核心功能](#核心功能)
- [架构设计决策](#架构设计决策)
- [安全设计](#安全设计)
- [技术栈](#技术栈)
- [项目结构](#项目结构)
- [快速开始](#快速开始)
- [测试套件](#测试套件)
- [前端](#前端)
- [子图](#子图)
- [部署](#部署)
- [简历要点](#简历要点)

---

## 系统架构

### 总体架构：Hub-and-Spoke

```
                          ┌──────────────────────────────────────┐
                          │           TreasuryFactory             │
                          │   一键部署所有合约 (CREATE2 模式)       │
                          └──────────────┬───────────────────────┘
                                         │ 部署 3 个 UUPS 代理
              ┌──────────────────────────┼──────────────────────────┐
              ▼                          ▼                          ▼
   ┌──────────────────┐    ┌─────────────────────┐    ┌──────────────────────┐
   │   TreasuryCore   │    │  StreamingManager   │    │    YieldManager      │
   │   (Hub - 金库)   │    │  (Spoke - 流支付)    │    │   (Spoke - 收益)      │
   │                  │    │                     │    │                      │
   │ "持有全部资产"    │◄───│ "只能通过 Hub 转出"  │    │ "只能通过 Hub 转出"   │
   │                  │    │                     │    │                      │
   │ 5 个内部模块:     │    │ UUPS + ERC-7201     │    │ UUPS + ERC-7201      │
   │ · MultiSigModule │    │ · createStream      │    │ · addStrategy        │
   │ · TimelockModule │    │ · withdrawFromStream│    │ · depositToStrategy  │
   │ · BudgetModule   │    │ · cancelStream      │    │ · withdraw/harvest   │
   │ · EmergencyModule│    │ · batchCreateStreams│    │ · rebalance          │
   │ · AccessModule   │    │ · 线性释放计算       │    │ · ERC-4626 集成      │
   └──────────────────┘    └─────────────────────┘    └──────────────────────┘
```

### 为什么选 Hub-and-Spoke 而非 Diamond (EIP-2535)

| 维度 | Hub-and-Spoke (本项目) | Diamond (EIP-2535) |
|------|----------------------|---------------------|
| **资产安全** | TreasuryCore 持有全部资产，外部模块必须通过 `onlyModule` 门禁才能转出 | 所有 Facet 共享 storage，一个 Facet 的 bug 可能导致全部资产损失 |
| **升级独立性** | StreamingManager / YieldManager 可独立升级，不影响核心金库 | 所有 Facet 统一通过 diamondCut 升级，耦合度高 |
| **Storage 管理** | ERC-7201 命名空间存储，每个合约独立 slot，数学上不可能碰撞 | 需要 AppStorage / Diamond Storage 模式手动管理，容易出错 |
| **审计难度** | 模块边界清晰，每个合约职责单一 | delegatecall 路由 + 共享存储，审计复杂度高 |
| **Gas 成本** | 跨合约调用有额外 gas（治理操作低频，可接受） | 单次 delegatecall 更低 |

详见 [ADR-001: UUPS over Diamond](docs/ADR/001-uups-over-diamond.md)。

### ERC-7201 命名空间存储

所有合约使用 ERC-7201 公式计算 storage slot，彻底消除升级中的存储碰撞风险：

```solidity
// slot = keccak256(abi.encode(uint256(keccak256("treasury.core.storage")) - 1)) & ~bytes32(uint256(0xff))
bytes32 private constant STORAGE_SLOT =
    0x78b80d75e1e78a0e3b63f253e108249e7b250f3e2a1b471a5c631e75a2b40900;
```

不同于传统的非结构化存储（手动选 slot）或继承链存储（依赖编译器布局），ERC-7201 使用命名空间字符串生成确定性 slot。两个不同的 namespace 必然产生不同的 slot，数学上不可能碰撞。详见 [ADR-002](docs/ADR/002-erc7201-storage.md)。

---

## 核心功能

### 1. 多签治理 (MultiSigModule)

```
工作流: PROPOSE → APPROVE × N → 达阈值 → QUEUE(时间锁) → READY → EXECUTE
                                   ↘ (无延迟) → READY → EXECUTE
```

| 特性 | 实现 |
|------|------|
| **N/M 阈值** | 灵活配置，最大支持 256 个签名者 |
| **EIP-712 链下签名** | `approveBySignature(txId, deadline, v, r, s)` — gasless 审批，签名者无需支付 gas |
| **Bitmap 审批追踪** | `uint256 approvalBitmap` 位图记录，O(1) 查询 + O(1) 更新，一个 slot 支持最多 256 个签名者 |
| **防重放** | EIP-712 签名含 nonce + deadline，过期签名自动拒绝 |
| **重复交易检测** | `executedTxHashes` mapping 防同一交易重复执行 |
| **生命周期** | Draft → Queued → Ready → Executed / Cancelled / Failed |

### 2. 时间锁 (TimelockModule)

| 特性 | 实现 |
|------|------|
| **棘轮机制** | `setDefaultMinDelay` 只能增加不能减少，增加安全性 |
| **例外覆盖** | `DEFAULT_ADMIN_ROLE` 可通过 `forceSetMinDelay` 强制降低（用于紧急情况） |
| **自动状态转换** | 审批达阈值后自动从 Draft → Queued（有时间锁）或 Draft → Ready（无时间锁） |
| **延迟范围** | 1 小时 ~ 30 天，可配置 |

### 3. 流支付 (StreamingManager)

Sablier 式的线性释放支付系统：

```
创建流 → (Cliff 期) → 线性释放 → 收款方主动提现 (Pull over Push)
                ↘ 创建者可取消 → 剩余资金退还金库
```

| 特性 | 实现 |
|------|------|
| **线性释放** | `vestedAmount = total × (t - start) / (end - start)` |
| **Cliff 期** | 可配置，cliff 期间 vestedAmount 恒为 0 |
| **Pull over Push** | 收款方主动调用 `withdrawFromStream`，避免被动接收问题 |
| **批量创建** | `batchCreateStreams` 支持一次创建多个流（如批量发工资） |
| **可取消** | 创建者可取消流，剩余资金自动退回金库 |
| **独立升级** | 独立的 UUPS 代理，升级不影响金库核心 |

### 4. DeFi 收益管理 (YieldManager)

基于 ERC-4626 标准的策略管理系统：

```
注册策略 → 存入 (deposit) → 收益累计 → 收割 (harvest) → 提现
                                    ↘ 调仓 (rebalance)
```

| 特性 | 实现 |
|------|------|
| **ERC-4626 标准** | 兼容 Aave / Lido / Compound / Yearn 等所有 ERC-4626 金库 |
| **策略白名单** | 只有注册的策略才能存入，防止 rug pull |
| **分配上限** | 每个策略可设 `allocationCap`，防止过度集中 |
| **收益收割** | 自动计算 yield = 当前资产 - 本金，仅提取收益部分 |
| **调仓** | `rebalance(from, to, shares)` 一键在策略间迁移资金 |
| **紧急提现** | `emergencyWithdrawAll` 由 TREASURY_CONTROLLER 触发，全部赎回 |
| **滑点保护** | `minSharesOut` / `minAssetsOut` 参数防止 MEV 抢跑 |
| **三步交互模式** | YieldManager 从 TreasuryCore 拉取资产 → 授权金库 → 存入/赎回，全程不持有资产 |

### 5. 预算管理 (BudgetModule)

```
创建预算 → 提案(冻结) → 审批 → 执行(冻结→已花) → 关闭(退回剩余)
                 ↘ 取消(解冻)
```

| 特性 | 实现 |
|------|------|
| **冻结-结算** | 提案时冻结资金 → 执行成功转已花 → 执行失败/取消解冻，防止双花 |
| **周期限制** | 预算有 startTime / endTime，到期自动失效 |
| **单笔上限** | `maxSingleSpend` 限制单笔最大支出 |
| **审批人** | 每个预算有独立审批人列表（可与全局签名者不同） |
| **支出历史** | `budgetSpendHistory` 链上完整追溯 |

### 6. 三级应急系统 (EmergencyModule)

```
Tier 1: Pause (即时)
  └─ 暂停提案、支出、模块转账
  └─ 不影响已发起的审批（签名者仍可投票）

Tier 2: Shutdown (即时)
  └─ Tier 1 全部 + 暂停所有资金转账
  └─ 自动触发 Pause

Tier 3: Recovery (48h 延迟)
  └─ 预授权 recovery 地址
  └─ initiate → 48h 等待期 → execute
  └─ 48h 延迟给社区反应时间
```

### 7. 细粒度角色权限 (AccessModule)

9 个独立角色，遵循最小权限原则：

| 角色 | 权限 |
|------|------|
| `DEFAULT_ADMIN_ROLE` | 超管：管理角色、升级合约、强制降时间锁 |
| `TREASURY_CONTROLLER_ROLE` | 运营：管理签名者/阈值/模块、暂停/关闭 |
| `SIGNER_ROLE` | 签名者：审批/拒绝交易 |
| `PROPOSER_ROLE` | 提案人：创建多签提案 |
| `EXECUTOR_ROLE` | 执行人：执行已通过的交易 |
| `CANCELLER_ROLE` | 取消人：取消待处理交易 |
| `STRATEGIST_ROLE` | 策略师：管理 DeFi 策略 |
| `BUDGET_MANAGER_ROLE` | 预算管理：创建/修改/关闭预算 |
| `RECOVERY_ROLE` | 恢复人：发起紧急恢复（48h 延迟） |

角色之间互不重叠 —— 策略师无法动多签，签名者无权调策略。

---

## 架构设计决策

| 决策 | 选项 | 选择 | 原因 |
|------|------|------|------|
| 代理模式 | UUPS / Transparent / Diamond | **UUPS** | 更轻量，升级逻辑在实现合约中，无额外 proxy admin 开销 |
| 存储模式 | 继承链 / 非结构化 / ERC-7201 | **ERC-7201** | 标准化命名空间，数学保证无碰撞 |
| 合约拆分 | 单体 / Hub-Spoke / Microservices | **Hub-Spoke** | 资产集中保管 + 功能独立升级 |
| 防重入 | ReentrancyGuard / Transient | **Transient (EIP-1153)** | Cancun 升级后 gas 更低，自动清理 |
| 签名标准 | EIP-712 / EIP-191 / 自定义 | **EIP-712** | 类型化数据，钱包友好显示 |
| 时间锁 | 固定 / 可增可减 / 棘轮 | **棘轮（只增不减）** | 防社工攻击逐步缩短延迟 |
| 流支付 | 推式 / 拉式 (Pull) | **拉式 (Pull)** | 收款方主动提现，避免 gas 浪费 |
| 收益标准 | 自定义 / ERC-4626 | **ERC-4626** | 行业标准，兼容所有主流金库 |
| 预算管理 | 乐观记账 / 冻结-结算 | **冻结-结算** | 提案即冻结，执行才扣款，防双花 |

详见 [docs/ADR/](docs/ADR/)。

---

## 安全设计

### 防护矩阵

| 攻击面 | 风险等级 | 防护措施 |
|--------|---------|---------|
| 重入攻击 | 🔴 严重 | `ReentrancyGuardTransient` (EIP-1153) + Checks-Effects-Interactions |
| 升级存储碰撞 | 🔴 严重 | ERC-7201 命名空间 + `_disableInitializers()` 防实现劫持 |
| 未授权升级 | 🔴 严重 | `_authorizeUpgrade` 仅 `DEFAULT_ADMIN_ROLE` |
| 签名重放 | 🟠 高 | EIP-712 含 nonce + deadline |
| 时间锁绕过 | 🟠 高 | 棘轮机制：只能增加，减少需 admin 强制覆盖 |
| 预算双花 | 🟠 高 | 冻结-结算机制，提案即冻结，执行/取消才变动 |
| 签名者删除 < 阈值 | 🟡 中 | `removeSigner` 检查剩余活跃数 >= 阈值 |
| 重复交易 | 🟡 中 | `executedTxHashes` mapping 防重放 |
| 未授权模块 | 🟡 中 | `onlyModule` 检查 `moduleRegistry`，仅 admin 可注册 |
| block.timestamp 操纵 | 🟢 低 | 仅用于天级延迟比较，不用于随机数或精确计时 |

### 紧急响应流程

```
发现异常
  ├─ 严重程度低 → Pause (即时，暂停操作但保留审批)
  ├─ 严重程度中 → Shutdown (即时，冻结全部转账)
  └─ 严重程度高 → Recovery (48h 延迟后提取资产到预授权地址)
```

详见 [docs/SECURITY.md](docs/SECURITY.md)。

---

## 技术栈

| 层 | 技术 | 说明 |
|----|------|------|
| 智能合约 | Solidity 0.8.24 + Foundry | via IR 编译，Cancun EVM 目标 |
| 合约库 | OpenZeppelin Contracts v5.6.1 | AccessControl, UUPS, ReentrancyGuardTransient, ERC-4626 |
| 代理模式 | UUPS (EIP-1822) | 轻量级可升级代理 |
| 存储模式 | ERC-7201 | 命名空间存储，防升级碰撞 |
| 签名标准 | EIP-712 | 类型化结构化数据签名 |
| 瞬态存储 | EIP-1153 (Cancun) | 防重入 gas 优化 |
| 前端 | Next.js 16 + TypeScript + Tailwind CSS | App Router |
| Web3 库 | Wagmi v2 + Viem v2 + ConnectKit | 钱包连接 + 合约交互 |
| 子图 | The Graph (AssemblyScript) | 链上事件索引，GraphQL 查询 |
| CI/CD | GitHub Actions | 自动构建 + 测试 + Gas 报告 |
| 测试 | Foundry (Fuzz + Invariant) | 1000 次/用例 fuzz，256 depth invariant |

---

## 项目结构

```
Company-Treasury/
├── contracts/                        # Solidity 合约
│   ├── treasury/
│   │   ├── TreasuryCore.sol          # Hub: 资产保管 + 模块集成
│   │   ├── TreasuryCoreStorage.sol   # ERC-7201 存储布局 + 数据结构
│   │   └── modules/
│   │       ├── AccessModule.sol      # 角色权限 + 签名者管理
│   │       ├── MultiSigModule.sol    # N/M 多签 + EIP-712 签名
│   │       ├── TimelockModule.sol    # 棘轮时间锁
│   │       ├── BudgetModule.sol      # 预算创建/冻结/结算
│   │       └── EmergencyModule.sol   # Pause/Shutdown/Recovery
│   ├── streaming/
│   │   └── StreamingManager.sol      # 流支付 (独立 UUPS)
│   ├── yield/
│   │   └── YieldManager.sol          # 收益管理 (独立 UUPS)
│   ├── factory/
│   │   └── TreasuryFactory.sol       # 一键部署 3 个代理
│   ├── interfaces/                   # 事件 + 错误定义
│   └── libraries/                    # 角色常量
│
├── test/                             # Foundry 测试 (66 个)
│   ├── TreasuryCore.t.sol            # 17 单元测试
│   ├── YieldStrategy.t.sol           # 15 收益策略测试
│   ├── fuzz/                         # 9 个 Fuzz × 1000 runs
│   ├── invariants/                   # 7 个不变量测试
│   ├── integration/                  # 7 个集成测试
│   └── edge/                         # 10 个边界测试
│
├── frontend/                         # Next.js 16 前端
│   ├── src/app/                      # 6 个页面
│   │   ├── page.tsx                  # Dashboard + 分析图表
│   │   ├── transactions/page.tsx     # 交易列表 + 提案表单 + Toast
│   │   ├── budgets/page.tsx          # 预算管理 + 进度条
│   │   ├── streams/page.tsx          # 流支付 + 提现
│   │   ├── yield/page.tsx            # 收益策略 + 存入
│   │   └── admin/page.tsx            # 管理面板 + 紧急控制
│   ├── src/components/               # Toast, Skeleton, Analytics, EventSubscriber
│   ├── src/hooks/                    # Wagmi 合约读写 + 事件监听 hooks
│   └── src/lib/                      # ABIs + 配置 + Wagmi 配置
│
├── subgraph/                         # The Graph 子图
│   ├── schema.graphql                # 11 个实体
│   ├── subgraph.yaml                 # 3 数据源, 23 事件处理器
│   └── src/                          # AssemblyScript mappings
│
├── scripts/Deploy.s.sol              # 部署脚本 (自动注册模块)
├── .github/workflows/ci.yml          # CI: build + test + fmt
├── Makefile                          # 12 个命令
├── docs/                             # 架构决策记录 + 安全文档
└── README.md
```

---

## 快速开始

### 环境要求

- [Foundry](https://book.getfoundry.sh/getting-started/installation) >= 1.0
- [Node.js](https://nodejs.org/) >= 20.9

### 合约

```bash
# 安装依赖
forge install

# 编译
forge build

# 运行全部 51 个测试
forge test -vvv

# Fuzz 测试 (高轮次)
forge test --fuzz-runs 5000 --match-path "test/fuzz/*" -vvv

# Gas 报告
forge test --gas-report
```

### 前端

```bash
cd frontend
npm install --legacy-peer-deps
npm run dev
# 打开 http://localhost:3000
```

### 子图

```bash
cd subgraph
npm install --legacy-peer-deps
npm run codegen   # 生成类型
npm run build     # 编译 WASM
```

---

## 测试套件

66 个测试，7 个类别：

| 类别 | 数量 | 覆盖范围 |
|------|------|---------|
| **单元测试** | 17 | 多签流程、签名者管理、时间锁、预算 CRUD、流支付、收益策略、紧急控制 |
| **Fuzz (流支付)** | 5 × 1000 | 线性释放数学正确性、cliff 强制、提现累积、vested/releasable 一致性 |
| **Fuzz (多签)** | 4 × 1000 | 签名者数量/阈值组合、随机审批顺序、bitmap 正确性、预算冻结金额 |
| **不变量** | 7 | 预算会计恒等、取消释放冻结、模块注册权限、签名者一致性、关闭阻塞操作 |
| **集成测试** | 7 | 完整多签+预算流程、时间锁交易、流支付全生命周期、暂停/恢复、紧急恢复、收益存取、批量流 |
| **边界测试** | 10 | 阈值边界、签名者移除边界、零值交易、最小预算、未来时间预算、bitmap 碰撞、非授权拒绝 |
| **收益率策略** | 15 | 策略生命周期、存取款、滑点保护、收益收割、紧急提现、跨策略调仓、暂停控制、权限校验 |

```bash
# 全部测试
forge test -vvv
# Suite result: ok. 66 passed; 0 failed; 0 skipped
```

---

## 前端

6 个功能页面，全部基于 Next.js 16 App Router + Wagmi v2：

| 页面 | 路由 | 核心功能 |
|------|------|---------|
| **Dashboard** | `/` | 金库 ETH 余额、签名者比例、活跃流数量、策略数量、安全状态、快捷入口 |
| **Transactions** | `/transactions` | 交易列表、审批进度条（N/M 签名者头像）、EIP-712 浏览器签名、执行/取消、新建提案（关联预算） |
| **Budgets** | `/budgets` | 预算列表 + 分配/已花进度条、支出历史表、创建预算表单 |
| **Streams** | `/streams` | 流支付列表、线性释放进度条、提现按钮 |
| **Yield** | `/yield` | 策略列表、存入量/上限进度、风险等级 |
| **Admin** | `/admin` | 签名者增删、阈值调整、紧急暂停/关闭 |

技术特点：
- EIP-712 浏览器签名审批（ConnectKit 内置 `signTypedData`）
- 多签审批进度可视化（bitmap → N/M 头像栏）
- 所有数据通过 Wagmi `useReadContract` 从链上实时读取
- Recharts 分析图表（预算分配饼图、活动柱状图、策略风险分布）
- Toast 通知系统（交易提交 → 确认中 → 成功/失败）
- 合约事件实时监听 + React Query 自动刷新（TransactionProposed/Approved/Executed 等 8 个事件）
- Skeleton 加载态 + ErrorBoundary 错误处理
- Tailwind CSS 响应式布局

---

## 子图

索引 TreasuryCore、StreamingManager、YieldManager 三个合约的全部链上事件，提供 GraphQL 查询端点。

| 数据源 | 事件数 | 索引实体 |
|--------|--------|---------|
| TreasuryCore | 18 | Transaction, Approval, Signer, Budget, SpendRecord, EmergencyEvent, Treasury |
| StreamingManager | 3 | Stream, StreamWithdrawal |
| YieldManager | 7 | Strategy, Position |

### 示例查询

```graphql
# 查询某笔多签交易的详情和审批人
query TxDetail($id: ID!) {
  transaction(id: $id) {
    txId, proposer, description, status, approvalCount, approvalsRequired
    approvals { signer { id } timestamp }
  }
}

# 查询某预算的支出历史
query BudgetSpends($budgetId: ID!) {
  budget(id: $budgetId) {
    name, totalAllocated, totalSpent, totalFrozen
    spends(orderBy: timestamp, orderDirection: desc) {
      amount, recipient, purpose, timestamp
    }
  }
}

# 查询某地址的活跃流支付
query ActiveStreams($recipient: Bytes!) {
  streams(where: { recipient: $recipient, active: true }) {
    streamId, totalAmount, remainingBalance, endTime
  }
}
```

---

## 部署

### 测试网 (Sepolia)

```bash
# 配置环境变量
export PRIVATE_KEY=0x...
export TREASURY_ADMIN=0x...
export SIGNER_THRESHOLD=2
export MIN_DELAY=86400
export SIGNERS=0x...,0x...,0x...
export ETHERSCAN_API_KEY=...

# 部署 + 验证
make deploy-sepolia
```

部署脚本自动完成：
1. 部署 TreasuryCore + StreamingManager + YieldManager 的实现合约和代理
2. 自动注册 StreamingManager 和 YieldManager 到 TreasuryCore 的 moduleRegistry
3. 输出 `deployments/deployment.json` 部署产物

### 本地测试网

```bash
# 启动 anvil
anvil

# 部署
make deploy-local
```

---

## 简历要点

> **Company Treasury — 链上企业金库系统**
>
> * 设计并实现了基于 UUPS 可升级代理 + ERC-7201 命名空间存储的模块化 Hub-and-Spoke 架构，集成 N/M 多签（EIP-712 gasless 审批 + Bitmap 位图追踪）、棘轮时间锁、Sablier 式线性流支付、ERC-4626 DeFi 收益策略管理（含跨策略调仓/滑点保护/紧急提现）、部门预算分配（冻结-结算模型防双花）
> * 构建三级应急系统（Pause → Shutdown → 48h Recovery），采用 EIP-1153 瞬态存储防重入（ReentrancyGuardTransient + Checks-Effects-Interactions）；9 个细粒度角色遵循最小权限原则，角色间互不重叠
> * 编写 66 个 Foundry 测试（9 个 Fuzz × 1000 runs + 7 个不变量测试 + 15 个收益率策略专项测试），覆盖多签全生命周期、流支付数学正确性、预算会计恒等、收益存取一致性、紧急恢复全流程
> * 开发 The Graph 子图（3 数据源 / 23 事件处理器 / 11 实体），索引全部链上事件；构建 Next.js 16 + Wagmi/Viem 前端，实现 Recharts 分析看板、EIP-712 浏览器签名、Toast 交易通知、8 个链上事件实时监听 + React Query 自动刷新

---

## 许可证

MIT License
