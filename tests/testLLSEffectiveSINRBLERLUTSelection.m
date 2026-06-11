function ok = testLLSEffectiveSINRBLERLUTSelection()
%TESTLLSEFFECTIVESINRBLERLUTSELECTION Verify LUT-backed CQI selection path.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg = sixgr.util.structSet(cfg, "phy.csi.sinrToCQIMode", "effective_sinr_bler_lut");
cfg = sixgr.util.structSet(cfg, "phy.csi.effectiveSINRMethod", "eesm");
cfg = sixgr.util.structSet(cfg, "phy.csi.targetBLER", 0.1);
cfg = sixgr.util.structSet(cfg, "phy.csi.cqiTable", "table1");

try
    sixgr.link.resolveWidebandCQI(struct("WidebandSINR_dB", 0, "PerRBSINR_dB", [-2 -1 0 1]), cfg, "DL");
    error("sixgr:test:ExpectedUncalibratedBLERLUTRejection", ...
        "Uncalibrated effective-SINR BLER LUT mode must be rejected by default.");
catch ME
    assert(strcmp(ME.identifier, "sixgr:link:UncalibratedBLERLUT"), ...
        "Unexpected error while checking uncalibrated BLER LUT rejection: %s", ME.identifier);
end

cfg = sixgr.util.structSet(cfg, "phy.csi.allowUncalibratedBLERLUT", true);
low = sixgr.link.resolveWidebandCQI(struct("WidebandSINR_dB", 0, "PerRBSINR_dB", [-2 -1 0 1]), cfg, "DL");
high = sixgr.link.resolveWidebandCQI(struct("WidebandSINR_dB", 15, "PerRBSINR_dB", [12 14 15 16]), cfg, "DL");

assert(strcmpi(string(low.Mode), "effective_sinr_bler_target_lut"), ...
    "CQI resolver must advertise the LUT-backed BLER mode when explicitly configured.");
assert(strcmpi(string(low.BLERLUTSource), "resolveWidebandCQI.lab_default_bler_lut"), ...
    "Default BLER LUT source must stay honestly labeled as a lab default.");
assert(strcmpi(string(low.BLERLUTValueRole), "uncalibrated_lab_default"), ...
    "Default BLER LUT value role must identify the uncalibrated lab default.");
assert(all(isfinite(low.PredictedBLERByCQI) | isnan(low.PredictedBLERByCQI)), ...
    "Predicted BLER vector must contain numeric LUT-backed values.");
assert(double(high.WidebandCQI) > double(low.WidebandCQI), ...
    "Higher effective SINR must produce a higher CQI under the LUT-backed selector.");

cfgCatalog = sixgr.util.structSet(cfg, "phy.pdsch.configuredMCSIndex", 10);
cfgCatalog = sixgr.util.structSet(cfgCatalog, "phy.pdsch.eesmBetaMCSIndex", [9 10 11]);
cfgCatalog = sixgr.util.structSet(cfgCatalog, "phy.pdsch.eesmBetaByMCS_dB", [2.0 4.0 6.0]);
catalog = sixgr.link.resolveWidebandCQI(struct("WidebandSINR_dB", 8, "PerRBSINR_dB", [4 8 10 12]), cfgCatalog, "DL");
assert(abs(double(catalog.EffectiveSINRBeta_dB) - 4.0) < 1e-12, ...
    "EESM beta must resolve from the configured MCS-index catalog when MCS context is available.");
assert(strcmpi(string(catalog.EffectiveSINRBetaSource), "phy.pdsch.eesmBetaByMCS_dB") && ...
    strcmpi(string(catalog.EffectiveSINRBetaValueRole), "configured_mcs_index_beta_catalog"), ...
    "EESM beta catalog rows must carry explicit calibrated-catalog provenance.");

ok = true;
end
