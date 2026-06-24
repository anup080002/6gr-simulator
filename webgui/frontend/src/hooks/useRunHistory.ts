import { useEffect, useState } from 'react';
import { api } from '../api/client';

export type RunRow = {
  run_id?: string;
  id?: string;
  run_tag?: string;
  scenario_yaml?: string;
  status?: string;
  source?: string;
  updated_utc?: string;
  created_utc?: string;
};

export function useRunHistory(refreshKey = 0) {
  const [runs, setRuns] = useState<RunRow[]>([]);
  const [loading, setLoading] = useState(false);

  useEffect(() => {
    setLoading(true);
    api.get('/runs')
      .then((r) => setRuns(r.data))
      .finally(() => setLoading(false));
  }, [refreshKey]);

  return { runs, loading };
}

