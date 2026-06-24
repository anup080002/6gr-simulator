import { Tabs } from 'antd';
import ComplexityTab from './ComplexityTab';
import MissedFunctionTab from './MissedFunctionTab';
import TimeProfileTab from './TimeProfileTab';

export default function DevTools() {
  return (
    <Tabs
      items={[
        { key: 'time', label: 'Time Profile', children: <TimeProfileTab /> },
        { key: 'complexity', label: 'Complexity', children: <ComplexityTab /> },
        { key: 'missed', label: 'Missed Functions', children: <MissedFunctionTab /> },
      ]}
    />
  );
}

