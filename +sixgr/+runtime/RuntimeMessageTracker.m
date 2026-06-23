classdef RuntimeMessageTracker < handle
%RUNTIMEMESSAGETRACKER Generic message lifecycle evidence for later PHY phases.

    properties
        Bus sixgr.runtime.RuntimeEvidenceBus
    end

    methods
        function obj = RuntimeMessageTracker(bus)
            if ~isa(bus, "sixgr.runtime.RuntimeEvidenceBus")
                error("sixgr:runtime:MessageTrackerBadBus", "RuntimeMessageTracker requires a RuntimeEvidenceBus.");
            end
            obj.Bus = bus;
        end

        function messageId = createMessage(obj, messageType, varargin)
            messageId = localUUID();
            obj.emitMessage("MESSAGE_CREATE", messageId, messageType, "created", varargin{:});
        end

        function sendMessage(obj, messageId, messageType, varargin)
            obj.emitMessage("MESSAGE_SEND", messageId, messageType, "sent", varargin{:});
        end

        function receiveMessage(obj, messageId, messageType, varargin)
            obj.emitMessage("MESSAGE_RECEIVE", messageId, messageType, "received", varargin{:});
        end

        function consumeMessage(obj, messageId, messageType, varargin)
            obj.emitMessage("MESSAGE_CONSUME", messageId, messageType, "consumed", varargin{:});
        end

        function transitionState(obj, stateName, fromState, toState, varargin)
            obj.Bus.emit("STATE_TRANSITION", "Status", "transitioned", ...
                "ReasonCode", stateName, ...
                "Message", string(fromState) + "->" + string(toState), varargin{:});
        end
    end

    methods (Access = private)
        function emitMessage(obj, eventType, messageId, messageType, status, varargin)
            obj.Bus.emit(eventType, "Status", status, ...
                "ReasonCode", string(messageType), ...
                "Message", "message_id=" + string(messageId), varargin{:});
        end
    end
end

function id = localUUID()
try
    id = string(char(java.util.UUID.randomUUID()));
catch
    id = "msg_" + string(round(posixtime(datetime("now")) * 1e6)) + "_" + string(randi(1e9));
end
end
