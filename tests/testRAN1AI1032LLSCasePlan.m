function ok = testRAN1AI1032LLSCasePlan()
%TESTRAN1AI1032LLSCASEPLAN Verify complete fixed-MCS case/point identities.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.studies.ran1ai1032.loadStudyConfig();
out = sixgr.studies.ran1ai1032.buildLLSCasePlan(cfg);

% Four primary channels, antenna-rank multiplicity 1+2+4, and eleven
% curves (five F1 plus six F2) per physical branch.
expectedCases = 4 * 7 * 11;
expectedSNRPoints = numel(-10:45);
assert(out.Status == "PASS" && out.CaseCount == expectedCases && ...
    out.CoarsePointCount == expectedCases * expectedSNRPoints, ...
    "LLS plan must contain every F1/F2 physical branch and coarse SNR point.");
assert(all(out.CasePlan.ExecutionStatus == "planned_not_executed") && ...
    all(out.PointPlan.PointStatus == "planned_not_executed"), ...
    "Planning artifacts must never be mislabeled as executed PHY evidence.");

f1 = out.CasePlan(out.CasePlan.ExperimentID == "F1", :);
assert(isequal(sort(unique(f1.EntryID)), sort(["B27";"H0";"H1";"H2";"H3"])) && ...
    all(~f1.HARQEnabled & ~f1.ILLAEnabled & ~f1.OLLAEnabled), ...
    "F1 must compare B27/H0-H3 with HARQ and adaptation disabled.");
assert(all(out.CasePlan.Rank <= min(out.CasePlan.TxChains, out.CasePlan.RxChains)), ...
    "No planned case may exceed its physical spatial dimensions.");

oneCase = out.CasePlan.CaseID(1);
points = out.PointPlan(out.PointPlan.CaseID == oneCase, :);
assert(isequal(points.InputSNRdB, (-10:45).') && ...
    numel(unique(points.OutputGroupID)) == 1 && ...
    all(points.OutputGroupID == out.CasePlan.OutputGroupID(1)), ...
    "All SNR points for one curve must share one CSV/PNG aggregation identity.");

pair = out.PointPlan.ComparisonPairKey(1);
snr = out.PointPlan.InputSNRdB(1);
pairedRows = out.PointPlan.ComparisonPairKey == pair & ...
    out.PointPlan.InputSNRdB == snr;
assert(numel(unique(out.PointPlan.ChannelSeed(pairedRows))) == 1, ...
    "Compared entries at one operating point must share common random numbers.");
ok = true;
end
