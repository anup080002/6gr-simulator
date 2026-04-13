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
cfgStrict = sixgr.config.normalizeConfig(cfgStrict);
schStrict = sixgr.l2.mac.SchedulerPF(cfgStrict, "Direction", "DL");
[~, ~, nrePerPRB, info] = schStrict.estimateTBS("QPSK", 1, 12, [0 14], 0.5);
assert(~logical(info.UsedFastNREApprox), "Strict TBS mode must not use the fast NRE approximation.");
assert(double(nrePerPRB) < 12 * 14, "Strict TBS mode must use actual RE counting with DMRS/overhead removed.");

cfgGrant = sixgr.config.defaultConfig();
cfgGrant.run.useMex = false;
cfgGrant = sixgr.util.structSet(cfgGrant, "phy.pdsch.mcsTable", "qam256_table2");
cfgGrant = sixgr.util.structSet(cfgGrant, "phy.csi.cqiTable", "table2");
cfgGrant = sixgr.config.normalizeConfig(cfgGrant);
schGrant = sixgr.l2.mac.SchedulerRR(cfgGrant, "Direction", "DL");

ue = struct( ...
    "RNTI", 1, ...
    "DLBufferBytes", 120, ...
    "CQI", 15, ...
    "RI", 1, ...
    "HeadOfLineDelay_ms", 1);
[grants, ~] = schGrant.schedule(0, ue, struct("NPRB", 50, "SymbolAllocation", [0 14]));
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

ok = true;
end
