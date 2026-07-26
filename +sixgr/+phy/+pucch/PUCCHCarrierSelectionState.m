classdef PUCCHCarrierSelectionState
    %PUCCHCARRIERSELECTIONSTATE Causal PUCCH serving/feedback-cell state.

    properties (SetAccess=private)
        ServingCell
        PUCCHCell
        ConfiguredCells
        SelectionEventID
        Digest
    end

    methods
        function obj = PUCCHCarrierSelectionState( ...
                configuredCells,servingCell,pucchCell,eventID)
            configuredCells = unique(double(configuredCells(:).'),"stable");
            if isempty(configuredCells) || ...
                    ~ismember(double(servingCell),configuredCells) || ...
                    ~ismember(double(pucchCell),configuredCells) || ...
                    strlength(string(eventID))==0
                error("sixgr:phy:pucch:WrongResource", ...
                    "PUCCH-cell selection requires configured cells and decoded provenance.");
            end
            obj.ServingCell = double(servingCell);
            obj.PUCCHCell = double(pucchCell);
            obj.ConfiguredCells = configuredCells;
            obj.SelectionEventID = string(eventID);
            obj.Digest = sixgr.phy.pucch.PUCCHUtil.hash(struct( ...
                "ServingCell",obj.ServingCell,"PUCCHCell",obj.PUCCHCell, ...
                "ConfiguredCells",obj.ConfiguredCells, ...
                "SelectionEventID",obj.SelectionEventID));
        end
    end
end
