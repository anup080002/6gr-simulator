function ok = testObservedREAllocationRuntimeTruth()
%TESTOBSERVEDREALLOCATIONRUNTIMETRUTH Executed TX owns observed grid rows.

runRoot = tempname;
mkdir(runRoot);
cleanup = onCleanup(@() localCleanup(runRoot)); %#ok<NASGU>
cfg = sixgr.config.defaultConfig();
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.channel.model = "AWGN";
cfg.channel.awgnOnly = true;
cfg.channel.tdlProfile = "";
cfg.channel.cdlProfile = "";
cfg.channel.fading.profile = "";
cfg.phy.carrier.NSizeGrid = 24;
cfg.phy.csirs.enable = false;
cfg.phy.pdsch.executionProfile = "phy_calibration";
cfg.phy.pdsch.prbSet = 0:23;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.numPorts = 1;
cfg.phy.pdsch.PMI = NaN;
cfg.phy.pusch.numLayers = 1;
cfg.phy.pusch.prbSet = 0:23;
cfg.phy.pusch.NumAntennaPorts = 1;
cfg.phy.pusch.numAntennaPorts = 1;
cfg.phy.pusch.PMI = NaN;
cfg.phy.pusch.tpmi = NaN;
cfg = sixgr.config.normalizeConfig(cfg);

[txDL, ~] = sixgr.phy.dl.PDSCH_Tx(cfg, "CompactOutput", false);
dl = sixgr.truth.buildObservedREAllocation(txDL, ...
    "Direction", "DL", "AbsoluteSlot", 5, "CellID", 1, ...
    "UEID", 7, "AllocationID", "focused_dl_runtime");
localAssertRuntimeRows(dl, "DL", "PDSCH", 5, 7);
dlMaterialized = sixgr.phy.frame.ChannelAllocationMaterializer.materializePDSCH( ...
    txDL.Carrier, txDL.PDSCH, "AbsoluteSlot", 5);
assert(sum(dl.re_count) == size(unique( ...
    dlMaterialized.ActualCoordinates0Based, "rows"), 1), ...
    "DL runtime row RE count must equal exact executed occupied coordinates.");

[txUL, ~] = sixgr.phy.ul.PUSCH_Tx(cfg, "CompactOutput", false);
ul = sixgr.truth.buildObservedREAllocation(txUL, ...
    "Direction", "UL", "AbsoluteSlot", 6, "CellID", 1, ...
    "UEID", 7, "AllocationID", "focused_ul_runtime");
localAssertRuntimeRows(ul, "UL", "PUSCH", 6, 7);
ulMaterialized = sixgr.phy.frame.ChannelAllocationMaterializer.materializePUSCH( ...
    txUL.Carrier, txUL.PUSCH, "AbsoluteSlot", 6);
assert(sum(ul.re_count) == size(unique( ...
    ulMaterialized.ActualCoordinates0Based, "rows"), 1), ...
    "UL runtime row RE count must equal exact executed occupied coordinates.");

dciBits = int8(mod((0:31).', 2));
cfgPDCCH = cfg;
cfgPDCCH.phy.carrier.NSizeGrid = 52;
cfgPDCCH = sixgr.config.normalizeConfig(cfgPDCCH);
[executedPDCCH, ~] = sixgr.phy.dl.PDCCH_Tx(cfgPDCCH, ...
    "DCIBits", dciBits, "K", numel(dciBits), "OFDMModulate", true);
pdcchTx = struct("Carrier", executedPDCCH.Carrier, ...
    "Grid", executedPDCCH.Grid, ...
    "PDCCHIndices", executedPDCCH.PDCCHInd, ...
    "DMRSIndices", executedPDCCH.DMRSInd);
pdcch = sixgr.truth.buildObservedREAllocation(pdcchTx, ...
    "Direction", "DL", "Channel", "PDCCH", "AbsoluteSlot", 7, ...
    "CellID", 1, "UEID", 7, "AllocationID", "focused_pdcch_runtime");
localAssertRuntimeRows(pdcch, "DL", "PDCCH", 7, 7);
assert(all(ismember(unique(string(pdcch.component)), ["DATA"; "DM-RS"])), ...
    "PDCCH observed rows may contain only executed data and DM-RS REs.");
assert(sum(double(pdcch.re_count)) == numel(unique([ ...
    double(executedPDCCH.PDCCHInd(:)); double(executedPDCCH.DMRSInd(:))])), ...
    "PDCCH runtime row RE count must equal its exact executed indices.");

uciBits = int8([1; 0; 1; 1]);
pucchFixture = sixgr.phy.pucch.PUCCHFixtureFactory.connected(2, uciBits, ...
    "RNTI", 320, "NSizeGrid", double(cfg.phy.carrier.NSizeGrid));
pucchTrial = sixgr.link.runPUCCHWaveformTrial(pucchFixture.Carrier, ...
    "Assignment", pucchFixture.Assignment, ...
    "Report", pucchFixture.Report, ...
    "ReceiverContext", pucchFixture.Context, ...
    "Carrier", pucchFixture.Carrier, ...
    "SNR_dB", 35, "Seed", 320);
assert(logical(pucchTrial.Ok) && isstruct(pucchTrial.Transmitter), ...
    "The focused PUCCH transmitter/receiver trial must pass before occupancy export.");
pucch = sixgr.truth.buildObservedREAllocation(pucchTrial.Transmitter, ...
    "Direction", "UL", "Channel", "PUCCH", "AbsoluteSlot", 8, ...
    "CellID", 1, "UEID", 7, "AllocationID", "focused_pucch_runtime");
localAssertRuntimeRows(pucch, "UL", "PUCCH", 8, 7);
assert(all(ismember(unique(string(pucch.component)), ["DATA"; "DM-RS"])), ...
    "PUCCH observed rows may contain only executed data and DM-RS REs.");
assert(sum(double(pucch.re_count)) == numel(unique([ ...
    double(pucchTrial.Transmitter.PUCCHIndices(:)); ...
    double(pucchTrial.Transmitter.DMRSIndices(:))])), ...
    "PUCCH runtime row RE count must equal its exact executed indices.");

ok = true;
fprintf('%s\n', ['PASS testObservedREAllocationRuntimeTruth: executed ' ...
    'PDSCH/PUSCH/PDCCH/PUCCH Toolbox indices own the observed grid.']);
end

function localAssertRuntimeRows(T, direction, channel, slot0, ueID)
assert(istable(T) && ~isempty(T), ...
    "An executed transmitter must produce observed RE rows.");
assert(all(string(T.direction) == direction));
assert(all(string(T.channel) == channel));
assert(all(double(T.absolute_slot) == slot0));
assert(all(double(T.ue_id) == ueID));
assert(all(string(T.evidence_scope) == "runtime_observed_tx_occupancy"));
assert(all(string(T.authority) == "executed_tx_toolbox_config_and_indices"));
assert(all(double(T.subcarrier_count) >= 1) && all(double(T.re_count) >= 1));
assert(all(double(T.symbol_index) >= 0 & double(T.symbol_index) < 14));
end

function localCleanup(pathText)
if isfolder(pathText)
    rmdir(pathText, "s");
end
end
