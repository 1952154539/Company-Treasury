"use client";

import { useState } from "react";
import { useAccount, useWriteContract } from "wagmi";
import {
  useActiveSignerCount, useSignerList, useGlobalThreshold, useIsPaused,
  useIsEmergencyShutdown, useIsActiveSigner
} from "@/hooks/useTreasury";
import { ABIS, CONTRACTS } from "@/lib/contracts";

export default function AdminPage() {
  const { isConnected, address } = useAccount();

  return (
    <div>
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-gray-900">Administration</h1>
        <p className="text-sm text-gray-500 mt-1">Manage signers, thresholds, and emergency controls</p>
      </div>

      {!isConnected ? (
        <div className="text-center py-10 text-gray-500">Connect wallet to access admin panel</div>
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
      <h2 className="text-lg font-semibold text-gray-900 mb-4">Signer Management ({count} active)</h2>

      <div className="space-y-2 mb-4">
        {sigList.map((signer, i) => (
          <SignerRow key={i} address={signer as `0x${string}`} />
        ))}
      </div>

      <div className="flex gap-2">
        <input
          type="text" placeholder="New signer address"
          value={newSigner} onChange={(e) => setNewSigner(e.target.value)}
          className="flex-1 px-3 py-1.5 border border-gray-300 rounded text-sm font-mono"
        />
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
          className="px-4 py-1.5 bg-blue-600 text-white text-sm rounded hover:bg-blue-700 disabled:opacity-50"
        >
          Add
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
          {isActive ? "Active" : "Inactive"}
        </span>
        {isActive && (
          <button
            onClick={() => writeContract({
              address: CONTRACTS.treasuryCore,
              abi: ABIS.treasuryCore,
              functionName: "removeSigner",
              args: [address],
            })}
            className="text-xs text-red-600 hover:text-red-800"
          >
            Remove
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
      <h2 className="text-lg font-semibold text-gray-900 mb-4">Global Threshold</h2>
      <p className="text-sm text-gray-600 mb-3">
        Current: <span className="font-medium">{String(threshold)}</span> of <span className="font-medium">{String(activeCount)}</span> signers required
      </p>
      <div className="flex gap-2">
        <input
          type="number" placeholder="New threshold"
          value={newThreshold} onChange={(e) => setNewThreshold(e.target.value)}
          className="w-32 px-3 py-1.5 border border-gray-300 rounded text-sm"
        />
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
          className="px-4 py-1.5 bg-blue-600 text-white text-sm rounded hover:bg-blue-700 disabled:opacity-50"
        >
          Update
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
      <h2 className="text-lg font-semibold text-gray-900 mb-4">Emergency Controls</h2>
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
              } text-white`}
            >
              {isPaused ? "Unpause" : "Pause"}
            </button>
            <button
              onClick={() => writeContract({
                address: CONTRACTS.treasuryCore,
                abi: ABIS.treasuryCore,
                functionName: "triggerEmergencyShutdown",
              })}
              className="px-4 py-2 bg-red-600 text-white rounded text-sm font-medium hover:bg-red-700"
            >
              Emergency Shutdown
            </button>
          </>
        )}
        {isShutdown && (
          <p className="text-red-600 text-sm font-medium">
            Treasury is in emergency shutdown. Recovery requires contract interaction.
          </p>
        )}
      </div>
    </div>
  );
}
