"use client";

import { useState } from "react";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useBudgetIds, useBudget, useBudgetAvailable, useBudgetSpendHistory } from "@/hooks/useTreasury";
import { useTxToast } from "@/hooks/useContractWrite";
import { ABIS, CONTRACTS } from "@/lib/contracts";
import { RowSkeleton, EmptyState, PageHeader } from "@/components/Skeleton";
import { formatEther } from "viem";

export default function BudgetsPage() {
  const { isConnected } = useAccount();
  const { data: budgetIds, isLoading } = useBudgetIds();
  const ids = (budgetIds as `0x${string}`[]) || [];
  const [selected, setSelected] = useState<`0x${string}` | null>(null);

  return (
    <div>
      <PageHeader
        title="预算管理"
        description={ids.length > 0 ? `共 ${ids.length} 个预算` : undefined}
        action={<CreateBudgetForm />}
      />

      {!isConnected ? (
        <EmptyState icon="🔐" title="请连接钱包" description="连接钱包后可以查看和管理部门预算" />
      ) : isLoading ? (
        <RowSkeleton lines={4} />
      ) : ids.length === 0 ? (
        <EmptyState icon="💰" title="暂无预算" description="创建一个部门预算来开始资金管理" />
      ) : (
        <div className="space-y-3">
          {ids.map((id) => (
            <BudgetCard key={id} budgetId={id} isSelected={selected === id} onClick={() => setSelected(selected === id ? null : id)} />
          ))}
        </div>
      )}
    </div>
  );
}

function BudgetCard({ budgetId, isSelected, onClick }: { budgetId: `0x${string}`; isSelected: boolean; onClick: () => void }) {
  const { data: budget, isLoading, error } = useBudget(budgetId);
  const { data: available } = useBudgetAvailable(budgetId);

  if (error) return <div className="bg-red-50 border border-red-200 rounded-lg p-4 text-sm text-red-800">加载预算失败</div>;
  if (isLoading || !budget) return <div className="bg-white border border-gray-200 rounded-lg p-4 animate-pulse-slow"><div className="h-5 bg-gray-200 rounded w-1/3" /></div>;

  const b = budget as Record<string, unknown>;
  const allocated = Number(b.totalAllocated);
  const spent = Number(b.totalSpent);
  const pct = allocated > 0 ? Math.round((spent / allocated) * 100) : 0;

  return (
    <div className="bg-white border border-gray-200 rounded-lg hover:border-gray-300 transition-colors">
      <button onClick={onClick} className="w-full text-left p-4">
        <div className="flex items-center justify-between">
          <div>
            <span className="font-medium text-gray-900">{b.name as string}</span>
            <span className="ml-3 text-sm text-gray-500">负责人: {(b.owner as string)?.slice(0, 8)}...{(b.owner as string)?.slice(-4)}</span>
          </div>
          <div className="flex items-center gap-4">
            <span className="text-sm text-gray-600">
              可用 {formatEther(BigInt(available as string || "0"))} / {formatEther(BigInt(allocated))}
            </span>
            <div className="w-24 h-2 bg-gray-200 rounded-full overflow-hidden">
              <div className="h-full bg-blue-500 rounded-full transition-all" style={{ width: `${pct}%` }} />
            </div>
            <span className="text-xs text-gray-400">{pct}%</span>
          </div>
        </div>
      </button>
      {isSelected && <BudgetDetail budgetId={budgetId} />}
    </div>
  );
}

function BudgetDetail({ budgetId }: { budgetId: `0x${string}` }) {
  const { data: history } = useBudgetSpendHistory(budgetId);
  const { data: budget } = useBudget(budgetId);

  if (!budget) return null;
  const b = budget as Record<string, unknown>;
  const spends = (history as unknown[]) || [];

  return (
    <div className="border-t border-gray-100 p-4 space-y-3">
      <div className="grid grid-cols-3 gap-3 text-sm">
        <div><span className="text-gray-500">总预算:</span> <span className="font-medium">{formatEther(BigInt(b.totalAllocated as string))}</span></div>
        <div><span className="text-gray-500">已支出:</span> <span className="font-medium">{formatEther(BigInt(b.totalSpent as string))}</span></div>
        <div><span className="text-gray-500">已冻结:</span> <span className="font-medium text-yellow-600">{formatEther(BigInt(b.totalFrozen as string))}</span></div>
      </div>

      {spends.length > 0 && (
        <div>
          <h4 className="text-sm font-medium text-gray-700 mb-2">支出记录</h4>
          <table className="w-full text-xs">
            <thead>
              <tr className="text-left text-gray-500 border-b border-gray-100">
                <th className="pb-1">交易</th><th className="pb-1">金额</th><th className="pb-1">收款方</th><th className="pb-1">用途</th>
              </tr>
            </thead>
            <tbody>
              {spends.map((s, i) => {
                const spend = s as Record<string, unknown>;
                return (
                  <tr key={i} className="border-t border-gray-50">
                    <td className="py-1 font-mono">#{String(spend.transactionId)}</td>
                    <td className="py-1">{formatEther(BigInt(spend.amount as string))}</td>
                    <td className="py-1 font-mono">{(spend.recipient as string)?.slice(0, 8)}...</td>
                    <td className="py-1">{spend.purpose as string}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </div>
      )}
      {spends.length === 0 && (
        <p className="text-xs text-gray-400">暂无支出记录</p>
      )}
    </div>
  );
}

function CreateBudgetForm() {
  const { writeContract, data: writeHash, status } = useWriteContract();
  const { isLoading } = useWaitForTransactionReceipt({ hash: writeHash });
  const toast = useTxToast();
  const [showForm, setShowForm] = useState(false);
  const [name, setName] = useState("");
  const [owner, setOwner] = useState("");
  const [allocation, setAllocation] = useState("");

  const handleCreate = () => {
    if (!name || !owner || !allocation) return;
    const amount = BigInt(Math.floor(parseFloat(allocation) * 1e18));
    toast.submit("创建预算");
    writeContract(
      {
        address: CONTRACTS.treasuryCore,
        abi: ABIS.treasuryCore,
        functionName: "createBudget",
        args: [
          name,
          owner as `0x${string}`,
          amount,
          BigInt(Math.floor(Date.now() / 1000)),
          BigInt(Math.floor(Date.now() / 1000) + 365 * 86400),
          [owner as `0x${string}`],
          1n,
          amount,
        ],
      },
      {
        onSuccess: (hash) => {
          toast.confirm("创建预算", hash);
          setShowForm(false);
          setName("");
          setOwner("");
          setAllocation("");
        },
        onError: (err) => toast.fail("创建预算", err),
      }
    );
  };

  if (!showForm) {
    return (
      <button onClick={() => setShowForm(true)} className="px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700">
        + 创建预算
      </button>
    );
  }

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4 w-full max-w-sm shadow-lg">
      <h3 className="text-sm font-semibold text-gray-900 mb-3">创建预算</h3>
      <div className="space-y-2">
        <input type="text" placeholder="预算名称" value={name} onChange={(e) => setName(e.target.value)} className="w-full px-3 py-1.5 border border-gray-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
        <input type="text" placeholder="负责人地址" value={owner} onChange={(e) => setOwner(e.target.value)} className="w-full px-3 py-1.5 border border-gray-300 rounded text-sm font-mono focus:outline-none focus:ring-2 focus:ring-blue-500" />
        <input type="text" placeholder="预算金额 (ETH)" value={allocation} onChange={(e) => setAllocation(e.target.value)} className="w-full px-3 py-1.5 border border-gray-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
        <div className="flex gap-2">
          <button
            onClick={handleCreate}
            disabled={!name || !owner || !allocation || status === "pending" || isLoading}
            className="flex-1 px-3 py-2 bg-blue-600 text-white rounded text-sm font-medium hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {status === "pending" || isLoading ? "提交中..." : "创建预算"}
          </button>
          <button onClick={() => setShowForm(false)} className="px-3 py-2 bg-gray-100 text-gray-700 rounded text-sm font-medium hover:bg-gray-200">
            取消
          </button>
        </div>
      </div>
    </div>
  );
}
