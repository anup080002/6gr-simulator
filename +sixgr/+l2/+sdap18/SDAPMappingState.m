classdef SDAPMappingState < handle
    %SDAPMAPPINGSTATE Explicit QFI-to-DRB map with bounded default behavior.

    properties (SetAccess = private)
        PduSessionID (1,1) double
        DefaultDRBID double = []
        ConfigurationEpoch (1,1) double = 0
    end

    properties (Access = private)
        Map
    end

    methods
        function obj = SDAPMappingState(pduSessionID, defaultDRBID)
            arguments
                pduSessionID (1,1) double {mustBeInteger,mustBePositive}
                defaultDRBID = []
            end
            obj.PduSessionID = pduSessionID;
            if ~isempty(defaultDRBID)
                obj.DefaultDRBID = ...
                    sixgr.l2.sdap18.SDAPMappingState.validateDRB(defaultDRBID);
            end
            obj.Map = containers.Map('KeyType', 'double', ...
                'ValueType', 'double');
        end

        function configure(obj, qfi, drbID, epoch)
            qfi = sixgr.l2.sdap18.SDAPMappingState.validateQFI(qfi);
            drbID = sixgr.l2.sdap18.SDAPMappingState.validateDRB(drbID);
            if epoch < obj.ConfigurationEpoch
                error("sixgr:sdap:MalformedPDU", ...
                    "SDAP configuration epoch cannot move backwards.");
            end
            obj.Map(qfi) = drbID;
            obj.ConfigurationEpoch = epoch;
        end

        function drbID = resolve(obj, qfi)
            qfi = sixgr.l2.sdap18.SDAPMappingState.validateQFI(qfi);
            if isKey(obj.Map, qfi)
                drbID = obj.Map(qfi);
            elseif ~isempty(obj.DefaultDRBID)
                drbID = obj.DefaultDRBID;
            else
                error("sixgr:sdap:MissingQFIMap", ...
                    "QFI %d has neither an explicit nor default DRB mapping.", qfi);
            end
        end

        function applyReflective(obj, qfi, drbID, epoch)
            obj.configure(qfi, drbID, epoch);
        end
    end

    methods (Static, Access = private)
        function value = validateQFI(value)
            if ~isscalar(value) || ~isfinite(value) || ...
                    value ~= floor(value) || value < 0 || value > 63
                error("sixgr:sdap:MalformedPDU", "QFI must be in [0,63].");
            end
            value = double(value);
        end

        function value = validateDRB(value)
            if ~isscalar(value) || ~isfinite(value) || ...
                    value ~= floor(value) || value < 1 || value > 32
                error("sixgr:sdap:MissingQFIMap", ...
                    "DRB identity must be in [1,32].");
            end
            value = double(value);
        end
    end
end
