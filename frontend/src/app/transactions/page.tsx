"use client";

import { useState } from "react";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useTransaction, useTransactionApprovals, useSignerList, useIsPaused, useTransactionCount } from "@/hooks/useTreasury";
import { useTxToast } from "@/hooks/useContractWrite";
import { ABIS, CONTRACTS, TX_STATUS_LABELS } from "@/lib/contracts";
import { RowSkeleton, EmptyState, ErrorBanner, PageHeader } from "@/components/Skeleton";
import { formatEther, zeroAddress, parseEther } from "viem";

export default function TransactionsPage() {
  const { isConnected, address } = useAccount();
  const { data: isPaused } = useIsPaused();
  const { data: rawCount } = useTransactionCount();
  const count = rawCount ? Number(rawCount) : 0;
  const [selectedTx, setSelectedTx] = useState<bigint>(0n);

  return (
    <div>
      <PageHeader
        title="多签交易"
        description={count > 0 ? `共 ${count} 笔交易` : undefined}
        action={<ProposeForm />}
      />

      {isPaused && (
        <div className="mb-4 p-3 bg-yellow-50 border border-yellow-200 text-yellow-800 rounded-lg text-sm flex items-center gap-2">
          <span>⏸</span> 金库已暂停，无法新建提案。
        </div>
      )}

      {!isConnected ? (
        <EmptyState icon="🔐" title="请连接钱包" description="连接钱包后可以查看、审批和执行多签交易" />
      ) : count === 0 ? (
        <EmptyState icon="📝" title="暂无交易" description="创建第一笔多签提案来开始使用金库" />
      ) : (
        <div className="space-y-3">
          {Array.from({ length: Math.min(count, 20) }, (_, i) => count - i).map((id) => (
            <TransactionCard
              key={id}
              txId={BigInt(id)}
              isSelected={selectedTx === BigInt(id)}
              onClick={() => setSelectedTx(selectedTx === BigInt(id) ? 0n : BigInt(id))}
              userAddress={address}
            />
          ))}
        </div>
      )}
    </div>
  );
}

function TransactionCard({
  txId,
  isSelected,
  onClick,
  userAddress,
}: {
  txId: bigint;
  isSelected: boolean;
  onClick: () => void;
  userAddress?: `0x${string}`;
}) {
  const { data: tx, isLoading, error } = useTransaction(txId);
  const { data: approvals } = useTransactionApprovals(txId);

  if (error) return <ErrorBanner message={`加载交易 #${String(txId)} 失败`} />;
  if (isLoading || !tx) return <div className="bg-white border border-gray-200 rounded-lg p-4 animate-pulse-slow"><div className="h-5 bg-gray-200 rounded w-1/3" /></div>;

  const t = tx as Record<string, unknown>;
  const status = Number(t.status);
  const value = t.value as bigint;
  const approvalsArr = approvals as boolean[] | undefined;
  const approvedCount = approvalsArr ? approvalsArr.filter(Boolean).length : 0;
  const required = Number(t.approvalsRequired);

  return (
    <div className="bg-white border border-gray-200 rounded-lg hover:border-gray-300 transition-colors">
      <button onClick={onClick} className="w-full text-left p-4">
        <div className="flex items-center justify-between">
          <div>
            <span className="font-mono text-sm text-gray-900">#{String(txId)}</span>
            <span className="ml-3 text-sm text-gray-600">{t.description as string}</span>
          </div>
          <div className="flex items-center gap-3">
            <span className="text-sm text-gray-500">
              {approvedCount}/{required} 已审批
            </span>
            <span className={`px-2 py-0.5 rounded text-xs font-medium ${
              status === 3 ? "bg-green-100 text-green-700" :
              status === 4 ? "bg-red-100 text-red-700" :
              status === 5 ? "bg-red-100 text-red-700" :
              "bg-blue-100 text-blue-700"
            }`}>
              {TX_STATUS_LABELS[status] || "未知"}
            </span>
            {value > 0n && (
              <span className="text-sm font-medium text-gray-700">{formatEther(value)} ETH</span>
            )}
          </div>
        </div>
      </button>
      {isSelected && <TxDetail txId={txId} userAddress={userAddress} />}
    </div>
  );
}

function TxDetail({ txId, userAddress }: { txId: bigint; userAddress?: `0x${string}` }) {
  const { data: tx } = useTransaction(txId);
  const { data: approvals } = useTransactionApprovals(txId);
  const { data: signers } = useSignerList();
  const { writeContract, data: writeHash, status, reset } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: writeHash });
  const toast = useTxToast();

  if (!tx) return null;
  const t = tx as Record<string, unknown>;
  const statusNum = Number(t.status);
  const signerList = (signers as string[]) || [];
  const approvalsArr = (approvals as boolean[]) || [];

  const handleAction = (fn: string, args: unknown[], label: string) => {
    toast.submit(label);
    writeContract(
      {
        address: CONTRACTS.treasuryCore,
        abi: ABIS.treasuryCore,
        functionName: fn,
        args,
      },
      {
        onSuccess: (hash) => {
          toast.confirm(label, hash);
        },
        onError: (err) => {
          toast.fail(label, err);
        },
      }
    );
  };

  return (
    <div className="border-t border-gray-100 p-4 space-y-4">
      <div className="grid grid-cols-2 gap-3 text-sm">
        <div><span className="text-gray-500">目标地址:</span> <span className="font-mono text-gray-700">{(t.target as string)?.slice(0, 10)}...{(t.target as string)?.slice(-6)}</span></div>
        <div><span className="text-gray-500">提案人:</span> <span className="font-mono text-gray-700">{(t.proposer as string)?.slice(0, 10)}...</span></div>
        <div><span className="text-gray-500">延迟时间:</span> <span className="text-gray-700">{String(t.minDelay)} 秒</span></div>
        <div><span className="text-gray-500">关联预算:</span> <span className="font-mono text-gray-700">{(t.budgetId as string) === "0x0000000000000000000000000000000000000000000000000000000000000000" ? "无" : (t.budgetId as string)?.slice(0, 10) + "..."}</span></div>
      </div>

      <div>
        <h4 className="text-sm font-medium text-gray-700 mb-2">审批进度 ({approvalsArr.filter(Boolean).length}/{t.approvalsRequired as number})</h4>
        <div className="flex gap-2 flex-wrap">
          {signerList.map((signer, i) => (
            <div
              key={i}
              className={`px-2 py-1 rounded text-xs font-mono ${
                approvalsArr[i] ? "bg-green-100 text-green-700" : "bg-gray-100 text-gray-400"
              }`}
            >
              {signer.slice(0, 6)}...{signer.slice(-4)}
            </div>
          ))}
        </div>
      </div>

      {statusNum === 0 && userAddress && (
        <div className="flex gap-2">
          <button
            onClick={() => handleAction("approveTransaction", [txId], "审批交易")}
            disabled={status === "pending" || isConfirming}
            className="px-3 py-1.5 bg-blue-600 text-white text-sm rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {status === "pending" || isConfirming ? "提交中..." : "审批"}
          </button>
          <button
            onClick={() => handleAction("cancelTransaction", [txId], "取消交易")}
            disabled={status === "pending" || isConfirming}
            className="px-3 py-1.5 bg-red-100 text-red-700 text-sm rounded hover:bg-red-200 disabled:opacity-50"
          >
            取消
          </button>
        </div>
      )}
      {statusNum === 2 && (
        <button
          onClick={() => handleAction("executeTransaction", [txId], "执行交易")}
          disabled={status === "pending" || isConfirming}
          className="px-3 py-1.5 bg-green-600 text-white text-sm rounded hover:bg-green-700 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          {status === "pending" || isConfirming ? "提交中..." : "执行"}
        </button>
      )}
    </div>
  );
}

function ProposeForm() {
  const { writeContract, data: writeHash, status } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: writeHash });
  const toast = useTxToast();
  const [target, setTarget] = useState("");
  const [value, setValue] = useState("");
  const [description, setDescription] = useState("");
  const [budgetId, setBudgetId] = useState("");
  const [showForm, setShowForm] = useState(false);

  const handlePropose = () => {
    if (!target) return;
    toast.submit("发起提案");
    writeContract(
      {
        address: CONTRACTS.treasuryCore,
        abi: ABIS.treasuryCore,
        functionName: "proposeTransaction",
        args: [
          target as `0x${string}` || zeroAddress,
          value ? parseEther(value) : 0n,
          "0x",
          0n,
          0n,
          description || "Untitled",
          "0x0000000000000000000000000000000000000000000000000000000000000000",
          (budgetId || "0x0000000000000000000000000000000000000000000000000000000000000000") as `0x${string}`,
          value ? parseEther(value) : 0n,
        ],
      },
      {
        onSuccess: (hash) => {
          toast.confirm("发起提案", hash);
          setShowForm(false);
          setTarget("");
          setValue("");
          setDescription("");
          setBudgetId("");
        },
        onError: (err) => {
          toast.fail("发起提案", err);
        },
      }
    );
  };

  return (
    <div>
      {!showForm && (
        <button
          onClick={() => setShowForm(true)}
          className="px-4 py-2 bg-blue-600 text-white text-sm font-medium rounded-lg hover:bg-blue-700 transition-colors"
        >
          + 新建提案
        </button>
      )}
      {showForm && (
        <div className="bg-white border border-gray-200 rounded-lg p-4 w-full max-w-md shadow-lg">
          <h3 className="text-sm font-semibold text-gray-900 mb-3">发起提案</h3>
          <div className="space-y-2">
            <input type="text" placeholder="目标地址 (0x...)" value={target}
              onChange={(e) => setTarget(e.target.value)}
              className="w-full px-3 py-1.5 border border-gray-300 rounded text-sm font-mono focus:outline-none focus:ring-2 focus:ring-blue-500" />
            <input type="text" placeholder="金额 (ETH)" value={value}
              onChange={(e) => setValue(e.target.value)}
              className="w-full px-3 py-1.5 border border-gray-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            <input type="text" placeholder="描述" value={description}
              onChange={(e) => setDescription(e.target.value)}
              className="w-full px-3 py-1.5 border border-gray-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
            <input type="text" placeholder="预算ID (可选)" value={budgetId}
              onChange={(e) => setBudgetId(e.target.value)}
              className="w-full px-3 py-1.5 border border-gray-300 rounded text-sm font-mono focus:outline-none focus:ring-2 focus:ring-blue-500" />
            <div className="flex gap-2">
              <button
                onClick={handlePropose}
                disabled={!target || status === "pending" || isConfirming}
                className="flex-1 px-3 py-2 bg-blue-600 text-white rounded text-sm font-medium hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
              >
                {status === "pending" || isConfirming ? "提交中..." : "发起提案"}
              </button>
              <button
                onClick={() => setShowForm(false)}
                className="px-3 py-2 bg-gray-100 text-gray-700 rounded text-sm font-medium hover:bg-gray-200"
              >
                取消
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
