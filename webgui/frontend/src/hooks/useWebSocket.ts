import { useEffect, useMemo, useState } from 'react';
import { wsUrl } from '../api/client';

export type LiveMessage = {
  type: string;
  run_id?: string;
  message?: string;
  raw?: string;
  status?: string;
  data?: Record<string, string>;
  rows?: Record<string, unknown>[];
};

export function useWebSocket(runId: string) {
  const [messages, setMessages] = useState<LiveMessage[]>([]);
  const [status, setStatus] = useState<'idle' | 'open' | 'closed' | 'error'>('idle');

  useEffect(() => {
    if (!runId) {
      setStatus('idle');
      setMessages([]);
      return;
    }
    const socket = new WebSocket(wsUrl(runId));
    socket.onopen = () => setStatus('open');
    socket.onerror = () => setStatus('error');
    socket.onclose = () => setStatus('closed');
    socket.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data) as LiveMessage;
        setMessages((prev) => [...prev.slice(-500), msg]);
      } catch {
        setMessages((prev) => [...prev.slice(-500), { type: 'log', message: String(event.data) }]);
      }
    };
    return () => socket.close();
  }, [runId]);

  return useMemo(() => ({ messages, status }), [messages, status]);
}

