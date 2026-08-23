function ok = testCSIRSRPPhysicalMeasurement()
%TESTCSIRSRPPHYSICALMEASUREMENT Validate physical CSI-RSRP on the real DL chain.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg.phy.nTxAnt = 1;
cfg.phy.nRxAnt = 1;
cfg.phy.pdsch.enable = true;
cfg.phy.pdsch.nLayers = 1;
cfg.phy.pdsch.numLayers = 1;
cfg.phy.pdsch.SymbolAllocation = [2 12];
cfg.phy.pdsch.symbolAllocation = [2 12];
cfg.phy.pdsch.MappingType = "A";
cfg.phy.pdsch.mappingType = "A";
cfg.phy.pdsch.PRBSet = 0:(double(cfg.phy.carrier.NSizeGrid) - 1);
cfg.phy.pdsch.prbSet = cfg.phy.pdsch.PRBSet;
cfg.phy.pdsch.mcsTable = "calibration_explicit";
cfg.phy.pdsch.mcsIndex = 0;
cfg.phy.csirs.enable = true;
cfg.phy.csirs.period_slots = 1;
cfg.phy.csirs.offset_slots = 0;
cfg.phy.csirs.numResources = 1;
cfg.phy.csirs.nPorts = 1;
cfg.phy.csirs.rowNumber = 2;
cfg.phy.csirs.symbolLocations = 6;
cfg.phy.csirs.subcarrierLocations = 0;
cfg.phy.csirs.rbOffset = 0;
cfg.phy.csirs.numRB = double(cfg.phy.carrier.NSizeGrid);
cfg.phy.csirs.density = "one";
cfg.phy.csirs.precoderMatrices = 1;
cfg.phy.csirs.precoderDigests = ...
    sixgr.phy.mimo.MatrixContract.digest(cfg.phy.csirs.precoderMatrices);
cfg.phy.csirs.precoderBeamIndices = 0;
cfg.phy.csirs.precoderCodebookType = "focused_test_unit_norm_physical_precoder";

result = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", 1, ...
    "SNR_dB", 20, "ExecutionProfile", "phy_calibration");
assert(istable(result.CSIRSTrialTable) && height(result.CSIRSTrialTable) == 1, ...
    "The production DL chain must emit one measured CSI-RS runtime row.");
row = result.CSIRSTrialTable(1,:);
assert(logical(row.Transmitted) && logical(row.Observed) && ...
    logical(row.ResourceExtractionAvailable), ...
    "CSI-RSRP qualification requires the transmitted runtime CSI-RS resource.");
assert(strcmpi(string(row.PhysicalMeasurementStatus), "available") && ...
    isfinite(double(row.MeasurementRSRP_dBm)), ...
    "Physical CSI-RSRP must be available when the runtime PowerContext is sqrt(mW).");
expected = double(row.MeasurementRelativeRSRP_dB) - ...
    20 .* log10(double(row.MeasurementGridScaleToSqrtW)) + 30;
fprintf("CSI-RSRP relative=%.12g dB physical=%.12g dBm expected=%.12g dBm scale=%.12g Nfft=%.0f\n", ...
    double(row.MeasurementRelativeRSRP_dB), double(row.MeasurementRSRP_dBm), ...
    expected, double(row.MeasurementGridScaleToSqrtW), double(row.MeasurementFFTSize));
assert(abs(double(row.MeasurementRSRP_dBm) - expected) < 1e-8, ...
    "CSI-RSRP dBm must include Nfft and mW-to-W resource-grid scaling.");
assert(strcmpi(string(row.PhysicalMeasurementStandard), ...
    "3GPP_TS_38.215_via_nrCSIRSMeasurements"));
assert(strcmpi(string(row.MeasurementSource), ...
    "nrCSIRSMeasurements_runtime_received_grid"));
assert(strcmpi(string(row.MeasurementAntennaAggregation), ...
    "maximum_per_receive_antenna_rsrp_ts_38_215_diversity_rule"), ...
    "CSI-RSRP must follow the TS 38.215 receiver-diversity reporting rule.");
assert(isfinite(double(row.ReferenceMeasuredSINR_dB)) && ...
    strcmpi(string(row.ReferenceMeasuredSINRStatus), "available") && ...
    strcmpi(string(row.ReferenceMeasuredSINRSource), ...
    "csirs_resource_selective_hest_over_measured_noise_interference_variance"), ...
    "CSI-SINR must come from the CSI-RS estimate/noise plane, not PDSCH post-equalization SINR.");
ok = true;
end
