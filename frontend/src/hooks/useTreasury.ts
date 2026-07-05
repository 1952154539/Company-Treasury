"use client";

import { useReadContract, useWatchContractEvent } from "wagmi";
import { useQueryClient } from "@tanstack/react-query";
import { ABIS, CONTRACTS } from "@/lib/contracts";

// ---- Read Hooks ----

export function useETHBalance() {
  return useReadContract({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    functionName: "getETHBalance",
  });
}

export function useGlobalThreshold() {
  return useReadContract({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    functionName: "getGlobalThreshold",
  });
}

export function useActiveSignerCount() {
  return useReadContract({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    functionName: "getActiveSignerCount",
  });
}

export function useSignerList() {
  return useReadContract({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    functionName: "getSignerList",
  });
}

export function useIsActiveSigner(address: `0x${string}`) {
  return useReadContract({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    functionName: "isActiveSigner",
    args: [address],
    query: { enabled: !!address },
  });
}

export function useTransaction(txId: bigint) {
  return useReadContract({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    functionName: "getTransaction",
    args: [txId],
    query: { enabled: txId > 0n },
  });
}

export function useTransactionApprovals(txId: bigint) {
  return useReadContract({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    functionName: "getTransactionApprovals",
    args: [txId],
    query: { enabled: txId > 0n },
  });
}

export function useIsApproved(txId: bigint, signer: `0x${string}`) {
  return useReadContract({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    functionName: "isApproved",
    args: [txId, signer],
    query: { enabled: txId > 0n && !!signer },
  });
}

export function useIsPaused() {
  return useReadContract({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    functionName: "isPaused",
  });
}

export function useIsEmergencyShutdown() {
  return useReadContract({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    functionName: "isEmergencyShutdown",
  });
}

export function useTransactionCount() {
  return useReadContract({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    functionName: "getTransactionCount",
  });
}

// ---- Budget Hooks ----

export function useBudget(budgetId: `0x${string}`) {
  return useReadContract({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    functionName: "getBudget",
    args: [budgetId],
    query: { enabled: !!budgetId && budgetId !== "0x0000000000000000000000000000000000000000000000000000000000000000" },
  });
}

export function useBudgetAvailable(budgetId: `0x${string}`) {
  return useReadContract({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    functionName: "getBudgetAvailable",
    args: [budgetId],
    query: { enabled: !!budgetId && budgetId !== "0x0000000000000000000000000000000000000000000000000000000000000000" },
  });
}

export function useBudgetIds() {
  return useReadContract({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    functionName: "getBudgetIds",
  });
}

export function useBudgetSpendHistory(budgetId: `0x${string}`) {
  return useReadContract({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    functionName: "getBudgetSpendHistory",
    args: [budgetId],
    query: { enabled: !!budgetId && budgetId !== "0x0000000000000000000000000000000000000000000000000000000000000000" },
  });
}

// ---- Event Hooks with Auto-Refresh ----

export function useTreasuryEvents() {
  const queryClient = useQueryClient();

  useWatchContractEvent({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    eventName: "TransactionProposed",
    onLogs: () => {
      queryClient.invalidateQueries({ queryKey: ["readContract"] });
    },
  });
  useWatchContractEvent({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    eventName: "TransactionApproved",
    onLogs: () => {
      queryClient.invalidateQueries({ queryKey: ["readContract"] });
    },
  });
  useWatchContractEvent({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    eventName: "TransactionExecuted",
    onLogs: () => {
      queryClient.invalidateQueries({ queryKey: ["readContract"] });
    },
  });
  useWatchContractEvent({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    eventName: "TransactionCancelled",
    onLogs: () => {
      queryClient.invalidateQueries({ queryKey: ["readContract"] });
    },
  });
}
