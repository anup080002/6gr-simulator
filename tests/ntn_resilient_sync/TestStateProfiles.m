classdef TestStateProfiles < matlab.unittest.TestCase
    methods(Test)
        function allProfilesValidate(tc)
            s=sixgr.ntn.resilientsync.buildScenario('configs/ntn_resilient_sync/quick.yaml');
            tc.verifyEqual(numel(s.StateProfiles),5);
            for i=1:numel(s.StateProfiles),sixgr.ntn.resilientsync.state.validateCompensationStateProfile(s.StateProfiles(i));end
        end
        function duplicateFeederRejected(tc)
            s=sixgr.ntn.resilientsync.buildScenario('configs/ntn_resilient_sync/quick.yaml');p=s.StateProfiles(2);
            p.ul_timing.status='ue_compensated_service_plus_feeder';
            tc.verifyError(@()sixgr.ntn.resilientsync.state.validateCompensationStateProfile(p), ...
                'sixgr:ntn:resilientsync:DuplicateFeederCompensation');
        end
    end
end
