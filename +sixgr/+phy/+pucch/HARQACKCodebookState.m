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
        ProcedureContext
        Digest
    end

    methods
        function obj = HARQACKCodebookState(type,events,epoch,sourceIndices,procedure)
            if nargin<4, sourceIndices=(1:numel(events)).'; end
            if nargin<5, procedure=struct(); end
            assert(isstruct(procedure) && isscalar(procedure), ...
                'sixgr:phy:pucch:InvalidHARQEvent','Use one procedure context.');
            assert(isnumeric(sourceIndices) && isreal(sourceIndices) && ...
                all(isfinite(sourceIndices(:))) && all(sourceIndices(:)==fix(sourceIndices(:))) && ...
                all(sourceIndices(:)>=0 & sourceIndices(:)<=numel(events)), ...
                'sixgr:phy:pucch:InvalidHARQEvent','Invalid codebook bit-to-event mapping.');
            sourceIndices=sourceIndices(:);
            retainedSources=sourceIndices(sourceIndices>0);
            expectedSources=1:numel(events);
            assert(isequal(retainedSources(:),expectedSources(:)), ...
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
            obj.ProcedureContext=procedure;
            identity=struct( ...
                "Type",obj.CodebookType,"Tokens",tokens.', ...
                "Order",order.',"Epoch",epoch, ...
                "SourceEventIndex",sourceIndices.', ...
                "EventDigests",arrayfun(@(e)string(e.Digest),events).');
            % Preserve existing PUCCH/vector identities when there is no
            % additional transport authority. Bind received UL DAI otherwise.
            if ~isempty(fieldnames(procedure)), identity.ProcedureContext=procedure; end
            obj.Digest=sixgr.phy.pucch.PUCCHUtil.hash(identity);
        end
    end
end
