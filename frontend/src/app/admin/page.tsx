"use client";

import { useState } from "react";
import { useAccount, useWriteContract } from "wagmi";
import {
  useActiveSignerCount, useSignerList, useGlobalThreshold, useIsPaused,
  useIsEmergencyShutdown, useIsActiveSigner
} from "@/hooks/useTreasury";
import { ABIS, CONTRACTS } from "@/lib/contracts";

export default function AdminPage() {
  const { isConnected } = useAccount();

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">管理面板</h1>
        <p className="text-sm text-gray-500 mt-1">管理签名者、阈值和紧急控制</p>
      </div>

      {!isConnected ? (
        <div className="text-center py-10 text-gray-500">请连接钱包访问管理面板</div>
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
  const { data: signers } = useSignerList();
  const { data: activeCount } = useActiveSignerCount();
  const { writeContract } = useWriteContract();

  const [newSigner, setNewSigner] = useState("");

  const sigList = (signers as string[]) || [];
  const count = activeCount ? Number(activeCount) : 0;

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-6">
      <h2 className="text-lg font-semibold text-gray-900 mb-4">签名者管理（{count} 人活跃）</h2>

      <div className="space-y-2 mb-4">
        {sigList.map((signer, i) => (
          <SignerRow key={i} address={signer as `0x${string}`} />
        ))}
      </div>

      <div className="flex gap-2">
        <input type="text" placeholder="新签名者地址"
          value={newSigner} onChange={(e) => setNewSigner(e.target.value)}
          className="flex-1 px-3 py-1.5 border border-gray-300 rounded text-sm font-mono" />
        <button
          onClick={() => {
            writeContract({
              address: CONTRACTS.treasuryCore,
              abi: ABIS.treasuryCore,
              functionName: "addSigner",
              args: [newSigner as `0x${string}`],
            });
            setNewSigner("");
          }}
          disabled={!newSigner}
          className="px-4 py-1.5 bg-blue-600 text-white text-sm rounded hover:bg-blue-700 disabled:opacity-50">
          添加
        </button>
      </div>
    </div>
  );
}

function SignerRow({ address }: { address: `0x${string}` }) {
  const { data: isActive } = useIsActiveSigner(address);
  const { writeContract } = useWriteContract();

  return (
    <div className="flex items-center justify-between py-1.5 px-3 bg-gray-50 rounded">
      <span className="font-mono text-sm text-gray-700">{address}</span>
      <div className="flex items-center gap-2">
        <span className={`px-2 py-0.5 rounded text-xs ${isActive ? "bg-green-100 text-green-700" : "bg-red-100 text-red-700"}`}>
          {isActive ? "活跃" : "已移除"}
        </span>
        {isActive && (
          <button
            onClick={() => writeContract({
              address: CONTRACTS.treasuryCore,
              abi: ABIS.treasuryCore,
              functionName: "removeSigner",
              args: [address],
            })}
            className="text-xs text-red-600 hover:text-red-800">
            移除
          </button>
        )}
      </div>
    </div>
  );
}

function ThresholdControl() {
  const { data: threshold } = useGlobalThreshold();
  const { data: activeCount } = useActiveSignerCount();
  const { writeContract } = useWriteContract();
  const [newThreshold, setNewThreshold] = useState("");

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-6">
      <h2 className="text-lg font-semibold text-gray-900 mb-4">全局阈值</h2>
      <p className="text-sm text-gray-600 mb-3">
        当前: <span className="font-medium">{String(threshold)}</span> / <span className="font-medium">{String(activeCount)}</span> 签名者
      </p>
      <div className="flex gap-2">
        <input type="number" placeholder="新阈值"
          value={newThreshold} onChange={(e) => setNewThreshold(e.target.value)}
          className="w-32 px-3 py-1.5 border border-gray-300 rounded text-sm" />
        <button
          onClick={() => {
            writeContract({
              address: CONTRACTS.treasuryCore,
              abi: ABIS.treasuryCore,
              functionName: "setGlobalThreshold",
              args: [BigInt(newThreshold)],
            });
            setNewThreshold("");
          }}
          disabled={!newThreshold}
          className="px-4 py-1.5 bg-blue-600 text-white text-sm rounded hover:bg-blue-700 disabled:opacity-50">
          更新
        </button>
      </div>
    </div>
  );
}

function EmergencyControls() {
  const { data: isPaused } = useIsPaused();
  const { data: isShutdown } = useIsEmergencyShutdown();
  const { writeContract } = useWriteContract();

  return (
    <div className="bg-white border border-gray-200 rounded-lg p-6">
      <h2 className="text-lg font-semibold text-gray-900 mb-4">紧急控制</h2>
      <div className="flex gap-3">
        {!isShutdown && (
          <>
            <button
              onClick={() => writeContract({
                address: CONTRACTS.treasuryCore,
                abi: ABIS.treasuryCore,
                functionName: isPaused ? "unpause" : "pause",
              })}
              className={`px-4 py-2 rounded text-sm font-medium ${
                isPaused ? "bg-green-600 hover:bg-green-700" : "bg-yellow-600 hover:bg-yellow-700"
              } text-white`}>
              {isPaused ? "恢复" : "暂停"}
            </button>
            <button
              onClick={() => writeContract({
                address: CONTRACTS.treasuryCore,
                abi: ABIS.treasuryCore,
                functionName: "triggerEmergencyShutdown",
              })}
              className="px-4 py-2 bg-red-600 text-white rounded text-sm font-medium hover:bg-red-700">
              紧急关闭
            </button>
          </>
        )}
        {isShutdown && (
          <p className="text-red-600 text-sm font-medium">
            金库已紧急关闭，恢复资产需要合约交互。
          </p>
        )}
      </div>
    </div>
  );
}
