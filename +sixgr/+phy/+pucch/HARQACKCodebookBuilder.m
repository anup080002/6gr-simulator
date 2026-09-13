classdef HARQACKCodebookBuilder
    %HARQACKCODEBOOKBUILDER Scalar-TB HARQ event procedure adapter.
    % Type 2: EventIndex is the unique chronological monitoring-pair ordinal,
    % not the modulo DAI. Optional MonitoringOccasionIndex groups cells in the
    % same monitoring occasion; EventIndex orders receptions within that cell.
    % One invocation represents one feedback occasion and priority. This API
    % does not implement CBG, multi-TB bundling, SPS append or Type-2 grouping.

    methods (Static)
        function state = build(type,eventData,epoch)
            validateattributes(epoch,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
            type = upper(string(type));
            if ~ismember(type,["TYPE1_SEMISTATIC","TYPE2_DYNAMIC", ...
                    "TYPE3_ONESHOT"])
                error("sixgr:phy:pucch:UnsupportedHARQCodebook", ...
                    "Unsupported HARQ-ACK codebook %s.",type);
            end
            if isempty(eventData)
                events = sixgr.phy.pucch.HARQACKEvent.empty(0,1);
            else
                events = sixgr.phy.pucch.HARQACKEvent.empty(0,1);
                for index = 1:numel(eventData)
                    events(end+1,1) = sixgr.phy.pucch.HARQACKEvent(eventData(index)); %#ok<AGROW>
                end
                indexes = arrayfun(@(x) double(x.Data.EventIndex),events);
                if numel(unique(indexes)) ~= numel(indexes)
                    error("sixgr:phy:pucch:UnsupportedHARQCodebook", ...
                        "HARQ event indices must be unique.");
                end
            end
            if type == "TYPE2_DYNAMIC"
                [events,sourceIndices] = sixgr.phy.pucch.type2HARQACKLayout(events,epoch);
            else
                sourceIndices=(1:numel(events)).';
            end
            state = sixgr.phy.pucch.HARQACKCodebookState(type,events,epoch,sourceIndices);
        end

        function state = buildVector(row)
            decoded = jsondecode(char(sixgr.phy.pucch.PUCCHUtil.text( ...
                row,"EventsJSON","[]")));
            state = sixgr.phy.pucch.HARQACKCodebookBuilder.build( ...
                sixgr.phy.pucch.PUCCHUtil.text(row,"CodebookType"), ...
                decoded,sixgr.phy.pucch.PUCCHUtil.number( ...
                row,"ConfigurationEpoch",0));
        end
    end
end
