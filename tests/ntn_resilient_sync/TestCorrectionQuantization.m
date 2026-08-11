classdef TestCorrectionQuantization < matlab.unittest.TestCase
    methods(Test)
        function quantizationActivationAndNoDoubleApply(tc)
            q=struct('TimingError_s',10.2e-6,'FrequencyError_Hz',123, ...
                'TimingRange_s',250e-6,'FrequencyRange_Hz',20e3, ...
                'TimingStep_s',1e-6,'FrequencyStep_Hz',50, ...
                'ActivationTime_s',2,'StateVersion',3);
            r=sixgr.ntn.resilientsync.prach.evaluateResidualCorrection(q,struct('Time_s',2,'StateVersion',3,'AppliedStateVersion',2));
            tc.verifyLessThanOrEqual(abs(r.TimingApplied_s+q.TimingError_s),q.TimingStep_s/2+eps);
            tc.verifyLessThanOrEqual(abs(r.FrequencyApplied_Hz+q.FrequencyError_Hz),q.FrequencyStep_Hz/2+eps);
            d=sixgr.ntn.resilientsync.prach.evaluateResidualCorrection(q,struct('Time_s',3,'StateVersion',3,'AppliedStateVersion',3));
            tc.verifyEqual([d.TimingApplied_s d.FrequencyApplied_Hz],[0 0]);
        end
    end
end
