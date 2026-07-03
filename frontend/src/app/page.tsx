"use client";

import { useAccount } from "wagmi";
import { useETHBalance, useTransactionCount, useIsPaused, useIsEmergencyShutdown, useActiveSignerCount, useGlobalThreshold } from "@/hooks/useTreasury";
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
  const { data: txCount } = useTransactionCount();
  const { data: streamCount } = useStreamCount();
  const { data: strategyIds } = useStrategyIds();
  const { data: isPaused } = useIsPaused();
  const { data: isShutdown } = useIsEmergencyShutdown();
  const { data: signerCount } = useActiveSignerCount();
  const { data: threshold } = useGlobalThreshold();

  const ethFormatted = ethBalance ? Number(formatEther(ethBalance as bigint)).toFixed(4) : "0";
  const streamCountNum = streamCount ? Number(streamCount) : 0;
  const strategyCount = strategyIds ? (strategyIds as readonly string[]).length : 0;
  const txCountNum = txCount ? Number(txCount) : 0;

  return (
    <div>
      <div className="mb-8">
        <h1 className="text-2xl font-bold text-gray-900">Treasury Dashboard</h1>
        <p className="mt-1 text-sm text-gray-500">
          On-chain corporate treasury management system
        </p>
      </div>

      {!isConnected ? (
        <div className="text-center py-20">
          <h2 className="text-lg font-medium text-gray-600 mb-4">Connect your wallet to view treasury data</h2>
        </div>
      ) : (
        <>
          {(isPaused || isShutdown) && (
            <div className={`mb-6 p-4 rounded-lg ${isShutdown ? "bg-red-100 text-red-800" : "bg-yellow-100 text-yellow-800"}`}>
              <span className="font-bold">{isShutdown ? "EMERGENCY SHUTDOWN" : "PAUSED"}</span>
              {" — "}Some operations are restricted.
            </div>
          )}

          <dl className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4 mb-8">
            <StatCard label="ETH Balance" value={ethFormatted} unit="ETH" />
            <StatCard label="Active Signers" value={`${signerCount || 0} / ${threshold || 0}`} />
            <StatCard label="Active Streams" value={String(streamCountNum)} />
            <StatCard label="Transactions" value={String(txCountNum)} />
          </dl>

          <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
            <div className="bg-white rounded-lg border border-gray-200 p-6">
              <h3 className="text-sm font-medium text-gray-500">Yield Strategies</h3>
              <p className="mt-2 text-2xl font-semibold text-gray-900">{strategyCount}</p>
            </div>
            <div className="bg-white rounded-lg border border-gray-200 p-6">
              <h3 className="text-sm font-medium text-gray-500">Security Status</h3>
              <p className={`mt-2 text-lg font-semibold ${isShutdown ? "text-red-600" : isPaused ? "text-yellow-600" : "text-green-600"}`}>
                {isShutdown ? "Shutdown" : isPaused ? "Paused" : "Active"}
              </p>
            </div>
            <div className="bg-white rounded-lg border border-gray-200 p-6">
              <h3 className="text-sm font-medium text-gray-500">Quick Actions</h3>
              <div className="mt-3 space-y-2">
                <a href="/transactions" className="block text-sm text-blue-600 hover:text-blue-800">Propose Transaction →</a>
                <a href="/budgets" className="block text-sm text-blue-600 hover:text-blue-800">Manage Budgets →</a>
                <a href="/streams" className="block text-sm text-blue-600 hover:text-blue-800">View Streams →</a>
              </div>
            </div>
          </div>
        </>
      )}
    </div>
  );
}
