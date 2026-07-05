"use client";

import { useState } from "react";
import { useAccount, useWriteContract, useWaitForTransactionReceipt } from "wagmi";
import { useStreamCount, useStream, useVestedAmount, useReleasableAmount } from "@/hooks/useStreaming";
import { useTxToast } from "@/hooks/useContractWrite";
import { ABIS, CONTRACTS } from "@/lib/contracts";
import { RowSkeleton, EmptyState, PageHeader } from "@/components/Skeleton";
import { formatEther } from "viem";

export default function StreamsPage() {
  const { isConnected } = useAccount();
  const { data: streamCount, isLoading } = useStreamCount();
  const count = streamCount ? Number(streamCount) : 0;

  return (
    <div>
      <PageHeader
        title="流支付"
        description={count > 0 ? `共 ${count} 个活跃流` : undefined}
      />

      {!isConnected ? (
        <EmptyState icon="🔐" title="请连接钱包" description="连接钱包后可查看和管理流支付" />
      ) : isLoading ? (
        <RowSkeleton lines={4} />
      ) : count === 0 ? (
        <EmptyState icon="🌊" title="暂无流支付" description="创建一个流支付来开始线性释放资金" />
      ) : (
        <div className="space-y-3">
          {Array.from({ length: Math.min(count, 20) }, (_, i) => i + 1).map((id) => (
            <StreamCard key={id} streamId={BigInt(id)} />
          ))}
        </div>
      )}
    </div>
  );
}

function StreamCard({ streamId }: { streamId: bigint }) {
  const { data: stream, isLoading, error } = useStream(streamId);
  const { data: vested } = useVestedAmount(streamId);
  const { data: releasable } = useReleasableAmount(streamId);
  const { writeContract, data: writeHash, status } = useWriteContract();
  const { isLoading: isConfirming } = useWaitForTransactionReceipt({ hash: writeHash });
  const toast = useTxToast();

  if (error) return <div className="bg-red-50 border border-red-200 rounded-lg p-4 text-sm text-red-800">加载流 #{String(streamId)} 失败</div>;
  if (isLoading || !stream) return <div className="bg-white border border-gray-200 rounded-lg p-4 animate-pulse-slow"><div className="h-5 bg-gray-200 rounded w-1/3" /></div>;

  const s = stream as Record<string, unknown>;
  const total = s.totalAmount as bigint;
  const vestedAmt = vested as bigint || 0n;
  const releaseAmt = releasable as bigint || 0n;
  const pct = total > 0n ? Number((vestedAmt * 100n) / total) : 0;

  const handleWithdraw = () => {
    toast.submit("提现流支付");
    writeContract(
      {
        address: CONTRACTS.streamingManager,
        abi: ABIS.streamingManager,
        functionName: "withdrawFromStream",
        args: [streamId],
      },
      {
        onSuccess: (hash) => toast.confirm("提现流支付", hash),
        onError: (err) => toast.fail("提现流支付", err),
      }
    );
  };

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4 hover:border-gray-300 transition-colors">
      <div className="flex items-center justify-between">
        <div>
          <span className="font-mono text-sm text-gray-900">流 #{String(streamId)}</span>
          <span className="ml-3 text-sm text-gray-600">收款方: {(s.recipient as string)?.slice(0, 8)}...{(s.recipient as string)?.slice(-4)}</span>
        </div>
        <div className="flex items-center gap-4">
          <span className="text-sm text-gray-500">{formatEther(total)} 总额</span>
          <span className={`px-2 py-0.5 rounded text-xs font-medium ${(s.active as boolean) ? "bg-green-100 text-green-700" : "bg-gray-100 text-gray-500"}`}>
            {(s.active as boolean) ? "活跃" : "已结束"}
          </span>
        </div>
      </div>

      <div className="mt-3">
        <div className="flex justify-between text-xs text-gray-500 mb-1">
          <span>已释放: {formatEther(vestedAmt)} / {formatEther(total)}</span>
          <span>{pct}%</span>
        </div>
        <div className="w-full h-2 bg-gray-200 rounded-full overflow-hidden">
          <div className="h-full bg-green-500 rounded-full transition-all duration-500" style={{ width: `${pct}%` }} />
        </div>
      </div>

      {releaseAmt > 0n && (
        <div className="mt-3 flex justify-between items-center">
          <span className="text-sm text-gray-600">可提取: {formatEther(releaseAmt)}</span>
          <button
            onClick={handleWithdraw}
            disabled={status === "pending" || isConfirming}
            className="px-3 py-1 bg-green-600 text-white text-xs rounded hover:bg-green-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            {status === "pending" || isConfirming ? "提现中..." : "提现"}
          </button>
        </div>
      )}
    </div>
  );
}
