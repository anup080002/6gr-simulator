classdef HandoverProcedure < handle
    %HANDOVERPROCEDURE Filtered-measurement-driven bounded intra-frequency HO.

    properties (SetAccess = private)
        State (1,1) string = "SERVING"
        ServingCell (1,1) string
        CandidateCell (1,1) string = ""
        FilteredServingRSRP (1,1) double = NaN
        FilteredCandidateRSRP (1,1) double = NaN
        EntryTime double = []
        HysteresisDB (1,1) double
        TimeToTriggerMs (1,1) double
    end

    properties (Access = private)
        TransitionTable table
    end

    methods
        function obj = HandoverProcedure(servingCell, hysteresisDB, tttMs, vectorRoot)
            obj.ServingCell = string(servingCell);
            obj.HysteresisDB = double(hysteresisDB);
            obj.TimeToTriggerMs = double(tttMs);
            obj.TransitionTable = readtable(fullfile(vectorRoot, ...
                "protocol_handover_state_vectors.csv"), ...
                "TextType","string","VariableNamingRule","preserve");
        end

        function entered = measurement(obj, timeMs, servingRSRP, ...
                candidateCell, candidateRSRP, alpha)
            arguments
                obj
                timeMs (1,1) double
                servingRSRP (1,1) double
                candidateCell (1,1) string
                candidateRSRP (1,1) double
                alpha (1,1) double = 0.5
            end
            if ~(alpha > 0 && alpha <= 1)
                error("sixgr:rrc:HandoverStateViolation", ...
                    "Measurement filter alpha must be in (0,1].");
            end
            if isnan(obj.FilteredServingRSRP)
                obj.FilteredServingRSRP = servingRSRP;
                obj.FilteredCandidateRSRP = candidateRSRP;
            else
                obj.FilteredServingRSRP = alpha * servingRSRP + ...
                    (1-alpha) * obj.FilteredServingRSRP;
                obj.FilteredCandidateRSRP = alpha * candidateRSRP + ...
                    (1-alpha) * obj.FilteredCandidateRSRP;
            end
            condition = obj.FilteredCandidateRSRP > ...
                obj.FilteredServingRSRP + obj.HysteresisDB;
            if condition
                if isempty(obj.EntryTime)
                    obj.EntryTime = timeMs;
                    obj.CandidateCell = candidateCell;
                end
                entered = timeMs - obj.EntryTime >= obj.TimeToTriggerMs;
            else
                obj.EntryTime = [];
                obj.CandidateCell = "";
                entered = false;
            end
        end

        function next = apply(obj, rlcMode, event)
            rows = obj.TransitionTable( ...
                obj.TransitionTable.RLCMode == upper(string(rlcMode)) & ...
                obj.TransitionTable.FromState == obj.State & ...
                obj.TransitionTable.Event == string(event), :);
            rows = rows(lower(rows.ExpectedValid) == "true", :);
            if height(rows) ~= 1
                error("sixgr:rrc:HandoverStateViolation", ...
                    "Illegal handover transition %s --%s--> ?.", ...
                    obj.State, string(event));
            end
            obj.State = rows.ToState;
            if obj.State == "SERVING_TARGET"
                obj.ServingCell = obj.CandidateCell;
                obj.CandidateCell = "";
            end
            next = obj.State;
        end
    end
end
