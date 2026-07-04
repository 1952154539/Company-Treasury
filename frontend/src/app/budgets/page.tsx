"use client";

import { useState } from "react";
import { useAccount, useWriteContract } from "wagmi";
import { useBudgetIds, useBudget, useBudgetAvailable, useBudgetSpendHistory } from "@/hooks/useTreasury";
import { ABIS, CONTRACTS } from "@/lib/contracts";
import { formatEther } from "viem";

export default function BudgetsPage() {
  const { isConnected } = useAccount();
  const { data: budgetIds } = useBudgetIds();
  const ids = (budgetIds as `0x${string}`[]) || [];
  const [selected, setSelected] = useState<`0x${string}` | null>(null);

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">预算管理</h1>
          <p className="text-sm text-gray-500 mt-1">共 {ids.length} 个预算</p>
        </div>
        <CreateBudgetForm />
      </div>

      {!isConnected ? (
        <div className="text-center py-10 text-gray-500">请连接钱包查看预算</div>
      ) : ids.length === 0 ? (
        <div className="text-center py-10 text-gray-500">暂无预算</div>
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
  const { data: budget } = useBudget(budgetId);
  const { data: available } = useBudgetAvailable(budgetId);

  if (!budget) return null;
  const b = budget as Record<string, unknown>;
  const allocated = Number(b.totalAllocated);
  const spent = Number(b.totalSpent);
  const pct = allocated > 0 ? Math.round((spent / allocated) * 100) : 0;

  return (
    <div className="bg-white border border-gray-200 rounded-lg">
      <button onClick={onClick} className="w-full text-left p-4">
        <div className="flex items-center justify-between">
          <div>
            <span className="font-medium text-gray-900">{b.name as string}</span>
            <span className="ml-3 text-sm text-gray-500">负责人: {(b.owner as string)?.slice(0, 8)}...</span>
          </div>
          <div className="flex items-center gap-4">
            <span className="text-sm text-gray-600">
              {formatEther(BigInt(available as string || "0"))} / {formatEther(BigInt(allocated))} 可用
            </span>
            <div className="w-24 h-2 bg-gray-200 rounded-full overflow-hidden">
              <div className="h-full bg-blue-500 rounded-full" style={{ width: `${pct}%` }} />
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
        <div><span className="text-gray-500">已冻结:</span> <span className="font-medium">{formatEther(BigInt(b.totalFrozen as string))}</span></div>
      </div>

      {spends.length > 0 && (
        <div>
          <h4 className="text-sm font-medium text-gray-700 mb-2">支出记录</h4>
          <table className="w-full text-xs">
            <thead>
              <tr className="text-left text-gray-500">
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
    </div>
  );
}

function CreateBudgetForm() {
  const { writeContract } = useWriteContract();
  const [name, setName] = useState("");
  const [owner, setOwner] = useState("");
  const [allocation, setAllocation] = useState("");

  const handleCreate = () => {
    writeContract({
      address: CONTRACTS.treasuryCore,
      abi: ABIS.treasuryCore,
      functionName: "createBudget",
      args: [
        name,
        owner as `0x${string}`,
        allocation ? BigInt(Math.floor(parseFloat(allocation) * 1e18)) : 0n,
        BigInt(Math.floor(Date.now() / 1000)),
        BigInt(Math.floor(Date.now() / 1000) + 365 * 86400),
        [owner as `0x${string}`],
        1n,
        allocation ? BigInt(Math.floor(parseFloat(allocation) * 1e18)) : 0n,
      ],
    });
  };

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4 w-full max-w-sm">
      <h3 className="text-sm font-semibold text-gray-900 mb-3">创建预算</h3>
      <div className="space-y-2">
        <input type="text" placeholder="预算名称" value={name} onChange={(e) => setName(e.target.value)} className="w-full px-3 py-1.5 border border-gray-300 rounded text-sm" />
        <input type="text" placeholder="负责人地址" value={owner} onChange={(e) => setOwner(e.target.value)} className="w-full px-3 py-1.5 border border-gray-300 rounded text-sm font-mono" />
        <input type="text" placeholder="预算金额 (ETH)" value={allocation} onChange={(e) => setAllocation(e.target.value)} className="w-full px-3 py-1.5 border border-gray-300 rounded text-sm" />
        <button onClick={handleCreate} disabled={!name || !owner} className="w-full px-3 py-2 bg-blue-600 text-white rounded text-sm font-medium hover:bg-blue-700 disabled:opacity-50">
          创建预算
        </button>
      </div>
    </div>
  );
}
