classdef HARQACKCodebookBuilder
    %HARQACKCODEBOOKBUILDER Release-pinned Type-1/2/3 event ordering.

    methods (Static)
        function state = build(type,eventData,epoch)
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
                if type == "TYPE2_DYNAMIC"
                    dai = arrayfun(@(x) double(x.Data.DAI),events);
                    if any(dai < 1 | dai > 4)
                        error("sixgr:phy:pucch:UnsupportedHARQCodebook", ...
                            "Type-2 DAI values must be in [1,4].");
                    end
                end
            end
            state = sixgr.phy.pucch.HARQACKCodebookState(type,events,epoch);
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
