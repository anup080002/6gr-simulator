function ok = testRAN1LLSLinkAdaptation()
%TESTRAN1LLSLINKADAPTATION Prove causal AMC is bound to actual PHY trials.

setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
tmp = string(tempname);
mkdir(tmp);
cleanup = onCleanup(@()localCleanup(tmp)); %#ok<NASGU>
result = sixgr.lls.runLLS( ...
    "configs/lls/pusch_awgn_link_adaptation_regression.yaml", ...
    "OutputRoot",tmp,"RunTag","link_adaptation","GeneratePlots",false);

assert(result.Status == "complete_valid");
T = result.TrialTable;
policy = result.Config.linkAdaptation;
assert(T.LinkAdaptationDecisionSource(1) == "configured_bootstrap_mcs");
assert(all(T.LinkAdaptationDecisionSource(2:end) == ...
    "previous_trial_receiver_post_equalization_sinr"));
assert(all(T.LinkAdaptationFeedbackTrialIndex(2:end) == T.TrialIndex(1:end-1)));
assert(all(abs(T.LinkAdaptationFeedbackSINRdB(2:end)-T.PostEqSINRdB(1:end-1)) < 1e-12));
for index = 2:height(T)
    cqi = sum(T.LinkAdaptationEffectiveSINRdB(index) >= ...
        double(policy.sinrThresholdsDb(:).'));
    if cqi < 1
        expectedMCS = double(policy.minimumMCSIndex);
    else
        amc = sixgr.link.resolveMCSFromCQI(cqi,policy.mcsTable,policy.cqiTable);
        assert(amc.Valid);
        expectedMCS = double(amc.MCSIndex);
    end
    expectedMCS = max(double(policy.minimumMCSIndex), ...
        min(double(policy.maximumMCSIndex),expectedMCS));
    assert(T.MCSIndex(index) == expectedMCS && ...
        T.LinkAdaptationSelectedMCSIndex(index) == expectedMCS);
    profile = sixgr.link.resolveMCSProfile(T.MCSTable(index),T.MCSIndex(index));
    assert(profile.Valid && strcmpi(string(profile.Modulation),T.Modulation(index)) && ...
        abs(profile.TargetCodeRate-T.TargetCodeRate(index)) < 1e-12);
end
assert(result.TruthContractTable.ActualLinkAdaptation);
assert(~any(result.RequiredSNRTable.Valid));
assert(all(result.RequiredSNRTable.Status == ...
    "not_applicable_link_adaptation_throughput_reported_separately"));
fprintf("RAN1LLSLinkAdaptation: TB=%d MCS=[%s] throughput=%.3f Mbps.\n", ...
    height(T),strjoin(string(T.MCSIndex.'),","),result.SummaryTable.ThroughputBps/1e6);
ok = true;
end

function localCleanup(path)
if exist(path,"dir") == 7
    rmdir(path,"s");
end
end
