"use client";

import { useReadContract, useWriteContract, useWatchContractEvent } from "wagmi";
import { ABIS, CONTRACTS } from "@/lib/contracts";
import { parseEther, formatEther, type Hash } from "viem";

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

// ---- Write Hooks ----

export function useProposeTransaction() {
  return useWriteContract({
    // We'll configure per-call
  });
}

export function useApproveTransaction() {
  return useWriteContract({
    // Configured per-call
  });
}

export function useExecuteTransaction() {
  return useWriteContract({
    // Configured per-call
  });
}

export function useCancelTransaction() {
  return useWriteContract({
    // Configured per-call
  });
}

export function usePause() {
  return useWriteContract({});
}

export function useUnpause() {
  return useWriteContract({});
}

// ---- Event Hooks ----

export function useWatchTransactionEvents(onLogs?: (logs: unknown[]) => void) {
  useWatchContractEvent({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    eventName: "TransactionProposed",
    onLogs,
  });
  useWatchContractEvent({
    address: CONTRACTS.treasuryCore,
    abi: ABIS.treasuryCore,
    eventName: "TransactionExecuted",
    onLogs,
  });
}
