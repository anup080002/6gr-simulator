classdef PDCPCountState < handle
    %PDCPCOUNTSTATE Exact 32-bit HFN/SN COUNT authority.

    properties (SetAccess = private)
        SNBits (1,1) double
        HFN (1,1) uint32
        SN (1,1) uint32
        COUNT (1,1) uint64
        Exhausted (1,1) logical = false
    end

    methods
        function obj = PDCPCountState(snBits, hfn, sn)
            arguments
                snBits (1,1) double
                hfn (1,1) double = 0
                sn (1,1) double = 0
            end
            if ~ismember(snBits, [12 18])
                error("sixgr:pdcp:MalformedPDU", ...
                    "PDCP SN length must be 12 or 18.");
            end
            maxHFN = 2^(32-snBits) - 1;
            if hfn < 0 || hfn ~= floor(hfn) || hfn > maxHFN || ...
                    sn < 0 || sn ~= floor(sn) || sn >= 2^snBits
                error("sixgr:pdcp:MalformedPDU", ...
                    "Initial HFN/SN is outside the 32-bit COUNT space.");
            end
            obj.SNBits = snBits;
            obj.HFN = uint32(hfn);
            obj.SN = uint32(sn);
            obj.COUNT = bitshift(uint64(obj.HFN), snBits) + uint64(obj.SN);
        end

        function value = current(obj)
            value = obj.COUNT;
        end

        function advance(obj)
            if obj.Exhausted || obj.COUNT == uint64(4294967295)
                obj.Exhausted = true;
                error("sixgr:pdcp:CountExhausted", ...
                    "PDCP COUNT cannot wrap beyond 2^32-1.");
            end
            nextSN = double(obj.SN) + 1;
            nextHFN = double(obj.HFN);
            if nextSN == 2^obj.SNBits
                nextSN = 0;
                nextHFN = nextHFN + 1;
            end
            obj.SN = uint32(nextSN);
            obj.HFN = uint32(nextHFN);
            obj.COUNT = obj.COUNT + 1;
        end
    end
end
