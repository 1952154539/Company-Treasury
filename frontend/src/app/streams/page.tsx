"use client";

import { useAccount, useWriteContract } from "wagmi";
import { useStreamCount, useStream, useVestedAmount, useReleasableAmount } from "@/hooks/useStreaming";
import { ABIS, CONTRACTS } from "@/lib/contracts";
import { formatEther } from "viem";

export default function StreamsPage() {
  const { isConnected } = useAccount();
  const { data: streamCount } = useStreamCount();
  const count = streamCount ? Number(streamCount) : 0;

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">流支付</h1>
        <p className="text-sm text-gray-500 mt-1">共 {count} 个活跃流</p>
      </div>

      {!isConnected ? (
        <div className="text-center py-10 text-gray-500">请连接钱包查看流支付</div>
      ) : count === 0 ? (
        <div className="text-center py-10 text-gray-500">暂无流支付</div>
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
  const { data: stream } = useStream(streamId);
  const { data: vested } = useVestedAmount(streamId);
  const { data: releasable } = useReleasableAmount(streamId);
  const { writeContract } = useWriteContract();

  if (!stream) return null;
  const s = stream as Record<string, unknown>;
  const total = s.totalAmount as bigint;
  const vestedAmt = vested as bigint || 0n;
  const releaseAmt = releasable as bigint || 0n;
  const pct = total > 0n ? Number((vestedAmt * 100n) / total) : 0;

  const handleWithdraw = () => {
    writeContract({
      address: CONTRACTS.streamingManager,
      abi: ABIS.streamingManager,
      functionName: "withdrawFromStream",
      args: [streamId],
    });
  };

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-4">
      <div className="flex items-center justify-between">
        <div>
          <span className="font-mono text-sm text-gray-900">流 #{String(streamId)}</span>
          <span className="ml-3 text-sm text-gray-600">收款方: {(s.recipient as string)?.slice(0, 8)}...</span>
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
          <span>已释放: {formatEther(vestedAmt)}</span>
          <span>{pct}%</span>
        </div>
        <div className="w-full h-2 bg-gray-200 rounded-full overflow-hidden">
          <div className="h-full bg-green-500 rounded-full transition-all" style={{ width: `${pct}%` }} />
        </div>
      </div>

      {releaseAmt > 0n && (
        <div className="mt-3 flex justify-between items-center">
          <span className="text-sm text-gray-600">可提取: {formatEther(releaseAmt)}</span>
          <button onClick={handleWithdraw} className="px-3 py-1 bg-green-600 text-white text-xs rounded hover:bg-green-700">
            提现
          </button>
        </div>
      )}
    </div>
  );
}
