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
absoluteSlot = double(cfg.SlotNumbers(1));
carrier.NSlot = mod(absoluteSlot,double(carrier.SlotsPerFrame));
carrier.NFrame = mod(floor(absoluteSlot/double(carrier.SlotsPerFrame)),1024);

csirs = nrCSIRSConfig;
csirs.CSIRSType = char(string(cfg.CSIRSType));
csirs.CSIRSPeriod = char(string(cfg.CSIRSPeriod));
csirs.RowNumber = double(cfg.RowNumber);
if double(cfg.RowNumber) == 1
    csirs.Density = "three";
end
locations=reshape(double(cfg.SymbolLocation),1,[]);
assert(numel(locations)==2 && any(all(locations==[4 8;5 9;6 10],2)), ...
    'sixgr:phy:trs:UnsupportedTrackingSymbolPair', ...
    'The implemented FR1/FR2 common TRS pattern requires an explicit symbol pair [4,8], [5,9] or [6,10].');
assert(double(cfg.RowNumber)==1 && double(cfg.NumCSIRSPortsRequested)==1, ...
    'sixgr:phy:trs:InvalidTrackingDensityPorts', ...
    'trs-Info requires one-port density-three NZP CSI-RS (TS 38.211 mapping row 1).');
csirs.SymbolLocations = locations(1);
csirs.SubcarrierLocations = double(cfg.SubcarrierLocation);
csirs.NumRB = double(cfg.NumRB);
csirs.RBOffset = double(cfg.RBOffset);
csirs.NID = double(cfg.NID);

resourceSet = struct();
resourceSet.Carrier = carrier;
resourceSet.CSIRS = csirs;
resourceSet.Resources=cell(1,numel(locations));
for resourceIndex=1:numel(locations)
    resource=csirs; resource.SymbolLocations=locations(resourceIndex);
    resourceSet.Resources{resourceIndex}=resource;
end
resourceSet.SlotNumbers = double(cfg.SlotNumbers(:).');
resourceSet.ImplementationStatus = "toolbox_nzp_csirs_trs_resource_materialized";
end
