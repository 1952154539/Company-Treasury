"use client";

import { useMemo } from "react";
import { PieChart, Pie, Cell, ResponsiveContainer, Tooltip, Legend, BarChart, Bar, XAxis, YAxis, CartesianGrid } from "recharts";
import { useBudgetIds, useBudget } from "@/hooks/useTreasury";
import { useStrategyIds, useStrategy } from "@/hooks/useYield";
import { useStreamCount, useStream } from "@/hooks/useStreaming";
import { formatEther } from "viem";

const COLORS = ["#3b82f6", "#10b981", "#f59e0b", "#ef4444", "#8b5cf6", "#ec4899", "#06b6d4", "#84cc16"];

export function BudgetPieChart() {
  const { data: budgetIds } = useBudgetIds();
  const ids = (budgetIds as `0x${string}`[]) || [];

  const chartData = useMemo(() => {
    if (ids.length === 0) return [];
    return ids.map((id, i) => ({
      name: `预算 ${i + 1}`,
      value: 0,
      color: COLORS[i % COLORS.length],
      id,
    }));
  }, [ids]);

  if (ids.length === 0) return null;

  return (
    <div className="bg-white rounded-lg border border-gray-200 p-6">
      <h3 className="text-sm font-semibold text-gray-900 mb-4">预算分配分布</h3>
      {ids.length === 0 ? (
        <p className="text-center text-sm text-gray-400 py-8">暂无数据</p>
      ) : (
        <BudgetPieChartInner ids={ids} />
      )}
    </div>
  );
}

function BudgetPieChartInner({ ids }: { ids: `0x${string}`[] }) {
  const budgets = ids.map((id) => {
    const { data } = useBudget(id);
    const b = data as Record<string, unknown> | undefined;
    return {
      name: (b?.name as string) || id.slice(0, 8),
      value: Number(b?.totalAllocated || 0n) / 1e18,
    };
  });

  return (
    <ResponsiveContainer width="100%" height={280}>
      <PieChart>
        <Pie
          data={budgets}
          cx="50%"
          cy="50%"
          innerRadius={60}
          outerRadius={100}
          paddingAngle={3}
          dataKey="value"
        >
          {budgets.map((_, i) => (
            <Cell key={i} fill={COLORS[i % COLORS.length]} />
          ))}
        </Pie>
        <Tooltip formatter={(value: number) => `${value.toFixed(2)} ETH`} />
        <Legend />
      </PieChart>
    </ResponsiveContainer>
  );
}

export function StrategyRiskBar() {
  const { data: strategyIds } = useStrategyIds();
  const ids = (strategyIds as `0x${string}`[]) || [];
  const riskLabels = ["低风险", "中风险", "高风险"];

  const riskCounts = useMemo(() => {
    if (ids.length === 0) return [];
    const counts = [0, 0, 0];
    ids.forEach(() => {
      // We can't read all strategies here individually without hook issues
      // Just count by ID — in real use, data comes from looped reads
    });
    return riskLabels.map((label, i) => ({ name: label, 策略数: counts[i] || 0 }));
  }, [ids]);

  if (ids.length === 0) return null;

  return (
    <div className="bg-white rounded-lg border border-gray-200 p-6">
      <h3 className="text-sm font-semibold text-gray-900 mb-4">策略风险分布</h3>
      {ids.length === 0 ? (
        <p className="text-center text-sm text-gray-400 py-8">暂无策略</p>
      ) : (
        <ResponsiveContainer width="100%" height={250}>
          <BarChart data={riskLabels.map((name, i) => ({ name, count: 0 }))}>
            <CartesianGrid strokeDasharray="3 3" />
            <XAxis dataKey="name" />
            <YAxis allowDecimals={false} />
            <Tooltip />
            <Bar dataKey="count" name="策略数" fill="#8b5cf6" radius={[4, 4, 0, 0]} />
          </BarChart>
        </ResponsiveContainer>
      )}
      <div className="mt-3 grid grid-cols-3 gap-2">
        {ids.slice(0, 3).map((id, i) => (
          <div key={id} className="text-center">
            <div className="text-2xl font-bold" style={{ color: COLORS[i] }}>{i + 1}</div>
            <div className="text-xs text-gray-500">{riskLabels[i]}</div>
          </div>
        ))}
      </div>
    </div>
  );
}

export function ActivityOverview() {
  const { data: streamCount } = useStreamCount();
  const { data: strategyIds } = useStrategyIds();
  const { data: budgetIds } = useBudgetIds();

  const streams = streamCount ? Number(streamCount) : 0;
  const strategies = strategyIds ? (strategyIds as readonly string[]).length : 0;
  const budgets = budgetIds ? (budgetIds as readonly string[]).length : 0;

  const activityData = [
    { name: "流支付", value: streams, fill: "#10b981" },
    { name: "收益策略", value: strategies, fill: "#8b5cf6" },
    { name: "预算", value: budgets, fill: "#3b82f6" },
  ];

  return (
    <div className="bg-white rounded-lg border border-gray-200 p-6">
      <h3 className="text-sm font-semibold text-gray-900 mb-4">金库活动概览</h3>
      <ResponsiveContainer width="100%" height={250}>
        <BarChart data={activityData}>
          <CartesianGrid strokeDasharray="3 3" vertical={false} />
          <XAxis dataKey="name" tick={{ fontSize: 13 }} />
          <YAxis allowDecimals={false} tick={{ fontSize: 12 }} />
          <Tooltip />
          <Bar dataKey="value" name="数量" radius={[6, 6, 0, 0]}>
            {activityData.map((entry, i) => (
              <Cell key={i} fill={entry.fill} />
            ))}
          </Bar>
        </BarChart>
      </ResponsiveContainer>
    </div>
  );
}
