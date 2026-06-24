import { CheckCircleOutlined, FileSearchOutlined, PlayCircleOutlined, UploadOutlined } from '@ant-design/icons';
import Editor from '@monaco-editor/react';
import { Alert, Button, Form, InputNumber, Select, Space, Switch, Tag, Upload, message } from 'antd';
import type { UploadProps } from 'antd';
import { useEffect, useState } from 'react';
import { api } from '../../api/client';
import { useRunStore } from '../../store/runStore';

type ScenarioRow = { path: string; name: string; root: string };

export default function ConfigPanel() {
  const { selectedScenario, setSelectedScenario, setSelectedRunId } = useRunStore();
  const [scenarios, setScenarios] = useState<ScenarioRow[]>([]);
  const [yamlText, setYamlText] = useState('');
  const [validation, setValidation] = useState<{ valid?: boolean; error?: string }>({});
  const [launching, setLaunching] = useState(false);

  useEffect(() => {
    api.get('/config/scenarios').then((r) => setScenarios(r.data));
  }, []);

  useEffect(() => {
    if (!selectedScenario) return;
    api.get('/config/file', { params: { path: selectedScenario } })
      .then((r) => {
        setYamlText(r.data.text ?? '');
        setValidation({ valid: r.data.valid, error: r.data.error });
      })
      .catch(() => setValidation({ valid: false, error: 'Could not load selected scenario.' }));
  }, [selectedScenario]);

  const uploadProps: UploadProps = {
    maxCount: 1,
    showUploadList: false,
    customRequest: async ({ file, onSuccess, onError }) => {
      try {
        const form = new FormData();
        form.append('file', file as File);
        const res = await api.post('/runs/upload-yaml', form);
        if (res.data.valid) {
          setYamlText(await (file as File).text());
          setValidation({ valid: true });
          message.success('YAML parsed successfully');
        } else {
          setValidation({ valid: false, error: res.data.error });
        }
        onSuccess?.(res.data);
      } catch (err) {
        onError?.(err as Error);
      }
    },
  };

  async function validateText() {
    const res = await api.post('/config/validate', { text: yamlText });
    setValidation(res.data);
  }

  async function launch(values: { snr_db: number; slot_steps: number; execute: boolean }) {
    setLaunching(true);
    try {
      const res = await api.post('/runs', {
        scenario_yaml: selectedScenario,
        snr_db: values.snr_db,
        slot_steps: values.slot_steps,
        dut_blocks: ['PDSCH', 'PUSCH', 'PDCCH', 'PUCCH', 'SRS', 'TRS'],
        run_tag_prefix: 'webgui',
        execute: values.execute,
      });
      setSelectedRunId(res.data.run_id);
      message.success(`Run queued: ${res.data.run_id}`);
    } finally {
      setLaunching(false);
    }
  }

  return (
    <div className="two-column">
      <section>
        <Space direction="vertical" size={12} style={{ width: '100%' }}>
          <Select
            showSearch
            value={selectedScenario}
            onChange={setSelectedScenario}
            style={{ width: '100%' }}
            options={scenarios.map((s) => ({ label: s.path, value: s.path }))}
          />
          <div className="toolbar-row">
            <Upload {...uploadProps}>
              <Button icon={<UploadOutlined />}>Upload YAML</Button>
            </Upload>
            <Button icon={<FileSearchOutlined />} onClick={validateText}>Validate</Button>
            {validation.valid === true && <Tag color="green" icon={<CheckCircleOutlined />}>valid YAML</Tag>}
          </div>
          {validation.valid === false && <Alert type="error" message="Config validation failed" description={validation.error} />}
          <Form layout="vertical" initialValues={{ snr_db: 12, slot_steps: 500, execute: true }} onFinish={launch}>
            <Form.Item label="SNR dB" name="snr_db">
              <InputNumber min={-20} max={60} step={0.5} style={{ width: '100%' }} />
            </Form.Item>
            <Form.Item label="Slot steps" name="slot_steps">
              <InputNumber min={1} max={100000} style={{ width: '100%' }} />
            </Form.Item>
            <Form.Item label="Execute MATLAB now" name="execute" valuePropName="checked">
              <Switch />
            </Form.Item>
            <Button type="primary" htmlType="submit" icon={<PlayCircleOutlined />} loading={launching}>
              Queue Run
            </Button>
          </Form>
        </Space>
      </section>
      <section>
        <Editor
          height="640px"
          language="yaml"
          theme="vs-dark"
          value={yamlText}
          onChange={(v) => setYamlText(v ?? '')}
          options={{ minimap: { enabled: false }, fontSize: 12, wordWrap: 'on' }}
        />
      </section>
    </div>
  );
}

