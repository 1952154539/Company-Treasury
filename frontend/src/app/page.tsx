"use client";

import { useAccount } from "wagmi";
import { useETHBalance, useIsPaused, useIsEmergencyShutdown, useActiveSignerCount, useGlobalThreshold } from "@/hooks/useTreasury";
import { useStreamCount } from "@/hooks/useStreaming";
import { useStrategyIds } from "@/hooks/useYield";
import { formatEther } from "viem";

function StatCard({ label, value, unit }: { label: string; value: string; unit?: string }) {
  return (
    <div className="bg-white rounded-lg border border-gray-200 p-6">
      <dt className="text-sm font-medium text-gray-500 truncate">{label}</dt>
      <dd className="mt-2 text-3xl font-semibold text-gray-900">
        {value}
        {unit && <span className="text-lg text-gray-400 ml-1">{unit}</span>}
      </dd>
    </div>
  );
}

export default function DashboardPage() {
  const { isConnected } = useAccount();
  const { data: ethBalance } = useETHBalance();
  const { data: streamCount } = useStreamCount();
  const { data: strategyIds } = useStrategyIds();
  const { data: isPaused } = useIsPaused();
  const { data: isShutdown } = useIsEmergencyShutdown();
  const { data: signerCount } = useActiveSignerCount();
  const { data: threshold } = useGlobalThreshold();

  const ethFormatted = ethBalance ? Number(formatEther(ethBalance as bigint)).toFixed(4) : "0";
  const streamCountNum = streamCount ? Number(streamCount) : 0;
  const strategyCount = strategyIds ? (strategyIds as readonly string[]).length : 0;
  return (
    <div>
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-gray-900">金库仪表盘</h1>
        <p className="mt-1 text-sm text-gray-500">链上企业金库管理系统</p>
      </div>

      {!isConnected ? (
        <div className="text-center py-20">
          <h2 className="text-lg font-medium text-gray-600 mb-4">请连接钱包查看金库数据</h2>
        </div>
      ) : (
        <>
          {(isPaused || isShutdown) && (
            <div className={`mb-6 p-4 rounded-lg ${isShutdown ? "bg-red-100 text-red-800" : "bg-yellow-100 text-yellow-800"}`}>
              <span className="font-bold">{isShutdown ? "⚠ 紧急关闭" : "⏸ 已暂停"}</span>
              {" — "}部分操作受限。
            </div>
          )}

          <dl className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4 mb-8">
            <StatCard label="ETH 余额" value={ethFormatted} unit="ETH" />
            <StatCard label="签名者" value={`${signerCount || 0} / ${threshold || 0}`} />
            <StatCard label="活跃流支付" value={String(streamCountNum)} />
            <StatCard label="收益策略" value={String(strategyCount)} />
          </dl>

          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <div className="bg-white rounded-lg border border-gray-200 p-6">
              <h3 className="text-sm font-medium text-gray-500">收益策略</h3>
              <p className="mt-2 text-2xl font-semibold text-gray-900">{strategyCount}</p>
            </div>
            <div className="bg-white rounded-lg border border-gray-200 p-6">
              <h3 className="text-sm font-medium text-gray-500">安全状态</h3>
              <p className={`mt-2 text-lg font-semibold ${isShutdown ? "text-red-600" : isPaused ? "text-yellow-600" : "text-green-600"}`}>
                {isShutdown ? "已关闭" : isPaused ? "已暂停" : "正常"}
              </p>
            </div>
            <div className="bg-white rounded-lg border border-gray-200 p-6">
              <h3 className="text-sm font-medium text-gray-500">快捷操作</h3>
              <div className="mt-3 space-y-2">
                <a href="/transactions" className="block text-sm text-blue-600 hover:text-blue-800">发起提案 →</a>
                <a href="/budgets" className="block text-sm text-blue-600 hover:text-blue-800">管理预算 →</a>
                <a href="/streams" className="block text-sm text-blue-600 hover:text-blue-800">查看流支付 →</a>
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
