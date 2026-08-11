classdef TestEstimator < matlab.unittest.TestCase
    methods(Test)
        function noiselessAndIdentityWLS(tc)
            H=[-1 -1;1 -1];x=[2e-6;0.1e-6];g=[0.2e-6;0.2e-6];y=H*x+g;
            e=sixgr.ntn.resilientsync.measurement.estimateRangeRateOscillator(y,H,g,eye(2));
            tc.verifyEqual(e.XHat,x,'AbsTol',1e-15);
            tc.verifyEqual(e.RhoHat,(y(2)-y(1))/2,'AbsTol',1e-15);
        end
    end
end
