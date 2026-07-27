classdef RRCStateMachine < handle
    %RRCSTATEMACHINE Event-sourced bounded UE/gNB RRC state.

    properties (SetAccess = private)
        Endpoint (1,1) string
        UEID (1,1) string
        State (1,1) string = "RRC_IDLE"
        ActiveTransactionID double = []
        ConfigurationEpoch (1,1) double = 0
    end

    properties (Access = private)
        TransitionTable table
        EventStore sixgr.protocol.ProtocolEventStore
    end

    methods
        function obj = RRCStateMachine(endpoint, ueID, vectorRoot, eventStore)
            arguments
                endpoint (1,1) string
                ueID (1,1) string
                vectorRoot (1,1) string
                eventStore sixgr.protocol.ProtocolEventStore = ...
                    sixgr.protocol.ProtocolEventStore()
            end
            endpoint = upper(endpoint);
            if ~ismember(endpoint, ["UE","GNB"])
                error("sixgr:rrc:ASN1ConstraintViolation", ...
                    "RRC endpoint must be UE or GNB.");
            end
            obj.Endpoint = endpoint;
            obj.UEID = ueID;
            obj.EventStore = eventStore;
            obj.TransitionTable = readtable(fullfile(vectorRoot, ...
                "protocol_rrc_state_transition_vectors.csv"), ...
                "TextType", "string", "VariableNamingRule", "preserve");
        end

        function event = apply(obj, eventName, time, transactionID)
            arguments
                obj
                eventName (1,1) string
                time (1,1) double
                transactionID = []
            end
            rows = obj.TransitionTable( ...
                obj.TransitionTable.FromState == obj.State & ...
                obj.TransitionTable.Event == eventName, :);
            valid = rows(lower(rows.ExpectedValid) == "true", :);
            if height(valid) ~= 1
                error("sixgr:rrc:TransactionMismatch", ...
                    "Illegal RRC transition %s --%s--> ?.", ...
                    obj.State, eventName);
            end
            requires = lower(valid.TransactionRequired) == "true";
            if requires && (isempty(transactionID) || ...
                    ~ismember(transactionID, 0:3))
                error("sixgr:rrc:TransactionMismatch", ...
                    "RRC transition %s requires a two-bit transaction ID.", ...
                    eventName);
            end
            previous = obj.State;
            next = valid.ToState;
            if requires
                if ~isempty(obj.ActiveTransactionID) && ...
                        obj.ActiveTransactionID ~= transactionID && ...
                        ~contains(eventName, "COMPLETE")
                    error("sixgr:rrc:TransactionMismatch", ...
                        "Concurrent RRC transaction IDs do not match.");
                end
                obj.ActiveTransactionID = transactionID;
            end
            obj.State = next;
            if contains(eventName, "COMPLETE") || startsWith(eventName, "RRC_RELEASE")
                obj.ActiveTransactionID = [];
            end
            event = obj.EventStore.append(time, "RRC", eventName, ...
                "UEID", obj.UEID, "ConfigurationEpoch", ...
                obj.ConfigurationEpoch, "Payload", struct( ...
                "Endpoint", obj.Endpoint, "FromState", previous, ...
                "ToState", next, "TransactionID", transactionID));
        end

        function setConfigurationEpoch(obj, epoch)
            if epoch <= obj.ConfigurationEpoch || epoch ~= floor(epoch)
                error("sixgr:rrc:BearerCommitFailed", ...
                    "RRC configuration epoch must increase monotonically.");
            end
            obj.ConfigurationEpoch = epoch;
        end
    end
end
