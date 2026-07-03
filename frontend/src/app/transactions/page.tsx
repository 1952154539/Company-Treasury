"use client";

import { useState } from "react";
import { useAccount, useWriteContract } from "wagmi";
import { useTransactionCount, useTransaction, useTransactionApprovals, useIsApproved, useSignerList, useGlobalThreshold, useIsPaused } from "@/hooks/useTreasury";
import { ABIS, CONTRACTS, TX_STATUS_LABELS } from "@/lib/contracts";
import { formatEther, zeroAddress, parseEther } from "viem";

export default function TransactionsPage() {
  const { isConnected, address } = useAccount();
  const { data: txCount } = useTransactionCount();
  const { data: signers } = useSignerList();
  const { data: isPaused } = useIsPaused();
  const [selectedTx, setSelectedTx] = useState<bigint>(0n);

  const count = txCount ? Number(txCount) : 0;

  return (
    <div>
      <div className="flex items-center justify-between mb-6">
        <div>
          <h1 className="text-2xl font-bold text-gray-900">Transactions</h1>
          <p className="text-sm text-gray-500 mt-1">
            {count} total transactions
          </p>
        </div>
        <ProposeForm />
      </div>

      {isPaused && (
        <div className="mb-4 p-3 bg-yellow-100 text-yellow-800 rounded-lg text-sm">
          Treasury is paused. New proposals are blocked.
        </div>
      )}

      {!isConnected ? (
        <div className="text-center py-10 text-gray-500">Connect wallet to view transactions</div>
      ) : count === 0 ? (
        <div className="text-center py-10 text-gray-500">No transactions yet</div>
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
  const { data: tx } = useTransaction(txId);
  const { data: approvals } = useTransactionApprovals(txId);

  if (!tx) return null;
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
              {approvedCount}/{required} approved
            </span>
            <span className={`px-2 py-0.5 rounded text-xs font-medium ${
              status === 3 ? "bg-green-100 text-green-700" :
              status === 4 ? "bg-red-100 text-red-700" :
              status === 5 ? "bg-red-100 text-red-700" :
              "bg-blue-100 text-blue-700"
            }`}>
              {TX_STATUS_LABELS[status] || "Unknown"}
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
  const { writeContract } = useWriteContract();

  if (!tx) return null;
  const t = tx as Record<string, unknown>;
  const status = Number(t.status);
  const signerList = (signers as string[]) || [];
  const approvalsArr = (approvals as boolean[]) || [];

  const handleApprove = () => {
    writeContract({
      address: CONTRACTS.treasuryCore,
      abi: ABIS.treasuryCore,
      functionName: "approveTransaction",
      args: [txId],
    });
  };

  const handleExecute = () => {
    writeContract({
      address: CONTRACTS.treasuryCore,
      abi: ABIS.treasuryCore,
      functionName: "executeTransaction",
      args: [txId],
    });
  };

  const handleCancel = () => {
    writeContract({
      address: CONTRACTS.treasuryCore,
      abi: ABIS.treasuryCore,
      functionName: "cancelTransaction",
      args: [txId],
    });
  };

  return (
    <div className="border-t border-gray-100 p-4 space-y-4">
      <div className="grid grid-cols-2 gap-3 text-sm">
        <div><span className="text-gray-500">Target:</span> <span className="font-mono text-gray-700">{(t.target as string)?.slice(0, 10)}...</span></div>
        <div><span className="text-gray-500">Proposer:</span> <span className="font-mono text-gray-700">{(t.proposer as string)?.slice(0, 10)}...</span></div>
        <div><span className="text-gray-500">Min Delay:</span> <span className="text-gray-700">{String(t.minDelay)}s</span></div>
        <div><span className="text-gray-500">Budget:</span> <span className="font-mono text-gray-700">{(t.budgetId as string)?.slice(0, 10)}...</span></div>
      </div>

      {/* Approval Progress */}
      <div>
        <h4 className="text-sm font-medium text-gray-700 mb-2">Approvals ({approvalsArr.filter(Boolean).length}/{t.approvalsRequired as number})</h4>
        <div className="flex gap-2 flex-wrap">
          {signerList.map((signer, i) => (
            <div
              key={i}
              className={`px-2 py-1 rounded text-xs font-mono ${
                approvalsArr[i] ? "bg-green-100 text-green-700" : "bg-gray-100 text-gray-400"
              }`}
            >
              {signer.slice(0, 6)}
            </div>
          ))}
        </div>
      </div>

      {/* Actions */}
      {status === 0 && userAddress && (
        <div className="flex gap-2">
          <button onClick={handleApprove} className="px-3 py-1.5 bg-blue-600 text-white text-sm rounded hover:bg-blue-700">
            Approve
          </button>
          <button onClick={handleCancel} className="px-3 py-1.5 bg-red-100 text-red-700 text-sm rounded hover:bg-red-200">
            Cancel
          </button>
        </div>
      )}
      {status === 2 && (
        <button onClick={handleExecute} className="px-3 py-1.5 bg-green-600 text-white text-sm rounded hover:bg-green-700">
          Execute
        </button>
      )}
    </div>
  );
}

function ProposeForm() {
  const { writeContract } = useWriteContract();
  const [target, setTarget] = useState("");
  const [value, setValue] = useState("");
  const [description, setDescription] = useState("");
  const [budgetId, setBudgetId] = useState("");

  const handlePropose = () => {
    writeContract({
      address: CONTRACTS.treasuryCore,
      abi: ABIS.treasuryCore,
      functionName: "proposeTransaction",
      args: [
        target as `0x${string}` || zeroAddress,
        value ? parseEther(value) : 0n,
        "0x",
        0n,
        0n,
        description,
        "0x0000000000000000000000000000000000000000000000000000000000000000",
        (budgetId || "0x0000000000000000000000000000000000000000000000000000000000000000") as `0x${string}`,
        value ? parseEther(value) : 0n,
      ],
    });
  };

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4 w-full max-w-md">
      <h3 className="text-sm font-semibold text-gray-900 mb-3">Propose Transaction</h3>
      <div className="space-y-2">
        <input
          type="text" placeholder="Target address (0x...)" value={target}
          onChange={(e) => setTarget(e.target.value)}
          className="w-full px-3 py-1.5 border border-gray-300 rounded text-sm font-mono"
        />
        <input
          type="text" placeholder="Value (ETH)" value={value}
          onChange={(e) => setValue(e.target.value)}
          className="w-full px-3 py-1.5 border border-gray-300 rounded text-sm"
        />
        <input
          type="text" placeholder="Description" value={description}
          onChange={(e) => setDescription(e.target.value)}
          className="w-full px-3 py-1.5 border border-gray-300 rounded text-sm"
        />
        <input
          type="text" placeholder="Budget ID (optional)" value={budgetId}
          onChange={(e) => setBudgetId(e.target.value)}
          className="w-full px-3 py-1.5 border border-gray-300 rounded text-sm font-mono"
        />
        <button
          onClick={handlePropose}
          disabled={!target}
          className="w-full px-3 py-2 bg-blue-600 text-white rounded text-sm font-medium hover:bg-blue-700 disabled:opacity-50"
        >
          Propose
        </button>
      </div>
    </div>
  );
}
