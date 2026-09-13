classdef HARQACKCodebookState
    %HARQACKCODEBOOKSTATE Immutable ordered HARQ-ACK codebook.

    properties (SetAccess=private)
        CodebookType
        Events
        BitTokens
        Bits
        DTXMask
        EventOrder
        SourceEventIndex
        MissingAssignmentMask
        ConfigurationEpoch
        Digest
    end

    methods
        function obj = HARQACKCodebookState(type,events,epoch,sourceIndices)
            if nargin<4, sourceIndices=(1:numel(events)).'; end
            assert(isnumeric(sourceIndices) && isreal(sourceIndices) && ...
                all(isfinite(sourceIndices(:))) && all(sourceIndices(:)==fix(sourceIndices(:))) && ...
                all(sourceIndices(:)>=0 & sourceIndices(:)<=numel(events)), ...
                'sixgr:phy:pucch:InvalidHARQEvent','Invalid codebook bit-to-event mapping.');
            sourceIndices=sourceIndices(:);
            assert(isequal(sourceIndices(sourceIndices>0),(1:numel(events)).'), ...
                'sixgr:phy:pucch:InvalidHARQEvent', ...
                'Every received scalar-TB event must own exactly one ordered codebook position.');
            obj.CodebookType = string(type);
            obj.Events = events;
            obj.SourceEventIndex=sourceIndices;
            obj.MissingAssignmentMask=sourceIndices==0;
            states = repmat("NACK",numel(sourceIndices),1);
            order = strings(numel(sourceIndices),1);
            for index = 1:numel(sourceIndices)
                source=sourceIndices(index);
                if source==0, continue; end
                states(index) = string(events(source).Data.State);
                order(index) = string(events(source).Data.PDSCHID);
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
                "Order",order.',"Epoch",epoch, ...
                "SourceEventIndex",sourceIndices.', ...
                "EventDigests",arrayfun(@(e)string(e.Digest),events).'));
        end
    end
end
