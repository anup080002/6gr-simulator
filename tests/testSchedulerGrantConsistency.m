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
    assert(isstruct(g.DCI) && isfield(g.DCI, "Bits") && isfield(g.DCI, "Hex"), "Missing DCI bitfield payload.");
    if ~isempty(g.PRBSet)
        assert(numel(g.DCI.Bits) > 0, "DCI bits must be populated for allocated grants.");
    end
end
ok = true;
end
