"use client";

import { useState } from "react";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import {
  useActiveSignerCount, useSignerList, useGlobalThreshold, useIsPaused,
  useIsEmergencyShutdown, useIsActiveSigner
} from "@/hooks/useTreasury";
import { useTxToast } from "@/hooks/useContractWrite";
import { ABIS, CONTRACTS } from "@/lib/contracts";
import { EmptyState, PageHeader } from "@/components/Skeleton";

export default function AdminPage() {
  const { isConnected } = useAccount();

  return (
    <div>
      <PageHeader title="管理面板" description="管理签名者、阈值和紧急控制" />

      {!isConnected ? (
        <EmptyState icon="🔐" title="请连接钱包" description="连接管理员钱包以访问管理面板" />
      ) : (
        <div className="space-y-6">
          <SignerManagement />
          <ThresholdControl />
          <EmergencyControls />
        </div>
      )}
    </div>
  );
}

function SignerManagement() {
  const { data: signers, isLoading } = useSignerList();
  const { data: activeCount } = useActiveSignerCount();
  const { writeContract, data: writeHash, status } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: writeHash });
  const toast = useTxToast();

  const [newSigner, setNewSigner] = useState("");
  const sigList = (signers as string[]) || [];
  const count = activeCount ? Number(activeCount) : 0;

  const handleAdd = () => {
    toast.submit("添加签名者");
    writeContract(
      {
        address: CONTRACTS.treasuryCore,
        abi: ABIS.treasuryCore,
        functionName: "addSigner",
        args: [newSigner as `0x${string}`],
      },
      {
        onSuccess: (hash) => {
          toast.confirm("添加签名者", hash);
          setNewSigner("");
        },
        onError: (err) => toast.fail("添加签名者", err),
      }
    );
  };

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-6">
      <h2 className="text-lg font-semibold text-gray-900 mb-1">签名者管理</h2>
      <p className="text-sm text-gray-500 mb-4">{count} 位签名者活跃</p>

      {isLoading ? (
        <div className="space-y-2 mb-4">
          {[1, 2, 3].map((i) => <div key={i} className="h-10 bg-gray-100 rounded animate-pulse-slow" />)}
        </div>
      ) : (
        <div className="space-y-2 mb-4">
          {sigList.map((signer, i) => (
            <SignerRow key={i} address={signer as `0x${string}`} />
          ))}
        </div>
      )}

      <div className="flex gap-2">
        <input type="text" placeholder="新签名者地址 (0x...)" value={newSigner}
          onChange={(e) => setNewSigner(e.target.value)}
          className="flex-1 px-3 py-1.5 border border-gray-300 rounded text-sm font-mono focus:outline-none focus:ring-2 focus:ring-blue-500" />
        <button
          onClick={handleAdd}
          disabled={!newSigner || status === "pending" || isConfirming}
          className="px-4 py-1.5 bg-blue-600 text-white text-sm rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          {status === "pending" || isConfirming ? "添加中..." : "添加"}
        </button>
      </div>
    </div>
  );
}

function SignerRow({ address }: { address: `0x${string}` }) {
  const { data: isActive, isLoading } = useIsActiveSigner(address);
  const { writeContract, data: writeHash, status } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: writeHash });
  const toast = useTxToast();

  if (isLoading) return <div className="h-10 bg-gray-100 rounded animate-pulse-slow" />;

  const handleRemove = () => {
    toast.submit("移除签名者");
    writeContract(
      {
        address: CONTRACTS.treasuryCore,
        abi: ABIS.treasuryCore,
        functionName: "removeSigner",
        args: [address],
      },
      {
        onSuccess: (hash) => toast.confirm("移除签名者", hash),
        onError: (err) => toast.fail("移除签名者", err),
      }
    );
  };

  return (
    <div className="flex items-center justify-between py-1.5 px-3 bg-gray-50 rounded">
      <span className="font-mono text-sm text-gray-700">{address.slice(0, 14)}...{address.slice(-6)}</span>
      <div className="flex items-center gap-2">
        <span className={`px-2 py-0.5 rounded text-xs font-medium ${isActive ? "bg-green-100 text-green-700" : "bg-red-100 text-red-700"}`}>
          {isActive ? "活跃" : "已移除"}
        </span>
        {isActive && (
          <button
            onClick={handleRemove}
            disabled={status === "pending" || isConfirming}
            className="text-xs text-red-600 hover:text-red-800 disabled:opacity-50 transition-colors"
          >
            {status === "pending" || isConfirming ? "移除中..." : "移除"}
          </button>
        )}
      </div>
    </div>
  );
}

function ThresholdControl() {
  const { data: threshold } = useGlobalThreshold();
  const { data: activeCount } = useActiveSignerCount();
  const { writeContract, data: writeHash, status } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: writeHash });
  const toast = useTxToast();
  const [newThreshold, setNewThreshold] = useState("");

  const handleUpdate = () => {
    toast.submit("更新阈值");
    writeContract(
      {
        address: CONTRACTS.treasuryCore,
        abi: ABIS.treasuryCore,
        functionName: "setGlobalThreshold",
        args: [BigInt(newThreshold)],
      },
      {
        onSuccess: (hash) => {
          toast.confirm("更新阈值", hash);
          setNewThreshold("");
        },
        onError: (err) => toast.fail("更新阈值", err),
      }
    );
  };

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-6">
      <h2 className="text-lg font-semibold text-gray-900 mb-1">全局阈值</h2>
      <p className="text-sm text-gray-600 mb-3">
        当前需要 <span className="font-medium text-gray-900">{String(threshold)}</span> / <span className="font-medium text-gray-900">{String(activeCount)}</span> 位签名者审批
      </p>
      <div className="flex gap-2">
        <input type="number" placeholder="新阈值" value={newThreshold}
          onChange={(e) => setNewThreshold(e.target.value)}
          className="w-32 px-3 py-1.5 border border-gray-300 rounded text-sm focus:outline-none focus:ring-2 focus:ring-blue-500" />
        <button
          onClick={handleUpdate}
          disabled={!newThreshold || status === "pending" || isConfirming}
          className="px-4 py-1.5 bg-blue-600 text-white text-sm rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
        >
          {status === "pending" || isConfirming ? "更新中..." : "更新阈值"}
        </button>
      </div>
    </div>
  );
}

function EmergencyControls() {
  const { data: isPaused } = useIsPaused();
  const { data: isShutdown } = useIsEmergencyShutdown();
  const { writeContract, data: writeHash, status } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: writeHash });
  const toast = useTxToast();

  const handlePause = () => {
    const label = isPaused ? "恢复金库" : "暂停金库";
    toast.submit(label);
    writeContract(
      {
        address: CONTRACTS.treasuryCore,
        abi: ABIS.treasuryCore,
        functionName: isPaused ? "unpause" : "pause",
      },
      {
        onSuccess: (hash) => toast.confirm(label, hash),
        onError: (err) => toast.fail(label, err),
      }
    );
  };

  const handleShutdown = () => {
    toast.submit("紧急关闭");
    writeContract(
      {
        address: CONTRACTS.treasuryCore,
        abi: ABIS.treasuryCore,
        functionName: "triggerEmergencyShutdown",
      },
      {
        onSuccess: (hash) => toast.confirm("紧急关闭", hash),
        onError: (err) => toast.fail("紧急关闭", err),
      }
    );
  };

  const isPending = status === "pending" || isConfirming;

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-6">
      <h2 className="text-lg font-semibold text-gray-900 mb-1">紧急控制</h2>
      <p className="text-sm text-gray-500 mb-4">暂停或紧急关闭金库操作，需管理员权限</p>
      <div className="flex gap-3">
        {!isShutdown ? (
          <>
            <button
              onClick={handlePause}
              disabled={isPending}
              className={`px-4 py-2 rounded text-sm font-medium transition-colors disabled:opacity-50 disabled:cursor-not-allowed ${
                isPaused ? "bg-green-600 hover:bg-green-700 text-white" : "bg-yellow-600 hover:bg-yellow-700 text-white"
              }`}
            >
              {isPending ? "处理中..." : isPaused ? "恢复金库" : "暂停金库"}
            </button>
            <button
              onClick={handleShutdown}
              disabled={isPending}
              className="px-4 py-2 bg-red-600 text-white rounded text-sm font-medium hover:bg-red-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
            >
              {isPending ? "处理中..." : "紧急关闭"}
            </button>
          </>
        ) : (
          <div className="p-3 bg-red-50 border border-red-200 rounded-lg">
            <p className="text-red-700 text-sm font-medium">
              金库已紧急关闭，所有资金转账已冻结。需通过 48 小时恢复流程提取资产。
            </p>
          </div>
        )}
      </div>
    </div>
  );
}
