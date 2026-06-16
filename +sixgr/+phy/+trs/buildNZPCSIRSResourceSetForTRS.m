function resourceSet = buildNZPCSIRSResourceSetForTRS(cfg)
%BUILDNZPCSIRSRESOURCESETFORTRS Materialize toolbox NZP-CSI-RS TRS resource.

needed = ["nrCarrierConfig","nrCSIRSConfig","nrCSIRS","nrCSIRSIndices"];
for ii = 1:numel(needed)
    if isempty(which(char(needed(ii))))
        error("sixgr:phy:trs:ToolboxMissing", ...
            "Strict TRS requires 5G Toolbox function %s.", needed(ii));
    end
end

carrier = nrCarrierConfig;
carrier.NCellID = double(cfg.NCellID);
carrier.NSizeGrid = double(cfg.NSizeGrid);
carrier.NStartGrid = double(cfg.NStartGrid);
carrier.SubcarrierSpacing = double(cfg.SubcarrierSpacingKHz);
carrier.NSlot = double(cfg.SlotNumbers(1));

csirs = nrCSIRSConfig;
csirs.CSIRSType = char(string(cfg.CSIRSType));
csirs.CSIRSPeriod = char(string(cfg.CSIRSPeriod));
csirs.RowNumber = double(cfg.RowNumber);
if double(cfg.RowNumber) == 1
    csirs.Density = "three";
end
csirs.SymbolLocations = double(cfg.SymbolLocation);
csirs.SubcarrierLocations = double(cfg.SubcarrierLocation);
csirs.NumRB = double(cfg.NumRB);
csirs.RBOffset = double(cfg.RBOffset);
csirs.NID = double(cfg.NID);

resourceSet = struct();
resourceSet.Carrier = carrier;
resourceSet.CSIRS = csirs;
resourceSet.SlotNumbers = double(cfg.SlotNumbers(:).');
resourceSet.ImplementationStatus = "toolbox_nzp_csirs_trs_resource_materialized";
end
