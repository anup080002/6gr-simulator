function [valid, detail] = validateLinkAdaptationTrialEvidence(cfg,trials)
%VALIDATELINKADAPTATIONTRIALEVIDENCE Validate causal CQI/ILLA/OLLA rows.
% Validation is performed independently for every SNR point because trial
% indices and adaptation state restart at each independently seeded point.

arguments
    cfg (1,1) struct
    trials table
end

enabled = logical(sixgr.util.structGet(cfg,"linkAdaptation.enabled",false));
detail = struct("Enabled",enabled,"RequiredColumnsPresent",false, ...
    "GroupCount",0,"FailedGroup",NaN,"Reason","");
if ~enabled
    valid = ~ismember("LinkAdaptationEnabled",string(trials.Properties.VariableNames)) || ...
        ~any(logical(trials.LinkAdaptationEnabled));
    detail.RequiredColumnsPresent = true;
    if ~valid
        detail.Reason = "disabled_configuration_contains_enabled_rows";
    end
    return;
end

required = ["TrialIndex","CRCError","PostEqSINRdB","PostEqSINRValueStatus", ...
    "PostEqSINRValueRole","MCSIndex","MCSTable","Modulation","TargetCodeRate", ...
    "LinkAdaptationEnabled","LinkAdaptationDecisionSource", ...
    "LinkAdaptationFeedbackTrialIndex","LinkAdaptationFeedbackDelaySlots", ...
    "LinkAdaptationFeedbackAgeSlots","LinkAdaptationFeedbackSINRdB", ...
    "LinkAdaptationEffectiveSINRdB","LinkAdaptationSelectedCQI", ...
    "LinkAdaptationSelectedMCSIndex","LinkAdaptationSchedulingEligible", ...
    "LinkAdaptationForcedWaveformProbe","LinkAdaptationDecisionClass", ...
    "LinkAdaptationDecisionValueRole","LinkAdaptationOutOfRangeCQIPolicy", ...
    "LinkAdaptationThresholdSource","LinkAdaptationThresholdValueRole", ...
    "LinkAdaptationThresholdCalibrationId", ...
    "LinkAdaptationThresholdComparisonToleranceDb","OLLAEnabled", ...
    "OLLAOffsetDbApplied","OLLATargetBLER","OLLAACKStepDb", ...
    "OLLANACKStepDb","OLLAMinimumOffsetDb","OLLAMaximumOffsetDb", ...
    "OLLAUpdateSource","OLLAFeedbackTrialIndex","OLLAFeedbackACK", ...
    "OLLAUpdateCount","OLLAStateAuthority"];
detail.RequiredColumnsPresent = all(ismember(required, ...
    string(trials.Properties.VariableNames)));
if isempty(trials) || ~detail.RequiredColumnsPresent
    valid = false;
    detail.Reason = "missing_required_runtime_columns";
    return;
end

if ismember("SNRIndex",string(trials.Properties.VariableNames))
    groupValues = unique(double(trials.SNRIndex),'stable');
else
    groupValues = 1;
end
detail.GroupCount = numel(groupValues);
valid = true;
for groupIndex = 1:numel(groupValues)
    if ismember("SNRIndex",string(trials.Properties.VariableNames))
        point = trials(double(trials.SNRIndex) == groupValues(groupIndex),:);
    else
        point = trials;
    end
    [pointValid,reason] = localValidatePoint(cfg,point);
    if ~pointValid
        valid = false;
        detail.FailedGroup = groupValues(groupIndex);
        detail.Reason = reason;
        return;
    end
end
detail.Reason = "causal_runtime_evidence_valid";
end

function [valid,reason] = localValidatePoint(cfg,T)
valid = false;
reason = "unknown";
n = height(T);
delay = double(cfg.linkAdaptation.feedbackDelaySlots);
trialIndex = double(T.TrialIndex);
if n < 1 || ~isequal(trialIndex(:),(1:n).')
    reason = "nonsequential_trial_indices";
    return;
end
if ~all(logical(T.LinkAdaptationEnabled)) || ...
        ~all(double(T.LinkAdaptationFeedbackDelaySlots) == delay)
    reason = "configured_delay_or_enable_mismatch";
    return;
end

bootstrapCount = min(n,delay);
bootstrap = false(n,1);
bootstrap(1:bootstrapCount) = true;
feedback = ~bootstrap;
probe = logical(T.LinkAdaptationForcedWaveformProbe);
scheduled = ~probe;

source = string(T.LinkAdaptationDecisionSource);
decisionClass = string(T.LinkAdaptationDecisionClass);
if source(1) ~= "configured_bootstrap_mcs" || ...
        decisionClass(1) ~= "scheduled_bootstrap"
    reason = "first_bootstrap_decision_mismatch";
    return;
end
if bootstrapCount > 1
    pending = (2:bootstrapCount).';
    if ~all(source(pending) == "configured_bootstrap_mcs_feedback_pending") || ...
            ~all(decisionClass(pending) == "scheduled_bootstrap_feedback_pending")
        reason = "feedback_pending_bootstrap_mismatch";
        return;
    end
end
normalFeedback = feedback & scheduled;
if ~all(source(normalFeedback) == ...
        "receiver_post_equalization_sinr_after_configured_feedback_delay") || ...
        ~all(source(probe) == ...
        "diagnostic_minimum_mcs_waveform_probe_from_delayed_receiver_post_equalization_sinr")
    reason = "receiver_feedback_source_mismatch";
    return;
end
if ~all(decisionClass(normalFeedback) == "scheduled_cqi_amc") || ...
        ~all(decisionClass(probe) == "diagnostic_minimum_mcs_outage_probe") || ...
        ~all(logical(T.LinkAdaptationSchedulingEligible(scheduled))) || ...
        any(logical(T.LinkAdaptationSchedulingEligible(probe)))
    reason = "decision_classification_mismatch";
    return;
end
if ~all(string(T.LinkAdaptationDecisionValueRole(scheduled)) == ...
        "executable_scheduler_decision") || ...
        ~all(string(T.LinkAdaptationDecisionValueRole(probe)) == ...
        "diagnostic_waveform_probe_not_scheduler_decision")
    reason = "decision_value_role_mismatch";
    return;
end

policy = lower(string(cfg.linkAdaptation.outOfRangeCQIPolicy));
if ~all(lower(string(T.LinkAdaptationOutOfRangeCQIPolicy)) == policy) || ...
        (policy == "block_scheduling" && any(probe)) || ...
        (policy == "minimum_mcs_waveform_probe" && ...
        string(cfg.simulation.statisticalClass) ~= "diagnostic_only")
    reason = "out_of_range_policy_mismatch";
    return;
end
if ~all(abs(double(T.LinkAdaptationThresholdComparisonToleranceDb) - ...
        double(cfg.linkAdaptation.thresholdComparisonToleranceDb)) <= 1e-15) || ...
        any(strlength(string(T.LinkAdaptationThresholdSource)) == 0) || ...
        any(strlength(string(T.LinkAdaptationThresholdValueRole)) == 0) || ...
        any(strlength(string(T.LinkAdaptationThresholdCalibrationId)) == 0)
    reason = "cqi_threshold_provenance_mismatch";
    return;
end

if any(double(T.LinkAdaptationFeedbackTrialIndex(bootstrap)) ~= 0) || ...
        any(isfinite(double(T.LinkAdaptationFeedbackAgeSlots(bootstrap)))) || ...
        any(isfinite(double(T.LinkAdaptationFeedbackSINRdB(bootstrap)))) || ...
        any(isfinite(double(T.LinkAdaptationEffectiveSINRdB(bootstrap)))) || ...
        any(isfinite(double(T.LinkAdaptationSelectedCQI(bootstrap))))
    reason = "bootstrap_claims_unavailable_feedback";
    return;
end
if any(feedback)
    feedbackRows = find(feedback);
    sourceRows = feedbackRows-delay;
    expectedTrialIndex = trialIndex(sourceRows);
    if any(double(T.LinkAdaptationFeedbackTrialIndex(feedbackRows)) ~= expectedTrialIndex) || ...
            any(double(T.LinkAdaptationFeedbackAgeSlots(feedbackRows)) ~= delay) || ...
            any(abs(double(T.LinkAdaptationFeedbackSINRdB(feedbackRows)) - ...
            double(T.PostEqSINRdB(sourceRows))) > 1e-12) || ...
            any(abs(double(T.LinkAdaptationEffectiveSINRdB(feedbackRows)) - ...
            (double(T.PostEqSINRdB(sourceRows)) + ...
            double(T.OLLAOffsetDbApplied(feedbackRows)))) > 1e-12)
        reason = "configured_feedback_delay_not_observed";
        return;
    end
    thresholds = double(cfg.linkAdaptation.sinrThresholdsDb(:).');
    tolerance = double(cfg.linkAdaptation.thresholdComparisonToleranceDb);
    for k = 1:numel(feedbackRows)
        rowIndex = feedbackRows(k);
        [expectedCQI,~] = sixgr.link.resolveCQIFromConfiguredThresholds( ...
            double(T.LinkAdaptationEffectiveSINRdB(rowIndex)),thresholds,tolerance);
        if double(T.LinkAdaptationSelectedCQI(rowIndex)) ~= expectedCQI
            reason = "cqi_quantization_mismatch";
            return;
        end
        if expectedCQI < 1
            expectedMCS = double(cfg.linkAdaptation.minimumMCSIndex);
        else
            amc = sixgr.link.resolveMCSFromCQI(expectedCQI, ...
                cfg.linkAdaptation.mcsTable,cfg.linkAdaptation.cqiTable);
            if ~amc.Valid
                reason = "cqi_to_mcs_mapping_invalid";
                return;
            end
            expectedMCS = double(amc.MCSIndex);
        end
        expectedMCS = max(double(cfg.linkAdaptation.minimumMCSIndex), ...
            min(double(cfg.linkAdaptation.maximumMCSIndex),expectedMCS));
        if double(T.MCSIndex(rowIndex)) ~= expectedMCS || ...
                double(T.LinkAdaptationSelectedMCSIndex(rowIndex)) ~= expectedMCS
            reason = "inner_loop_mcs_mismatch";
            return;
        end
    end
end

olla = cfg.linkAdaptation.olla;
if ~all(logical(T.OLLAEnabled) == logical(olla.enabled)) || ...
        any(abs(double(T.OLLATargetBLER)-double(olla.targetBLER)) > 1e-12) || ...
        any(abs(double(T.OLLAACKStepDb)-double(olla.ackStepDb)) > 1e-12) || ...
        any(abs(double(T.OLLANACKStepDb)-double(olla.nackStepDb)) > 1e-12) || ...
        any(abs(double(T.OLLAMinimumOffsetDb)-double(olla.minimumOffsetDb)) > 1e-12) || ...
        any(abs(double(T.OLLAMaximumOffsetDb)-double(olla.maximumOffsetDb)) > 1e-12) || ...
        any(string(T.OLLAStateAuthority) ~= "receiver_harq_feedback_state")
    reason = "outer_loop_policy_mismatch";
    return;
end
if string(T.OLLAUpdateSource(1)) ~= "no_prior_ack_nack" || ...
        double(T.OLLAFeedbackTrialIndex(1)) ~= 0 || ...
        isfinite(double(T.OLLAFeedbackACK(1)))
    reason = "first_outer_loop_state_mismatch";
    return;
end
if bootstrapCount > 1
    pending = (2:bootstrapCount).';
    if ~all(string(T.OLLAUpdateSource(pending)) == "configured_feedback_delay_pending") || ...
            any(double(T.OLLAFeedbackTrialIndex(pending)) ~= 0) || ...
            any(isfinite(double(T.OLLAFeedbackACK(pending))))
        reason = "outer_loop_feedback_pending_mismatch";
        return;
    end
end

expectedOffset = double(olla.initialOffsetDb);
expectedUpdateCount = 0;
if any(abs(double(T.OLLAOffsetDbApplied(bootstrap))-expectedOffset) > 1e-12) || ...
        any(double(T.OLLAUpdateCount(bootstrap)) ~= 0)
    reason = "bootstrap_outer_loop_offset_mismatch";
    return;
end
feedbackRows = find(feedback);
for k = 1:numel(feedbackRows)
    rowIndex = feedbackRows(k);
    sourceIndex = rowIndex-delay;
    expectedAck = double(~T.CRCError(sourceIndex));
    if logical(olla.enabled)
        if expectedAck == 1
            expectedOffset = min(double(olla.maximumOffsetDb), ...
                expectedOffset + double(olla.ackStepDb));
        else
            expectedOffset = max(double(olla.minimumOffsetDb), ...
                expectedOffset - double(olla.nackStepDb));
        end
        expectedUpdateCount = expectedUpdateCount + 1;
    end
    if string(T.OLLAUpdateSource(rowIndex)) ~= ...
            "decoded_transport_block_crc_after_configured_feedback_delay" || ...
            double(T.OLLAFeedbackTrialIndex(rowIndex)) ~= trialIndex(sourceIndex) || ...
            double(T.OLLAFeedbackACK(rowIndex)) ~= expectedAck || ...
            abs(double(T.OLLAOffsetDbApplied(rowIndex))-expectedOffset) > 1e-12 || ...
            double(T.OLLAUpdateCount(rowIndex)) ~= expectedUpdateCount
        reason = "outer_loop_update_mismatch";
        return;
    end
end

if any(double(T.LinkAdaptationSelectedMCSIndex) ~= double(T.MCSIndex)) || ...
        any(~isfinite(double(T.PostEqSINRdB))) || ...
        ~all(startsWith(string(T.PostEqSINRValueStatus),"OK")) || ...
        ~all(string(T.PostEqSINRValueRole) == ...
        "measured_post_equalization_scheduling_input")
    reason = "executed_phy_binding_mismatch";
    return;
end
for rowIndex = 1:n
    profile = sixgr.link.resolveMCSProfile(T.MCSTable(rowIndex),T.MCSIndex(rowIndex));
    if ~profile.Valid || ...
            ~strcmpi(string(profile.Modulation),string(T.Modulation(rowIndex))) || ...
            abs(double(profile.TargetCodeRate)-double(T.TargetCodeRate(rowIndex))) > 1e-12
        reason = "executed_mcs_profile_mismatch";
        return;
    end
end

valid = true;
reason = "causal_point_evidence_valid";
end
