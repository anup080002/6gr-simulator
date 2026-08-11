classdef TestManifest < matlab.unittest.TestCase
    methods(Test)
        function stableHash(tc)
            a=sixgr.util.sha256Hex(uint8('resilient-ntn'));b=sixgr.util.sha256Hex(uint8('resilient-ntn'));
            tc.verifyEqual(a,b);tc.verifyEqual(strlength(a),64);
        end
    end
end
