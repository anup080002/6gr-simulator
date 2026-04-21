function ok = testLLSEffectiveSINRBLERLUTSelection()
%TESTLLSEFFECTIVESINRBLERLUTSELECTION Verify LUT-backed CQI selection path.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg = sixgr.util.structSet(cfg, "phy.csi.sinrToCQIMode", "effective_sinr_bler_lut");
cfg = sixgr.util.structSet(cfg, "phy.csi.effectiveSINRMethod", "eesm");
cfg = sixgr.util.structSet(cfg, "phy.csi.targetBLER", 0.1);
cfg = sixgr.util.structSet(cfg, "phy.csi.cqiTable", "table1");

low = sixgr.link.resolveWidebandCQI(struct("WidebandSINR_dB", 0, "PerRBSINR_dB", [-2 -1 0 1]), cfg, "DL");
high = sixgr.link.resolveWidebandCQI(struct("WidebandSINR_dB", 15, "PerRBSINR_dB", [12 14 15 16]), cfg, "DL");

assert(strcmpi(string(low.Mode), "effective_sinr_bler_target_lut"), ...
    "CQI resolver must advertise the LUT-backed BLER mode when explicitly configured.");
assert(strcmpi(string(low.BLERLUTSource), "resolveWidebandCQI.lab_default_bler_lut"), ...
    "Default BLER LUT source must stay honestly labeled as a lab default.");
assert(strcmpi(string(low.BLERLUTValueRole), "lab_default"), ...
    "Default BLER LUT value role must remain lab_default.");
assert(all(isfinite(low.PredictedBLERByCQI) | isnan(low.PredictedBLERByCQI)), ...
    "Predicted BLER vector must contain numeric LUT-backed values.");
assert(double(high.WidebandCQI) > double(low.WidebandCQI), ...
    "Higher effective SINR must produce a higher CQI under the LUT-backed selector.");

ok = true;
end
