"use client";

import { useAccount } from "wagmi";
import { useTreasuryEvents } from "@/hooks/useTreasury";
import { useStreamingEvents } from "@/hooks/useStreaming";
import { useYieldEvents } from "@/hooks/useYield";

export function EventSubscriber() {
  const { isConnected } = useAccount();

  if (!isConnected) return null;
  return <Inner />;
}

function Inner() {
  useTreasuryEvents();
  useStreamingEvents();
  useYieldEvents();
  return null;
}
