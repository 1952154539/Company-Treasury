"use client";

import { useReadContract } from "wagmi";
import { ABIS, CONTRACTS } from "@/lib/contracts";

export function useStream(streamId: bigint) {
  return useReadContract({
    address: CONTRACTS.streamingManager,
    abi: ABIS.streamingManager,
    functionName: "getStream",
    args: [streamId],
    query: { enabled: streamId > 0n },
  });
}

export function useStreamCount() {
  return useReadContract({
    address: CONTRACTS.streamingManager,
    abi: ABIS.streamingManager,
    functionName: "getStreamCount",
  });
}

export function useVestedAmount(streamId: bigint) {
  return useReadContract({
    address: CONTRACTS.streamingManager,
    abi: ABIS.streamingManager,
    functionName: "vestedAmount",
    args: [streamId],
    query: { enabled: streamId > 0n },
  });
}

export function useReleasableAmount(streamId: bigint) {
  return useReadContract({
    address: CONTRACTS.streamingManager,
    abi: ABIS.streamingManager,
    functionName: "releasableAmount",
    args: [streamId],
    query: { enabled: streamId > 0n },
  });
}

export function useTreasuryCore() {
  return useReadContract({
    address: CONTRACTS.streamingManager,
    abi: ABIS.streamingManager,
    functionName: "getTreasuryCore",
  });
}
