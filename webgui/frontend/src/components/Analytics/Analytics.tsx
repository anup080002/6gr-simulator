import { ReloadOutlined } from '@ant-design/icons';
import { Button, Empty, Space, Table, Tabs } from 'antd';
import Plot from 'react-plotly.js';
import { useEffect, useState } from 'react';
import { api } from '../../api/client';
import { useRunStore } from '../../store/runStore';

export default function Analytics() {
  const { selectedRunId } = useRunStore();
  const [kpi, setKpi] = useState<any>(null);
  const [bler, setBler] = useState<any>(null);

  async function load() {
    if (!selectedRunId) return;
    const [k, b] = await Promise.all([
      api.get(`/analytics/kpi/${selectedRunId}`).catch(() => ({ data: null })),
      api.get(`/analytics/bler-curve/${selectedRunId}`).catch(() => ({ data: null })),
    ]);
    setKpi(k.data);
    setBler(b.data);
  }

  useEffect(() => { load(); }, [selectedRunId]);

  if (!selectedRunId) return <Empty description="Select a run to inspect analytics" />;

  return (
    <Space direction="vertical" size={12} style={{ width: '100%' }}>
      <div className="toolbar-row">
        <Button icon={<ReloadOutlined />} onClick={load}>Refresh Analytics</Button>
        <code>{selectedRunId}</code>
      </div>
      <Tabs
        items={[
          {
            key: 'kpi',
            label: 'KPI Lineage',
            children: (
              <Table
                size="small"
                dataSource={kpi?.lineage ?? kpi?.kpi ?? []}
                rowKey={(_, i) => String(i)}
                pagination={{ pageSize: 20 }}
                columns={columnsFromRows(kpi?.lineage ?? kpi?.kpi ?? [])}
              />
            ),
          },
          {
            key: 'bler',
            label: 'BLER Curve',
            children: (
              <Plot
                data={[
                  { x: (bler?.dl ?? []).map((r: any) => r.snr_db), y: (bler?.dl ?? []).map((r: any) => r.bler), name: 'DL', mode: 'lines+markers' },
                  { x: (bler?.ul ?? []).map((r: any) => r.snr_db), y: (bler?.ul ?? []).map((r: any) => r.bler), name: 'UL', mode: 'lines+markers' },
                ]}
                layout={{
                  height: 420,
                  paper_bgcolor: '#151922',
                  plot_bgcolor: '#10141b',
                  font: { color: '#d7dee9' },
                  xaxis: { title: 'SNR dB', gridcolor: '#29313d' },
                  yaxis: { title: 'BLER', type: 'log', gridcolor: '#29313d' },
                }}
                config={{ displayModeBar: false, responsive: true }}
                style={{ width: '100%' }}
              />
            ),
          },
        ]}
      />
    </Space>
  );
}

function columnsFromRows(rows: any[]) {
  const sample = rows?.[0] ?? {};
  return Object.keys(sample).slice(0, 12).map((key) => ({
    title: key,
    dataIndex: key,
    ellipsis: true,
    render: (v: unknown) => String(v ?? ''),
  }));
}

