function ok = testNRCQITableAndGrantSizing()
%TESTNRCQITABLEANDGRANTSIZING Validate NR CQI tables and queue-limited grant sizing.

setup6GRSimToolkit("Verbose", false);

% CQI table rows must resolve to the expected modulation families.
p = sixgr.link.resolveCQIProfile("table1", 6);
assert(p.Valid && strcmpi(string(p.Modulation), "QPSK"), "CQI Table 1 CQI 6 must resolve to QPSK.");
p = sixgr.link.resolveCQIProfile("table1", 7);
assert(p.Valid && strcmpi(string(p.Modulation), "16QAM"), "CQI Table 1 CQI 7 must resolve to 16QAM.");
p = sixgr.link.resolveCQIProfile("table1", 10);
assert(p.Valid && strcmpi(string(p.Modulation), "64QAM"), "CQI Table 1 CQI 10 must resolve to 64QAM.");
p = sixgr.link.resolveCQIProfile("table2", 12);
assert(p.Valid && strcmpi(string(p.Modulation), "256QAM"), "CQI Table 2 CQI 12 must resolve to 256QAM.");

expectedTable1 = [0 0 2 4 6 8 11 13 15 18 20 22 24 26 28];
expectedTable2 = [0 1 3 5 7 9 11 13 15 17 19 21 23 25 27];
resolvedTable1 = zeros(1, 15);
resolvedTable2 = zeros(1, 15);
for cqiIdx = 1:15
    amc1 = sixgr.link.resolveMCSFromCQI(cqiIdx, "qam64_table1", "table1");
    amc2 = sixgr.link.resolveMCSFromCQI(cqiIdx, "qam256_table2", "table2");
    resolvedTable1(cqiIdx) = double(amc1.MCSIndex);
    resolvedTable2(cqiIdx) = double(amc2.MCSIndex);
end
assert(isequal(resolvedTable1, expectedTable1), ...
    "CQI-to-MCS table1 mapping must match the Link Adaptation/TS 38.214 spectral-efficiency mapping.");
assert(isequal(resolvedTable2, expectedTable2), ...
    "CQI-to-MCS table2 mapping must match the Link Adaptation/TS 38.214 spectral-efficiency mapping.");

sinrEvidence = struct( ...
    "WidebandSINR_dB", 10.5, ...
    "SINRSource", "post_equalization_sinr_from_equalizer_channel_estimate", ...
    "SINRValueRole", "measured_post_equalization_scheduling_input", ...
    "SINRValueStatus", "OK");
cfgThreshold = struct();
cfgThreshold.phy.csi.cqiTable = "table1";
fbTable1 = sixgr.link.resolveWidebandCQI(sinrEvidence, cfgThreshold, "DL");
cfgThreshold.phy.csi.cqiTable = "table2";
fbTable2 = sixgr.link.resolveWidebandCQI(sinrEvidence, cfgThreshold, "DL");
assert(double(fbTable1.WidebandCQI) == 9 && double(fbTable2.WidebandCQI) == 7, ...
    "CQI threshold mode must use non-uniform table-specific thresholds, not a uniform ladder.");
assert(strcmpi(string(fbTable1.ThresholdSource), "resolveWidebandCQI.lab_default_threshold_table") && ...
    strcmpi(string(fbTable1.ThresholdValueRole), "lab_default"), ...
    "CQI feedback must disclose threshold-table lineage.");
sinrEvidence.WidebandSINR_dB = 25.1;
fbHigh = sixgr.link.resolveWidebandCQI(sinrEvidence, cfgThreshold, "DL");
assert(double(fbHigh.WidebandCQI) == 14, ...
    "CQI table2 high-SINR boundary must not saturate to CQI15 until the table2 CQI15 threshold is crossed.");

cfg = sixgr.config.defaultConfig();
cfg = sixgr.util.structSet(cfg, "phy.csi.cqiTable", "table1");
cfg = sixgr.util.structSet(cfg, "phy.pdsch.mcsTable", "qam64_table1");
cfg = sixgr.config.normalizeConfig(cfg);

[modStr, targetCodeRate, mcsIdx] = sixgr.link.amcFromCQI(10, "", NaN, cfg, "DL");
mcsProfile = sixgr.link.resolveMCSProfile(cfg.phy.pdsch.mcsTable, mcsIdx);
cqiProfile = sixgr.link.resolveCQIProfile(cfg.phy.csi.cqiTable, 10);
assert(mcsProfile.Valid, "AMC must resolve to a valid NR MCS profile.");
assert(strcmpi(string(modStr), string(mcsProfile.Modulation)), "AMC modulation must match the resolved MCS profile.");
assert(abs(double(targetCodeRate) - double(mcsProfile.TargetCodeRate)) <= 1e-12, ...
    "AMC target code rate must match the resolved MCS profile.");
assert(double(mcsProfile.SpectralEfficiency) <= double(cqiProfile.SpectralEfficiency) + 1e-9, ...
    "CQI-driven AMC must not exceed the CQI row spectral efficiency.");

cfgStrict = sixgr.config.defaultConfig();
cfgStrict.run.strictMode = true;
% Mapping type B permits a front-loaded DM-RS for this 13-symbol
% allocation. A full 14-symbol type-B allocation has no standard DM-RS
% position and is exercised below as a fail-closed negative case.
cfgStrict.phy.pdsch.symbolAllocation = [0 13];
cfgStrict.phy.pdsch.mappingType = "B";
cfgStrict = sixgr.config.normalizeConfig(cfgStrict);
schStrict = sixgr.l2.mac.SchedulerPF(cfgStrict, "Direction", "DL");
[~, ~, nrePerPRB, info] = schStrict.estimateTBS("QPSK", 1, 12, [0 13], 0.5);
assert(~logical(info.UsedFastNREApprox), "Strict TBS mode must not use the fast NRE approximation.");
assert(double(nrePerPRB) < 12 * 13, "Strict TBS mode must use actual RE counting with DMRS/overhead removed.");

invalidTypeBFailed = false;
try
    schStrict.estimateTBS("QPSK", 1, 12, [0 14], 0.5, "ForceExact", true);
catch ME
    invalidTypeBFailed = strcmp(string(ME.identifier), ...
        "sixgr:SchedulerBase:ExactResourceAccountingFailed") && ...
        contains(string(ME.message), "no DM-RS resource elements");
end
assert(invalidTypeBFailed, ...
    "An invalid full-slot mapping-type-B allocation must fail closed when it produces no DM-RS REs.");

cfgDefault = sixgr.config.defaultConfig();
cfgDefault = sixgr.config.normalizeConfig(cfgDefault);
schDefault = sixgr.l2.mac.SchedulerPF(cfgDefault, "Direction", "DL");
[~, ~, ~, defaultInfo] = schDefault.estimateTBS("QPSK", 1, 12, [0 14], 0.5);
assert(~logical(defaultInfo.UsedFastNREApprox) && strcmpi(string(defaultInfo.TBSMode), "faithful"), ...
    "Default executable TBS sizing must use faithful nrTBS resource accounting, not fast approximation.");

cfgULApprox = sixgr.config.defaultConfig();
cfgULApprox = sixgr.util.structSet(cfgULApprox, "phy.pusch.transformPrecoding", false);
cfgULApprox = sixgr.util.structSet(cfgULApprox, "phy.pusch.xOverhead", 0);
cfgULApprox = sixgr.util.structSet(cfgULApprox, "phy.carrier.NSizeGrid", 273);
cfgULApprox = sixgr.util.structSet(cfgULApprox, "mac.scheduler.tbsMode", "approximate");
cfgULApprox = sixgr.util.structSet(cfgULApprox, "mac.scheduler.fastNREApprox", true);
cfgULApprox = sixgr.config.normalizeConfig(cfgULApprox);
schULApprox = sixgr.l2.mac.SchedulerPF(cfgULApprox, "Direction", "UL");
[~, ~, ~, fastInfo] = schULApprox.estimateTBS("QPSK", 1, 134, [0 14], 193/1024);
assert(logical(fastInfo.UsedFastNREApprox), ...
    "Approximate scheduler probe must still be able to use the fast NRE path.");
[exactULBits, ~, exactULNRE, exactULInfo] = schULApprox.estimateTBS("QPSK", 1, 134, [0 14], 193/1024, ...
    "ForceExact", true);
[carrierUL, ~] = sixgr.phy.grid.makeCarrier(cfgULApprox, "NSizeGrid", 273);
[~, puschInfoRef] = sixgr.phy.grid.allocREsPUSCH(carrierUL, cfgULApprox, ...
    "PRBSet", 0:133, "SymbolAllocation", [0 14], "Modulation", "QPSK", "NumLayers", 1);
[nreRef, ~] = sixgr.util.resolveDataNREPerPRB(puschInfoRef, 134, "QPSK", 1);
refULBits = double(nrTBS("QPSK", 1, 134, double(nreRef), 193/1024, 0));
assert(~logical(exactULInfo.UsedFastNREApprox), ...
    "ForceExact UL TBS must not be served from a cached fast planning estimate.");
assert(double(exactULNRE) == double(nreRef) && double(exactULBits) == double(refULBits), ...
    "ForceExact UL TBS must match nrTBS for the exact nrPUSCH allocation RE budget.");

cfgGrant = sixgr.config.defaultConfig();
cfgGrant.run.useMex = false;
cfgGrant = sixgr.util.structSet(cfgGrant, "phy.pdsch.mcsTable", "qam256_table2");
cfgGrant = sixgr.util.structSet(cfgGrant, "phy.csi.cqiTable", "table2");
cfgGrant = withCanonicalSchedulerTiming(cfgGrant);
cfgGrant = sixgr.config.normalizeConfig(cfgGrant);
schGrant = sixgr.l2.mac.SchedulerRR(cfgGrant, "Direction", "DL");

ue = struct( ...
    "RNTI", 1, ...
    "DLBufferBytes", 120, ...
    "CQI", 15, ...
    "RI", 1, ...
    "HeadOfLineDelay_ms", 1);
[grants, ~] = schGrant.schedule(0, ue, struct( ...
    "NPRB", 50, "SymbolAllocation", [0 14], ...
    "ControlSymbolAllocation", [0 2]));
assert(~isempty(grants), "Queue-limited scheduler regression must produce at least one grant.");
g = grants(1);
assert(double(g.TBSBytes) <= double(ue.DLBufferBytes), "New-data grant TBS must not exceed queued bytes.");
assert(double(g.TBSBits) <= 8 * double(ue.DLBufferBytes), "New-data grant TBS must not exceed queued bits.");
assert(double(g.EstimatedTBSBytes) >= double(g.TBSBytes), "Grant must retain the pre-limit estimated TBS explicitly.");
assert(isfield(g, "QueueLimited"), "Grant must expose whether queue limiting was applied.");
[resolvedBits, ~] = sixgr.util.resolveGrantTBSBits(g, "test queue-limited grant");
assert(double(resolvedBits) == double(g.TBSBits), "Grant TBS fields must remain internally consistent after queue limiting.");

ui = find(double(schGrant.HARQ.UEList) == double(ue.RNTI), 1, "first");
assert(~isempty(ui), "HARQ state must be allocated for the queue-limited new-data grant.");
pid = double(g.HARQ.HarqID) + 1;
proc = schGrant.HARQ.UEProcs{ui}(pid);
assert(double(proc.TBSBytes) == double(g.TBSBytes), ...
    "HARQ new-data state must use the queue-limited TBS, not the oversized estimate.");

cfgQueueAware = sixgr.util.structSet(cfgGrant, "phy.linkAdaptation.mode", "amc");
cfgQueueAware = sixgr.util.structSet(cfgQueueAware, "phy.linkAdaptation.dlPolicy", "cqi_driven");
cfgQueueAware = sixgr.util.structSet(cfgQueueAware, "phy.linkAdaptation.queueAwareRankMCSReductionEnable", true);
cfgQueueAware = sixgr.util.structSet(cfgQueueAware, "phy.linkAdaptation.queueAwareLayerDecrementMax", 1);
cfgQueueAware = sixgr.util.structSet(cfgQueueAware, "phy.linkAdaptation.queueAwareMCSDecrementMax", 2);
cfgQueueAware = sixgr.util.structSet(cfgQueueAware, "phy.linkAdaptation.queueAwareMCSDecrementStep1", 1);
cfgQueueAware = sixgr.util.structSet(cfgQueueAware, "phy.linkAdaptation.queueAwareMCSDecrementStep2", 2);
cfgQueueAware = sixgr.util.structSet(cfgQueueAware, "phy.linkAdaptation.queueAwarePRBDelta1Fraction", 0.5);
cfgQueueAware = sixgr.util.structSet(cfgQueueAware, "phy.linkAdaptation.queueAwarePRBDelta2Fraction", 0.8);
schQueueAware = sixgr.l2.mac.SchedulerPF(cfgQueueAware, "Direction", "DL");
planQueueAware = schQueueAware.buildNewDataGrantPlan( ...
    struct("RNTI", 77, "DLBufferBytes", 90, "CQI", 15, "RI", 2), 0:49, [0 14], 90);
assert(planQueueAware.Valid && logical(planQueueAware.QueueAwareReductionApplied), ...
    "Queue-aware grant sizing must apply configured MCS/rank reduction when buffer occupancy is much smaller than the PRB share.");
assert((double(planQueueAware.InitialMCSIndex) > double(planQueueAware.MCSIndex) || ...
    double(planQueueAware.InitialNumLayers) > double(planQueueAware.NumLayers)) && ...
    (double(planQueueAware.MCSReductionSteps) + double(planQueueAware.LayerReductionSteps)) >= 1, ...
    "Queue-aware grant sizing must disclose the exact MCS or layer reduction applied before TB sizing.");
assert(double(planQueueAware.TBSBytes) <= 90 && double(planQueueAware.TBSBits) > 0, ...
    "Queue-aware MCS/rank reduction must still produce a real standards-sized TB that fits the queue.");

ok = true;
end
