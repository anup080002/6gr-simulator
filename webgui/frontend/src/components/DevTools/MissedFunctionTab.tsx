import { Empty, Progress, Select, Space, Table, Tag } from 'antd';
import { useState } from 'react';
import { useAnalytics } from '../../hooks/useAnalytics';
import { useRunStore } from '../../store/runStore';

const STATUS_COLORS: Record<string, string> = {
  CALLED: 'green',
  NOT_CALLED: 'orange',
  MISSING: 'red',
  BYPASSED: 'purple',
};

export default function MissedFunctionTab() {
  const { selectedRunId } = useRunStore();
  const [filter, setFilter] = useState('ALL');
  const { data } = useAnalytics<any>(`/functions/${selectedRunId}/missed`, Boolean(selectedRunId));
  if (!selectedRunId) return <Empty description="Select a completed run" />;
  const rows = data?.functions ?? [];
  const visible = filter === 'ALL' ? rows : rows.filter((r: any) => r.status === filter);
  const summary = data?.summary ?? { total: 0, called: 0 };
  const pct = summary.total ? Math.round((100 * summary.called) / summary.total) : 0;
  return (
    <Space direction="vertical" size={12} style={{ width: '100%' }}>
      <div className="toolbar-row">
        <Progress type="circle" percent={pct} size={76} />
        <Select value={filter} onChange={setFilter} options={['ALL', 'CALLED', 'NOT_CALLED', 'MISSING', 'BYPASSED'].map((v) => ({ value: v, label: v }))} />
        <Tag color={summary.oracle_violations ? 'red' : 'green'}>{summary.oracle_violations ?? 0} oracle guard findings</Tag>
      </div>
      <Table
        dataSource={visible}
        rowKey={(r) => r.full_name}
        size="small"
        pagination={{ pageSize: 25 }}
        columns={[
          { title: 'Status', dataIndex: 'status', width: 120, render: (v) => <Tag color={STATUS_COLORS[v]}>{v}</Tag> },
          { title: 'Function', dataIndex: 'function', width: 260, render: (v) => <code>{v}</code> },
          { title: 'Module', dataIndex: 'module', ellipsis: true },
          { title: 'Category', dataIndex: 'category', width: 150, render: (v) => <Tag>{v}</Tag> },
          { title: 'Prompt', dataIndex: 'prompt', width: 85, render: (v) => <Tag color="blue">P{v}</Tag> },
          { title: 'Impl', dataIndex: 'impl_status', width: 140 },
          { title: 'Next Step', dataIndex: 'next_step', ellipsis: true },
        ]}
      />
    </Space>
  );
}

