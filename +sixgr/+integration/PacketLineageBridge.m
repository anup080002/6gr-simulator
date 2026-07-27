classdef PacketLineageBridge < handle
    %PACKETLINEAGEBRIDGE Byte-conservation ledger across protocol/PHY ownership.
    properties (SetAccess=immutable)
        RunID (1,1) string
    end
    properties (Access=private)
        Rows
    end
    methods
        function obj = PacketLineageBridge(runID)
            obj.RunID = string(runID);
            variableTypes = ["string","string","double","double", ...
                "double","double","double","double","string"];
            variableNames = ["RunID","PacketID","ArrivedBytes", ...
                "QueuedBytes","InFlightBytes","DeliveredBytes", ...
                "DroppedBytes","ConservationErrorBytes","Status"];
            obj.Rows = table('Size',[0 9], ...
                'VariableTypes',cellstr(variableTypes), ...
                'VariableNames',cellstr(variableNames));
        end
        function append(obj,packetID,arrived,queued,inFlight,delivered,dropped)
            values = double([arrived queued inFlight delivered dropped]);
            conservation = values(1)-sum(values(2:5));
            if any(values < 0) || conservation ~= 0
                error("sixgr:integration:PacketConservationFailure", ...
                    "Packet %s violates byte conservation.",string(packetID));
            end
            obj.Rows(end+1,:) = {obj.RunID,string(packetID),values(1), ...
                values(2),values(3),values(4),values(5),conservation,"PASS"};
        end
        function value = table(obj)
            value = obj.Rows;
        end
    end
end
