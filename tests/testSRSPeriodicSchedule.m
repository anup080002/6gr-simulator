function ok = testSRSPeriodicSchedule()
setup6GRSimToolkit("Verbose", false);
T = sixgr.phy.srs.validateSRSPeriodicSchedule(srsStrictAnchorResult().Config);
assert(height(T) >= 2 && all(logical(T.ExpectedOccasion)) && all(logical(T.ObservedOccasion)), ...
    "Periodic SRS occasions must be derived from configured periodicity/offset.");
ok = true;
end
