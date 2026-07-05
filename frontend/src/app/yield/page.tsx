"use client";

import { useState } from "react";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useStrategyIds, useStrategy } from "@/hooks/useYield";
import { useTxToast } from "@/hooks/useContractWrite";
import { ABIS, CONTRACTS } from "@/lib/contracts";
import { RowSkeleton, EmptyState, PageHeader } from "@/components/Skeleton";
import { formatEther, parseEther } from "viem";

export default function YieldPage() {
  const { isConnected } = useAccount();
  const { data: strategyIds, isLoading } = useStrategyIds();
  const ids = (strategyIds as `0x${string}`[]) || [];

  return (
    <div>
      <PageHeader
        title="收益策略"
        description={ids.length > 0 ? `已注册 ${ids.length} 个策略` : undefined}
        action={<DepositForm />}
      />

      {!isConnected ? (
        <EmptyState icon="🔐" title="请连接钱包" description="连接钱包后可查看和管理 DeFi 收益策略" />
      ) : isLoading ? (
        <RowSkeleton lines={4} />
      ) : ids.length === 0 ? (
        <EmptyState icon="📈" title="暂无策略" description="注册一个 ERC-4626 策略来开始收益管理" />
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
  const { data: strategy, isLoading, error } = useStrategy(strategyId);

  if (error) return <div className="bg-red-50 border border-red-200 rounded-lg p-4 text-sm text-red-800">加载策略失败</div>;
  if (isLoading || !strategy) return <div className="bg-white border border-gray-200 rounded-lg p-4 animate-pulse-slow"><div className="h-5 bg-gray-200 rounded w-1/3" /></div>;

  const s = strategy as Record<string, unknown>;
  const deposited = s.totalDeposited as bigint;
  const cap = s.allocationCap as bigint;
  const riskLabels = ["低风险", "中风险", "高风险"];
  const riskColors = ["text-green-600", "text-yellow-600", "text-red-600"];

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4 hover:border-gray-300 transition-colors">
      <div className="flex items-center justify-between">
        <div>
          <span className="font-medium text-gray-900">{s.name as string}</span>
          <span className="ml-2 text-xs text-gray-500 font-mono">金库: {(s.vault as string)?.slice(0, 8)}...{(s.vault as string)?.slice(-4)}</span>
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
          <span className="text-gray-500">策略上限:</span>
          <span className="ml-1 font-medium">{formatEther(cap)}</span>
        </div>
        <div>
          <span className="text-gray-500">风险:</span>
          <span className={`ml-1 font-medium ${riskColors[Number(s.riskLevel)] || ""}`}>{riskLabels[Number(s.riskLevel)] || "未知"}</span>
        </div>
      </div>
      <div className="mt-3">
        <div className="flex justify-between text-xs text-gray-500 mb-1">
          <span>已使用</span>
          <span>{cap > 0n ? Number((deposited * 100n) / cap) : 0}%</span>
        </div>
        <div className="w-full h-2 bg-gray-200 rounded-full overflow-hidden">
          <div className="h-full bg-purple-500 rounded-full transition-all" style={{ width: `${cap > 0n ? Number((deposited * 100n) / cap) : 0}%` }} />
        </div>
      </div>
    </div>
  );
}

function DepositForm() {
  const { writeContract, data: writeHash, status } = useWriteContract();
  const { isLoading } = useWaitForTransactionReceipt({ hash: writeHash });
  const toast = useTxToast();
  const { data: strategyIds } = useStrategyIds();
  const ids = (strategyIds as `0x${string}`[]) || [];
  const [showForm, setShowForm] = useState(false);
  const [strategyId, setStrategyId] = useState("");
  const [amount, setAmount] = useState("");

  const handleDeposit = () => {
    if (!strategyId || !amount) return;
    const amt = parseEther(amount);
    toast.submit("存入策略");
    writeContract(
      {
        address: CONTRACTS.yieldManager,
        abi: ABIS.yieldManager,
        functionName: "depositToStrategy",
        args: [strategyId as `0x${string}`, amt, 1n],
      },
      {
        onSuccess: (hash) => {
          toast.confirm("存入策略", hash);
          setShowForm(false);
          setAmount("");
        },
        onError: (err) => toast.fail("存入策略", err),
      }
    );
  };

  if (!showForm) {
    return (
      <button onClick={() => setShowForm(true)} className="px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700">
        + 存入资金
      </button>
    );
  }

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4 w-full max-w-sm shadow-lg">
      <h3 className="text-sm font-semibold text-gray-900 mb-3">存入收益策略</h3>
      <div className="space-y-2">
        <select
          value={strategyId}
          onChange={(e) => setStrategyId(e.target.value)}
          className="w-full px-3 py-1.5 border border-gray-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-blue-500"
        >
          <option value="">选择策略...</option>
          {ids.map((id) => (
            <option key={id} value={id}>{id.slice(0, 12)}...</option>
          ))}
        </select>
        <input type="text" placeholder="存入金额 (ETH)" value={amount}
          onChange={(e) => setAmount(e.target.value)}
          className="w-full px-3 py-1.5 border border-gray-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
        <div className="flex gap-2">
          <button
            onClick={handleDeposit}
            disabled={!strategyId || !amount || status === "pending" || isLoading}
            className="flex-1 px-3 py-2 bg-blue-600 text-white rounded text-sm font-medium hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {status === "pending" || isLoading ? "存入中..." : "存入"}
          </button>
          <button onClick={() => setShowForm(false)} className="px-3 py-2 bg-gray-100 text-gray-700 rounded text-sm font-medium hover:bg-gray-200">
            取消
          </button>
        </div>
      </div>
    </div>
  );
}
