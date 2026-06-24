import {
  ApiOutlined,
  BarChartOutlined,
  CodeOutlined,
  ControlOutlined,
  DashboardOutlined,
} from '@ant-design/icons';
import { Layout, Tabs, Tag, Typography } from 'antd';
import { useEffect, useState } from 'react';
import { api } from './api/client';
import Analytics from './components/Analytics/Analytics';
import ConfigPanel from './components/ConfigPanel/ConfigPanel';
import DevTools from './components/DevTools/DevTools';
import RealTimeDash from './components/RealTimeDash/RealTimeDash';
import RunManager from './components/RunManager/RunManager';

const { Header, Content } = Layout;

export default function App() {
  const [health, setHealth] = useState<{ mode?: string; ok?: boolean } | null>(null);

  useEffect(() => {
    api.get('/health').then((r) => setHealth(r.data)).catch(() => setHealth({ ok: false, mode: 'offline' }));
  }, []);

  return (
    <Layout className="app-shell">
      <Header className="topbar">
        <div>
          <Typography.Text className="brand">6GR LLS WebGUI</Typography.Text>
          <Typography.Text className="subtitle">Configuration, execution, evidence, and analytics</Typography.Text>
        </div>
        <Tag color={health?.ok ? 'green' : 'red'}>{health?.mode ?? 'checking'}</Tag>
      </Header>
      <Content className="workspace">
        <Tabs
          defaultActiveKey="config"
          items={[
            { key: 'config', label: <span><ControlOutlined /> Config</span>, children: <ConfigPanel /> },
            { key: 'runs', label: <span><ApiOutlined /> Run Manager</span>, children: <RunManager /> },
            { key: 'realtime', label: <span><DashboardOutlined /> Real-Time</span>, children: <RealTimeDash /> },
            { key: 'analytics', label: <span><BarChartOutlined /> Analytics</span>, children: <Analytics /> },
            { key: 'devtools', label: <span><CodeOutlined /> Developer Tools</span>, children: <DevTools /> },
          ]}
        />
      </Content>
    </Layout>
  );
}

