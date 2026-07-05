"use client";

import { useReadContract, useWatchContractEvent } from "wagmi";
import { useQueryClient } from "@tanstack/react-query";
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

export function useStreamingEvents() {
  const queryClient = useQueryClient();

  useWatchContractEvent({
    address: CONTRACTS.streamingManager,
    abi: ABIS.streamingManager,
    eventName: "StreamCreated",
    onLogs: () => {
      queryClient.invalidateQueries({ queryKey: ["readContract"] });
    },
  });
  useWatchContractEvent({
    address: CONTRACTS.streamingManager,
    abi: ABIS.streamingManager,
    eventName: "StreamWithdrawn",
    onLogs: () => {
      queryClient.invalidateQueries({ queryKey: ["readContract"] });
    },
  });
}
