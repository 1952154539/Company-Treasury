"use client";

import {
  createContext,
  useContext,
  useState,
  useCallback,
  type ReactNode,
} from "react";

export type ToastType = "success" | "error" | "info" | "pending";

export interface Toast {
  id: number;
  type: ToastType;
  title: string;
  message?: string;
  txHash?: string;
}

interface ToastContextValue {
  toasts: Toast[];
  addToast: (toast: Omit<Toast, "id">) => number;
  removeToast: (id: number) => void;
  updateToast: (id: number, updates: Partial<Toast>) => void;
}

const ToastContext = createContext<ToastContextValue | null>(null);

let nextId = 0;

export function ToastProvider({ children }: { children: ReactNode }) {
  const [toasts, setToasts] = useState<Toast[]>([]);

  const addToast = useCallback((toast: Omit<Toast, "id">) => {
    const id = ++nextId;
    setToasts((prev) => [...prev.slice(-4), { ...toast, id }]);
    if (toast.type !== "pending") {
      setTimeout(() => {
        setToasts((prev) => prev.filter((t) => t.id !== id));
      }, 6000);
    }
    return id;
  }, []);

  const removeToast = useCallback((id: number) => {
    setToasts((prev) => prev.filter((t) => t.id !== id));
  }, []);

  const updateToast = useCallback((id: number, updates: Partial<Toast>) => {
    setToasts((prev) =>
      prev.map((t) => (t.id === id ? { ...t, ...updates } : t))
    );
  }, []);

  return (
    <ToastContext.Provider value={{ toasts, addToast, removeToast, updateToast }}>
      {children}
      <ToastContainer />
    </ToastContext.Provider>
  );
}

export function useToast() {
  const ctx = useContext(ToastContext);
  if (!ctx) throw new Error("useToast must be used within ToastProvider");
  return ctx;
}

function ToastContainer() {
  const { toasts, removeToast } = useToast();

  return (
    <div className="fixed bottom-4 right-4 z-[100] flex flex-col gap-2 max-w-sm">
      {toasts.map((toast) => (
        <div
          key={toast.id}
          className={`rounded-lg border p-4 shadow-lg transition-all animate-slide-up ${
            toast.type === "success"
              ? "bg-green-50 border-green-200"
              : toast.type === "error"
              ? "bg-red-50 border-red-200"
              : toast.type === "pending"
              ? "bg-blue-50 border-blue-200"
              : "bg-gray-50 border-gray-200"
          }`}
        >
          <div className="flex items-start justify-between gap-2">
            <div className="flex items-center gap-2">
              {toast.type === "success" && (
                <span className="text-green-600 text-sm">✓</span>
              )}
              {toast.type === "error" && (
                <span className="text-red-600 text-sm">✗</span>
              )}
              {toast.type === "pending" && (
                <span className="text-blue-600 text-sm animate-spin">⏳</span>
              )}
              {toast.type === "info" && (
                <span className="text-gray-600 text-sm">ℹ</span>
              )}
              <div>
                <p
                  className={`text-sm font-medium ${
                    toast.type === "success"
                      ? "text-green-800"
                      : toast.type === "error"
                      ? "text-red-800"
                      : toast.type === "pending"
                      ? "text-blue-800"
                      : "text-gray-800"
                  }`}
                >
                  {toast.title}
                </p>
                {toast.message && (
                  <p className="text-xs text-gray-600 mt-0.5">
                    {toast.message}
                  </p>
                )}
                {toast.txHash && (
                  <a
                    href={`https://sepolia.etherscan.io/tx/${toast.txHash}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="text-xs text-blue-600 hover:text-blue-800 mt-0.5 block font-mono"
                  >
                    查看交易: {toast.txHash.slice(0, 10)}...
                  </a>
                )}
              </div>
            </div>
            <button
              onClick={() => removeToast(toast.id)}
              className="text-gray-400 hover:text-gray-600 text-sm shrink-0"
            >
              ✕
            </button>
          </div>
        </div>
      ))}
    </div>
  );
}
