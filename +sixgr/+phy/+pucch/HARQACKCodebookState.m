classdef HARQACKCodebookState
    %HARQACKCODEBOOKSTATE Immutable ordered HARQ-ACK codebook.

    properties (SetAccess=private)
        CodebookType
        Events
        BitTokens
        Bits
        DTXMask
        EventOrder
        ConfigurationEpoch
        Digest
    end

    methods
        function obj = HARQACKCodebookState(type,events,epoch)
            obj.CodebookType = string(type);
            obj.Events = events;
            states = strings(numel(events),1);
            order = strings(numel(events),1);
            for index = 1:numel(events)
                states(index) = string(events(index).Data.State);
                order(index) = string(events(index).Data.PDSCHID);
            end
            obj.DTXMask = states == "DTX";
            tokens = strings(numel(states),1);
            tokens(states == "ACK") = "1";
            tokens(states == "NACK") = "0";
            tokens(states == "DTX") = "D";
            obj.BitTokens = tokens;
            obj.Bits = int8(states == "ACK");
            obj.EventOrder = order;
            obj.ConfigurationEpoch = double(epoch);
            obj.Digest = sixgr.phy.pucch.PUCCHUtil.hash(struct( ...
                "Type",obj.CodebookType,"Tokens",tokens.', ...
                "Order",order.',"Epoch",epoch));
        end
    end
end
