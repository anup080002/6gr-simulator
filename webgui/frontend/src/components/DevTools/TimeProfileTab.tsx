import { Empty, Select, Space, Table, Tag, Tooltip } from 'antd';
import Plot from 'react-plotly.js';
import { useState } from 'react';
import { useAnalytics } from '../../hooks/useAnalytics';
import { useRunStore } from '../../store/runStore';

export default function TimeProfileTab() {
  const { selectedRunId } = useRunStore();
  const [view, setView] = useState('table');
  const { data } = useAnalytics<any>(`/profile/${selectedRunId}`, Boolean(selectedRunId));
  if (!selectedRunId) return <Empty description="Select a completed run" />;
  const rows = data?.functions ?? [];
  return (
    <Space direction="vertical" size={12} style={{ width: '100%' }}>
      <div className="toolbar-row">
        <Select value={view} onChange={setView} options={[{ value: 'table', label: 'Table' }, { value: 'sunburst', label: 'Sunburst' }]} />
        <span className="muted">Top bottleneck: <code>{data?.top_5_by_time?.[0]?.FunctionName ?? 'unavailable'}</code></span>
      </div>
      {view === 'table' ? (
        <Table
          dataSource={rows}
          rowKey={(r) => `${r.FunctionName}-${r.Stage}`}
          size="small"
          pagination={{ pageSize: 20 }}
          columns={[
            { title: 'Function', dataIndex: 'FunctionName', ellipsis: true, render: (v) => <Tooltip title={v}><code>{String(v).split('.').pop()}</code></Tooltip> },
            { title: 'Stage', dataIndex: 'Stage', width: 160, render: (v) => <Tag>{v}</Tag> },
            { title: 'Calls', dataIndex: 'call_count', width: 80, align: 'right' },
            { title: 'Total s', dataIndex: 'total_time_s', width: 100, align: 'right', render: (v) => Number(v).toFixed(3), sorter: (a, b) => a.total_time_s - b.total_time_s },
            { title: '% Time', dataIndex: 'time_pct', width: 90, align: 'right', render: (v) => `${Number(v).toFixed(1)}%` },
            { title: 'FLOPs', dataIndex: 'total_flops', width: 120, align: 'right', render: compactNumber },
            { title: 'Bytes', dataIndex: 'total_bytes', width: 120, align: 'right', render: compactNumber },
          ]}
        />
      ) : (
        <Plot
          data={[{ type: 'sunburst', labels: rows.map((r: any) => String(r.FunctionName).split('.').pop()), parents: rows.map((r: any) => r.Stage || ''), values: rows.map((r: any) => r.total_time_s) }]}
          layout={{ height: 520, paper_bgcolor: '#151922', font: { color: '#d7dee9' }, margin: { t: 10, b: 10, l: 10, r: 10 } }}
          config={{ displayModeBar: false, responsive: true }}
          style={{ width: '100%' }}
        />
      )}
    </Space>
  );
}

function compactNumber(v: number) {
  const n = Number(v);
  if (!Number.isFinite(n)) return '';
  if (Math.abs(n) >= 1e9) return `${(n / 1e9).toFixed(1)}G`;
  if (Math.abs(n) >= 1e6) return `${(n / 1e6).toFixed(1)}M`;
  if (Math.abs(n) >= 1e3) return `${(n / 1e3).toFixed(1)}K`;
  return n.toFixed(0);
}

