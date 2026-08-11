classdef TestStepHandling < matlab.unittest.TestCase
    methods(Test)
        function splitRuleMarksBoundary(tc)
            s=sixgr.ntn.resilientsync.buildScenario('configs/ntn_resilient_sync/quick.yaml');p=s.StateProfiles(string({s.StateProfiles.id})=="STEPWISE_COMMON_COMP");
            r=sixgr.ntn.resilientsync.state.handleStepBoundary(p,[9;11],[1;2]);
            tc.verifyTrue(r.StraddlesStep);tc.verifyEqual(r.SegmentIndex,[1;2]);
        end
    end
end
