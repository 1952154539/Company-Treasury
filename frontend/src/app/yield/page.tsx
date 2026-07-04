"use client";

import { useAccount } from "wagmi";
import { useStrategyIds, useStrategy } from "@/hooks/useYield";
import { formatEther } from "viem";

export default function YieldPage() {
  const { isConnected } = useAccount();
  const { data: strategyIds } = useStrategyIds();
  const ids = (strategyIds as `0x${string}`[]) || [];

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">收益策略</h1>
        <p className="text-sm text-gray-500 mt-1">已注册 {ids.length} 个策略</p>
      </div>

      {!isConnected ? (
        <div className="text-center py-10 text-gray-500">请连接钱包查看策略</div>
      ) : ids.length === 0 ? (
        <div className="text-center py-10 text-gray-500">暂无策略</div>
      ) : (
        <div className="space-y-3">
          {ids.map((id) => (
            <StrategyCard key={id} strategyId={id} />
          ))}
        </div>
      )}
    </div>
  );
}

function StrategyCard({ strategyId }: { strategyId: `0x${string}` }) {
  const { data: strategy } = useStrategy(strategyId);

  if (!strategy) return null;
  const s = strategy as Record<string, unknown>;
  const deposited = s.totalDeposited as bigint;
  const cap = s.allocationCap as bigint;
  const riskLabels = ["低", "中", "高"];

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4">
      <div className="flex items-center justify-between">
        <div>
          <span className="font-medium text-gray-900">{s.name as string}</span>
          <span className="ml-2 text-xs text-gray-500">金库: {(s.vault as string)?.slice(0, 8)}...</span>
        </div>
        <span className={`px-2 py-0.5 rounded text-xs font-medium ${
          (s.active as boolean) ? "bg-green-100 text-green-700" : "bg-red-100 text-red-700"
        }`}>
          {(s.active as boolean) ? "活跃" : "已停用"}
        </span>
      </div>
      <div className="mt-3 grid grid-cols-3 gap-3 text-sm">
        <div>
          <span className="text-gray-500">已存入:</span>
          <span className="ml-1 font-medium">{formatEther(deposited)}</span>
        </div>
        <div>
          <span className="text-gray-500">上限:</span>
          <span className="ml-1 font-medium">{formatEther(cap)}</span>
        </div>
        <div>
          <span className="text-gray-500">风险:</span>
          <span className="ml-1 font-medium">{riskLabels[Number(s.riskLevel)] || "未知"}</span>
        </div>
      </div>
      <div className="mt-3">
        <div className="w-full h-2 bg-gray-200 rounded-full overflow-hidden">
          <div
            className="h-full bg-purple-500 rounded-full"
            style={{ width: `${cap > 0n ? Number((deposited * 100n) / cap) : 0}%` }}
          />
        </div>
        <p className="text-xs text-gray-400 mt-1">
          已使用上限的 {cap > 0n ? Number((deposited * 100n) / cap) : 0}%
        </p>
      </div>
    </div>
  );
}
