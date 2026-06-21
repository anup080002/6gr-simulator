function ok = testSRSPeriodicSchedule()
setup6GRSimToolkit("Verbose", false);
T = sixgr.phy.srs.validateSRSPeriodicSchedule(srsStrictAnchorResult().Config);
assert(height(T) >= 2 && all(logical(T.ExpectedOccasion)) && all(logical(T.ObservedOccasion)), ...
    "Periodic SRS occasions must be derived from configured periodicity/offset.");

cfg = struct();
cfg = sixgr.util.structSet(cfg, "phy.srs.slotWithinPeriod1Based", [5 10 15 20]);
assert(~sixgr.truth.coupledSRSResourceOpportunity(cfg, 9, 1, 2, 20, "multiplex_due_users", 2), ...
    "Coupled SRS multiplexing must not turn a non-SRS slot into an SRS occasion.");
assert(sixgr.truth.coupledSRSResourceOpportunity(cfg, 10, 1, 2, 20, "multiplex_due_users", 2) && ...
    sixgr.truth.coupledSRSResourceOpportunity(cfg, 10, 2, 2, 20, "multiplex_due_users", 2), ...
    "Coupled SRS multiplexing must allow both UEs on a configured SRS occasion.");
ok = true;
end
