import { useEffect, useState } from 'react';
import { api } from '../api/client';

export function useAnalytics<T>(path: string, enabled: boolean) {
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    if (!enabled) {
      setData(null);
      return;
    }
    setLoading(true);
    api.get(path)
      .then((r) => setData(r.data))
      .finally(() => setLoading(false));
  }, [enabled, path]);

  return { data, loading };
}

