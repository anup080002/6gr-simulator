import { ReloadOutlined, StopOutlined } from '@ant-design/icons';
import { Button, Space, Table, Tag, Tooltip } from 'antd';
import { useState } from 'react';
import { api } from '../../api/client';
import { useRunHistory } from '../../hooks/useRunHistory';
import { useRunStore } from '../../store/runStore';

export default function RunManager() {
  const [refreshKey, setRefreshKey] = useState(0);
  const { runs, loading } = useRunHistory(refreshKey);
  const { selectedRunId, setSelectedRunId } = useRunStore();

  async function stop(runId: string) {
    await api.delete(`/runs/${runId}`);
    setRefreshKey((v) => v + 1);
  }

  return (
    <Space direction="vertical" size={12} style={{ width: '100%' }}>
      <div className="toolbar-row">
        <Button icon={<ReloadOutlined />} onClick={() => setRefreshKey((v) => v + 1)}>Refresh</Button>
        <span className="muted">Selected run: <code>{selectedRunId || 'none'}</code></span>
      </div>
      <Table
        loading={loading}
        rowKey={(row, index) => row.run_id ?? row.id ?? row.run_tag ?? `row_${index ?? 0}`}
        dataSource={runs}
        size="small"
        pagination={{ pageSize: 15 }}
        onRow={(row) => ({
          onClick: () => setSelectedRunId(String(row.run_id ?? row.id ?? row.run_tag ?? '')),
        })}
        columns={[
          {
            title: 'Run',
            render: (_, row) => <Tooltip title={row.run_tag}><code>{row.run_id ?? row.id ?? row.run_tag}</code></Tooltip>,
          },
          { title: 'Status', dataIndex: 'status', width: 120, render: (v) => <Tag color={v === 'completed' ? 'green' : v === 'failed' ? 'red' : 'blue'}>{v ?? 'unknown'}</Tag> },
          { title: 'Scenario', dataIndex: 'scenario_yaml', ellipsis: true },
          { title: 'Source', dataIndex: 'source', width: 160 },
          {
            title: 'Action',
            width: 100,
            render: (_, row) => {
              const id = String(row.run_id ?? row.id ?? '');
              return <Button size="small" icon={<StopOutlined />} onClick={(e) => { e.stopPropagation(); stop(id); }}>Stop</Button>;
            },
          },
        ]}
      />
    </Space>
  );
}
