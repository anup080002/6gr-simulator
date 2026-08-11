classdef TestErrorMapping < matlab.unittest.TestCase
    methods(Test)
        function zeroMapsToZero(tc)
            [state,errors,rule]=localFixture();o=sixgr.ntn.resilientsync.geometry.sourceErrorToULRP(state,errors,rule);
            tc.verifyEqual([o.DeltaTauSL_s o.ULRPArrivalError_s o.ULFrequencyError_Hz],[0 0 0],'AbsTol',1e-15);
        end
        function kappaAndOscillator(tc)
            [state,errors,rule]=localFixture();errors.DeltaUEPosition_m=[10 0 0];rule.OscillatorFractional=0.1e-6;
            o=sixgr.ntn.resilientsync.geometry.sourceErrorToULRP(state,errors,rule);
            tc.verifyEqual(o.ULRPArrivalError_s,-2*o.DeltaTauSL_s,'AbsTol',1e-15);
            tc.verifyEqual(o.ULFrequencyError_Hz,200,'AbsTol',1e-10);
        end
    end
end
function [state,errors,rule]=localFixture()
state=struct('SatellitePosition_m',[6971e3 0 0],'SatelliteVelocity_m_s',[0 7500 0], ...
    'UEPosition_m',[6371e3 0 0],'UEVelocity_m_s',[0 0 0]);
errors=struct('DeltaSatellitePosition_m',[0 0 0],'DeltaUEPosition_m',[0 0 0], ...
    'DeltaSatelliteVelocity_m_s',[0 0 0],'DeltaUEVelocity_m_s',[0 0 0]);
rule=struct('SpeedOfLight_m_s',299792458,'KappaT',2,'TimingCommon_s',0, ...
    'TimingCorrection_s',0,'ULCarrier_Hz',2e9,'DLToULFrequency_Hz',0, ...
    'OscillatorFractional',0,'FrequencyCommon_Hz',0,'FrequencyCorrection_Hz',0);
end
