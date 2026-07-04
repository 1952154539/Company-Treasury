"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { ConnectKitButton } from "connectkit";

const NAV_ITEMS = [
  { href: "/", label: "仪表盘" },
  { href: "/transactions", label: "交易" },
  { href: "/budgets", label: "预算" },
  { href: "/streams", label: "流支付" },
  { href: "/yield", label: "收益" },
  { href: "/admin", label: "管理" },
];

export function NavBar() {
  const pathname = usePathname();

  return (
    <nav className="bg-white border-b border-gray-200 sticky top-0 z-50">
      <div className="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8">
        <div className="flex h-16 items-center justify-between">
          <div className="flex items-center gap-8">
            <Link href="/" className="text-lg font-bold text-gray-900">
              Treasury
            </Link>
            <div className="hidden sm:flex sm:gap-1">
              {NAV_ITEMS.map((item) => (
                <Link
                  key={item.href}
                  href={item.href}
                  className={`px-3 py-2 rounded-md text-sm font-medium transition-colors ${
                    pathname === item.href
                      ? "bg-gray-100 text-gray-900"
                      : "text-gray-600 hover:text-gray-900 hover:bg-gray-50"
                  }`}
                >
                  {item.label}
                </Link>
              ))}
            </div>
          </div>
          <ConnectKitButton />
        </div>
      </div>
    </nav>
  );
}
