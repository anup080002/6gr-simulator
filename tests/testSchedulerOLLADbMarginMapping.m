function ok = testSchedulerOLLADbMarginMapping()
%TESTSCHEDULEROLLADBMARGINMAPPING OLLA dB margins must not be MCS index deltas.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

if exist("nrTBS", "file") ~= 2
    ok = true;
    return;
end

cfg = sixgr.config.defaultConfig();
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.mode", "amc");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.dlPolicy", "baseline");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.outerLoopFlag", true);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.deltaMCSPolicy", "olla");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.bootstrapCQIMode", "estimated");
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaStepDown", 0.9);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaStepUp", 0.1);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaMarginMinDb", -10);
cfg = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaMarginMaxDb", 10);
cfg = sixgr.util.structSet(cfg, "phy.pdsch.mcsTable", "qam64_table1");
cfg = sixgr.util.structSet(cfg, "phy.csi.cqiTable", "table1");

sinrEvidence = struct( ...
    "WidebandSINR_dB", 10.5, ...
    "SINRSource", "post_equalization_sinr_from_equalizer_channel_estimate", ...
    "SINRValueRole", "measured_post_equalization_scheduling_input", ...
    "SINRValueStatus", "OK");
fb = sixgr.link.resolveWidebandCQI(sinrEvidence, cfg, "DL");
[cqiThresholds, cqiInfo] = sixgr.link.cqiRequiredSINRTable("table1", cfg, "DL");
assert(isequal(double(fb.SINRThresholds_dB(:).'), double(cqiThresholds(:).')), ...
    "Wideband CQI and OLLA must share the same CQI SINR threshold table.");
assert(strcmpi(string(cqiInfo.Source), string(fb.ThresholdSource)), ...
    "Shared CQI threshold helper must preserve threshold lineage.");

[req, reqInfo] = sixgr.link.mcsRequiredSINRTable("qam64_table1", "table1", "DL", "Config", cfg);
assert(all(isfinite(req)) && all(diff(req) >= -1e-12), ...
    "Derived MCS required-SINR table must be finite and monotonic for valid qam64 table1 rows.");
assert(contains(string(reqInfo.ValueRole), "derived_from_cqi"), ...
    "MCS required-SINR table must disclose that it is derived from CQI operating points.");

baseMCS = double(sixgr.link.resolveMCSFromCQI(12, "qam64_table1", "table1").MCSIndex);
deltaDb = -5.4;
[mappedMCS, detail] = sixgr.link.applyOLLADeltaDbToMCSIndex(baseMCS, deltaDb, ...
    "qam64_table1", "table1", "DL", "Config", cfg);
rawIndexMathMCS = floor(baseMCS + deltaDb);
assert(double(mappedMCS) > double(rawIndexMathMCS), ...
    "A %.1f dB OLLA margin must convert through SINR thresholds, not subtract %.1f MCS rows.", ...
    abs(deltaDb), abs(deltaDb));
assert(abs(double(detail.TargetRequiredSINR_dB) - (double(detail.BaseRequiredSINR_dB) + deltaDb)) < 1e-12, ...
    "OLLA target required SINR must equal base required SINR plus the dB margin.");

scheduler = sixgr.l2.mac.SchedulerPF(cfg, "Direction", "DL");
ue = struct("RNTI", 9101, "CQI", 12, "RI", 1);
[~, ~, ~, amcBase] = scheduler.selectAMC(ue);
assert(double(amcBase.MCSIndex) == baseMCS, "Baseline scheduler MCS must match CQI-derived MCS.");
for k = 1:6
    scheduler.updateAfterRx(struct("RNTI", 9101, "Ack", false, "TBSBits", 2048, ...
        "RV", 0, "IsRetransmission", false));
end
[~, ~, ~, amcBackedOff] = scheduler.selectAMC(ue);
assert(abs(double(amcBackedOff.OLLADeltaDb) - deltaDb) < 1e-12 && ...
    abs(double(amcBackedOff.OLLADeltaMCS) - double(amcBackedOff.OLLADeltaDb)) < 1e-12, ...
    "Scheduler must store OLLA as a dB margin and keep OLLADeltaMCS only as a legacy alias.");
assert(double(amcBackedOff.MCSIndex) == double(mappedMCS), ...
    "Scheduler OLLA-adjusted MCS must match the shared dB-to-MCS conversion helper.");
assert(double(amcBackedOff.MCSIndex) > double(rawIndexMathMCS), ...
    "Scheduler must not use raw MCS-index addition for OLLA.");
assert(strcmpi(string(amcBackedOff.MCSValueStatus), "measured_cqi_mapped_olla_db_margin_adjusted"), ...
    "Scheduler must disclose dB-margin OLLA adjustment status.");
assert(isfinite(double(amcBackedOff.OLLABaseRequiredSINR_dB)) && ...
    isfinite(double(amcBackedOff.OLLATargetRequiredSINR_dB)) && ...
    strlength(string(amcBackedOff.OLLAThresholdSource)) > 0, ...
    "Scheduler must export the required-SINR lineage used by OLLA.");

cfgClamp = sixgr.util.structSet(cfg, "phy.linkAdaptation.ollaMarginMinDb", -2);
cfgClamp = sixgr.util.structSet(cfgClamp, "phy.linkAdaptation.ollaMarginMaxDb", 2);
clampedScheduler = sixgr.l2.mac.SchedulerPF(cfgClamp, "Direction", "DL");
for k = 1:20
    clampedScheduler.updateAfterRx(struct("RNTI", 9201, "Ack", false, "TBSBits", 2048, ...
        "RV", 0, "IsRetransmission", false));
end
[deltaAfterClamp, ~] = clampedScheduler.getOLLAMCSDelta(9201);
assert(abs(double(deltaAfterClamp) + 2) < 1e-12, ...
    "Scheduler OLLA clamp must apply to the accumulated dB margin, not to a post-hoc MCS index.");

ok = true;
end
