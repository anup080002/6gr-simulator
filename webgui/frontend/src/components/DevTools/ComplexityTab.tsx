import { Empty, Progress, Space, Table, Tag } from 'antd';
import { useAnalytics } from '../../hooks/useAnalytics';
import { useRunStore } from '../../store/runStore';

const COLORS: Record<string, string> = {
  low: 'green',
  medium: 'gold',
  high: 'orange',
  extreme: 'red',
};

export default function ComplexityTab() {
  const { selectedRunId } = useRunStore();
  const { data } = useAnalytics<any>(`/complexity/${selectedRunId}`, Boolean(selectedRunId));
  if (!selectedRunId) return <Empty description="Select a completed run" />;
  const rows = data?.functions ?? [];
  return (
    <Space direction="vertical" size={12} style={{ width: '100%' }}>
      <div className="metric-strip">
        <div>Total FLOPs: <strong>{compactNumber(data?.total_flops ?? 0)}</strong></div>
        <div>Total Bytes: <strong>{compactNumber(data?.total_bytes ?? 0)}</strong></div>
        <div>Bottleneck: <code>{data?.bottleneck_function ?? 'unavailable'}</code></div>
      </div>
      <Table
        dataSource={rows}
        rowKey={(r) => String(r.FunctionName)}
        size="small"
        pagination={{ pageSize: 20 }}
        columns={[
          { title: 'Function', dataIndex: 'FunctionName', ellipsis: true, render: (v) => <code>{String(v).split('.').pop()}</code> },
          { title: 'Stage', dataIndex: 'stage', width: 160 },
          { title: 'Calls', dataIndex: 'calls', width: 80, align: 'right' },
          { title: 'Time', dataIndex: 'time_tier', width: 90, render: tierTag },
          { title: 'FLOPs', dataIndex: 'flops_tier', width: 90, render: tierTag },
          { title: 'Bytes', dataIndex: 'bytes_tier', width: 90, render: tierTag },
          { title: 'Score', dataIndex: 'bottleneck_score', width: 180, render: (v) => <Progress percent={Math.round(Number(v) * 100)} size="small" /> },
        ]}
      />
    </Space>
  );
}

function tierTag(v: string) {
  return <Tag color={COLORS[v] ?? 'default'}>{v}</Tag>;
}

function compactNumber(v: number) {
  const n = Number(v);
  if (!Number.isFinite(n)) return '';
  if (Math.abs(n) >= 1e9) return `${(n / 1e9).toFixed(1)}G`;
  if (Math.abs(n) >= 1e6) return `${(n / 1e6).toFixed(1)}M`;
  if (Math.abs(n) >= 1e3) return `${(n / 1e3).toFixed(1)}K`;
  return n.toFixed(0);
}

