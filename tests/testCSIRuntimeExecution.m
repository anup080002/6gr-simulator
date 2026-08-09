function ok = testCSIRuntimeExecution()
%TESTCSIRUNTIMEEXECUTION Verify runtime PMI/RI/CRI computation and exports.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.phy.nTxAnt = 4;
cfg.phy.nRxAnt = 2;
cfg = sixgr.util.structSet(cfg, "phy.csi.reportCQI", true);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportPMI", true);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportRI", true);
cfg = sixgr.util.structSet(cfg, "phy.csi.reportCRI", true);
cfg = sixgr.util.structSet(cfg, "phy.csirs.numResources", 4);
cfg = sixgr.util.structSet(cfg, "phy.beamManagement.trpCount", 4);

resourceCfg = cfg;
resourceCfg.phy.csirs.enable = true;
resourceCfg.phy.csirs.nPorts = 2;
resourceCfg.phy.csirs.numResources = 2;
resourceCfg.phy.csirs.resourceSetID = 0;
resourceCfg.phy.csirs.resourceIDs = [0 1];
resourceCfg.phy.csirs.rowNumbers = [3 3];
resourceCfg.phy.csirs.symbolLocationsByResource = [10 11];
resourceCfg.phy.csirs.subcarrierLocationsByResource = [0 0];
resourceCfg.phy.csirs.rbOffsetsByResource = [0 0];
resourceCfg.phy.csirs.numRBsByResource = repmat(double(resourceCfg.phy.carrier.NSizeGrid), 1, 2);
[resourceCarrier, ~] = sixgr.phy.grid.makeCarrier(resourceCfg);
[resourceIndices, resourceSymbols, resourceInfo] = ...
    sixgr.phy.refsig.csirs(resourceCarrier, resourceCfg);
assert(double(resourceInfo.NumResources) == 2 && numel(resourceInfo.Resources) == 2);
assert(numel(resourceIndices) == numel(resourceSymbols));
plane = double(resourceCfg.phy.carrier.NSizeGrid) * 12 * 14;
firstRE = unique(mod(double(resourceInfo.Resources(1).Indices(:)) - 1, plane) + 1);
secondRE = unique(mod(double(resourceInfo.Resources(2).Indices(:)) - 1, plane) + 1);
assert(isempty(intersect(firstRE, secondRE)), ...
    "Configured CSI-RS beam resources must occupy disjoint physical REs.");

Hwb = [1.05 + 0.05j, 0.35 - 0.10j, 0.20 + 0.03j, 0.05; ...
       0.18 + 0.04j, 0.95 + 0.02j, 0.12 - 0.08j, 0.30 + 0.05j];
Hest = repmat(reshape(Hwb, 1, 1, size(Hwb, 1), size(Hwb, 2)), [24, 14, 1, 1]);
rxGrid = complex(zeros(24, 14, size(Hwb, 1)));
refInd = uint32([1; 9; 17]);
refSym = ones(numel(refInd), 1);
for rxIdx = 1:size(Hwb, 1)
    rxGrid(double(refInd) + (rxIdx - 1) * 24 * 14) = ...
        Hwb(rxIdx, 1) .* refSym;
end
rxRef = nrExtractResources(refInd, rxGrid);
expectedMeasuredRSRP_dB = 10 * log10(mean(abs(double(rxRef(:))).^2));
expectedRSSI_dB = 10 * log10(sum(abs(double(rxGrid(:, 1, :))).^2, "all"));
expectedRSRQ_dB = 10 * log10(2 * 10^(expectedMeasuredRSRP_dB/10) / 10^(expectedRSSI_dB/10));

cfg = sixgr.util.structSet(cfg, "phy.csi.pmiCodebookMode", "type1_su_mimo");
cfg = sixgr.util.structSet(cfg, "phy.csi.codebookType", "type1");
csi1 = sixgr.phy.dl.CSI_Feedback(Hest, 0.02, cfg, "MaxRank", 2);
assert(~isfinite(csi1.CQI), "CQI must remain unavailable when no measured reference-signal SINR was provided.");
assert(isfinite(csi1.RI) && csi1.RI >= 1 && csi1.RI <= 2, "RI must be reported from the runtime channel.");
assert(isfinite(csi1.PMI), "PMI must be reported from the runtime channel.");
assert(isfinite(csi1.CRI) && csi1.CRI >= 0 && csi1.CRI < 4, "CRI must be reported from configured resource candidates.");
assert(strcmpi(string(csi1.PMIType), "type1"), "Type-1 PMI mode must be preserved in runtime output.");
assert(size(csi1.SelectedPrecoder, 1) == 4, "Selected precoder must match the Tx-port count.");
assert(csi1.CSIPayloadBitLength > 0, "Runtime CSI feedback must export a packed payload.");
assert(strlength(string(csi1.CSIPayloadHex)) > 0, "Runtime CSI feedback must export payload hex.");
assert(~isfinite(csi1.SINR_dB) && strcmpi(string(csi1.SINRSource), "reference_signal_sinr_unavailable"), ...
    "CSI feedback must not export gain/noise model SINR when no measured reference-signal SINR was provided.");
assert(~isfinite(csi1.RSRP_dB) && strcmpi(string(csi1.RSRPSource), "measurement_unavailable"), ...
    "CSI feedback must not export channel-gain proxy RSRP when no measured reference signal was provided.");
assert(strcmpi(string(csi1.ReferenceSINRValueStatus), "unavailable_missing_reference_signal_measurement"), ...
    "CSI feedback must disclose missing reference-signal SINR instead of a gain/noise fallback.");

cfgSISO = cfg;
cfgSISO.phy.nTxAnt = 1;
cfgSISO.phy.nRxAnt = 1;
Hgrid = ones(24, 14);
csiGrid = sixgr.phy.dl.CSI_Feedback(Hgrid, 1, cfgSISO, "MaxRank", 1);
assert(~isfinite(double(csiGrid.SINR_dB)) && abs(double(csiGrid.ModelEffectiveSINR_dB)) < 1e-9, ...
    "2-D SISO Hest-only input must keep measured SINR unavailable while preserving the 0 dB model descriptor.");

[csiMeasured, infoMeasured] = sixgr.phy.dl.CSI_Feedback(Hest, 0.02, cfg, "MaxRank", 2, ...
    "ReceivedGrid", rxGrid, "ReferenceIndices", refInd, "ReferenceSymbols", refSym);
assert(isfinite(csiMeasured.CQI), ...
    "CQI must be finite when measured reference-signal SINR is available.");
assert(abs(double(csiMeasured.RSRP_dB) - expectedMeasuredRSRP_dB) < 1e-9, ...
    "CSI feedback must derive RSRP from measured reference-signal RE power.");
assert(strcmpi(string(csiMeasured.RSRPSource), "received_reference_signal_power"), ...
    "CSI feedback must label measured RSRP honestly.");
assert(strcmpi(string(infoMeasured.RSRPSource), "received_reference_signal_power"), ...
    "CSI feedback info must retain the measured-RSRP provenance.");
assert(abs(double(csiMeasured.RSSI_dB) - expectedRSSI_dB) < 1e-9 && ...
    strcmpi(string(csiMeasured.RSSISource), "received_signal_strength_indicator_measurement_bandwidth"), ...
    "CSI feedback must derive RSSI from the received measurement bandwidth.");
assert(abs(double(csiMeasured.RSRQ_dB) - expectedRSRQ_dB) < 1e-9 && ...
    strcmpi(string(csiMeasured.RSRQSource), "ts38215_n_times_rsrp_over_rssi"), ...
    "CSI feedback must compute RSRQ as N times RSRP over RSSI.");

ulMetricNoRef = sixgr.phy.ul.measureULLinkState(Hest, 0.02, cfg, ...
    "ChannelEstimateDomain", "srs_port_domain");
assert(~isfinite(ulMetricNoRef.CQI), ...
    "UL CQI must remain unavailable when no measured UL reference-signal SINR was provided.");
assert(~isfinite(ulMetricNoRef.SINR_dB) && strcmpi(string(ulMetricNoRef.SINRValueRole), "unavailable") && ...
    strcmpi(string(ulMetricNoRef.SINRValueStatus), "unavailable"), ...
    "UL link-state export must keep SINR unavailable when no measured UL reference-signal evidence is present.");
assert(strcmpi(string(ulMetricNoRef.SINRNAReason), "ul_reference_signal_sinr_not_available_from_receiver_evidence"), ...
    "UL link-state export must explain that measured receiver evidence is missing.");
assert(~isfinite(ulMetricNoRef.CSI_RSRP_dB) && strcmpi(string(ulMetricNoRef.CSI_RSRPSource), "measurement_unavailable"), ...
    "UL link-state export must not substitute channel-estimate gain for measured UL RSRP.");

ulMetricMeasured = sixgr.phy.ul.measureULLinkState(Hest, 0.02, cfg, ...
    "ReceivedGrid", rxGrid, "ReferenceIndices", refInd, "ReferenceSymbols", refSym, ...
    "ChannelEstimateDomain", "srs_port_domain");
assert(isfinite(ulMetricMeasured.CQI), ...
    "UL CQI must be finite when measured UL reference-signal SINR is available.");
assert(isfinite(ulMetricMeasured.CSI_RSSI_dB) && isfinite(ulMetricMeasured.CSI_RSRQ_dB), ...
    "UL link-state metrics must include RSSI and RSRQ when measured reference evidence is available.");

cfg = sixgr.util.structSet(cfg, "phy.csi.pmiCodebookMode", "type2_mu_mimo");
cfg = sixgr.util.structSet(cfg, "phy.csi.codebookType", "type2");
csi2 = sixgr.phy.dl.CSI_Feedback(Hest, 0.02, cfg, "MaxRank", 2);
assert(strcmpi(string(csi2.PMIType), "type2"), "Type-2 PMI mode must be preserved in runtime output.");
assert(csi2.PMICandidateCount >= csi1.PMICandidateCount, "Type-2 codebook should not reduce candidate coverage.");

cfg = sixgr.util.structSet(cfg, "phy.csi.pmiCodebookMode", "etype2_candidate");
cfg = sixgr.util.structSet(cfg, "phy.csi.codebookType", "etype2");
csi3 = sixgr.phy.dl.CSI_Feedback(Hest, 0.02, cfg, "MaxRank", 2);
assert(strcmpi(string(csi3.PMIType), "etype2"), "eType2 PMI mode must be preserved in runtime output.");
assert(csi3.PMICandidateCount >= csi2.PMICandidateCount, "eType2 codebook should not reduce candidate coverage.");

cfgRun = cfg;
cfgRun.phy.pdsch.enable = true;
cfgRun.phy.pdsch.nLayers = 1;
cfgRun.phy.pdsch.numLayers = 1;
cfgRun.phy.pdsch.SymbolAllocation = [2 12];
cfgRun.phy.pdsch.symbolAllocation = [2 12];
cfgRun.phy.pdsch.MappingType = "A";
cfgRun.phy.pdsch.mappingType = "A";
cfgRun.phy.pdsch.PRBSet = 0:(double(cfgRun.phy.carrier.NSizeGrid) - 1);
cfgRun.phy.pdsch.prbSet = cfgRun.phy.pdsch.PRBSet;
cfgRun.phy.pdsch.mcsTable = "calibration_explicit";
cfgRun.phy.pdsch.mcsIndex = 0;
cfgRun.phy.pdsch.UECapability1024QAM = false;
cfgRun.phy.pdsch.RRCEnabled1024QAM = false;
cfgRun.phy.pdsch.DCIEnabled1024QAM = false;
cfgRun.phy.pdsch.DeploymentAllows1024QAM = false;
cfgRun.phy.pdsch.FrequencyRangeAllows1024QAM = false;
cfgRun.phy.pdsch.BandAllows1024QAM = false;
cfgRun.phy.pdsch.FrequencyRange = "FR1";
cfgRun.phy.pdsch.OperatingBand = "n77";
cfgRun.phy.pdsch.DeploymentClass = "macro";
cfgRun.phy.pdsch.DCIFormat = "1_1";
cfgRun.phy.csirs.enable = true;
cfgRun.phy.csirs.numResources = 1;
cfgRun.phy.csirs.nPorts = 1;
cfgRun.phy.csirs.rowNumber = 2;
cfgRun.phy.csirs.symbolLocations = 6;
cfgRun.phy.csirs.subcarrierLocations = 0;
cfgRun.phy.csirs.rbOffset = 0;
cfgRun.phy.csirs.density = "one";
cfgRun.phy.csirs.precoderMatrices = 1;
cfgRun.phy.csirs.precoderDigests = ...
    sixgr.phy.mimo.MatrixContract.digest(cfgRun.phy.csirs.precoderMatrices);
cfgRun.phy.csirs.precoderBeamIndices = 0;
cfgRun.phy.csirs.precoderCodebookType = "focused_test_unit_norm_physical_precoder";
cfgRun.phy.nRxAnt = 1;
dl = sixgr.link.runDLPDSCHThroughput(cfgRun, "NumFrames", 2, ...
    "SNR_dB", 20, "ExecutionProfile", "phy_calibration");
assert(istable(dl.TrialTable), "DL runtime must return a trial table.");
assert(all(ismember(["CRI","PMIType","PMICodebookMode","CSIReportMode","CSIPayloadBitLength","CSIPayloadHex","CSI_RSSI_dB","CSI_RSRQ_dB"], string(dl.TrialTable.Properties.VariableNames))), ...
    "DL trial tables must export CSI runtime fields.");
if ~(istable(dl.CSIRSTrialTable) && height(dl.CSIRSTrialTable) == 2)
    statusToken = "";
    if istable(dl.TrialTable) && ismember("Notes",string(dl.TrialTable.Properties.VariableNames))
        statusToken = strjoin(unique(string(dl.TrialTable.Notes))," | ");
    end
    error("testCSIRuntimeExecution:MissingCSIRSRows", ...
        "DL runtime must emit one CSI-RS row per waveform trial; observed %d rows. Trial notes: %s", ...
        height(dl.CSIRSTrialTable),statusToken);
end
assert(all(logical(dl.CSIRSTrialTable.Transmitted)) && all(logical(dl.CSIRSTrialTable.Observed)) && ...
    all(logical(dl.CSIRSTrialTable.Consumed)) && ...
    all(logical(dl.CSIRSTrialTable.ResourceExtractionAvailable)) && ...
    all(logical(dl.CSIRSTrialTable.ChannelEstimateAvailable)) && ...
    all(logical(dl.CSIRSTrialTable.CSIMeasurementAvailable)) && ...
    all(isfinite(double(dl.CSIRSTrialTable.CQI))) && ...
    all(isfinite(double(dl.CSIRSTrialTable.RI))) && ...
    all(isfinite(double(dl.CSIRSTrialTable.PMI))) && ...
    all(isfinite(double(dl.CSIRSTrialTable.CRI))) && ...
    all(strlength(strtrim(string(dl.CSIRSTrialTable.HestDimensions))) > 0) && ...
    all(strlength(strtrim(string(dl.CSIRSTrialTable.SINRMeasurementDomain))) > 0) && ...
    all(strcmpi(string(dl.CSIRSTrialTable.MeasurementSource), "received_csirs_reference_signal_power")) && ...
    all(strcmpi(string(dl.CSIRSTrialTable.TxRuntimeMaterializationStatus), ...
        "physical_element_domain_csirs_resource_set_mapping")) && ...
    all(strcmpi(string(dl.CSIRSTrialTable.RxRuntimeObservationStatus), ...
        "runtime_observed")), ...
    "CSI-RS runtime rows must carry measured resource extraction, per-resource channel estimation, and CRI/RI/PMI/CQI evidence.");

cfgNoCSIRS = cfgRun;
cfgNoCSIRS.phy.csirs.enable = false;
dlNoCSIRS = sixgr.link.runDLPDSCHThroughput(cfgNoCSIRS, "NumFrames", 1, ...
    "SNR_dB", 20, "ExecutionProfile", "phy_calibration");
assert(istable(dlNoCSIRS.CSIRSTrialTable) && isempty(dlNoCSIRS.CSIRSTrialTable), ...
    "DL runtime must not fabricate CSI-RS rows when CSI-RS is inactive.");

ul = sixgr.link.runULPUSCHThroughput(cfgRun, "NumFrames", 2, "SNR_dB", 20);
assert(istable(ul.TrialTable), "UL runtime must return a trial table.");
assert(all(ismember(["CRI","PMIType","PMICodebookMode","CSIReportMode","CSIPayloadBitLength","CSIPayloadHex","CSI_RSSI_dB","CSI_RSRQ_dB"], string(ul.TrialTable.Properties.VariableNames))), ...
    "UL trial tables must export CSI runtime fields.");

ok = true;
end
