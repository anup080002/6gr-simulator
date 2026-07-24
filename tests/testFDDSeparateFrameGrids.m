function ok = testFDDSeparateFrameGrids()
%TESTFDDSEPARATEFRAMEGRIDS Prove simultaneous FDD uses distinct grids/waveforms.

setup6GRSimToolkit("Verbose", false);
fdd = sixgr.phy.frame.FDDCarrierContexts.create( ...
    "CellID", 7, "DLCCID", 1, "ULCCID", 1, ...
    "DLBWPID", 10, "ULBWPID", 20, ...
    "DLCenterFrequencyHz", 2.14e9, ...
    "ULCenterFrequencyHz", 1.95e9, ...
    "SubcarrierSpacingKHz", 30, ...
    "DLNumRB", 106, "ULNumRB", 106, ...
    "ULTimingAdvanceSamples", 32);
assert(fdd.DuplexMode == "FDD");
assert(fdd.Downlink.GridID ~= fdd.Uplink.GridID);
assert(fdd.Downlink.CenterFrequencyHz ~= fdd.Uplink.CenterFrequencyHz);
assert(fdd.Uplink.TimingAdvanceSamples == 32);
assert(fdd.Downlink.Mu == 1 && fdd.Uplink.Mu == 1);
assert(fdd.SlotsPerFrame == 20 && fdd.SymbolsPerSlot == 14);
assert(fdd.isAvailable(0, "DL", fdd.Downlink));
assert(fdd.isAvailable(0, "UL", fdd.Uplink));

dlKey = fdd.resourceKey("DL", 4, 3, 5, 2, 0);
ulKey = fdd.resourceKey("UL", 4, 3, 5, 2, 0);
assert(string(dlKey) ~= string(ulKey), ...
    "Simultaneous DL/UL FDD resources collided.");

% Materialize real Toolbox channel allocations at one common frame/slot.
carrierDL = localCarrier();
carrierUL = localCarrier();
pdcch = localPDCCH(carrierDL);
pdsch = nrPDSCHConfig;
pdsch.NSizeBWP = carrierDL.NSizeGrid;
pdsch.NStartBWP = carrierDL.NStartGrid;
pdsch.PRBSet = 24:47;
pdsch.SymbolAllocation = [2 10];
pdsch.MappingType = "A";
pdsch.Modulation = "QPSK";
pdsch.NumLayers = 1;
pdsch.NID = carrierDL.NCellID;
pdsch.RNTI = 41;
pusch = nrPUSCHConfig;
pusch.NSizeBWP = carrierUL.NSizeGrid;
pusch.NStartBWP = carrierUL.NStartGrid;
pusch.PRBSet = 12:35;
pusch.SymbolAllocation = [0 12];
pusch.MappingType = "B";
pusch.Modulation = "QPSK";
pusch.NumLayers = 1;
pusch.NID = carrierUL.NCellID;
pusch.RNTI = 41;

dlControl = sixgr.phy.frame.ChannelAllocationMaterializer. ...
    materializePDCCH(carrierDL, pdcch, ...
    "CCID", 1, "BWPID", 10, "AbsoluteSlot", 4, ...
    "GridID", fdd.Downlink.GridID, "TestID", "fdd_pdcch");
dlData = sixgr.phy.frame.ChannelAllocationMaterializer. ...
    materializePDSCH(carrierDL, pdsch, ...
    "CCID", 1, "BWPID", 10, "AbsoluteSlot", 4, ...
    "GridID", fdd.Downlink.GridID, "TestID", "fdd_pdsch");
ulData = sixgr.phy.frame.ChannelAllocationMaterializer. ...
    materializePUSCH(carrierUL, pusch, ...
    "CCID", 1, "BWPID", 20, "AbsoluteSlot", 4, ...
    "GridID", fdd.Uplink.GridID, "TestID", "fdd_pusch");
assert(dlControl.Exact && dlData.Exact && ulData.Exact);
assert(dlControl.GridID == fdd.Downlink.GridID && ...
    dlData.GridID == fdd.Downlink.GridID && ...
    ulData.GridID == fdd.Uplink.GridID);

% Populate physically independent grids from the exact Toolbox indices.
dlGrid = fdd.createGrid("DL", 1, 1);
ulGrid = fdd.createGrid("UL", 1, 1);
dlGrid = localMapComponent(dlGrid, dlControl.Data, 1 + 1i);
dlGrid = localMapComponent(dlGrid, dlControl.DMRS, -1 + 1i);
dlGrid = localMapComponent(dlGrid, dlData.Data, 2 + 1i);
dlGrid = localMapComponent(dlGrid, dlData.DMRS, -2 + 1i);
dlBeforeULMap = dlGrid;
ulGrid = localMapComponent(ulGrid, ulData.Data, 3 - 1i);
ulGrid = localMapComponent(ulGrid, ulData.DMRS, -3 - 1i);
assert(isequaln(dlGrid, dlBeforeULMap), ...
    "Mapping the UL allocation mutated the DL grid.");
expectedDL = unique([dlControl.Data.Indices1Based; ...
    dlControl.DMRS.Indices1Based; dlData.Data.Indices1Based; ...
    dlData.DMRS.Indices1Based]);
expectedUL = unique([ulData.Data.Indices1Based; ...
    ulData.DMRS.Indices1Based]);
assert(isequal(find(dlGrid ~= 0), expectedDL));
assert(isequal(find(ulGrid ~= 0), expectedUL));

% Both directional grids become independent, nonempty OFDM waveforms at
% the same NFrame/NSlot. No TDD token participates in their placement.
dlWaveform = nrOFDMModulate(carrierDL, dlGrid, "Windowing", 0);
ulWaveform = nrOFDMModulate(carrierUL, ulGrid, "Windowing", 0);
assert(~isempty(dlWaveform) && ~isempty(ulWaveform));
assert(size(dlWaveform, 1) == size(ulWaveform, 1));
dlRecovered = nrOFDMDemodulate(carrierDL, dlWaveform);
ulRecovered = nrOFDMDemodulate(carrierUL, ulWaveform);
assert(localNMSE(dlGrid, dlRecovered) <= 1e-12);
assert(localNMSE(ulGrid, ulRecovered) <= 1e-12);

% A positive UL timing-advance command moves the actual UL waveform
% earlier while preserving its length and leaving DL untouched.
advanced = fdd.applyUplinkTimingAdvance(ulWaveform);
expectedAdvanced = [ulWaveform(33:end, :); ...
    zeros(32, size(ulWaveform, 2), "like", ulWaveform)];
assert(advanced.TimingAdvanceApplied);
assert(advanced.TimingAdvanceSamples == 32);
assert(advanced.LengthPreserved && ...
    isequal(size(advanced.Waveform), size(ulWaveform)));
assert(isequaln(advanced.Waveform, expectedAdvanced));
assert(isequaln(dlWaveform, nrOFDMModulate(carrierDL, dlGrid, ...
    "Windowing", 0)));

dlAllocation = dlControl.Allocation;
ulAllocation = ulData.Allocation;
simultaneous = sixgr.phy.frame.ResourceAllocationValidator.validateSet( ...
    [dlAllocation ulAllocation], fdd);
assert(simultaneous.ActualValid, ...
    "Separate FDD grids must permit simultaneous DL and UL resources.");
assert(numel(unique(simultaneous.Occupancy.REKey)) == ...
    height(simultaneous.Occupancy));

% The public frame facade must expose the same two directional contexts.
cfg = struct;
cfg.frequency = struct("center_frequency_hz", 2.14e9, ...
    "dl_center_frequency_hz", 2.14e9, ...
    "ul_center_frequency_hz", 1.95e9, ...
    "range_name", "FR1", "bandwidth_hz", 40e6, ...
    "duplex_mode", "FDD", "n_size_grid", 106);
cfg.frame = struct("scs_khz", 30, "cp_type", "normal");
cfg.phy = struct;
cfg.phy.carrier = struct("NCellID", 7, "NSizeGrid", 106, ...
    "NStartGrid", 0);
cfg.phy.duplex = struct("mode", "FDD", "fdd", struct( ...
    "dlCenterFrequencyHz", 2.14e9, ...
    "ulCenterFrequencyHz", 1.95e9, ...
    "dlCCID", 1, "ulCCID", 1, ...
    "dlBWPID", 10, "ulBWPID", 20, ...
    "ulNSizeGrid", 106, "ulTimingAdvanceSamples", 32));
engine = sixgr.phy.FrameStructureEngine(cfg, "FrameCoreOnly", true);
assert(engine.DuplexMode == "FDD");
assert(engine.FDDContexts.Downlink.GridID == fdd.Downlink.GridID);
assert(engine.FDDContexts.Uplink.GridID == fdd.Uplink.GridID);
assert(engine.FDDContexts.isAvailable(4, "DL", ...
    engine.FDDContexts.Downlink));
assert(engine.FDDContexts.isAvailable(4, "UL", ...
    engine.FDDContexts.Uplink));

localAssertError(@() fdd.TDDToken(0), ...
    "sixgr:phy:frame:FDDHasNoTDDToken");
localAssertError(@() fdd.isAvailable(0, "DL", fdd.Uplink), ...
    "sixgr:phy:frame:FDDGridContextMismatch");
badState = struct("DuplexMode", "FDD", ...
    "ResolvedDirection", "F");
localAssertError(@() sixgr.phy.frame.SlotFormatResolver.isAvailable( ...
    badState, 0, 0, 1, "DL"), ...
    "sixgr:phy:frame:TDDResolverCalledForFDD");
ok = true;
end

function carrier = localCarrier()
carrier = nrCarrierConfig;
carrier.NCellID = 7;
carrier.SubcarrierSpacing = 30;
carrier.CyclicPrefix = "normal";
carrier.NSizeGrid = 106;
carrier.NStartGrid = 0;
carrier.NFrame = 2;
carrier.NSlot = 4;
end

function pdcch = localPDCCH(carrier)
coreset = nrCORESETConfig;
coreset.CORESETID = 0;
coreset.Duration = 2;
coreset.FrequencyResources = [1 1];
searchSpace = nrSearchSpaceConfig;
searchSpace.SearchSpaceID = 1;
searchSpace.CORESETID = 0;
searchSpace.StartSymbolWithinSlot = 0;
searchSpace.SlotPeriodAndOffset = [1 0];
searchSpace.Duration = 1;
searchSpace.NumCandidates = [0 0 1 0 0];
pdcch = nrPDCCHConfig;
pdcch.NSizeBWP = carrier.NSizeGrid;
pdcch.NStartBWP = carrier.NStartGrid;
pdcch.CORESET = coreset;
pdcch.SearchSpace = searchSpace;
pdcch.AggregationLevel = 4;
pdcch.AllocatedCandidate = 1;
pdcch.RNTI = 41;
pdcch.DMRSScramblingID = carrier.NCellID;
end

function grid = localMapComponent(grid, component, value)
indices = double(component.Indices1Based(:));
assert(~isempty(indices), "%s materialized no RE.", component.Label);
grid(indices) = value;
end

function value = localNMSE(reference, observed)
assert(isequal(size(reference), size(observed)));
value = sum(abs(observed(:) - reference(:)).^2) / ...
    max(sum(abs(reference(:)).^2), eps);
end

function localAssertError(f, id)
try
    f();
catch ME
    assert(string(ME.identifier) == string(id), ...
        "Observed %s, expected %s.", ME.identifier, id);
    return;
end
error("sixgr:test:ExpectedErrorNotThrown", "Expected %s.", id);
end
