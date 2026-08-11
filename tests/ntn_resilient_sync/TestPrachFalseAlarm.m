classdef TestPrachFalseAlarm < matlab.unittest.TestCase
    methods(Test)
        function globalThresholdUsesNoiseOnlyWaveforms(tc)
            scenario=sixgr.ntn.resilientsync.buildScenario('configs/ntn_resilient_sync/quick.yaml');
            source=sixgr.lls6g.config.loadScenarioConfig(scenario.physical_layer.prach_scenario_config);
            base=source.toStruct();cfg=sixgr.phy.prach.buildPRACHConfigFromScenario(base, ...
                'RunFolder',tempdir,'ScenarioName','prach_threshold_unit');
            r=sixgr.ntn.resilientsync.prach.calibrateFalseAlarmThreshold(cfg,0.2,5,[0],19);
            tc.verifyGreaterThanOrEqual(r.Threshold,0);tc.verifyEqual(height(r.TrialTable),5);
            tc.verifyTrue(all(r.TrialTable.Provenance=="CALIBRATED_LLS"));
        end
    end
end
