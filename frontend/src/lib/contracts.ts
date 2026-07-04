import TreasuryCoreABI from "./abis/TreasuryCore.json";
import StreamingManagerABI from "./abis/StreamingManager.json";
import YieldManagerABI from "./abis/YieldManager.json";

// Update these after deployment
export const CONTRACTS = {
  treasuryCore: "0x1e135cc50b4d39458ca835c8f3ff515587ebc31e" as `0x${string}`,
  streamingManager: "0x0f63b50b342f97d1057a5f0d4084650bde3abb9c" as `0x${string}`,
  yieldManager: "0x8d04e86e4340bbd74d0d88ebea99c87228f49d63" as `0x${string}`,
} as const;

export const ABIS = {
  treasuryCore: TreasuryCoreABI,
  streamingManager: StreamingManagerABI,
  yieldManager: YieldManagerABI,
} as const;

// Role hashes for frontend display
export const ROLES = {
  DEFAULT_ADMIN_ROLE: "0x0000000000000000000000000000000000000000000000000000000000000000",
  TREASURY_CONTROLLER_ROLE: "0x17a8e30262c1f919c33056d877a3c22b95c2f5e4dac44683c1c2323cd79fbdb0",
  SIGNER_ROLE: "0xe2f4eaae4a9751e85a3e4a7b9587827a877f29914755229b07a7b2da98285f70",
  PROPOSER_ROLE: "0xb09aa5aeb3702cfd50b6b62bc4532604938f21248a27a1d5ca736082b6819cc1",
  EXECUTOR_ROLE: "0xd8aa0f3194971a2a116679f7c2090f6939c8d4e01a2a8d7e41d55e5351469e63",
  STRATEGIST_ROLE: "0x928286f435dedd3b80f7a0bcb60cfb33da087ab44b3c028ade9903e58205d934",
  BUDGET_MANAGER_ROLE: "0x4d2b5a50a63f235ec870b20b9b6638d88aa0501011616a5fbf0eeafaccca8535",
} as const;

export const ROLE_LABELS: Record<string, string> = {
  [ROLES.DEFAULT_ADMIN_ROLE]: "管理员",
  [ROLES.TREASURY_CONTROLLER_ROLE]: "运营",
  [ROLES.SIGNER_ROLE]: "签名者",
  [ROLES.PROPOSER_ROLE]: "提案人",
  [ROLES.EXECUTOR_ROLE]: "执行人",
  [ROLES.STRATEGIST_ROLE]: "策略师",
  [ROLES.BUDGET_MANAGER_ROLE]: "预算管理",
};

export const TX_STATUS_LABELS: Record<number, string> = {
  0: "草稿",
  1: "排队中",
  2: "就绪",
  3: "已执行",
  4: "已取消",
  5: "失败",
};
