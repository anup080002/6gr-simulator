import { ReloadOutlined } from '@ant-design/icons';
import { Button, Empty, Space, Statistic, Tag } from 'antd';
import Plot from 'react-plotly.js';
import { useEffect, useMemo, useState } from 'react';
import { api } from '../../api/client';
import { LiveMessage, useWebSocket } from '../../hooks/useWebSocket';
import { useRunStore } from '../../store/runStore';

export default function RealTimeDash() {
  const { selectedRunId } = useRunStore();
  const { messages, status } = useWebSocket(selectedRunId);
  const [snapshot, setSnapshot] = useState<any>(null);

  const progress = useMemo(() => messages.filter((m) => m.type === 'progress'), [messages]);
  const logLines = useMemo(() => messages.filter((m) => m.type === 'log').map((m) => m.message ?? m.raw ?? ''), [messages]);
  const stageLines = useMemo(() => messages.filter((m) => m.type === 'stage_update'), [messages]);

  async function refresh() {
    if (!selectedRunId) return;
    const res = await api.get(`/analytics/real-time/${selectedRunId}`).catch(() => ({ data: null }));
    setSnapshot(res.data);
  }

  useEffect(() => {
    refresh();
  }, [selectedRunId]);

  if (!selectedRunId) return <Empty description="Select or queue a run first" />;

  const slots = progress.map((m) => parseSlot(m));
  const dlBler = progress.map((m) => parseNumber(m.data?.DL_BLER));
  const ulBler = progress.map((m) => parseNumber(m.data?.UL_BLER));
  const goodput = progress.map((m) => parseNumber((m.data?.goodput_DL ?? '').replace('Mbps', '')));

  return (
    <Space direction="vertical" size={14} style={{ width: '100%' }}>
      <div className="toolbar-row">
        <Tag color={status === 'open' ? 'green' : status === 'error' ? 'red' : 'default'}>WebSocket {status}</Tag>
        <code>{selectedRunId}</code>
        <Button icon={<ReloadOutlined />} onClick={refresh}>REST Snapshot</Button>
      </div>
      <div className="metric-strip">
        <Statistic title="DL BLER" value={lastFinite(dlBler) ?? snapshot?.dl?.bler ?? 'unavailable'} precision={4} />
        <Statistic title="UL BLER" value={lastFinite(ulBler) ?? snapshot?.ul?.bler ?? 'unavailable'} precision={4} />
        <Statistic title="DL Goodput Mbps" value={lastFinite(goodput) ?? snapshot?.dl?.goodput_mbps ?? 'unavailable'} precision={2} />
        <Statistic title="Stage Events" value={stageLines.length} />
      </div>
      <div className="panel-grid">
        <div className="chart-box">
          <Plot
            data={[
              { x: slots, y: dlBler, name: 'DL BLER', mode: 'lines+markers', line: { color: '#5b8def' } },
              { x: slots, y: ulBler, name: 'UL BLER', mode: 'lines+markers', line: { color: '#f59e0b' } },
            ]}
            layout={plotLayout('Live BLER vs Slot', 'Slot', 'BLER')}
            config={{ displayModeBar: false, responsive: true }}
            style={{ width: '100%' }}
          />
        </div>
        <div className="chart-box">
          <Plot
            data={[{ x: slots, y: goodput, name: 'DL Goodput', mode: 'lines+markers', fill: 'tozeroy', line: { color: '#31c48d' } }]}
            layout={plotLayout('Live Goodput vs Slot', 'Slot', 'Mbps')}
            config={{ displayModeBar: false, responsive: true }}
            style={{ width: '100%' }}
          />
        </div>
      </div>
      <div className="console">
        {logLines.length ? logLines.slice(-200).map((line, i) => <div key={`${i}-${line}`}>{line}</div>) : <span>No MATLAB log messages yet.</span>}
      </div>
    </Space>
  );
}

function parseSlot(msg: LiveMessage): number | null {
  const slot = msg.data?.slot ?? '';
  const first = slot.split('/')[0];
  return parseNumber(first);
}

function parseNumber(value?: string): number | null {
  const n = Number(value);
  return Number.isFinite(n) ? n : null;
}

function lastFinite(values: (number | null)[]): number | null {
  for (let i = values.length - 1; i >= 0; i -= 1) {
    if (typeof values[i] === 'number') return values[i] as number;
  }
  return null;
}

function plotLayout(title: string, xTitle: string, yTitle: string) {
  return {
    title,
    height: 310,
    margin: { t: 42, b: 45, l: 55, r: 16 },
    paper_bgcolor: '#151922',
    plot_bgcolor: '#10141b',
    font: { color: '#d7dee9' },
    xaxis: { title: xTitle, gridcolor: '#29313d' },
    yaxis: { title: yTitle, gridcolor: '#29313d' },
    legend: { orientation: 'h' },
  };
}

