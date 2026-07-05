"use client";

import { useReadContract, useWatchContractEvent } from "wagmi";
import { useQueryClient } from "@tanstack/react-query";
import { ABIS, CONTRACTS } from "@/lib/contracts";

export function useStrategy(strategyId: `0x${string}`) {
  return useReadContract({
    address: CONTRACTS.yieldManager,
    abi: ABIS.yieldManager,
    functionName: "getStrategy",
    args: [strategyId],
    query: { enabled: !!strategyId && strategyId !== "0x0000000000000000000000000000000000000000000000000000000000000000" },
  });
}

export function useStrategyIds() {
  return useReadContract({
    address: CONTRACTS.yieldManager,
    abi: ABIS.yieldManager,
    functionName: "getStrategyIds",
  });
}

export function usePosition(positionId: `0x${string}`) {
  return useReadContract({
    address: CONTRACTS.yieldManager,
    abi: ABIS.yieldManager,
    functionName: "getPosition",
    args: [positionId],
    query: { enabled: !!positionId && positionId !== "0x0000000000000000000000000000000000000000000000000000000000000000" },
  });
}

export function useYieldEvents() {
  const queryClient = useQueryClient();

  useWatchContractEvent({
    address: CONTRACTS.yieldManager,
    abi: ABIS.yieldManager,
    eventName: "Deposited",
    onLogs: () => {
      queryClient.invalidateQueries({ queryKey: ["readContract"] });
    },
  });
  useWatchContractEvent({
    address: CONTRACTS.yieldManager,
    abi: ABIS.yieldManager,
    eventName: "Withdrawn",
    onLogs: () => {
      queryClient.invalidateQueries({ queryKey: ["readContract"] });
    },
  });
}
