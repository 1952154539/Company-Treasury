"use client";

import { useAccount } from "wagmi";
import { useETHBalance, useIsPaused, useIsEmergencyShutdown, useActiveSignerCount, useGlobalThreshold } from "@/hooks/useTreasury";
import { useStreamCount } from "@/hooks/useStreaming";
import { useStrategyIds } from "@/hooks/useYield";
import { CardSkeleton } from "@/components/Skeleton";
import { ActivityOverview, BudgetPieChart, StrategyRiskBar } from "@/components/Analytics";
import { formatEther } from "viem";

function StatCard({ label, value, unit, loading }: { label: string; value: string; unit?: string; loading?: boolean }) {
  if (loading) return <CardSkeleton />;
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
  const { data: ethBalance, isLoading: ethLoading } = useETHBalance();
  const { data: streamCount, isLoading: streamLoading } = useStreamCount();
  const { data: strategyIds, isLoading: strategyLoading } = useStrategyIds();
  const { data: isPaused } = useIsPaused();
  const { data: isShutdown } = useIsEmergencyShutdown();
  const { data: signerCount, isLoading: signerLoading } = useActiveSignerCount();
  const { data: threshold, isLoading: thresholdLoading } = useGlobalThreshold();

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
          <div className="text-4xl mb-4">🏦</div>
          <h2 className="text-lg font-medium text-gray-600 mb-2">请连接钱包查看金库数据</h2>
          <p className="text-sm text-gray-400">连接钱包后可以查看金库余额、审批交易、管理预算等</p>
        </div>
      ) : (
        <>
          {(isPaused || isShutdown) && (
            <div className={`mb-6 p-4 rounded-lg border ${isShutdown ? "bg-red-50 border-red-200 text-red-800" : "bg-yellow-50 border-yellow-200 text-yellow-800"}`}>
              <div className="flex items-center gap-2">
                <span className="font-bold text-lg">{isShutdown ? "⚠" : "⏸"}</span>
                <div>
                  <p className="font-bold">{isShutdown ? "紧急关闭" : "已暂停"}</p>
                  <p className="text-sm opacity-80">{isShutdown ? "所有资金转账已冻结，需通过 48h 恢复流程提取资产" : "新建提案和支出操作已暂停，审批功能正常"}</p>
                </div>
              </div>
            </div>
          )}

          <dl className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4 mb-8">
            <StatCard label="ETH 余额" value={ethFormatted} unit="ETH" loading={ethLoading} />
            <StatCard label="签名者" value={`${signerCount || 0} / ${threshold || 0}`} loading={signerLoading || thresholdLoading} />
            <StatCard label="活跃流支付" value={String(streamCountNum)} loading={streamLoading} />
            <StatCard label="收益策略" value={String(strategyCount)} loading={strategyLoading} />
          </dl>

          <div className="grid grid-cols-1 gap-6 lg:grid-cols-2">
            <div className="bg-white rounded-lg border border-gray-200 p-6">
              <h3 className="text-sm font-semibold text-gray-900 mb-4">金库概览</h3>
              <div className="space-y-3">
                <div className="flex justify-between text-sm">
                  <span className="text-gray-500">安全状态</span>
                  <span className={`font-medium ${isShutdown ? "text-red-600" : isPaused ? "text-yellow-600" : "text-green-600"}`}>
                    {isShutdown ? "已关闭" : isPaused ? "已暂停" : "正常运行"}
                  </span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-gray-500">多签阈值</span>
                  <span className="font-medium text-gray-900">{String(signerCount || 0)} 位签名者, 需 {String(threshold || 0)} 人审批</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-gray-500">流支付数量</span>
                  <span className="font-medium text-gray-900">{streamCountNum} 个活跃流</span>
                </div>
                <div className="flex justify-between text-sm">
                  <span className="text-gray-500">收益策略</span>
                  <span className="font-medium text-gray-900">{strategyCount} 个已注册</span>
                </div>
              </div>
            </div>

            <div className="bg-white rounded-lg border border-gray-200 p-6">
              <h3 className="text-sm font-semibold text-gray-900 mb-4">快捷操作</h3>
              <div className="grid grid-cols-2 gap-3">
                <a href="/transactions" className="flex flex-col items-center p-4 rounded-lg border border-gray-200 hover:border-blue-300 hover:bg-blue-50 transition-colors">
                  <span className="text-2xl mb-1">📝</span>
                  <span className="text-sm font-medium text-gray-700">发起提案</span>
                  <span className="text-xs text-gray-400 mt-0.5">创建多签交易</span>
                </a>
                <a href="/budgets" className="flex flex-col items-center p-4 rounded-lg border border-gray-200 hover:border-green-300 hover:bg-green-50 transition-colors">
                  <span className="text-2xl mb-1">💰</span>
                  <span className="text-sm font-medium text-gray-700">管理预算</span>
                  <span className="text-xs text-gray-400 mt-0.5">部门资金分配</span>
                </a>
                <a href="/streams" className="flex flex-col items-center p-4 rounded-lg border border-gray-200 hover:border-purple-300 hover:bg-purple-50 transition-colors">
                  <span className="text-2xl mb-1">🌊</span>
                  <span className="text-sm font-medium text-gray-700">流支付</span>
                  <span className="text-xs text-gray-400 mt-0.5">线性释放资金</span>
                </a>
                <a href="/yield" className="flex flex-col items-center p-4 rounded-lg border border-gray-200 hover:border-orange-300 hover:bg-orange-50 transition-colors">
                  <span className="text-2xl mb-1">📈</span>
                  <span className="text-sm font-medium text-gray-700">收益策略</span>
                  <span className="text-xs text-gray-400 mt-0.5">ERC-4626 理财</span>
                </a>
              </div>
            </div>
          </div>

          <div className="grid grid-cols-1 gap-6 lg:grid-cols-2 mt-8">
            <ActivityOverview />
            <StrategyRiskBar />
          </div>
        </>
      )}
    </div>
  );
}
