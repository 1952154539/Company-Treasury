"use client";

import { useToast, type ToastType } from "@/components/Toast";
import { useCallback, useRef } from "react";

export function useTxToast() {
  const { addToast, updateToast } = useToast();
  const idRef = useRef<number>(0);

  const submit = useCallback(
    (label: string) => {
      idRef.current = addToast({
        type: "pending",
        title: `${label} — 请在钱包中确认`,
      });
    },
    [addToast]
  );

  const confirm = useCallback(
    (label: string, hash: string) => {
      updateToast(idRef.current, {
        type: "pending",
        title: `${label} — 交易确认中...`,
        txHash: hash,
      });
    },
    [updateToast]
  );

  const success = useCallback(
    (label: string) => {
      updateToast(idRef.current, {
        type: "success",
        title: `${label} — 成功`,
        message: undefined,
      });
    },
    [updateToast]
  );

  const fail = useCallback(
    (label: string, err?: Error) => {
      updateToast(idRef.current, {
        type: "error",
        title: `${label} — 失败`,
        message: err ? err.message.slice(0, 120) : undefined,
      });
    },
    [updateToast]
  );

  return { submit, confirm, success, fail };
}
