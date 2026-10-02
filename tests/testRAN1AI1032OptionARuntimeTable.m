function ok = testRAN1AI1032OptionARuntimeTable()
%TESTRAN1AI1032OPTIONARUNTIMETABLE Runtime codepoints must be immutable.

setup6GRSimToolkit("Verbose", false);
out = sixgr.studies.ran1ai1032.validateOptionARuntimeTable();
assert(out.Ok && out.EntryCount == 32 && out.IndexWidthBits == 5 && ...
    ~out.StandardNR && contains(out.AdaptiveSelectionStatus, "blocked_until_LLS"), ...
    "Option-A fixed-MCS execution must be exact and adaptive use fail-closed.");
p27 = sixgr.link.resolveMCSProfile(out.Table, 27);
p28 = sixgr.link.resolveMCSProfile(out.Table, 28);
p31 = sixgr.link.resolveMCSProfile(out.Table, 31);
assert(p27.Valid && p27.Qm == 8 && abs(p27.TargetCodeRate - 948/1024) < 1e-14 && ...
    p28.Valid && p28.Qm == 10 && abs(p28.TargetCodeRate - 805.5/1024) < 1e-14 && ...
    p31.Valid && p31.Qm == 10 && abs(p31.TargetCodeRate - 948/1024) < 1e-14, ...
    "B27/H0/H3 must preserve their exact physical meanings at indices 27/28/31.");
ok = true;
end
