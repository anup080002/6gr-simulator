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
delay = double(policy.feedbackDelaySlots);
bootstrapRows = T.TrialIndex <= delay;
feedbackRows = T.TrialIndex > delay;
assert(T.LinkAdaptationDecisionSource(1) == "configured_bootstrap_mcs");
probeRows = logical(T.LinkAdaptationForcedWaveformProbe);
scheduledRows = ~probeRows;
assert(all(T.LinkAdaptationDecisionSource(bootstrapRows & T.TrialIndex > 1) == ...
    "configured_bootstrap_mcs_feedback_pending"));
assert(all(T.LinkAdaptationDecisionSource(scheduledRows & feedbackRows) == ...
    "receiver_post_equalization_sinr_after_configured_feedback_delay"));
assert(all(T.LinkAdaptationDecisionSource(probeRows) == ...
    "diagnostic_minimum_mcs_waveform_probe_from_delayed_receiver_post_equalization_sinr"));
assert(all(T.LinkAdaptationSchedulingEligible(scheduledRows)) && ...
    ~any(T.LinkAdaptationSchedulingEligible(probeRows)) && ...
    all(T.LinkAdaptationDecisionValueRole(probeRows) == ...
        "diagnostic_waveform_probe_not_scheduler_decision"));
assert(all(T.LinkAdaptationFeedbackTrialIndex(bootstrapRows) == 0));
assert(all(T.LinkAdaptationFeedbackTrialIndex(feedbackRows) == ...
    T.TrialIndex(1:end-delay)));
assert(all(T.LinkAdaptationFeedbackAgeSlots(feedbackRows) == delay));
assert(all(abs(T.LinkAdaptationFeedbackSINRdB(feedbackRows)- ...
    T.PostEqSINRdB(1:end-delay)) < 1e-12));
for index = delay+1:height(T)
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
[causalValid, causalDetail] = ...
    sixgr.lls.validateLinkAdaptationTrialEvidence(result.Config,T);
assert(causalValid,string(causalDetail.Reason));

% A multi-SNR run restarts trial indices and adaptation state independently
% at every point.  The evidence validator must preserve that boundary and
% must still reject a source-index violation inside either point.
T2 = T;
T2.SNRIndex(:) = 2;
multiPoint = [T; T2];
[multiPointValid, multiPointDetail] = ...
    sixgr.lls.validateLinkAdaptationTrialEvidence(result.Config,multiPoint);
assert(multiPointValid && double(multiPointDetail.GroupCount) == 2, ...
    string(multiPointDetail.Reason));
bad = multiPoint;
secondPointFirstFeedback = height(T) + delay + 1;
bad.LinkAdaptationFeedbackTrialIndex(secondPointFirstFeedback) = 0;
[badValid,badDetail] = ...
    sixgr.lls.validateLinkAdaptationTrialEvidence(result.Config,bad);
assert(~badValid && string(badDetail.Reason) == ...
    "configured_feedback_delay_not_observed");
assert(result.TruthContractTable.ActualLinkAdaptation && ...
    result.TruthContractTable.LinkAdaptationEvidenceValid);
assert(result.TruthContractTable.DiagnosticLinkAdaptationProbeUsed == any(probeRows) && ...
    result.TruthContractTable.SchedulerEligibleLinkAdaptationEvidence == ~any(probeRows));
assert(~result.TruthContractTable.ActualHARQ && ...
    result.TruthContractTable.HARQEvidenceValid && ...
    ~result.TruthContractTable.ActualInterference && ...
    result.TruthContractTable.InterferenceEvidenceValid);
assert(~any(result.RequiredSNRTable.Valid));
assert(all(result.RequiredSNRTable.Status == ...
    "not_applicable_link_adaptation_throughput_reported_separately"));
assert(height(result.LinkAdaptationOperatingPointSummary) == 1);
adaptationSummary = result.LinkAdaptationOperatingPointSummary(1,:);
assert(adaptationSummary.RuntimeTrials == height(T));
assert(adaptationSummary.FeedbackDelaySlots == delay);
assert(adaptationSummary.BootstrapTrials == delay);
assert(adaptationSummary.PostDelayEvaluationTrials == height(T)-delay);
assert(adaptationSummary.ILLAFeedbackAppliedTrials == height(T)-delay);
assert(adaptationSummary.OLLAUpdateCount == height(T)-delay);
assert(adaptationSummary.OLLAACKCount + adaptationSummary.OLLANACKCount == ...
    height(T)-delay);
assert(adaptationSummary.ExecutionBackend == "waveform_truth" && ...
    adaptationSummary.ApproximationMode == "none");
assert(exist(fullfile(result.RunFolder, ...
    "link_adaptation_operating_point_summary.csv"),"file") == 2);
operatingGate = result.ValidityTable( ...
    result.ValidityTable.Check == "link_adaptation_operating_response",:);
assert(height(operatingGate) == 1 && operatingGate.Pass);
shapeGate = result.ValidityTable( ...
    result.ValidityTable.Check == "bler_statistical_noninversion",:);
assert(height(shapeGate) == 1 && shapeGate.Pass && ...
    contains(shapeGate.Evidence,"not applicable to adaptive-MCS operation"));
fprintf("RAN1LLSLinkAdaptation: TB=%d MCS=[%s] throughput=%.3f Mbps.\n", ...
    height(T),strjoin(string(T.MCSIndex.'),","),result.SummaryTable.ThroughputBps/1e6);
ok = true;
end

function localCleanup(path)
if exist(path,"dir") == 7
    rmdir(path,"s");
end
end
