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

Hwb = [1.05 + 0.05j, 0.35 - 0.10j, 0.20 + 0.03j, 0.05; ...
       0.18 + 0.04j, 0.95 + 0.02j, 0.12 - 0.08j, 0.30 + 0.05j];
Hest = repmat(reshape(Hwb, 1, 1, size(Hwb, 1), size(Hwb, 2)), [24, 14, 1, 1]);
rxGrid = complex(zeros(24, 14, 1));
refInd = uint32([1; 9; 17]);
rxGrid(double(refInd)) = [1+1j; 2; 0.5-0.5j];
refSym = ones(numel(refInd), 1);
expectedMeasuredRSRP_dB = 10 * log10(mean(abs(double(rxGrid(double(refInd)))).^2));

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
assert(strcmpi(string(csi1.RSRPSource), "channel_estimate_gain_proxy"), ...
    "CSI feedback must label proxy RSRP honestly when no measured RS is provided.");
assert(strcmpi(string(csi1.ReferenceSINRValueStatus), "fallback_to_channel_gain_over_noise"), ...
    "CSI feedback must disclose when SINR fell back to channel-gain-over-noise instead of a measured RS SINR.");

cfgSISO = cfg;
cfgSISO.phy.nTxAnt = 1;
cfgSISO.phy.nRxAnt = 1;
Hgrid = ones(24, 14);
csiGrid = sixgr.phy.dl.CSI_Feedback(Hgrid, 1, cfgSISO, "MaxRank", 1);
assert(abs(double(csiGrid.SINR_dB)) < 1e-9, ...
    "2-D SISO resource-grid Hest must collapse to a wideband scalar and report 0 dB for unit gain/unit noise.");

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

ulMetricNoRef = sixgr.phy.ul.measureULLinkState(Hest, 0.02, cfg);
assert(~isfinite(ulMetricNoRef.CQI), ...
    "UL CQI must remain unavailable when no measured UL reference-signal SINR was provided.");
assert(strcmpi(string(ulMetricNoRef.SINRValueStatus), "fallback"), ...
    "UL link-state export must disclose the SINR fallback state instead of converting it into measured CQI.");

ulMetricMeasured = sixgr.phy.ul.measureULLinkState(Hest, 0.02, cfg, ...
    "ReceivedGrid", rxGrid, "ReferenceIndices", refInd, "ReferenceSymbols", refSym);
assert(isfinite(ulMetricMeasured.CQI), ...
    "UL CQI must be finite when measured UL reference-signal SINR is available.");

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
cfgRun.phy.csirs.enable = true;
cfgRun.phy.csirs.nPorts = 1;
cfgRun.phy.csirs.rowNumber = 1;
cfgRun.phy.nRxAnt = 1;
dl = sixgr.link.runDLPDSCHThroughput(cfgRun, "NumFrames", 2, "SNR_dB", 20);
assert(istable(dl.TrialTable), "DL runtime must return a trial table.");
assert(all(ismember(["CRI","PMIType","PMICodebookMode","CSIReportMode","CSIPayloadBitLength","CSIPayloadHex"], string(dl.TrialTable.Properties.VariableNames))), ...
    "DL trial tables must export CSI runtime fields.");
assert(istable(dl.CSIRSTrialTable) && height(dl.CSIRSTrialTable) == 2, ...
    "DL runtime must emit one dedicated CSI-RS runtime row per waveform trial when CSI-RS is enabled.");
assert(all(logical(dl.CSIRSTrialTable.Transmitted)) && all(logical(dl.CSIRSTrialTable.Observed)) && ...
    all(logical(dl.CSIRSTrialTable.Consumed)) && ...
    all(strcmpi(string(dl.CSIRSTrialTable.MeasurementSource), "received_csirs_reference_signal_power")), ...
    "CSI-RS runtime rows must come from transmitted and observed waveform reference REs consumed by CSI feedback.");

cfgNoCSIRS = cfgRun;
cfgNoCSIRS.phy.csirs.enable = false;
dlNoCSIRS = sixgr.link.runDLPDSCHThroughput(cfgNoCSIRS, "NumFrames", 1, "SNR_dB", 20);
assert(istable(dlNoCSIRS.CSIRSTrialTable) && isempty(dlNoCSIRS.CSIRSTrialTable), ...
    "DL runtime must not fabricate CSI-RS rows when CSI-RS is inactive.");

ul = sixgr.link.runULPUSCHThroughput(cfgRun, "NumFrames", 2, "SNR_dB", 20);
assert(istable(ul.TrialTable), "UL runtime must return a trial table.");
assert(all(ismember(["CRI","PMIType","PMICodebookMode","CSIReportMode","CSIPayloadBitLength","CSIPayloadHex"], string(ul.TrialTable.Properties.VariableNames))), ...
    "UL trial tables must export CSI runtime fields.");

ok = true;
end
