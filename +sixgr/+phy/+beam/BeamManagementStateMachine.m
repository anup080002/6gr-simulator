classdef BeamManagementStateMachine < handle
    %BEAMMANAGEMENTSTATEMACHINE Measured P1/P2/P3, TCI and BFR procedure.

    properties (SetAccess = private)
        State (1,1) string = "IDLE"
        EventSequence (1,1) double = 0
        ActiveTCIState (1,1) double = NaN
        AppliedBeamID (1,1) string = ""
        History table
    end

    methods
        function obj = BeamManagementStateMachine(initialState)
            arguments
                initialState (1,1) string = "IDLE"
            end
            validStates = ["IDLE","P1_MEASURING","P1_REPORTED","TCI_PENDING", ...
                "TCI_ACTIVE","P2_REFINING","DATA_ACTIVE", ...
                "BEAM_FAILURE_DETECTED","BFR_RA","RECOVERED"];
            if ~any(initialState == validStates)
                error("sixgr:mimo:InvalidBeamStateTransition", ...
                    "Unknown initial beam state %s.",initialState);
            end
            obj.State = initialState;
            obj.History = table('Size',[0 9], ...
                'VariableTypes',["double","string","string","string","string", ...
                                 "double","double","double","logical"], ...
                'VariableNames',["EventSequence","FromState","Event","ToState", ...
                                 "MeasuredResourceID","MeasuredRSRPDBM","MeasuredSINRDB", ...
                                 "ActivatedTCIState","GeometryOracleUsed"]);
        end

        function row = transition(obj,event,options)
            arguments
                obj
                event (1,1) string
                options.MeasuredResourceID (1,1) string = ""
                options.MeasuredRSRPDBM (1,1) double = NaN
                options.MeasuredSINRDB (1,1) double = NaN
                options.ActivatedTCIState (1,1) double = NaN
                options.GeometryOracleUsed (1,1) logical = false
            end
            if options.GeometryOracleUsed
                error("sixgr:mimo:BeamMeasurementOracleForbidden", ...
                    "Geometry may configure the channel, but cannot select a strict beam.");
            end
            toState = localNextState(obj.State,event);
            if toState == ""
                error("sixgr:mimo:InvalidBeamStateTransition", ...
                    "Event %s is invalid from state %s.",event,obj.State);
            end
            if any(toState == ["P1_REPORTED","P2_REFINING","TCI_PENDING", ...
                    "TCI_ACTIVE","DATA_ACTIVE","BEAM_FAILURE_DETECTED","BFR_RA","RECOVERED"]) && ...
                    strlength(options.MeasuredResourceID) == 0
                error("sixgr:mimo:BeamReportMismatch", ...
                    "Transition %s requires measured resource identity.",event);
            end
            if toState == "TCI_ACTIVE"
                if ~isfinite(options.ActivatedTCIState)
                    error("sixgr:mimo:InactiveTCIState", ...
                        "TCI activation requires the decoded active state.");
                end
                obj.ActiveTCIState = options.ActivatedTCIState;
            end
            fromState = obj.State;
            obj.State = toState;
            obj.EventSequence = obj.EventSequence+1;
            if toState == "DATA_ACTIVE"
                obj.AppliedBeamID = options.MeasuredResourceID;
            end
            row = table(obj.EventSequence,fromState,event,toState, ...
                options.MeasuredResourceID,options.MeasuredRSRPDBM, ...
                options.MeasuredSINRDB,options.ActivatedTCIState,false, ...
                'VariableNames',obj.History.Properties.VariableNames);
            obj.History = [obj.History;row];
        end
    end
end

function toState = localNextState(fromState,event)
states = ["IDLE","P1_MEASURING","P1_REPORTED","TCI_PENDING","TCI_ACTIVE", ...
          "P2_REFINING","DATA_ACTIVE","BEAM_FAILURE_DETECTED","BFR_RA","RECOVERED"];
from = find(states == fromState,1);
toState = "";
if isempty(from)
    return;
end
allowed = containers.Map('KeyType','char','ValueType','char');
allowed('IDLE|AUTO_EVENT_FOR_P1_MEASURING') = 'P1_MEASURING';
allowed('P1_MEASURING|AUTO_EVENT_FOR_P1_REPORTED') = 'P1_REPORTED';
allowed('P1_REPORTED|AUTO_EVENT_FOR_TCI_PENDING') = 'TCI_PENDING';
allowed('TCI_PENDING|AUTO_EVENT_FOR_TCI_ACTIVE') = 'TCI_ACTIVE';
allowed('TCI_ACTIVE|AUTO_EVENT_FOR_DATA_ACTIVE') = 'DATA_ACTIVE';
allowed('TCI_ACTIVE|AUTO_EVENT_FOR_P2_REFINING') = 'P2_REFINING';
allowed('P2_REFINING|AUTO_EVENT_FOR_TCI_PENDING') = 'TCI_PENDING';
allowed('P2_REFINING|AUTO_EVENT_FOR_DATA_ACTIVE') = 'DATA_ACTIVE';
allowed('DATA_ACTIVE|AUTO_EVENT_FOR_P2_REFINING') = 'P2_REFINING';
allowed('DATA_ACTIVE|AUTO_EVENT_FOR_BEAM_FAILURE_DETECTED') = 'BEAM_FAILURE_DETECTED';
allowed('TCI_ACTIVE|AUTO_EVENT_FOR_BEAM_FAILURE_DETECTED') = 'BEAM_FAILURE_DETECTED';
allowed('BEAM_FAILURE_DETECTED|AUTO_EVENT_FOR_BFR_RA') = 'BFR_RA';
allowed('BFR_RA|AUTO_EVENT_FOR_RECOVERED') = 'RECOVERED';
allowed('RECOVERED|AUTO_EVENT_FOR_TCI_ACTIVE') = 'TCI_ACTIVE';
allowed('RECOVERED|AUTO_EVENT_FOR_DATA_ACTIVE') = 'DATA_ACTIVE';
key = char(fromState+"|"+event);
if isKey(allowed,key)
    toState = string(allowed(key));
end
end
