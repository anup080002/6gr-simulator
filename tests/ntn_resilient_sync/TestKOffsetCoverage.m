classdef TestKOffsetCoverage < matlab.unittest.TestCase
    methods(Test)
        function slotQuantizationCovers(tc)
            required=linspace(0,0.0123,1000).';slot=1e-3/(120/15);configured=ceil(required/slot)*slot;
            tc.verifyTrue(all(configured+eps>=required));
            tc.verifyEqual(configured/slot,round(configured/slot),'AbsTol',1e-12);
        end
    end
end
