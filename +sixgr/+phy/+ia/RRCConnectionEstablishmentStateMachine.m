classdef RRCConnectionEstablishmentStateMachine
    %RRCCONNECTIONESTABLISHMENTSTATEMACHINE Bounded RRC setup state owner.

    methods (Static)
        function result = evaluate(varargin)
            p = inputParser;
            p.FunctionName = ...
                "sixgr.phy.ia.RRCConnectionEstablishmentStateMachine.evaluate";
            addParameter(p, "CaseID", "", @localTextScalar);
            addParameter(p, "EventSequence", "", @localTextScalar);
            addParameter(p, "ExpectedTransactionID", ...
                NaN, @localTransactionID);
            addParameter(p, "ReceivedTransactionID", ...
                NaN, @localTransactionID);
            addParameter(p, "UEIdentity", "", @localTextScalar);
            addParameter(p, "ReceivedUEIdentity", "", @localTextScalar);
            addParameter(p, "SRB1InstalledBeforeSetupComplete", ...
                false, @localLogicalScalar);
            parse(p, varargin{:});
            opt = p.Results;

            events = split(string(opt.EventSequence), "|");
            events = upper(strtrim(events(:)));
            ueState = "IDLE";
            gnbState = "IDLE";
            errorID = "";
            failureIndex = NaN;
            trace = repmat(localTraceRow(), numel(events), 1);
            for ii = 1:numel(events)
                beforeUE = ueState;
                beforeGNB = gnbState;
                event = events(ii);
                [ueState, gnbState, errorID] = localStep( ...
                    ueState, gnbState, event, opt);
                if strlength(errorID) > 0
                    ueState = "FAILED";
                    gnbState = "FAILED";
                    failureIndex = ii;
                end
                trace(ii) = struct( ...
                    "Ordinal", ii, ...
                    "Event", event, ...
                    "UEStateBefore", beforeUE, ...
                    "GNBStateBefore", beforeGNB, ...
                    "UEStateAfter", ueState, ...
                    "GNBStateAfter", gnbState, ...
                    "ErrorIdentifier", errorID);
                if strlength(errorID) > 0
                    break;
                end
            end
            trace = trace(1:ii);
            connected = ueState == "CONNECTED" && ...
                gnbState == "CONNECTED";
            if ~connected && strlength(errorID) == 0
                errorID = "sixgr:phy:ia:InvalidRRCStateTransition";
                ueState = "FAILED";
                gnbState = "FAILED";
                failureIndex = numel(trace);
            end

            payload = struct( ...
                "ContractVersion", ...
                    "sixgr_rrc_connection_establishment_release18/v1", ...
                "CaseID", string(opt.CaseID), ...
                "EventSequence", string(opt.EventSequence), ...
                "ExpectedTransactionID", ...
                    double(opt.ExpectedTransactionID), ...
                "ReceivedTransactionID", ...
                    double(opt.ReceivedTransactionID), ...
                "UEIdentity", string(opt.UEIdentity), ...
                "ReceivedUEIdentity", ...
                    string(opt.ReceivedUEIdentity), ...
                "SRB1InstalledBeforeSetupComplete", ...
                    logical(opt.SRB1InstalledBeforeSetupComplete), ...
                "FinalUEState", ueState, ...
                "FinalGNBState", gnbState, ...
                "RRCConnected", logical(connected), ...
                "ErrorIdentifier", errorID, ...
                "FailureEventOrdinal", failureIndex, ...
                "StateMutationAfterFailure", false, ...
                "ProxyUsed", false, ...
                "FallbackUsed", false, ...
                "Status", string(localStatus(connected, errorID)));
            result = payload;
            result.Trace = struct2table(trace, "AsArray", true);
            result.ResolutionSHA256 = ...
                sixgr.util.sha256Hex(jsonencode(payload));
        end

        function result = execute(varargin)
            result = sixgr.phy.ia. ...
                RRCConnectionEstablishmentStateMachine.evaluate( ...
                varargin{:});
            if strlength(result.ErrorIdentifier) > 0
                error(char(result.ErrorIdentifier), ...
                    "RRC connection establishment failed at event %g.", ...
                    result.FailureEventOrdinal);
            end
        end
    end
end

function [ue, gnb, errorID] = localStep(ue, gnb, event, opt)
errorID = "";
switch event
    case "CELL_SELECTED"
        if ue ~= "IDLE" || gnb ~= "IDLE"
            errorID = "sixgr:phy:ia:InvalidRRCStateTransition";
        else
            ue = "CAMPED";
            gnb = "CELL_AVAILABLE";
        end
    case "MSG3_RRC_SETUP_REQUEST_OK"
        if ue ~= "CAMPED" || gnb ~= "CELL_AVAILABLE"
            errorID = "sixgr:phy:ia:InvalidRRCStateTransition";
        else
            ue = "WAIT_RRC_SETUP";
            gnb = "SETUP_REQUEST_RECEIVED";
        end
    case "MSG4_RRC_SETUP_OK"
        if ue ~= "WAIT_RRC_SETUP" || ...
                gnb ~= "SETUP_REQUEST_RECEIVED"
            errorID = "sixgr:phy:ia:InvalidRRCStateTransition";
        elseif string(opt.UEIdentity) ~= ...
                string(opt.ReceivedUEIdentity) || ...
                double(opt.ExpectedTransactionID) ~= ...
                double(opt.ReceivedTransactionID)
            errorID = "sixgr:phy:ia:RRCSetupFailure";
        else
            ue = "WAIT_SETUP_COMPLETE";
            gnb = "WAIT_SETUP_COMPLETE";
        end
    case "RRC_SETUP_COMPLETE_OK"
        if ue ~= "WAIT_SETUP_COMPLETE" || ...
                gnb ~= "WAIT_SETUP_COMPLETE"
            errorID = "sixgr:phy:ia:InvalidRRCStateTransition";
        elseif ~logical(opt.SRB1InstalledBeforeSetupComplete)
            errorID = "sixgr:phy:ia:RRCSetupCompleteFailure";
        else
            ue = "CONNECTED";
            gnb = "CONNECTED";
        end
    case "DUPLICATE_SETUP_COMPLETE"
        if ue ~= "CONNECTED" || gnb ~= "CONNECTED"
            errorID = "sixgr:phy:ia:InvalidRRCStateTransition";
        end
    case "UL_DCCH_CRC_FAIL"
        if ue == "CAMPED"
            errorID = "sixgr:phy:ia:RRCSetupRequestFailure";
        elseif ue == "WAIT_SETUP_COMPLETE"
            errorID = "sixgr:phy:ia:RRCSetupCompleteFailure";
        else
            errorID = "sixgr:phy:ia:InvalidRRCStateTransition";
        end
    case {"WRONG_IDENTITY", "WRONG_TRANSACTION", "T300_EXPIRE"}
        if ue == "WAIT_RRC_SETUP"
            errorID = "sixgr:phy:ia:RRCSetupFailure";
        else
            errorID = "sixgr:phy:ia:InvalidRRCStateTransition";
        end
    otherwise
        errorID = "sixgr:phy:ia:InvalidRRCStateTransition";
end
end

function status = localStatus(connected, errorID)
if connected
    status = "connected";
elseif strlength(errorID) > 0
    status = "failed";
else
    status = "incomplete";
end
end

function row = localTraceRow()
row = struct( ...
    "Ordinal", NaN, ...
    "Event", "", ...
    "UEStateBefore", "", ...
    "GNBStateBefore", "", ...
    "UEStateAfter", "", ...
    "GNBStateAfter", "", ...
    "ErrorIdentifier", "");
end

function tf = localTextScalar(value)
tf = ischar(value) || (isstring(value) && isscalar(value));
end

function tf = localTransactionID(value)
tf = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value >= 0 && value <= 3 && value == fix(value);
end

function tf = localLogicalScalar(value)
tf = (islogical(value) || isnumeric(value)) && isscalar(value);
end
