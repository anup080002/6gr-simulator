classdef PUCCHPowerControlState
    %PUCCHPOWERCONTROLSTATE Immutable causal PUCCH power-control ledger.

    properties (SetAccess=private)
        Data
        Digest
    end

    methods
        function obj = PUCCHPowerControlState(data)
            required = ["Mu","MRB","P0dBm","PathlossdB","DeltaFdB", ...
                "DeltaTFdB","ClosedLoopAdjustmentdB","PCMAXdBm", ...
                "PathlossReferenceRSID","TPCCommandSource","StateID"];
            sixgr.phy.pucch.UCIReport.requireFields(data,required);
            numericFields = ["Mu","MRB","P0dBm","PathlossdB", ...
                "DeltaFdB","DeltaTFdB","ClosedLoopAdjustmentdB", ...
                "PCMAXdBm","PathlossReferenceRSID"];
            values = zeros(size(numericFields));
            for index = 1:numel(numericFields)
                values(index) = double(data.(numericFields(index)));
            end
            if any(~isfinite(values)) || values(1) < 0 || ...
                    values(1) ~= fix(values(1)) || values(2) < 1 || ...
                    values(2) ~= fix(values(2)) || ...
                    values(4) < 0 || strlength(string(data.StateID)) == 0 || ...
                    strlength(string(data.TPCCommandSource)) == 0
                error("sixgr:phy:pucch:InvalidPowerControlState", ...
                    "PUCCH power-control state is incomplete or nonphysical.");
            end
            obj.Data = data;
            obj.Digest = sixgr.phy.pucch.PUCCHUtil.hash(data);
        end
    end
end
