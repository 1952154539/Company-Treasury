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
        <h1 className="text-2xl font-bold text-gray-900">Yield Strategies</h1>
        <p className="text-sm text-gray-500 mt-1">{ids.length} strategies registered</p>
      </div>

      {!isConnected ? (
        <div className="text-center py-10 text-gray-500">Connect wallet to view strategies</div>
      ) : ids.length === 0 ? (
        <div className="text-center py-10 text-gray-500">No strategies configured</div>
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
  const riskLabels = ["Low", "Medium", "High"];

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4">
      <div className="flex items-center justify-between">
        <div>
          <span className="font-medium text-gray-900">{s.name as string}</span>
          <span className="ml-2 text-xs text-gray-500">Vault: {(s.vault as string)?.slice(0, 8)}...</span>
        </div>
        <span className={`px-2 py-0.5 rounded text-xs font-medium ${
          (s.active as boolean) ? "bg-green-100 text-green-700" : "bg-red-100 text-red-700"
        }`}>
          {(s.active as boolean) ? "Active" : "Inactive"}
        </span>
      </div>
      <div className="mt-3 grid grid-cols-3 gap-3 text-sm">
        <div>
          <span className="text-gray-500">Deposited:</span>
          <span className="ml-1 font-medium">{formatEther(deposited)}</span>
        </div>
        <div>
          <span className="text-gray-500">Cap:</span>
          <span className="ml-1 font-medium">{formatEther(cap)}</span>
        </div>
        <div>
          <span className="text-gray-500">Risk:</span>
          <span className="ml-1 font-medium">{riskLabels[Number(s.riskLevel)] || "Unknown"}</span>
        </div>
      </div>
      {/* Progress bar */}
      <div className="mt-3">
        <div className="w-full h-2 bg-gray-200 rounded-full overflow-hidden">
          <div
            className="h-full bg-purple-500 rounded-full"
            style={{ width: `${cap > 0n ? Number((deposited * 100n) / cap) : 0}%` }}
          />
        </div>
        <p className="text-xs text-gray-400 mt-1">
          {cap > 0n ? Number((deposited * 100n) / cap) : 0}% of cap used
        </p>
      </div>
    </div>
  );
}
