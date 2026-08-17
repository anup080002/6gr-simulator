function ok = testPhase7GateApplicability()
%TESTPHASE7GATEAPPLICABILITY Explicit N/A gates do not become synthetic PASS.

gateNames = sixgr.runtime.Phase7TruthEvaluator.gateNames();
flags = struct();
for index = 1:numel(gateNames)
    flags.(char(gateNames(index))) = true;
end
for name = ["Phase1Ok","Phase2Ok","Phase3Ok","Phase4Ok","Phase5Ok","Phase6Ok"]
    flags.(char(name)) = true;
end
flags.PublicationReadinessOk = true;

flags.FullTrajectoryExecutedOk = false;
flags.MobilityStateContinuousOk = false;
flags.NotApplicableGateNames = ["FullTrajectoryExecutedOk"; "MobilityStateContinuousOk"];
status = sixgr.runtime.Phase7TruthEvaluator.evaluate(flags);
assert(logical(status.Phase7Ok) && logical(status.ResultOk), ...
    "Explicit mode-inapplicable gates must not fail an otherwise valid run.");
assert(~logical(status.FullTrajectoryExecutedOk) && ...
    ~logical(status.MobilityStateContinuousOk), ...
    "Not-applicable evidence must remain false, never be relabeled as PASS.");
assert(~any(contains(string(status.FailureCodes), ...
    ["FullTrajectoryExecutedOk_false","MobilityStateContinuousOk_false"])), ...
    "Not-applicable gates must be absent from failure codes.");

T = sixgr.runtime.Phase7TruthEvaluator.table(status);
assert(height(T) == 1 && contains(string(T.NotApplicableGateNames(1)), ...
    "FullTrajectoryExecutedOk"), ...
    "The tabular status must preserve explicit applicability provenance.");

bad = flags;
bad.NotApplicableGateNames = "NotARealPhase7Gate";
threw = false;
try
    sixgr.runtime.Phase7TruthEvaluator.evaluate(bad);
catch ME
    threw = strcmp(ME.identifier, ...
        "sixgr:runtime:UnknownPhase7GateApplicability");
end
assert(threw, "Unknown applicability exclusions must fail loudly.");

ok = true;
fprintf("PASS testPhase7GateApplicability: N/A gates remain explicit and fail-closed.\n");
end
