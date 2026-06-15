function ok = testSchedulerPFFairness()
%TESTSCHEDULERPFFAIRNESS Verify PF scheduler serves all UEs under mixed CQI.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

cfg = sixgr.config.defaultConfig();
cfg = sixgr.util.structSet(cfg, "mac.scheduler.alpha", 0.99);
cfg = sixgr.util.structSet(cfg, "mac.scheduler.maxUEPerSlot", 2);
cfg = sixgr.util.structSet(cfg, "mac.scheduler.minPRBPerUE", 4);
cfg = sixgr.util.structSet(cfg, "mac.scheduler.maxPRBAllocationPerUE", 12);

sched = sixgr.l2.mac.SchedulerPF(cfg, "Direction", "DL");
cqiVals = [3 3 8 8 13 13];
ues = repmat(struct("RNTI", 0, "CQI", 0, "RI", 1, ...
    "DLBufferBytes", 50000, "ULBufferBytes", 0, ...
    "ControlEligible", true, "GrantControlState", "ok"), 1, 6);
for i = 1:6
    ues(i).RNTI = i;
    ues(i).CQI = cqiVals(i);
end

budget = struct("PRBSet", 0:71, "SymbolAllocation", [0 14]);
tbs = zeros(6, 1);
for slot = 1:200
    [grants, ~] = sched.schedule(slot, ues, budget);
    for g = 1:numel(grants)
        idx = find([ues.RNTI] == double(grants(g).RNTI), 1);
        if ~isempty(idx)
            tbs(idx) = tbs(idx) + double(grants(g).TBSBits);
        end
    end
end

jain = sum(tbs)^2 / (6 * sum(tbs.^2));
assert(all(tbs > 0), "All six UEs must receive scheduled data.");
assert(jain > 0.6, "PF Jain fairness must exceed 0.6; got %.3f.", jain);

clear sched
ok = true;
end
