import { create } from 'zustand';

type RunStore = {
  selectedRunId: string;
  selectedScenario: string;
  setSelectedRunId: (runId: string) => void;
  setSelectedScenario: (scenario: string) => void;
};

export const useRunStore = create<RunStore>((set) => ({
  selectedRunId: '',
  selectedScenario: 'simulator/configs/scenarios/lls_mobile_2ue_100kmh_1sector_full_capture.yaml',
  setSelectedRunId: (runId) => set({ selectedRunId: runId }),
  setSelectedScenario: (scenario) => set({ selectedScenario: scenario }),
}));

