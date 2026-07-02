function ok = testSchedulerGrantConsistency()
%TESTSCHEDULERGRANTCONSISTENCY Ensure scheduler grants carry PHY/control fields.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.mac.scheduler.maxUEPerSlot = 4;
cfg.mac.scheduler.minPRBPerUE = 4;

ue = repmat(struct("RNTI",0,"DLBufferBytes",0,"CQI",10,"RI",1,"HeadOfLineDelay_ms",1), 4, 1);
for k = 1:4
    ue(k).RNTI = k;
    ue(k).DLBufferBytes = 1200 + 200*k;
    ue(k).CQI = 6 + k;
end

sch = sixgr.l2.mac.SchedulerPF(cfg, "Direction", "DL");
[grants, ~] = sch.schedule(0, ue, struct("NPRB", 40, "SymbolAllocation", [0 14]));
assert(~isempty(grants), "Scheduler returned no grants for non-empty buffers");

reqFields = ["MCSIndex","CQIUsed","DAI","K1","K2","SearchSpaceID","CORESETID", ...
    "BWPId","HeadOfLineDelay_ms","BufferBytesBefore","BufferBytesAfter","GrantReason","DCI"];
for i = 1:numel(grants)
    g = grants(i);
    for f = 1:numel(reqFields)
        assert(isfield(g, reqFields(f)), "Missing grant field: %s", reqFields(f));
    end
    assert(double(g.BufferBytesAfter) <= double(g.BufferBytesBefore), ...
        "BufferBytesAfter must not exceed BufferBytesBefore");
    assert(double(g.TBSBits) >= 0 && double(g.TBSBytes) >= 0, "Invalid TBS fields");
    [tbsBits, upperBoundBits] = sixgr.util.resolveGrantTBSBits(g, sprintf("test grant %d", i));
    assert(double(tbsBits) == double(g.TBSBits), "Resolved TBSBits does not match grant field.");
    assert(double(tbsBits) <= double(upperBoundBits), "Grant TBS exceeds loose allocation upper bound.");
    assert(isstruct(g.DCI) && isfield(g.DCI, "Bits") && isfield(g.DCI, "Hex"), "Missing DCI bitfield payload.");
    if ~isempty(g.PRBSet)
        assert(numel(g.DCI.Bits) > 0, "DCI bits must be populated for allocated grants.");
    end
end

cfgUL = struct();
cfgUL = sixgr.util.structSet(cfgUL, "phy.carrier.NSizeGrid", 52);
cfgUL = sixgr.util.structSet(cfgUL, "phy.numerology.scs_kHz", 30);
cfgUL = sixgr.util.structSet(cfgUL, "phy.pusch.modulation", "QPSK");
cfgUL = sixgr.util.structSet(cfgUL, "phy.pusch.nLayers", 1);
cfgUL = sixgr.util.structSet(cfgUL, "phy.pusch.codeRate", 0.5);
cfgUL = sixgr.util.structSet(cfgUL, "phy.pusch.dmrs.DMRSTypeAPosition", 2);
cfgUL = sixgr.util.structSet(cfgUL, "mac.scheduler.fastNREApprox", false);
cfgUL = sixgr.util.structSet(cfgUL, "mac.scheduler.tbsMode", "faithful");
schUL = sixgr.l2.mac.SchedulerRR(cfgUL, "Direction", "UL");
lateULGrant = struct( ...
    "Direction", "UL", ...
    "RNTI", 7101, ...
    "Slot", 20, ...
    "Frame", 2, ...
    "PRBSet", 0:9, ...
    "SymbolAllocation", [7 7], ...
    "Modulation", "QPSK", ...
    "NumLayers", 1, ...
    "TargetCodeRate", 0.5, ...
    "MCSIndex", 4);
lateULGrant = schUL.freezePHYGrantForGrant(lateULGrant);
assert(logical(lateULGrant.ExactPHYFeasible), ...
    "Implicit late-symbol special-slot UL grant must finalize to a legal exact PHY allocation.");
assert(strcmp(string(lateULGrant.MappingType), "B") && ...
        strcmp(string(lateULGrant.MappingTypeSelectionSource), "scheduler_special_slot_legalization"), ...
    "Implicit MappingType A must be finalized as MappingType B before exact PUSCH accounting in late UL symbols.");
assert(double(lateULGrant.TBSBits) > 0 && double(lateULGrant.ExactNREPerPRB) > 0, ...
    "Special-slot MappingType B UL grant must carry exact positive TBS/NRE.");

cfgGuard = cfgUL;
cfgGuard = sixgr.util.structSet(cfgGuard, "phy.carrier.NSizeGrid", 106);
cfgGuard = sixgr.util.structSet(cfgGuard, "phy.linkAdaptation.mode", "amc");
cfgGuard = sixgr.util.structSet(cfgGuard, "phy.linkAdaptation.ulPolicy", "cqi");
cfgGuard = sixgr.util.structSet(cfgGuard, "phy.linkAdaptation.minPRBForWidebandCQIGrant", 4);
cfgGuard = sixgr.util.structSet(cfgGuard, "phy.pusch.mcsTable", "qam64_table1");
cfgGuard = sixgr.util.structSet(cfgGuard, "phy.pusch.nLayers", 2);
cfgGuard = sixgr.util.structSet(cfgGuard, "mac.scheduler.maxUEPerSlot", 1);
cfgGuard = sixgr.util.structSet(cfgGuard, "mac.scheduler.minPRBPerUE", 1);
schGuard = sixgr.l2.mac.SchedulerPF(cfgGuard, "Direction", "UL");
ueGuard = struct( ...
    "RNTI", 7201, ...
    "ULBufferBytes", 220, ...
    "CQI", 15, ...
    "RI", 2, ...
    "FeedbackValid", true, ...
    "CausalFeedbackUsable", true, ...
    "MCSIndexAuthority", "runtime_cqi_table", ...
    "HeadOfLineDelay_ms", 1);
[guardGrants, ~] = schGuard.schedule(5, ueGuard, struct("PRBSet", 0:52, "SymbolAllocation", [0 14]));
assert(~isempty(guardGrants), "Wideband-CQI guard fixture must still produce a valid UL grant.");
gGuard = guardGrants(1);
isTinyHighRank = numel(double(gGuard.PRBSet)) < 4 && double(gGuard.NumLayers) > 1 && double(gGuard.MCSIndex) >= 10;
assert(~isTinyHighRank, ...
    "Runtime wideband CQI without subband evidence must not produce a tiny high-rank/high-MCS UL grant.");
assert(logical(sixgr.util.structGet(gGuard, "QueueAwareReductionApplied", false)), ...
    "The small-PRB wideband-CQI guard must disclose the queue-aware rank/MCS reduction.");

ok = true;
end
