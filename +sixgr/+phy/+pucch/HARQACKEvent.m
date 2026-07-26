classdef HARQACKEvent
    %HARQACKEVENT Immutable decoded PDSCH/DCI/SPS feedback event.

    properties (SetAccess=private)
        Data
        Digest
    end

    methods
        function obj = HARQACKEvent(data)
            required = ["DAI","EventIndex","PDSCHID","Priority", ...
                "ServingCell","State"];
            sixgr.phy.pucch.UCIReport.requireFields(data,required);
            state = upper(string(data.State));
            if ~ismember(state,["ACK","NACK","DTX"])
                error("sixgr:phy:pucch:UnsupportedHARQCodebook", ...
                    "HARQ event State must be ACK, NACK or DTX.");
            end
            data.State = state;
            obj.Data = data;
            obj.Digest = sixgr.phy.pucch.PUCCHUtil.hash(data);
        end
    end
end
