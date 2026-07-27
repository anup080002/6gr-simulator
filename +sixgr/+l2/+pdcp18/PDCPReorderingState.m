classdef PDCPReorderingState < handle
    %PDCPREORDERINGSTATE Bounded first-delivery and reordering state.

    properties (SetAccess = private)
        SNBits (1,1) double
        RX_DELIV (1,1) double = 0
        RX_NEXT (1,1) double = 0
        RX_REORD (1,1) double = 0
        DuplicateCount (1,1) double = 0
        Delivered double = []
        Buffered double = []
    end

    methods
        function obj = PDCPReorderingState(snBits, initialSN)
            arguments
                snBits (1,1) double
                initialSN (1,1) double = 0
            end
            if ~ismember(snBits, [12 18])
                error("sixgr:pdcp:MalformedPDU", ...
                    "Reordering SN length must be 12 or 18.");
            end
            obj.SNBits = snBits;
            obj.RX_DELIV = initialSN;
            obj.RX_NEXT = initialSN;
            obj.RX_REORD = initialSN;
        end

        function delivered = receive(obj, sn)
            if sn < 0 || sn ~= floor(sn) || sn >= 2^obj.SNBits
                error("sixgr:pdcp:ReorderingStateViolation", ...
                    "Received SN is invalid.");
            end
            if ismember(sn, [obj.Delivered obj.Buffered])
                obj.DuplicateCount = obj.DuplicateCount + 1;
                delivered = [];
                return;
            end
            obj.Buffered(end+1) = sn;
            delivered = [];
            while ismember(obj.RX_DELIV, obj.Buffered)
                obj.Buffered(obj.Buffered == obj.RX_DELIV) = [];
                delivered(end+1) = obj.RX_DELIV; %#ok<AGROW>
                obj.Delivered(end+1) = obj.RX_DELIV;
                obj.RX_DELIV = mod(obj.RX_DELIV + 1, 2^obj.SNBits);
            end
            obj.RX_NEXT = obj.RX_DELIV;
            obj.RX_REORD = obj.RX_DELIV;
        end
    end
end
