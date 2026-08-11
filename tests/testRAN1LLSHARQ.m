function ok = testRAN1LLSHARQ()
%TESTRAN1LLSHARQ Verify actual retransmission and soft-combining semantics.

setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
tmp = string(tempname);
mkdir(tmp);
cleanup = onCleanup(@() localCleanup(tmp)); %#ok<NASGU>
result = sixgr.lls.runLLS( ...
    "configs/lls/pusch_awgn_harq_regression.yaml", ...
    "OutputRoot",tmp,"RunTag","harq","GeneratePlots",false);

assert(result.Status == "complete_valid");
T = result.TrialTable;
S = result.SummaryTable;
assert(any(T.AttemptIndex > 1),"The HARQ operating point must exercise retransmission.");
assert(all(T.HARQSoftCombiningApplied(T.AttemptIndex > 1)), ...
    "Every retransmission must apply the prior position-aware soft buffer.");
for packet = unique(T.PacketIndex).'
    P = sortrows(T(T.PacketIndex == packet,:),"AttemptIndex");
    assert(numel(unique(P.BitSeed)) == 1, ...
        "Every attempt of a packet must reuse the exact transport block seed.");
    expectedRV = double(result.Config.harq.rvSequence(:).');
    assert(isequal(P.RV(:).',expectedRV(1:height(P))), ...
        "Runtime RV progression must match YAML exactly.");
end
assert(S.PostHARQResidualBLER <= S.FirstTransmissionBLER);
assert(S.AverageTransmissions > 1 && S.NumTransmissions == height(T));
assert(result.TruthContractTable.ActualHARQ && ...
    result.TruthContractTable.HARQEvidenceValid && ...
    result.TruthContractTable.HARQMetricSeparation);
assert(~result.TruthContractTable.ActualInterference && ...
    result.TruthContractTable.InterferenceEvidenceValid && ...
    ~result.TruthContractTable.ActualLinkAdaptation && ...
    result.TruthContractTable.LinkAdaptationEvidenceValid);
assert(~any(result.RequiredSNRTable.Valid) && ...
    all(result.RequiredSNRTable.Status == ...
    "not_applicable_harq_metrics_reported_separately"));
fprintf("RAN1LLSHARQ: packets=%d transmissions=%d firstBLER=%g residualBLER=%g.\n", ...
    S.NumTB,S.NumTransmissions,S.FirstTransmissionBLER,S.PostHARQResidualBLER);
ok = true;
end

function localCleanup(path)
if exist(path,"dir") == 7
    rmdir(path,"s");
end
end
