function [decision, adaptationState] = computeLinkAdaptationDecision(cfg, direction, metrics, varargin)
%COMPUTELINKADAPTATIONDECISION Build the next closed-loop LLS adaptation decision.

ip = inputParser;
ip.addParameter("AdaptationState", struct(), @(x) isempty(x) || isstruct(x));
ip.parse(varargin{:});
opt = ip.Results;

direction = upper(string(direction));
if direction ~= "DL" && direction ~= "UL"
    error("sixgr:link:LinkAdaptation:BadDirection", ...
        "Direction must be 'DL' or 'UL'.");
end

if nargin < 3 || isempty(metrics)
    metrics = struct();
end

mode = lower(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.mode", "fixed")));
policyPath = localPolicyPath(direction);
policy = lower(string(sixgr.util.structGet(cfg, policyPath, "fixed")));
rankPolicy = lower(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.rankPolicy", "fixed")));
beamPolicy = lower(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.beamPolicy", "fixed")));

base = localBaseState(cfg, direction);
adaptationState = localInitAdaptationState(cfg, direction, opt.AdaptationState);
adaptationDomain = sixgr.link.resolveLinkAdaptationDomain(cfg, direction);
[ackKnown, ackObserved, ackSource] = localResolveAckOutcome(metrics);
[ollaUpdateAuthorized, ollaFeedbackEventType, ollaAuthoritySource] = ...
    localResolveOLLAUpdateAuthority(metrics, ackKnown);
[instantCQI, instantMCS, instantMod, instantCodeRate, mcsTable, cqiTable, cqiSource, calibrationProfile, cqiMeta] = ...
    localResolveInstantaneousAMC(cfg, direction, metrics, adaptationDomain);
[resetState, resetReason] = localShouldResetState(adaptationState, metrics, cfg);

decision = struct( ...
    "Enabled", localPolicyEnabled(mode) && (localPolicyEnabled(policy) || localPolicyEnabled(rankPolicy) || localPolicyEnabled(beamPolicy)), ...
    "Direction", char(direction), ...
    "Mode", char(mode), ...
    "Policy", char(policy), ...
    "RankPolicy", char(rankPolicy), ...
    "BeamPolicy", char(beamPolicy), ...
    "Valid", false, ...
    "Reason", "", ...
    "CQI", double(sixgr.util.structGet(metrics, "CQI", NaN)), ...
    "RI", double(sixgr.util.structGet(metrics, "RI", NaN)), ...
    "PMI", double(sixgr.util.structGet(metrics, "PMI", NaN)), ...
    "CRI", double(sixgr.util.structGet(metrics, "CRI", NaN)), ...
    "MeasuredSINR_dB", double(sixgr.util.structGet(metrics, "SINR_dB", NaN)), ...
    "MCSIndex", base.MCSIndex, ...
    "Modulation", char(base.Modulation), ...
    "TargetCodeRate", double(base.TargetCodeRate), ...
    "NumLayers", double(base.NumLayers), ...
    "PMIUpdated", false, ...
    "CRIUpdated", false, ...
    "RankUpdated", false, ...
    "RankUpdateStatus", "not_requested", ...
    "RankUpdateBlockedReason", "", ...
    "RankIncreaseConfirmationCount", double(adaptationState.RankIncreaseConfirmationCount), ...
    "RankIncreaseRequiredCount", double(adaptationState.RankIncreaseRequiredCount), ...
    "MCSUpdated", false, ...
    "PMIType", char(string(sixgr.util.structGet(metrics, "PMIType", ""))), ...
    "PMICodebookMode", char(string(sixgr.util.structGet(metrics, "PMICodebookMode", ""))), ...
    "CSIReportMode", char(string(sixgr.util.structGet(metrics, "CSIReportMode", ""))), ...
    "CSIPayloadBitLength", double(sixgr.util.structGet(metrics, "CSIPayloadBitLength", NaN)), ...
    "CSIPayloadHex", char(string(sixgr.util.structGet(metrics, "CSIPayloadHex", ""))), ...
    "LinkAdaptationDomain", char(adaptationDomain), ...
    "LinkAdaptationDomainSource", "phy.linkAdaptation.domain", ...
    "ResolvedCQI", double(instantCQI), ...
    "SmoothedCQI", double(adaptationState.SmoothedCQI), ...
    "CQIObservationCount", double(adaptationState.CQIObservationCount), ...
    "CQIOutageObservationCount", double(adaptationState.CQIOutageObservationCount), ...
    "CQIOutageRecoveryFilterApplied", false, ...
    "CQIOutageRecoveryPending", false, ...
    "CQIOutageRecoveryResolvedCQI", NaN, ...
    "CQIOutageRecoveryPositiveCount", double(adaptationState.CQIOutageRecoveryPositiveCount), ...
    "CQIOutageRecoveryRequiredCount", double(adaptationState.CQIOutageRecoveryRequiredCount), ...
    "CQIOutageRecoveryCandidate", double(adaptationState.CQIOutageRecoveryCandidate), ...
    "CQIOutageRecoveryCQITolerance", double(adaptationState.CQIOutageRecoveryCQITolerance), ...
    "CQIOutageRecoveryFeedbackGapSlots", NaN, ...
    "CQIOutageRecoveryMaxGapSlots", double(adaptationState.CQIOutageRecoveryMaxGapSlots), ...
    "CQISource", char(cqiSource), ...
    "MCSSelectionSource", char(localResolveMCSSelectionSource(adaptationDomain)), ...
    "MCSValueStatus", "unresolved", ...
    "OLLADomain", char(localResolveOLLADomain(adaptationDomain, adaptationState.OuterLoopEnabled)), ...
    "OLLAStateAuthority", char(string(sixgr.util.structGet(adaptationState, ...
        "OLLAStateAuthority", "receiver_harq_feedback_state"))), ...
    "OLLADeltaDb", double(adaptationState.DeltaMCS), ...
    "OLLADeltaMCS", double(adaptationState.DeltaMCS), ...
    "OLLAMarginMinDb", double(adaptationState.DeltaMCSMin), ...
    "OLLAMarginMaxDb", double(adaptationState.DeltaMCSMax), ...
    "OLLAAdjustedMCSBeforeCQICeiling", NaN, ...
    "OLLABaseRequiredSINR_dB", NaN, ...
    "OLLATargetRequiredSINR_dB", NaN, ...
    "OLLAThresholdSource", "", ...
    "OLLAUpdateCount", double(adaptationState.OLLAUpdateCount), ...
    "OLLAUpdateCountBeforeEvent", double(adaptationState.OLLAUpdateCount), ...
    "OLLAUpdateCountAfterEvent", double(adaptationState.OLLAUpdateCount), ...
    "OLLAUpdateAppliedAtThisEvent", false, ...
    "OLLAUpdateAuthorized", logical(ollaUpdateAuthorized), ...
    "OLLAFeedbackEventType", char(ollaFeedbackEventType), ...
    "OLLAUpdateAuthoritySource", char(ollaAuthoritySource), ...
    "OLLAFeedbackEligible", false, ...
    "OLLAFeedbackExclusionReason", "no_ack_nack_feedback", ...
    "CalibrationProfile", char(calibrationProfile), ...
    "CalibrationVersion", char(string(cqiMeta.CalibrationVersion)), ...
    "CQIBLERLUTSource", char(string(cqiMeta.BLERLUTSource)), ...
    "CQIBLERLUTValueRole", char(string(cqiMeta.BLERLUTValueRole)), ...
    "CQIBLERLUTCalibrationID", char(string(cqiMeta.BLERLUTCalibrationID)), ...
    "TargetBLER", double(cqiMeta.TargetBLER), ...
    "CausalFeedbackUsable", logical(cqiMeta.CausalFeedbackUsable), ...
    "CausalFeedbackStatus", char(string(cqiMeta.CausalFeedbackStatus)), ...
    "FeedbackAgeSlots", double(cqiMeta.FeedbackAgeSlots), ...
    "FeedbackAgingPenalty_dB", double(cqiMeta.FeedbackAgingPenalty_dB), ...
    "DirectionalSINRBackoff_dB", double(cqiMeta.DirectionalSINRBackoff_dB), ...
    "TotalCQISINRBackoff_dB", double(cqiMeta.TotalCQISINRBackoff_dB), ...
    "AgedSINR_dB", double(cqiMeta.AgedSINR_dB), ...
    "AgedCQI", double(cqiMeta.AgedCQI), ...
    "CSIAgingModel", char(string(cqiMeta.CSIAgingModel)), ...
    "AgedSubbandSINRVector_dB", char(string(cqiMeta.AgedSubbandSINRVector_dB)), ...
    "AgedLayerSINRVector_dB", char(string(cqiMeta.AgedLayerSINRVector_dB)), ...
    "SubbandAgingPenaltyVector_dB", char(string(cqiMeta.SubbandAgingPenaltyVector_dB)), ...
    "LayerAgingPenaltyVector_dB", char(string(cqiMeta.LayerAgingPenaltyVector_dB)), ...
    "CSIQuantizationBits", double(cqiMeta.CSIQuantizationBits), ...
    "CQITable", char(cqiTable), ...
    "MCSTable", char(mcsTable), ...
    "InstantaneousCQIMCS", double(instantMCS), ...
    "InstantaneousCQIModulation", char(instantMod), ...
    "InstantaneousCQITargetCodeRate", double(instantCodeRate), ...
    "CQISmoothingAlpha", double(adaptationState.CQISmoothingAlpha), ...
    "CQISmoothingAlphaSource", char(string(sixgr.util.structGet(adaptationState, "CQISmoothingAlphaSource", ""))), ...
    "CQIBasedMCS", double(adaptationState.CQIBasedMCS), ...
    "DeltaMCS", double(adaptationState.DeltaMCS), ...
    "StaticDeltaMCS", double(adaptationState.StaticDeltaMCS), ...
    "OuterLoopEnabled", logical(adaptationState.OuterLoopEnabled), ...
    "InnerLoopEnabled", logical(adaptationState.InnerLoopEnabled), ...
    "AckObserved", logical(ackObserved), ...
    "AckObservedValid", logical(ackKnown), ...
    "AckObservedSource", char(ackSource), ...
    "StateReset", logical(resetState), ...
    "StateResetReason", char(resetReason), ...
    "StateInitialized", logical(adaptationState.Initialized), ...
    "StateUpdateCount", double(adaptationState.UpdateCount));

if ~decision.Enabled
    decision.Reason = "link_adaptation_disabled";
    return;
end

if localPolicyEnabled(policy)
    % TS 38.214 CQI index 0 explicitly reports that the channel is out of
    % range.  It is feedback, not a schedulable minimum-MCS operating
    % point.  Fail closed before either ILLA smoothing or OLLA ACK/NACK
    % state is updated so an outage cannot be turned into an MCS-0 grant.
    rawReportedCQI = double(sixgr.util.structGet(metrics, "CQI", NaN));
    reportedCQI0IsAuthoritative = string(adaptationDomain) == "cqi" && ...
        isfinite(rawReportedCQI) && rawReportedCQI <= 0;
    if reportedCQI0IsAuthoritative || (isfinite(instantCQI) && double(instantCQI) <= 0)
        % CQI 0 is not schedulable, but it is still a real receiver
        % observation.  Retain it in the ILLA temporal state so that the
        % next positive, possibly CRC-unprotected UCI report cannot
        % initialize the filter at an arbitrarily high CQI.  This does not
        % initialize a grant/MCS state and does not update HARQ/OLLA.
        adaptationState.LastCQI = 0;
        adaptationState.SmoothedCQI = 0;
        adaptationState.LastCQIOutOfRange = true;
        adaptationState.CQIObservationCount = ...
            double(adaptationState.CQIObservationCount) + 1;
        adaptationState.CQIOutageObservationCount = ...
            double(adaptationState.CQIOutageObservationCount) + 1;
        adaptationState.CQIOutageRecoveryPositiveCount = 0;
        adaptationState.CQIOutageRecoveryCandidate = NaN;
        feedbackAbsoluteSlot = double(sixgr.util.structGet( ...
            metrics, "FeedbackAbsoluteSlot", NaN));
        if isfinite(feedbackAbsoluteSlot)
            adaptationState.LastCQIFeedbackAbsoluteSlot = feedbackAbsoluteSlot;
        end
        adaptationState.RankIncreaseCandidate = NaN;
        adaptationState.RankIncreaseConfirmationCount = 0;
        decision.ResolvedCQI = 0;
        decision.SmoothedCQI = 0;
        decision.CQIObservationCount = double(adaptationState.CQIObservationCount);
        decision.CQIOutageObservationCount = ...
            double(adaptationState.CQIOutageObservationCount);
        decision.CQIOutageRecoveryResolvedCQI = 0;
        decision.CQIOutageRecoveryPositiveCount = 0;
        decision.MCSIndex = NaN;
        decision.Modulation = "";
        decision.TargetCodeRate = NaN;
        decision.Reason = "measured_cqi_zero_out_of_range";
        decision.MCSSelectionSource = "blocked_measured_cqi_zero_out_of_range";
        decision.MCSValueStatus = "unavailable_measured_cqi_zero_out_of_range";
        decision.CausalFeedbackStatus = "measured_cqi_zero_out_of_range";
        return;
    end
    [decision, adaptationState] = localResolveMCSDecision(decision, adaptationState, cfg, direction, metrics, ...
        instantCQI, instantMCS, instantMod, instantCodeRate, mcsTable, cqiTable, adaptationDomain, ...
        ackKnown, ackObserved, ollaUpdateAuthorized, ollaFeedbackEventType, ...
        resetState, resetReason);
    if decision.CQIOutageRecoveryPending || ~decision.CausalFeedbackUsable
        % An RI/PMI/CRI update must not turn a rejected quality decision
        % into Valid=true below and authorize a new data operating point.
        % Retain raw received fields and the temporal recovery state only.
        return;
    end
    if ~decision.MCSUpdated && ~(isfinite(decision.CQIBasedMCS) || adaptationState.Initialized) && ...
            strlength(string(decision.Reason)) == 0
        decision.Reason = "missing_cqi";
        return;
    end
end

if localPolicyEnabled(rankPolicy)
    ri = decision.RI;
    if isfinite(ri)
        maxLayers = localMaxLayers(cfg, direction);
        requestedLayers = max(1, min(maxLayers, round(ri)));
        if requestedLayers < decision.NumLayers
            % A receiver-requested rank reduction is protective and is
            % applied immediately. Confirmation is required only for an
            % increase in the spatial operating point.
            adaptationState.RankIncreaseCandidate = NaN;
            adaptationState.RankIncreaseConfirmationCount = 0;
            decision.NumLayers = requestedLayers;
            decision.RankUpdated = true;
            decision.RankUpdateStatus = "requested_from_ri";
        elseif requestedLayers > decision.NumLayers
            previousCandidate = double(adaptationState.RankIncreaseCandidate);
            if isfinite(previousCandidate) && round(previousCandidate) == requestedLayers
                adaptationState.RankIncreaseConfirmationCount = ...
                    double(adaptationState.RankIncreaseConfirmationCount) + 1;
            else
                adaptationState.RankIncreaseCandidate = double(requestedLayers);
                adaptationState.RankIncreaseConfirmationCount = 1;
            end
            decision.RankIncreaseConfirmationCount = ...
                double(adaptationState.RankIncreaseConfirmationCount);
            if adaptationState.RankIncreaseConfirmationCount >= ...
                    adaptationState.RankIncreaseRequiredCount
                decision.NumLayers = requestedLayers;
                decision.RankUpdated = true;
                decision.RankUpdateStatus = "requested_from_confirmed_ri";
            else
                decision.RankUpdateStatus = "pending_increase_confirmation";
                decision.RankUpdateBlockedReason = ...
                    "rank_increase_requires_consecutive_received_ri_reports";
            end
        else
            adaptationState.RankIncreaseCandidate = NaN;
            adaptationState.RankIncreaseConfirmationCount = 0;
            decision.RankIncreaseConfirmationCount = 0;
        end
    end
end

if direction == "DL" && localPolicyEnabled(beamPolicy)
    pmi = decision.PMI;
    if isfinite(pmi)
        decision.PMI = round(pmi);
        decision.PMIUpdated = true;
    end
    cri = decision.CRI;
    if isfinite(cri)
        decision.CRI = round(cri);
        decision.CRIUpdated = true;
    end
end

% A PMI accompanying an unconfirmed higher RI belongs to the candidate
% rank, not the currently executable rank. Hold both parts of the spatial
% decision until the causal RI confirmation requirement is met.
if string(decision.RankUpdateStatus) == "pending_increase_confirmation"
    decision.PMIUpdated = false;
end

% Rank and precoder form one spatial decision.  Do not apply an RI-only
% rank transition while retaining an explicit matrix frozen for the old
% rank.  Without a simultaneous finite PMI there is no standards-backed
% codebook choice for the new rank, so hold the previous spatial state and
% allow any independent MCS decision to proceed.
if direction == "DL" && logical(decision.RankUpdated) && ...
        ~logical(decision.PMIUpdated) && ...
        localHasStaleExplicitPDSCHMatrix(cfg, decision.NumLayers)
    decision.NumLayers = double(base.NumLayers);
    decision.RankUpdated = false;
    decision.RankUpdateStatus = "held_missing_atomic_pmi";
    decision.RankUpdateBlockedReason = ...
        "explicit_precoder_rank_transition_requires_simultaneous_finite_pmi";
elseif logical(decision.RankUpdated)
    decision.RankUpdateStatus = "ready_to_apply";
    adaptationState.RankIncreaseCandidate = NaN;
    adaptationState.RankIncreaseConfirmationCount = 0;
end

decision.Valid = logical(decision.MCSUpdated || decision.RankUpdated || decision.PMIUpdated || decision.CRIUpdated);
if decision.Valid
    decision.Reason = "adaptation_scheduled";
else
    if strlength(decision.Reason) == 0
        if string(decision.RankUpdateStatus) == "pending_increase_confirmation"
            decision.Reason = "rank_increase_confirmation_pending";
        else
            decision.Reason = "no_change";
        end
    end
end
end

function [decision, adaptationState] = localResolveMCSDecision(decision, adaptationState, cfg, direction, metrics, instantCQI, instantMCS, instantMod, instantCodeRate, mcsTable, cqiTable, adaptationDomain, ackKnown, ackObserved, ollaUpdateAuthorized, ollaFeedbackEventType, resetState, resetReason)
previousMCS = double(decision.MCSIndex);
previousCodeRate = double(decision.TargetCodeRate);
previousModulation = char(string(decision.Modulation));
[effectiveCQIAlpha, csiTrustWeight, csiAge_s, csiCoherence_s] = ...
    localEffectiveCQISmoothingAlpha(adaptationState.CQISmoothingAlpha, cfg, metrics);
decision.EffectiveCQISmoothingAlpha = double(effectiveCQIAlpha);
decision.CSITemporalCorrelationWeight = double(csiTrustWeight);
decision.CSIAgeSeconds = double(csiAge_s);
decision.CSICoherenceTimeSeconds = double(csiCoherence_s);
decision.CausalFeedbackUsable = logical(sixgr.util.structGet(decision, "CausalFeedbackUsable", true));
if ~decision.CausalFeedbackUsable
    % Stale or otherwise unusable feedback must not mutate the temporal
    % CQI filter or any outage-recovery counter.
    decision.Reason = "stale_or_unusable_csi_feedback";
    return;
end

priorMeasuredOutage = adaptationDomain == "cqi" && ...
    logical(sixgr.util.structGet(adaptationState, "LastCQIOutOfRange", false)) && ...
    isfinite(double(adaptationState.SmoothedCQI));
feedbackAbsoluteSlot = double(sixgr.util.structGet( ...
    metrics, "FeedbackAbsoluteSlot", NaN));
% Keep the latest causal receiver-delivery clock for every usable CQI
% observation, not only CQI-0/recovery reports.  A later outage-recovery
% decision must compare against the preceding real report clock rather
% than an uninitialized timestamp.
if ~priorMeasuredOutage && isfinite(feedbackAbsoluteSlot)
    adaptationState.LastCQIFeedbackAbsoluteSlot = feedbackAbsoluteSlot;
end
if adaptationDomain ~= "legacy_mcs" && isfinite(instantCQI)
    if priorMeasuredOutage && logical(adaptationState.InnerLoopEnabled)
        % A measured CQI-0 observation is a valid temporal anchor.  Apply
        % the configured ILLA smoothing before allowing recovery from
        % outage.  This is intentionally distinct from the pre-feedback
        % bootstrap state, which must not invent CQI 0.
        alpha = double(effectiveCQIAlpha);
        smoothedCQI = alpha * double(instantCQI) + ...
            (1 - alpha) * double(adaptationState.SmoothedCQI);
    elseif resetState || ~adaptationState.Initialized || ~isfinite(adaptationState.SmoothedCQI)
        smoothedCQI = double(instantCQI);
    elseif logical(adaptationState.InnerLoopEnabled)
        alpha = double(effectiveCQIAlpha);
        smoothedCQI = alpha * double(instantCQI) + (1 - alpha) * double(adaptationState.SmoothedCQI);
    else
        smoothedCQI = double(instantCQI);
    end
    adaptationState.SmoothedCQI = double(smoothedCQI);
end
decision.SmoothedCQI = double(adaptationState.SmoothedCQI);
decision.CQIObservationCount = double(adaptationState.CQIObservationCount) + 1;
decision.CQIOutageObservationCount = double(adaptationState.CQIOutageObservationCount);

if priorMeasuredOutage
    decision.CQIOutageRecoveryFilterApplied = true;
    lastFeedbackAbsoluteSlot = double(sixgr.util.structGet( ...
        adaptationState, "LastCQIFeedbackAbsoluteSlot", NaN));
    feedbackGapSlots = NaN;
    if isfinite(feedbackAbsoluteSlot) && isfinite(lastFeedbackAbsoluteSlot)
        feedbackGapSlots = feedbackAbsoluteSlot - lastFeedbackAbsoluteSlot;
    end
    decision.CQIOutageRecoveryFeedbackGapSlots = feedbackGapSlots;

    candidate = double(sixgr.util.structGet( ...
        adaptationState, "CQIOutageRecoveryCandidate", NaN));
    positiveCount = double(adaptationState.CQIOutageRecoveryPositiveCount);
    gapExceeded = isfinite(feedbackGapSlots) && ...
        (feedbackGapSlots <= 0 || ...
        feedbackGapSlots > adaptationState.CQIOutageRecoveryMaxGapSlots);
    candidateConsistent = isfinite(candidate) && ...
        abs(double(instantCQI) - candidate) <= ...
        adaptationState.CQIOutageRecoveryCQITolerance;
    if gapExceeded || ~candidateConsistent
        candidate = double(instantCQI);
        positiveCount = 1;
    else
        % Use the lower member of the consistent pair as the scheduling
        % authority. This prevents the recovery gate itself from creating
        % an optimistic CQI while retaining only receiver-decoded reports.
        candidate = min(candidate, double(instantCQI));
        positiveCount = positiveCount + 1;
    end
    adaptationState.CQIOutageRecoveryCandidate = candidate;
    adaptationState.CQIOutageRecoveryPositiveCount = positiveCount;
    if isfinite(feedbackAbsoluteSlot)
        adaptationState.LastCQIFeedbackAbsoluteSlot = feedbackAbsoluteSlot;
    end
    decision.CQIOutageRecoveryPositiveCount = ...
        double(adaptationState.CQIOutageRecoveryPositiveCount);
    decision.CQIOutageRecoveryCandidate = candidate;
    recoveryCQI = floor(min(15, max(0, min( ...
        double(adaptationState.SmoothedCQI), candidate))));
    decision.CQIOutageRecoveryResolvedCQI = double(recoveryCQI);
    decision.ResolvedCQI = double(recoveryCQI);
    if recoveryCQI < 1 || ...
            adaptationState.CQIOutageRecoveryPositiveCount < ...
            adaptationState.CQIOutageRecoveryRequiredCount
        % Continue accumulating real positive observations without issuing
        % a grant until the filtered CQI leaves the out-of-range state and
        % enough causal positive reports have been received. This makes the
        % guard independent of the selected smoothing coefficient.
        adaptationState.LastCQI = double(instantCQI);
        adaptationState.LastCQIOutOfRange = true;
        adaptationState.CQIObservationCount = ...
            double(adaptationState.CQIObservationCount) + 1;
        decision.CQIObservationCount = double(adaptationState.CQIObservationCount);
        decision.CQIOutageRecoveryPending = true;
        decision.MCSIndex = NaN;
        decision.Modulation = "";
        decision.TargetCodeRate = NaN;
        decision.Reason = "cqi_outage_recovery_pending";
        decision.MCSSelectionSource = "blocked_cqi_outage_recovery_filter";
        decision.MCSValueStatus = "unavailable_cqi_outage_recovery_pending";
        return;
    end
    [instantMod, instantCodeRate, instantMCS] = sixgr.link.amcFromCQI( ...
        recoveryCQI, "", NaN, cfg, direction);
    decision.MCSSelectionSource = "runtime_cqi_outage_recovery_filter";
else
    adaptationState.CQIOutageRecoveryPositiveCount = 0;
    adaptationState.CQIOutageRecoveryCandidate = NaN;
    decision.CQIOutageRecoveryPositiveCount = 0;
end

if isfinite(instantMCS)
    mcsJumpReset = false;
    if ~resetState && adaptationState.Initialized && localMCSJumpResetEnabled(cfg) && ...
            isfinite(adaptationState.LastMCSIndex) && ...
            abs(double(instantMCS) - double(adaptationState.LastMCSIndex)) > localMCSJumpThreshold(cfg)
        mcsJumpReset = true;
        resetState = true;
        resetReason = "mcs_jump";
        cqiBasedMCS = double(instantMCS);
        adaptationState.CQIBasedMCS = double(cqiBasedMCS);
        if isfinite(instantCQI)
            adaptationState.SmoothedCQI = double(instantCQI);
            decision.SmoothedCQI = double(instantCQI);
        end
    end

    initializeCQIMCS = ~adaptationState.Initialized || ~isfinite(adaptationState.CQIBasedMCS) || resetState;
    if initializeCQIMCS
        cqiBasedMCS = double(instantMCS);
    elseif logical(adaptationState.InnerLoopEnabled)
        cqiBasedMCS = localSmoothCQIBasedMCS(adaptationState.CQIBasedMCS, instantMCS, effectiveCQIAlpha);
    else
        cqiBasedMCS = double(instantMCS);
    end
    adaptationState.CQIBasedMCS = double(cqiBasedMCS);
    adaptationState.LastInstantaneousMCS = double(instantMCS);
    adaptationState.LastInstantaneousModulation = char(instantMod);
    adaptationState.LastInstantaneousTargetCodeRate = double(instantCodeRate);
elseif adaptationState.Initialized && isfinite(adaptationState.CQIBasedMCS)
    cqiBasedMCS = double(adaptationState.CQIBasedMCS);
else
    decision.Reason = "missing_cqi";
    return;
end

if resetState
    adaptationState.DeltaMCS = 0;
    adaptationState.LastResetReason = char(resetReason);
end

feedbackEvent = metrics;
ollaCountBefore = double(adaptationState.OLLAUpdateCount);
feedbackEvent.AckObservedValid = logical(ackKnown) && logical(ollaUpdateAuthorized);
feedbackEvent.AckObserved = logical(ackObserved);
[adaptationState, ollaEvent] = sixgr.link.updateOLLAStateFromHARQFeedback( ...
    cfg, direction, feedbackEvent, adaptationState);
ollaFeedbackEligible = logical(ollaEvent.Eligible);
ollaFeedbackExclusionReason = string(ollaEvent.ExclusionReason);
if ~logical(ollaUpdateAuthorized)
    ollaFeedbackEligible = false;
    ollaFeedbackExclusionReason = "event_not_authorized_for_olla:" + string(ollaFeedbackEventType);
end
ollaCountAfter = double(adaptationState.OLLAUpdateCount);

maxMCS = localMaxValidMCS(mcsTable);
cqiCeilingMCS = double(instantMCS);
if ~(isfinite(cqiCeilingMCS) && cqiCeilingMCS >= 0)
    cqiCeilingMCS = double(maxMCS);
end
ollaAdjustedMCSBeforeCQICeiling = NaN;
ollaDetail = struct( ...
    "BaseRequiredSINR_dB", NaN, ...
    "TargetRequiredSINR_dB", NaN, ...
    "ThresholdSource", "");
% Inner-loop smoothing may use the legacy MCS domain, but the shared HARQ
% outer-loop state always carries dB. Never add it to an ordinal MCS index
% or overwrite it using MCS bounds.
[ollaAdjustedMCSBeforeCQICeiling, ollaDetail] = sixgr.link.applyOLLADeltaDbToMCSIndex( ...
    double(cqiBasedMCS), double(adaptationState.DeltaMCS), mcsTable, cqiTable, direction, ...
    "Config", cfg);
dynamicMCS = double(ollaAdjustedMCSBeforeCQICeiling) + double(adaptationState.StaticDeltaMCS);
selectedMCS = floor(min(double(dynamicMCS), double(cqiCeilingMCS)));
mcsClampedToCQI = isfinite(cqiCeilingMCS) && floor(double(dynamicMCS)) > floor(double(cqiCeilingMCS));
selectedMCS = max(0, min(double(maxMCS), double(selectedMCS)));
profile = sixgr.link.resolveMCSProfile(mcsTable, selectedMCS);
if ~logical(sixgr.util.structGet(profile, "Valid", false))
    decision.Reason = "invalid_mcs_profile";
    return;
end

decision.CQIBasedMCS = double(cqiBasedMCS);
decision.CQIBasedMCSNoOLLA = double(cqiBasedMCS);
decision.DeltaMCS = double(adaptationState.DeltaMCS);
decision.OLLADeltaDb = double(adaptationState.DeltaMCS);
decision.OLLADeltaMCS = double(adaptationState.DeltaMCS);
decision.OLLAMarginMinDb = double(adaptationState.DeltaMCSMin);
decision.OLLAMarginMaxDb = double(adaptationState.DeltaMCSMax);
decision.OLLAAdjustedMCSBeforeCQICeiling = double(ollaAdjustedMCSBeforeCQICeiling);
decision.OLLABaseRequiredSINR_dB = double(sixgr.util.structGet(ollaDetail, "BaseRequiredSINR_dB", NaN));
decision.OLLATargetRequiredSINR_dB = double(sixgr.util.structGet(ollaDetail, "TargetRequiredSINR_dB", NaN));
decision.OLLAThresholdSource = char(string(sixgr.util.structGet(ollaDetail, "ThresholdSource", "")));
decision.OLLAUpdateCount = double(adaptationState.OLLAUpdateCount);
decision.OLLAUpdateCountBeforeEvent = double(ollaCountBefore);
decision.OLLAUpdateCountAfterEvent = double(ollaCountAfter);
decision.OLLAUpdateAppliedAtThisEvent = logical(ollaFeedbackEligible) && ...
    double(ollaCountAfter) == double(ollaCountBefore) + 1;
decision.OLLAFeedbackEligible = logical(ollaFeedbackEligible);
decision.OLLAFeedbackExclusionReason = char(ollaFeedbackExclusionReason);
% Retired index-domain fields must not relabel the dB state.
decision.OLLAOffsetMCS = NaN;
decision.OLLAMCSBoundMin = NaN;
decision.OLLAMCSBoundMax = NaN;
decision.StaticDeltaMCS = double(adaptationState.StaticDeltaMCS);
decision.Modulation = char(string(profile.Modulation));
decision.TargetCodeRate = double(profile.TargetCodeRate);
decision.MCSIndex = double(selectedMCS);
if mcsClampedToCQI
    decision.MCSValueStatus = "clamped_to_cqi_max";
elseif adaptationState.OuterLoopEnabled && isfinite(double(adaptationState.DeltaMCS)) && ...
        abs(double(adaptationState.DeltaMCS)) > 0
    decision.MCSValueStatus = "measured_cqi_mapped_olla_db_margin_adjusted";
else
    decision.MCSValueStatus = "measured_cqi_mapped";
end
decision.MCSUpdated = resetState || ...
    ~(isfinite(previousMCS) && abs(previousMCS - double(selectedMCS)) <= 1e-9 && ...
    isfinite(previousCodeRate) && abs(previousCodeRate - double(profile.TargetCodeRate)) <= 1e-12 && ...
    strcmpi(previousModulation, char(string(profile.Modulation))));
decision.StateReset = logical(resetState);
decision.StateResetReason = char(resetReason);
decision.OuterLoopEnabled = logical(adaptationState.OuterLoopEnabled);
decision.InnerLoopEnabled = logical(adaptationState.InnerLoopEnabled);
decision.StateInitialized = true;
decision.StateUpdateCount = double(adaptationState.UpdateCount + 1);

adaptationState.Initialized = true;
adaptationState.LastCQI = double(instantCQI);
adaptationState.LastCQIOutOfRange = false;
adaptationState.CQIOutageRecoveryPositiveCount = 0;
adaptationState.CQIOutageRecoveryCandidate = NaN;
adaptationState.CQIObservationCount = ...
    double(adaptationState.CQIObservationCount) + 1;
adaptationState.LastRI = double(decision.RI);
adaptationState.LastMCSIndex = double(selectedMCS);
adaptationState.UpdateCount = adaptationState.UpdateCount + 1;
end

function [instantCQI, instantMCS, instantMod, instantCodeRate, mcsTable, cqiTable, cqiSource, calibrationProfile, cqiMeta] = localResolveInstantaneousAMC(cfg, direction, metrics, adaptationDomain)
mcsTable = sixgr.link.resolveConfiguredMCSTable(cfg, direction);
cqiTable = sixgr.link.resolveConfiguredCQITable(cfg, direction);
instantCQI = NaN;
instantMCS = NaN;
instantMod = "";
instantCodeRate = NaN;
cqiSource = "unavailable";
calibrationProfile = localResolveCalibrationProfile(cfg, direction, adaptationDomain);
[instantCQI, cqiSource, calibrationProfile, cqiMeta] = localResolveInstantaneousCQI(cfg, direction, metrics, adaptationDomain, calibrationProfile);
if ~(isfinite(instantCQI))
    return;
end
[instantMod, instantCodeRate, instantMCS] = sixgr.link.amcFromCQI(instantCQI, "", NaN, cfg, direction);
end

function [instantCQI, cqiSource, calibrationProfile, cqiMeta] = localResolveInstantaneousCQI(cfg, direction, metrics, adaptationDomain, calibrationProfile)
instantCQI = NaN;
cqiSource = "unavailable";
cqiMeta = localCQIMetaDefaults(cfg, direction, metrics);
if ~logical(cqiMeta.CausalFeedbackUsable)
    cqiSource = "stale_or_unusable_runtime_csi";
    return;
end

rawCQI = double(sixgr.util.structGet(metrics, "CQI", NaN));
rawSINR = double(sixgr.util.structGet(metrics, "SINR_dB", NaN));
rawSINRSource = string(sixgr.util.structGet(metrics, "SINRSource", ""));
rawSINRRole = string(sixgr.util.structGet(metrics, "SINRValueRole", ""));
rawSINRStatus = string(sixgr.util.structGet(metrics, "SINRValueStatus", ""));
rawSubbandSINR = localMetricVector(metrics, ["PerRBSINR_dB", "SubbandSINR_dB", "SubbandSINRVector_dB"]);
rawLayerSINR = localMetricVector(metrics, ["PostEqSINRPerLayer_dB", "PerLayerSINR_dB", "SelectedLayerSINR_dB", "LayerSINRdB"]);
if localSINRProvenanceBlockedForAMC(rawSINRSource, rawSINRRole, rawSINRStatus)
    rawSINR = NaN;
    rawSubbandSINR = [];
    rawLayerSINR = [];
    if strlength(strtrim(cqiSource)) == 0 || cqiSource == "unavailable"
        cqiSource = "sinr_input_rejected_non_scheduling_provenance";
    end
end
[agedSubbandSINR, subbandPenalty, subbandTrust] = localApplyVectorCSIAging( ...
    rawSubbandSINR, cfg, direction, metrics, "subband", cqiMeta.FeedbackAgingPenalty_dB);
[agedLayerSINR, layerPenalty, layerTrust] = localApplyVectorCSIAging( ...
    rawLayerSINR, cfg, direction, metrics, "layer", cqiMeta.FeedbackAgingPenalty_dB);
directionalBackoff_dB = double(cqiMeta.DirectionalSINRBackoff_dB);
if ~(isfinite(directionalBackoff_dB) && directionalBackoff_dB > 0)
    directionalBackoff_dB = 0;
end
if directionalBackoff_dB > 0
    if ~isempty(agedSubbandSINR)
        agedSubbandSINR = double(agedSubbandSINR) - directionalBackoff_dB;
        subbandPenalty = double(subbandPenalty) + directionalBackoff_dB;
    end
    if ~isempty(agedLayerSINR)
        agedLayerSINR = double(agedLayerSINR) - directionalBackoff_dB;
        layerPenalty = double(layerPenalty) + directionalBackoff_dB;
    end
end
if ~isempty(agedSubbandSINR)
    cqiMeta.AgedSubbandSINRVector_dB = localVectorToToken(agedSubbandSINR, "%.6g");
    cqiMeta.SubbandAgingPenaltyVector_dB = localVectorToToken(subbandPenalty, "%.6g");
    cqiMeta.CSIAgingModel = "per_subband_layer_jakes_measured_csi";
    if ~isempty(subbandTrust)
        cqiMeta.CSITemporalCorrelationWeight = min(double(cqiMeta.CSITemporalCorrelationWeight), min(double(subbandTrust), [], "omitnan"));
    end
end
if ~isempty(agedLayerSINR)
    cqiMeta.AgedLayerSINRVector_dB = localVectorToToken(agedLayerSINR, "%.6g");
    cqiMeta.LayerAgingPenaltyVector_dB = localVectorToToken(layerPenalty, "%.6g");
    cqiMeta.CSIAgingModel = "per_subband_layer_jakes_measured_csi";
    if ~isempty(layerTrust)
        cqiMeta.CSITemporalCorrelationWeight = min(double(cqiMeta.CSITemporalCorrelationWeight), min(double(layerTrust), [], "omitnan"));
    end
end
if isfinite(rawSINR)
    rawSINR = rawSINR - double(cqiMeta.TotalCQISINRBackoff_dB);
    cqiMeta.AgedSINR_dB = double(rawSINR);
elseif ~isempty(agedSubbandSINR)
    rawSINR = localMeanSINR_dB(agedSubbandSINR);
    cqiMeta.AgedSINR_dB = double(rawSINR);
    if strlength(strtrim(rawSINRSource)) == 0
        rawSINRSource = "aged_subband_measured_csi";
        rawSINRRole = "measured_post_equalization_scheduling_input";
        rawSINRStatus = "OK";
    end
elseif ~isempty(agedLayerSINR)
    rawSINR = localMeanSINR_dB(agedLayerSINR);
    cqiMeta.AgedSINR_dB = double(rawSINR);
    if strlength(strtrim(rawSINRSource)) == 0
        rawSINRSource = "aged_layer_measured_csi";
        rawSINRRole = "measured_post_equalization_scheduling_input";
        rawSINRStatus = "OK";
    end
end
if isfinite(rawCQI)
    % A delayed CQI is a quantized channel observation and must age by
    % default just like its underlying measured SINR.  Scenario masters can
    % explicitly disable this for independent fixed-SNR calibration points.
    if logical(sixgr.util.structGet(cfg, "phy.linkAdaptation.ageReportedCQI", true))
        rawCQI = localApplyCQIAging(rawCQI, cqiMeta.TotalCQISINRBackoff_dB, cfg);
    end
    cqiMeta.AgedCQI = double(rawCQI);
end
sinrInput = struct( ...
    "WidebandSINR_dB", rawSINR, ...
    "PerRBSINR_dB", double(agedSubbandSINR), ...
    "PostEqSINRPerLayer_dB", double(agedLayerSINR), ...
    "RankIndicator", double(sixgr.util.structGet(metrics, "RI", NaN)), ...
    "SINRSource", char(rawSINRSource), ...
    "SINRValueRole", char(rawSINRRole), ...
    "SINRValueStatus", char(rawSINRStatus));
preferMeasuredSINRForCQI = localUseAgedMeasuredSINRForCQI(cfg, direction) && isfinite(rawSINR);

switch string(adaptationDomain)
    case "effective_sinr"
        if isfinite(rawSINR)
            feedback = sixgr.link.resolveWidebandCQI(sinrInput, cfg, direction);
            instantCQI = double(sixgr.util.structGet(feedback, "WidebandCQI", NaN));
            cqiMeta = localApplyWidebandCQIMeta(cqiMeta, feedback);
            cqiSource = "runtime_effective_sinr";
            calibrationProfile = string(calibrationProfile) + ":" + string(sixgr.util.structGet(feedback, "Mode", ""));
        end
    case "bler_margin"
        if preferMeasuredSINRForCQI
            feedback = sixgr.link.resolveWidebandCQI(sinrInput, cfg, direction);
            instantCQI = double(sixgr.util.structGet(feedback, "WidebandCQI", NaN));
            cqiMeta = localApplyWidebandCQIMeta(cqiMeta, feedback);
            cqiSource = "runtime_aged_measured_sinr_cqi_for_bler_margin";
        elseif isfinite(rawCQI)
            instantCQI = rawCQI;
            cqiSource = "runtime_reported_cqi";
        elseif isfinite(rawSINR)
            feedback = sixgr.link.resolveWidebandCQI(sinrInput, cfg, direction);
            instantCQI = double(sixgr.util.structGet(feedback, "WidebandCQI", NaN));
            cqiMeta = localApplyWidebandCQIMeta(cqiMeta, feedback);
            cqiSource = "runtime_effective_sinr_proxy_for_bler_margin";
        end
    otherwise
        if preferMeasuredSINRForCQI
            feedback = sixgr.link.resolveWidebandCQI(sinrInput, cfg, direction);
            instantCQI = double(sixgr.util.structGet(feedback, "WidebandCQI", NaN));
            cqiMeta = localApplyWidebandCQIMeta(cqiMeta, feedback);
            cqiSource = "runtime_aged_measured_sinr_cqi";
            calibrationProfile = string(calibrationProfile) + ":" + string(sixgr.util.structGet(feedback, "Mode", ""));
        elseif isfinite(rawCQI)
            instantCQI = rawCQI;
            cqiSource = "runtime_reported_cqi";
        end
end
end

function tf = localSINRProvenanceBlockedForAMC(source, role, status)
token = lower(strjoin([string(source), string(role), string(status)], " "));
if strlength(strtrim(token)) == 0
    tf = false;
    return;
end
blocked = ["evm_proxy", "proxy", "fallback", "configured", "sweep", ...
    "oracle", "true_channel", "true-channel", ...
    "diagnostic", "not_scheduling", "unavailable", "failed", "rejected"];
tf = any(contains(token, blocked));
end

function profile = localResolveCalibrationProfile(cfg, direction, adaptationDomain)
targetBLER = localResolveTargetBLER(cfg, direction);
version = localCalibrationVersion(cfg, direction);
switch string(adaptationDomain)
    case "effective_sinr"
        feedbackMode = localResolveSINRToCQIMode(cfg, direction);
        profile = "calibrated_effective_sinr:" + feedbackMode + ":target_bler_" + localNumberToken(targetBLER) + ":" + version;
    case "bler_margin"
        profile = "calibrated_bler_margin_olla:target_bler_" + localNumberToken(targetBLER) + ":" + version;
    case "legacy_mcs"
        profile = "legacy_mcs_domain_smoothing";
    otherwise
        profile = "nr_cqi_table_amc:target_bler_" + localNumberToken(targetBLER) + ":" + version;
end
end

function meta = localCQIMetaDefaults(cfg, direction, metrics)
[usable, status, ageSlots, age_s, coherence_s, trustWeight, agingPenalty_dB] = ...
    localResolveCausalFeedbackFreshness(cfg, direction, metrics);
directionalBackoff_dB = localResolveDirectionalSINRBackoff(cfg, direction);
totalBackoff_dB = max(0, double(agingPenalty_dB)) + max(0, double(directionalBackoff_dB));
meta = struct( ...
    "CalibrationVersion", char(localCalibrationVersion(cfg, direction)), ...
    "BLERLUTSource", "", ...
    "BLERLUTValueRole", "", ...
    "BLERLUTCalibrationID", "", ...
    "TargetBLER", double(localResolveTargetBLER(cfg, direction)), ...
    "CausalFeedbackUsable", logical(usable), ...
    "CausalFeedbackStatus", char(status), ...
    "FeedbackAgeSlots", double(ageSlots), ...
    "FeedbackAgeSeconds", double(age_s), ...
    "CSICoherenceTimeSeconds", double(coherence_s), ...
    "CSITemporalCorrelationWeight", double(trustWeight), ...
    "FeedbackAgingPenalty_dB", double(agingPenalty_dB), ...
    "DirectionalSINRBackoff_dB", double(directionalBackoff_dB), ...
    "TotalCQISINRBackoff_dB", double(totalBackoff_dB), ...
    "AgedSINR_dB", NaN, ...
    "AgedCQI", NaN, ...
    "CSIAgingModel", "wideband_jakes_measured_csi", ...
    "AgedSubbandSINRVector_dB", "", ...
    "AgedLayerSINRVector_dB", "", ...
    "SubbandAgingPenaltyVector_dB", "", ...
    "LayerAgingPenaltyVector_dB", "", ...
    "CSIQuantizationBits", double(localCSIQuantizationBits(cfg, direction)));
end

function meta = localApplyWidebandCQIMeta(meta, feedback)
mode = lower(strtrim(string(sixgr.util.structGet(feedback, "Mode", ""))));
if mode ~= "effective_sinr_bler_target_lut"
    return;
end
source = string(sixgr.util.structGet(feedback, "BLERLUTSource", ""));
role = string(sixgr.util.structGet(feedback, "BLERLUTValueRole", ""));
calibrationID = string(sixgr.util.structGet(feedback, "BLERLUTCalibrationID", ""));
if strlength(strtrim(source)) > 0
    meta.BLERLUTSource = char(source);
end
if strlength(strtrim(role)) > 0
    meta.BLERLUTValueRole = char(role);
end
if strlength(strtrim(calibrationID)) > 0
    meta.BLERLUTCalibrationID = char(calibrationID);
    meta.CalibrationVersion = char(calibrationID);
end
end

function [usable, status, ageSlots, age_s, coherence_s, trustWeight, agingPenalty_dB] = localResolveCausalFeedbackFreshness(cfg, direction, metrics)
usable = true;
status = "OK";
ageSlots = double(sixgr.util.structGet(metrics, "CSIAgeSlots", ...
    sixgr.util.structGet(metrics, "FeedbackAgeSlots", NaN)));
age_s = double(sixgr.util.structGet(metrics, "CSIAgeSeconds", ...
    sixgr.util.structGet(metrics, "FeedbackAgeSeconds", NaN)));
if ~(isfinite(age_s) && age_s >= 0)
    slotDuration_s = localSlotDurationSeconds(cfg);
    if isfinite(ageSlots) && ageSlots >= 0 && isfinite(slotDuration_s) && slotDuration_s > 0
        age_s = double(ageSlots) * double(slotDuration_s);
    end
end
if ~(isfinite(ageSlots) && ageSlots >= 0) && isfinite(age_s) && age_s >= 0
    slotDuration_s = localSlotDurationSeconds(cfg);
    if isfinite(slotDuration_s) && slotDuration_s > 0
        ageSlots = double(age_s) / double(slotDuration_s);
    end
end

rawUsable = sixgr.util.structGet(metrics, "CausalFeedbackUsable", ...
    sixgr.util.structGet(metrics, "FeedbackUsable", ...
    sixgr.util.structGet(metrics, "CSICausalUsable", [])));
if ~isempty(rawUsable) && (islogical(rawUsable) || isnumeric(rawUsable)) && isscalar(rawUsable)
    usable = logical(rawUsable);
end
rawStatus = strtrim(string(sixgr.util.structGet(metrics, "CausalFeedbackStatus", ...
    sixgr.util.structGet(metrics, "FeedbackStatus", ""))));
if strlength(rawStatus) > 0
    status = rawStatus;
end

maxAgeSlots = localMaxCSIAgeSlots(cfg, direction);
if isfinite(maxAgeSlots) && isfinite(ageSlots) && ageSlots > maxAgeSlots
    usable = false;
    status = "stale_csi_age_exceeds_configured_limit";
elseif ~usable && status == "OK"
    status = "csi_marked_unusable_by_runtime";
end

dopplerHz = localFirstFiniteConfigValue(cfg, [ ...
    "channel.doppler_Hz"
    "channel.dopplerHz"
    "channel.fading.maxDoppler_Hz"
    "channels.doppler_hz"
    "frequency.doppler_hz"
    "phy.channel.doppler_Hz"], NaN);
coherence_s = NaN;
trustWeight = 1;
agingPenalty_dB = 0;
if isfinite(age_s) && age_s > 0 && isfinite(dopplerHz) && dopplerHz > 0
    coherence_s = 0.423 / max(double(dopplerHz), eps);
    trustWeight = abs(besselj(0, 2 * pi * double(dopplerHz) * double(age_s)));
    if ~(isfinite(trustWeight) && trustWeight >= 0)
        trustWeight = min(1, double(coherence_s) / max(double(age_s), eps));
    end
    trustWeight = min(1, max(0, double(trustWeight)));
    maxPenalty = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.maxCSIAgingPenalty_dB", 6));
    if ~(isfinite(maxPenalty) && maxPenalty >= 0)
        maxPenalty = 6;
    end
    minTrust = 10 ^ (-double(maxPenalty) / 20);
    agingPenalty_dB = -20 * log10(max(double(trustWeight), minTrust));
    agingPenalty_dB = min(double(maxPenalty), max(0, double(agingPenalty_dB)));
end
end

function maxAgeSlots = localMaxCSIAgeSlots(cfg, direction)
direction = upper(string(direction));
if direction == "UL"
    candidates = [ ...
        "phy.linkAdaptation.ulMaxCSIAgeSlots"
        "phy.linkAdaptation.maxCSIAgeSlots"
        "run.controlGating.srsMaxAgeSlots"];
else
    candidates = [ ...
        "phy.linkAdaptation.dlMaxCSIAgeSlots"
        "phy.linkAdaptation.maxCSIAgeSlots"
        "run.controlGating.csirsMaxAgeSlots"];
end
maxAgeSlots = localFirstFiniteConfigValue(cfg, candidates, inf);
if ~(isfinite(maxAgeSlots) && maxAgeSlots >= 0)
    maxAgeSlots = inf;
end
end

function backoff_dB = localResolveDirectionalSINRBackoff(cfg, direction)
direction = upper(string(direction));
if direction == "UL"
    candidates = [ ...
        "phy.linkAdaptation.ulMCSBackoff_dB"
        "phy.linkAdaptation.ulSINRBackoff_dB"
        "phy.linkAdaptation.mcsBackoffUL_dB"
        "phy.linkAdaptation.mcsBackoff_dB"
        "phy.linkAdaptation.sinrBackoff_dB"];
else
    candidates = [ ...
        "phy.linkAdaptation.dlMCSBackoff_dB"
        "phy.linkAdaptation.dlSINRBackoff_dB"
        "phy.linkAdaptation.mcsBackoffDL_dB"
        "phy.linkAdaptation.mcsBackoff_dB"
        "phy.linkAdaptation.sinrBackoff_dB"];
end
backoff_dB = localFirstFiniteConfigValue(cfg, candidates, 0);
if ~(isfinite(backoff_dB) && backoff_dB > 0)
    backoff_dB = 0;
end
end

function cqi = localApplyCQIAging(cqi, agingPenalty_dB, cfg)
cqi = double(sixgr.util.normalizeReportedCQI(cqi));
if ~(isfinite(cqi) && cqi >= 0)
    return;
end
penalty = double(agingPenalty_dB);
if ~(isfinite(penalty) && penalty > 0)
    return;
end
step_dB = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.cqiAgingStep_dB", 2));
if ~(isfinite(step_dB) && step_dB > 0)
    step_dB = 2;
end
cqi = max(0, min(15, cqi - ceil(penalty / step_dB)));
end

function tf = localUseAgedMeasuredSINRForCQI(cfg, direction)
direction = upper(string(direction));
if direction == "UL"
    candidates = [ ...
        "phy.pusch.useAgedMeasuredSINRForCQI"
        "phy.csi.ulUseAgedMeasuredSINRForCQI"
        "phy.linkAdaptation.ulUseAgedMeasuredSINRForCQI"
        "phy.linkAdaptation.useAgedMeasuredSINRForCQI"];
else
    candidates = [ ...
        "phy.pdsch.useAgedMeasuredSINRForCQI"
        "phy.csi.dlUseAgedMeasuredSINRForCQI"
        "phy.linkAdaptation.dlUseAgedMeasuredSINRForCQI"
        "phy.linkAdaptation.useAgedMeasuredSINRForCQI"];
end
tf = false;
for i = 1:numel(candidates)
    raw = sixgr.util.structGet(cfg, candidates(i), []);
    if isempty(raw)
        continue;
    end
    if ischar(raw) || isstring(raw)
        tf = any(lower(strtrim(string(raw))) == ["true", "1", "yes", "on"]);
    elseif isnumeric(raw) || islogical(raw)
        tf = logical(raw);
    end
    return;
end
end

function values = localMetricVector(metrics, candidates)
values = [];
if ~isstruct(metrics)
    return;
end
for i = 1:numel(candidates)
    raw = sixgr.util.structGet(metrics, candidates(i), []);
    values = localParseNumericVector(raw);
    if ~isempty(values)
        return;
    end
end
end

function values = localParseNumericVector(raw)
values = [];
if isempty(raw)
    return;
end
if isnumeric(raw) || islogical(raw)
    values = double(raw(:).');
elseif ischar(raw) || isstring(raw)
    text = strtrim(strjoin(string(raw(:).'), "|"));
    if strlength(text) == 0
        return;
    end
    parts = regexp(char(text), '[,;|\s]+', 'split');
    parts = parts(~cellfun(@isempty, parts));
    if isempty(parts)
        return;
    end
    values = str2double(string(parts));
else
    return;
end
values = double(values(:).');
values = values(isfinite(values));
end

function [aged, penalty, trustWeight] = localApplyVectorCSIAging(values, cfg, direction, metrics, domain, fallbackPenalty_dB)
aged = [];
penalty = [];
trustWeight = [];
values = double(values(:).');
values = values(isfinite(values));
if isempty(values)
    return;
end
n = numel(values);
age_s = localResolveAgingVector(metrics, domain, "seconds", n, NaN);
if isempty(age_s)
    age_s = repmat(double(sixgr.util.structGet(metrics, "CSIAgeSeconds", ...
        sixgr.util.structGet(metrics, "FeedbackAgeSeconds", NaN))), 1, n);
end
ageSlots = localResolveAgingVector(metrics, domain, "slots", n, NaN);
slotDuration_s = localSlotDurationSeconds(cfg);
if isempty(age_s) || any(~isfinite(age_s))
    if isempty(ageSlots)
        ageSlots = repmat(double(sixgr.util.structGet(metrics, "CSIAgeSlots", ...
            sixgr.util.structGet(metrics, "FeedbackAgeSlots", NaN))), 1, n);
    end
    if isfinite(slotDuration_s) && slotDuration_s > 0
        fillMask = ~isfinite(age_s);
        if isempty(age_s)
            fillMask = true(1, n);
            age_s = nan(1, n);
        end
        if numel(ageSlots) == n
            age_s(fillMask) = double(ageSlots(fillMask)) .* double(slotDuration_s);
        end
    end
end
if isempty(age_s)
    age_s = zeros(1, n);
end
age_s = localPadVector(age_s, n, 0);
age_s(~isfinite(age_s) | age_s < 0) = 0;

dopplerHz = localResolveAgingVector(metrics, domain, "doppler", n, NaN);
if isempty(dopplerHz)
    dopplerScalar = localFirstFiniteConfigValue(cfg, [ ...
        "channel.doppler_Hz"
        "channel.dopplerHz"
        "channel.fading.maxDoppler_Hz"
        "channels.doppler_hz"
        "frequency.doppler_hz"
        "phy.channel.doppler_Hz"], NaN);
    dopplerHz = repmat(double(dopplerScalar), 1, n);
end
dopplerHz = localPadVector(dopplerHz, n, NaN);

maxPenalty = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.maxCSIAgingPenalty_dB", 6));
if ~(isfinite(maxPenalty) && maxPenalty >= 0)
    maxPenalty = 6;
end
fallbackPenalty_dB = double(fallbackPenalty_dB);
if ~(isfinite(fallbackPenalty_dB) && fallbackPenalty_dB >= 0)
    fallbackPenalty_dB = 0;
end
penalty = repmat(fallbackPenalty_dB, 1, n);
trustWeight = ones(1, n);
for i = 1:n
    if isfinite(age_s(i)) && age_s(i) > 0 && isfinite(dopplerHz(i)) && dopplerHz(i) > 0
        try
            rho = abs(besselj(0, 2 * pi * double(dopplerHz(i)) * double(age_s(i))));
        catch
            coherence_s = 0.423 / max(double(dopplerHz(i)), eps);
            rho = min(1, double(coherence_s) / max(double(age_s(i)), eps));
        end
        if ~(isfinite(rho) && rho >= 0)
            rho = 1;
        end
        rho = min(1, max(0, double(rho)));
        minTrust = 10 ^ (-double(maxPenalty) / 20);
        penalty(i) = min(double(maxPenalty), max(0, -20 * log10(max(rho, minTrust))));
        trustWeight(i) = rho;
    end
end
aged = double(values) - double(penalty);
end

function values = localResolveAgingVector(metrics, domain, kind, n, defaultValue)
domain = lower(string(domain));
kind = lower(string(kind));
switch kind
    case "seconds"
        if domain == "subband"
            candidates = ["SubbandCSIAgeSeconds", "SubbandAgeSeconds", "PerSubbandCSIAgeSeconds", "PerRBAgeSeconds"];
        else
            candidates = ["LayerCSIAgeSeconds", "LayerAgeSeconds", "PerLayerCSIAgeSeconds"];
        end
    case "slots"
        if domain == "subband"
            candidates = ["SubbandCSIAgeSlots", "SubbandAgeSlots", "PerSubbandCSIAgeSlots", "PerRBAgeSlots"];
        else
            candidates = ["LayerCSIAgeSlots", "LayerAgeSlots", "PerLayerCSIAgeSlots"];
        end
    otherwise
        if domain == "subband"
            candidates = ["SubbandDopplerHz", "SubbandDoppler_Hz", "PerSubbandDopplerHz", "PerRBDopplerHz"];
        else
            candidates = ["LayerDopplerHz", "LayerDoppler_Hz", "PerLayerDopplerHz"];
        end
end
values = localMetricVector(metrics, candidates);
if isempty(values)
    raw = defaultValue;
    if isfinite(double(raw))
        values = repmat(double(raw), 1, n);
    end
    return;
end
values = localPadVector(values, n, NaN);
end

function values = localPadVector(values, n, fillValue)
values = double(values(:).');
if numel(values) == n
    return;
end
if isempty(values)
    values = repmat(double(fillValue), 1, n);
elseif numel(values) == 1
    values = repmat(double(values), 1, n);
elseif numel(values) > n
    values = values(1:n);
else
    values = [values repmat(double(fillValue), 1, n - numel(values))];
end
end

function value = localMeanSINR_dB(values)
values = double(values(:));
values = values(isfinite(values));
if isempty(values)
    value = NaN;
    return;
end
value = 10 * log10(max(mean(10 .^ (values / 10), "omitnan"), eps));
end

function token = localVectorToToken(values, fmt)
values = double(values(:).');
if nargin < 2 || strlength(string(fmt)) == 0
    fmt = "%.6g";
end
parts = strings(1, numel(values));
for i = 1:numel(values)
    if isfinite(values(i))
        parts(i) = string(sprintf(char(fmt), values(i)));
    else
        parts(i) = "NaN";
    end
end
token = strjoin(parts, "|");
end

function bits = localCSIQuantizationBits(cfg, direction)
direction = upper(string(direction));
if direction == "UL"
    bits = double(sixgr.util.structGet(cfg, "phy.csi.ulCQIQuantizationBits", ...
        sixgr.util.structGet(cfg, "phy.csi.cqiQuantizationBits", 4)));
else
    bits = double(sixgr.util.structGet(cfg, "phy.csi.dlCQIQuantizationBits", ...
        sixgr.util.structGet(cfg, "phy.csi.cqiQuantizationBits", 4)));
end
if ~(isfinite(bits) && bits >= 1)
    bits = 4;
end
bits = round(bits);
end

function targetBLER = localResolveTargetBLER(cfg, direction)
direction = upper(string(direction));
if direction == "UL"
    targetBLER = double(sixgr.util.structGet(cfg, "phy.pusch.targetBLER", ...
        sixgr.util.structGet(cfg, "phy.csi.targetBLER", ...
        sixgr.util.structGet(cfg, "phy.linkAdaptation.targetBLER", 0.1))));
else
    targetBLER = double(sixgr.util.structGet(cfg, "phy.pdsch.targetBLER", ...
        sixgr.util.structGet(cfg, "phy.csi.targetBLER", ...
        sixgr.util.structGet(cfg, "phy.linkAdaptation.targetBLER", 0.1))));
end
if ~(isfinite(targetBLER) && targetBLER > 0 && targetBLER < 1)
    targetBLER = 0.1;
end
end

function version = localCalibrationVersion(cfg, direction)
direction = upper(string(direction));
if direction == "UL"
    version = string(sixgr.util.structGet(cfg, "phy.linkAdaptation.ulCalibrationVersion", ...
        sixgr.util.structGet(cfg, "phy.linkAdaptation.calibrationVersion", "")));
else
    version = string(sixgr.util.structGet(cfg, "phy.linkAdaptation.dlCalibrationVersion", ...
        sixgr.util.structGet(cfg, "phy.linkAdaptation.calibrationVersion", "")));
end
version = strtrim(version);
if strlength(version) == 0
    version = "nr_cqi_mcs_table_v1";
end
end

function token = localNumberToken(value)
token = regexprep(string(sprintf("%.3g", double(value))), "[^0-9A-Za-z]+", "p");
end

function token = localResolveSINRToCQIMode(cfg, direction)
direction = upper(string(direction));
if direction == "UL"
    candidates = [ ...
        "phy.pusch.sinrToCQIMode"
        "phy.csi.ulSINRToCQIMode"
        "phy.csi.sinrToCQIMode"];
else
    candidates = [ ...
        "phy.pdsch.sinrToCQIMode"
        "phy.csi.dlSINRToCQIMode"
        "phy.csi.sinrToCQIMode"];
end
token = "";
for i = 1:numel(candidates)
    token = lower(strtrim(string(sixgr.util.structGet(cfg, candidates(i), ""))));
    if strlength(token) > 0
        return;
    end
end
token = "threshold_table";
end

function source = localResolveMCSSelectionSource(adaptationDomain)
switch string(adaptationDomain)
    case "effective_sinr"
        source = "effective_sinr_to_cqi_to_amc";
    case "bler_margin"
        source = "bler_margin_proxy_to_amc";
    case "legacy_mcs"
        source = "legacy_mcs_domain_smoothing";
    otherwise
        source = "runtime_cqi_to_amc";
end
end

function domain = localResolveOLLADomain(adaptationDomain, outerLoopEnabled)
if ~logical(outerLoopEnabled)
    domain = "disabled";
    return;
end
switch string(adaptationDomain)
    case "bler_margin"
        domain = "bler_margin_proxy_delta_db";
    case "legacy_mcs"
        domain = "delta_db_required_sinr_margin";
    otherwise
        domain = "delta_db_required_sinr_margin";
end
end

function [ackKnown, ackObserved, source] = localResolveAckOutcome(metrics)
ackKnown = false;
ackObserved = false;
source = "";
candidates = { ...
    "AckObserved"
    "ObservedAck"
    "CombinedDecodeOK"
    "CurrentDecodeOK"
    "CRCPass"};
for i = 1:numel(candidates)
    raw = sixgr.util.structGet(metrics, candidates{i}, []);
    if isempty(raw)
        continue;
    end
    if isnumeric(raw) || islogical(raw)
        if isscalar(raw) && isfinite(double(raw))
            ackKnown = true;
            ackObserved = logical(raw);
            source = candidates{i};
            return;
        end
    end
end
end

function [resetState, resetReason] = localShouldResetState(adaptationState, metrics, cfg)
resetState = false;
resetReason = "";
if ~adaptationState.Initialized
    return;
end

ri = double(sixgr.util.structGet(metrics, "RI", NaN));
if logical(adaptationState.ResetOnRIChange) && isfinite(ri) && isfinite(adaptationState.LastRI) && round(ri) ~= round(adaptationState.LastRI)
    resetState = true;
    resetReason = "ri_change";
    return;
end
end

function tf = localPolicyEnabled(token)
token = lower(string(token));
tf = ~(token == "" || ismember(token, ["disabled","none","off","false","fixed"]));
end

function path = localPolicyPath(direction)
if direction == "DL"
    path = "phy.linkAdaptation.dlPolicy";
else
    path = "phy.linkAdaptation.ulPolicy";
end
end

function base = localBaseState(cfg, direction)
if direction == "DL"
    base.Modulation = char(string(sixgr.util.structGet(cfg, "phy.pdsch.modulation", "QPSK")));
    base.TargetCodeRate = double(sixgr.util.structGet(cfg, "phy.pdsch.codeRate", 0.5));
    base.NumLayers = max(1, round(double(sixgr.util.structGet(cfg, "phy.pdsch.numLayers", ...
        sixgr.util.structGet(cfg, "phy.pdsch.nLayers", 1)))));
    configuredMCS = localFiniteScalar(sixgr.util.structGet(cfg, "phy.pdsch.mcsIndex", NaN), NaN);
    if isfinite(configuredMCS)
        base.MCSIndex = double(configuredMCS);
    else
        decision = sixgr.link.resolveMCSIndexFromProfile(base.Modulation, base.TargetCodeRate, ...
            "MCSTable", sixgr.link.resolveConfiguredMCSTable(cfg, "DL"));
        base.MCSIndex = double(decision.MCSIndex);
    end
else
    base.Modulation = char(string(sixgr.util.structGet(cfg, "phy.pusch.modulation", "QPSK")));
    base.TargetCodeRate = double(sixgr.util.structGet(cfg, "phy.pusch.codeRate", 0.5));
    base.NumLayers = max(1, round(double(sixgr.util.structGet(cfg, "phy.pusch.numLayers", ...
        sixgr.util.structGet(cfg, "phy.pusch.nLayers", 1)))));
    configuredMCS = localFiniteScalar(sixgr.util.structGet(cfg, "phy.pusch.mcsIndex", NaN), NaN);
    if isfinite(configuredMCS)
        base.MCSIndex = double(configuredMCS);
    else
        decision = sixgr.link.resolveMCSIndexFromProfile(base.Modulation, base.TargetCodeRate, ...
            "MCSTable", sixgr.link.resolveConfiguredMCSTable(cfg, "UL"));
        base.MCSIndex = double(decision.MCSIndex);
    end
end
end

function value = localFiniteScalar(raw, defaultValue)
value = defaultValue;
try
    candidate = double(raw);
    if isscalar(candidate) && isfinite(candidate)
        value = candidate;
    end
catch
end
end

function maxLayers = localMaxLayers(cfg, direction)
if direction == "DL"
    maxLayers = double(sixgr.util.structGet(cfg, "phy.pdsch.maxLayers", ...
        sixgr.util.structGet(cfg, "phy.maxDLLayers", ...
        sixgr.util.structGet(cfg, "phy.pdsch.numLayers", ...
        sixgr.util.structGet(cfg, "phy.pdsch.nLayers", ...
        sixgr.util.structGet(cfg, "phy.nTxAnt", 1))))));
else
    maxLayers = double(sixgr.util.structGet(cfg, "phy.pusch.maxLayers", ...
        sixgr.util.structGet(cfg, "phy.maxULLayers", ...
        sixgr.util.structGet(cfg, "phy.pusch.numLayers", ...
        sixgr.util.structGet(cfg, "phy.pusch.nLayers", ...
        sixgr.util.structGet(cfg, "phy.nTxAnt", 1))))));
end

maxLayers = max(1, round(maxLayers));
end

function [authorized, eventType, authoritySource] = localResolveOLLAUpdateAuthority(metrics, ackKnown)
% OLLA is driven only by a causal HARQ ACK/NACK delivery event.  CSI
% measurement rows can legitimately carry colocated decoder fields, but
% those fields are not HARQ feedback and must not move the outer loop.
eventType = lower(strtrim(string(sixgr.util.structGet( ...
    metrics, "FeedbackEventType", "legacy_unspecified"))));
rawAuthority = sixgr.util.structGet(metrics, "AllowOLLAUpdate", []);
if ~isempty(rawAuthority)
    if ~(isscalar(rawAuthority) && (islogical(rawAuthority) || ...
            (isnumeric(rawAuthority) && isfinite(double(rawAuthority)))))
        error("sixgr:link:LinkAdaptation:InvalidOLLAUpdateAuthority", ...
            "AllowOLLAUpdate must be a finite scalar logical/numeric value.");
    end
    authorized = logical(rawAuthority) && logical(ackKnown);
    authoritySource = "metrics.AllowOLLAUpdate";
    return;
end
if eventType ~= "legacy_unspecified"
    authorizedEventTypes = ["harq_feedback", "harq_ack_nack_delivery", ...
        "pucch_harq_feedback", "pusch_uci_harq_feedback"];
    authorized = logical(ackKnown) && any(eventType == authorizedEventTypes);
    authoritySource = "metrics.FeedbackEventType";
    return;
end
% Compatibility for direct component callers that predate the explicit
% event contract. Production coupled runtime always supplies authority.
authorized = logical(ackKnown);
authoritySource = "legacy_ack_field_compatibility";
end

function cqiBasedMCS = localSmoothCQIBasedMCS(previousCQIBasedMCS, instantMCS, alpha)
alpha = min(max(double(alpha), 0), 1);
newWeightPct = alpha * 100;
oldWeightPct = 100 - newWeightPct;
% Radisys-style inner loop keeps hundredth-MCS precision before the final
% floor to the integer MCS used by the grant.
cqiBasedMCS = ceil((newWeightPct * double(instantMCS) * 100 + ...
    oldWeightPct * double(previousCQIBasedMCS) * 100) / 100) / 100;
end

function [effectiveAlpha, trustWeight, age_s, coherence_s] = localEffectiveCQISmoothingAlpha(baseAlpha, cfg, metrics)
baseAlpha = min(max(double(baseAlpha), 0), 1);
effectiveAlpha = baseAlpha;
trustWeight = 1;
age_s = double(sixgr.util.structGet(metrics, "CSIAgeSeconds", NaN));
if ~(isfinite(age_s) && age_s >= 0)
    ageSlots = double(sixgr.util.structGet(metrics, "CSIAgeSlots", NaN));
    slotDuration_s = localSlotDurationSeconds(cfg);
    if isfinite(ageSlots) && ageSlots >= 0 && isfinite(slotDuration_s) && slotDuration_s > 0
        age_s = double(ageSlots) * double(slotDuration_s);
    end
end
dopplerHz = localFirstFiniteConfigValue(cfg, [ ...
    "channel.doppler_Hz"
    "channel.dopplerHz"
    "channel.fading.maxDoppler_Hz"
    "channels.doppler_hz"
    "frequency.doppler_hz"
    "phy.channel.doppler_Hz"], NaN);
coherence_s = NaN;
if ~(isfinite(age_s) && age_s > 0 && isfinite(dopplerHz) && dopplerHz > 0)
    return;
end
coherence_s = 0.423 / max(double(dopplerHz), eps);
% Clarke/Jakes temporal autocorrelation for isotropic Rayleigh fading.
% Low temporal correlation means the previous smoothed CQI/MCS state is
% stale, so the update must move faster toward the newest measurement.
try
    trustWeight = abs(besselj(0, 2 * pi * double(dopplerHz) * double(age_s)));
catch
    trustWeight = min(1, double(coherence_s) / max(double(age_s), eps));
end
if ~(isfinite(trustWeight) && trustWeight >= 0)
    trustWeight = 1;
end
trustWeight = min(1, max(0, double(trustWeight)));
effectiveAlpha = baseAlpha + (1 - baseAlpha) * (1 - trustWeight);
effectiveAlpha = min(1, max(baseAlpha, double(effectiveAlpha)));
end

function slotDuration_s = localSlotDurationSeconds(cfg)
scsKHz = localFirstFiniteConfigValue(cfg, [ ...
    "phy.carrier.SubcarrierSpacing"
    "phy.carrier.SubcarrierSpacing_kHz"
    "phy.numerology.scs_kHz"
    "frame.scs_khz"], NaN);
if isfinite(scsKHz)
    numerology = sixgr.phy.frame.NumerologyCatalog.resolve( ...
        scsKHz, "normal", "generic_waveform_test", "");
    slotDuration_s = double(numerology.SlotDurationSeconds);
    return;
end
slotDuration_s = localFirstFiniteConfigValue(cfg, [ ...
    "phy.numerology.slotDuration_s"
    "phy.numerology.slotDurationSeconds"
    "frame_timing.slot_duration_s"], NaN);
if isfinite(slotDuration_s) && slotDuration_s > 0
    return;
end
slotDuration_ms = localFirstFiniteConfigValue(cfg, [ ...
    "phy.numerology.slotDuration_ms"
    "frame_timing.slot_duration_ms"], NaN);
if isfinite(slotDuration_ms) && slotDuration_ms > 0
    slotDuration_s = double(slotDuration_ms) * 1e-3;
    return;
end
slotDuration_s = NaN;
end

function threshold = localMCSJumpThreshold(cfg)
threshold = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.mcsJumpResetThreshold", ...
    sixgr.util.structGet(cfg, "phy.linkAdaptation.cqiJumpResetThreshold", 5)));
if ~(isfinite(threshold) && threshold >= 0)
    threshold = 5;
end
end

function maxMCS = localMaxValidMCS(mcsTable)
maxMCS = 0;
for idx = 0:31
    profile = sixgr.link.resolveMCSProfile(mcsTable, idx);
    if logical(sixgr.util.structGet(profile, "Valid", false))
        maxMCS = idx;
    end
end
end

function adaptationState = localInitAdaptationState(cfg, direction, previousState)
[cqiSmoothingAlpha, cqiSmoothingAlphaSource] = localResolveCQISmoothingAlpha(cfg);
olla = sixgr.link.resolveOLLAConfig(cfg);
adaptationState = struct( ...
    "Direction", char(direction), ...
    "LinkAdaptationDomain", char(sixgr.link.resolveLinkAdaptationDomain(cfg, direction)), ...
    "Initialized", false, ...
    "InnerLoopEnabled", logical(sixgr.util.structGet(cfg, "phy.linkAdaptation.innerLoopFlag", false)), ...
    "OuterLoopEnabled", logical(olla.Enabled), ...
    "CQISmoothingAlpha", double(cqiSmoothingAlpha), ...
    "CQISmoothingAlphaSource", char(cqiSmoothingAlphaSource), ...
    "SmoothedCQI", NaN, ...
    "CQIBasedMCS", NaN, ...
    "DeltaMCS", 0, ...
    "StaticDeltaMCS", localResolveStaticDeltaMCS(cfg), ...
    "OLLAStepUp", double(olla.StepUpDb), ...
    "OLLAStepDown", double(olla.StepDownDb), ...
    "DeltaMCSMin", double(olla.MinimumOffsetDb), ...
    "DeltaMCSMax", double(olla.MaximumOffsetDb), ...
    "OLLAStateAuthority", char(olla.StateAuthority), ...
    "ResetOnRIChange", logical(sixgr.util.structGet(cfg, "phy.linkAdaptation.resetOnRIChange", false)), ...
    "CQIJumpResetThreshold", localResolveCQIJumpResetThreshold(cfg), ...
    "CQIObservationCount", 0, ...
    "CQIOutageObservationCount", 0, ...
    "LastCQIOutOfRange", false, ...
    "CQIOutageRecoveryPositiveCount", 0, ...
    "CQIOutageRecoveryRequiredCount", localPositiveIntegerConfig( ...
        cfg, "phy.linkAdaptation.outageRecoveryPositiveCQIReports", 1), ...
    "CQIOutageRecoveryCandidate", NaN, ...
    "CQIOutageRecoveryCQITolerance", localNonnegativeIntegerConfig( ...
        cfg, "phy.linkAdaptation.outageRecoveryCQITolerance", 0), ...
    "CQIOutageRecoveryMaxGapSlots", localPositiveIntegerOrInfConfig( ...
        cfg, "phy.linkAdaptation.outageRecoveryMaxGapSlots", Inf), ...
    "LastCQIFeedbackAbsoluteSlot", NaN, ...
    "LastCQI", NaN, ...
    "LastRI", NaN, ...
    "RankIncreaseCandidate", NaN, ...
    "RankIncreaseConfirmationCount", 0, ...
    "RankIncreaseRequiredCount", localPositiveIntegerConfig( ...
        cfg, "phy.linkAdaptation.rankIncreaseConfirmationReports", 1), ...
    "LastMCSIndex", NaN, ...
    "LastInstantaneousMCS", NaN, ...
    "LastInstantaneousModulation", "", ...
    "LastInstantaneousTargetCodeRate", NaN, ...
    "LastObservedAck", false, ...
    "OLLAUpdateCount", 0, ...
    "LastResetReason", "", ...
    "UpdateCount", 0);

if isempty(previousState) || ~isstruct(previousState)
    return;
end
prevFields = fieldnames(previousState);
for i = 1:numel(prevFields)
    adaptationState.(prevFields{i}) = previousState.(prevFields{i});
end
% Configuration remains authoritative if a long-lived state object crosses
% a scenario or configuration epoch.
adaptationState.CQIOutageRecoveryRequiredCount = localPositiveIntegerConfig( ...
    cfg, "phy.linkAdaptation.outageRecoveryPositiveCQIReports", 1);
adaptationState.CQIOutageRecoveryCQITolerance = localNonnegativeIntegerConfig( ...
    cfg, "phy.linkAdaptation.outageRecoveryCQITolerance", 0);
adaptationState.CQIOutageRecoveryMaxGapSlots = localPositiveIntegerOrInfConfig( ...
    cfg, "phy.linkAdaptation.outageRecoveryMaxGapSlots", Inf);
adaptationState.RankIncreaseRequiredCount = localPositiveIntegerConfig( ...
    cfg, "phy.linkAdaptation.rankIncreaseConfirmationReports", 1);
end

function value = localPositiveIntegerConfig(cfg, path, defaultValue)
raw = double(sixgr.util.structGet(cfg, path, defaultValue));
if ~(isscalar(raw) && isfinite(raw) && raw >= 1 && raw == fix(raw))
    error("sixgr:link:LinkAdaptation:InvalidConfirmationCount", ...
        "%s must be a positive integer; got %s.", char(path), mat2str(raw));
end
value = double(raw);
end

function value = localNonnegativeIntegerConfig(cfg, path, defaultValue)
raw = double(sixgr.util.structGet(cfg, path, defaultValue));
if ~(isscalar(raw) && isfinite(raw) && raw >= 0 && raw == fix(raw))
    error("sixgr:link:LinkAdaptation:InvalidCQITolerance", ...
        "%s must be a nonnegative integer; got %s.", char(path), mat2str(raw));
end
value = double(raw);
end

function value = localPositiveIntegerOrInfConfig(cfg, path, defaultValue)
raw = double(sixgr.util.structGet(cfg, path, defaultValue));
if ~(isscalar(raw) && ((isfinite(raw) && raw >= 1 && raw == fix(raw)) || isinf(raw)))
    error("sixgr:link:LinkAdaptation:InvalidFeedbackGap", ...
        "%s must be a positive integer or Inf; got %s.", char(path), mat2str(raw));
end
value = double(raw);
end

function [alpha, source] = localResolveCQISmoothingAlpha(cfg)
mode = lower(strtrim(string(sixgr.util.structGet(cfg, "phy.linkAdaptation.cqiSmoothingMode", ...
    sixgr.util.structGet(cfg, "link_adaptation.cqi_smoothing_mode", "")))));
if mode == "doppler_adaptive"
    [alpha, source] = localDopplerAdaptiveCQISmoothingAlpha(cfg);
    return;
end

alpha = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.cqiSmoothingAlpha", NaN));
if isfinite(alpha) && alpha >= 0 && alpha <= 1
    source = "configured_fixed_alpha";
    return;
end

[alpha, source] = localDopplerAdaptiveCQISmoothingAlpha(cfg);
if source ~= "doppler_unavailable_default_alpha"
    return;
end
alpha = 0.2;
source = "default_fixed_alpha";
end

function [alpha, source] = localDopplerAdaptiveCQISmoothingAlpha(cfg)
dopplerHz = localFirstFiniteConfigValue(cfg, [ ...
    "channel.doppler_Hz"
    "channel.dopplerHz"
    "channel.fading.maxDoppler_Hz"
    "phy.channel.doppler_Hz"], NaN);
slotDuration_s = localSlotDurationSeconds(cfg);
if ~(isfinite(dopplerHz) && dopplerHz >= 0 && isfinite(slotDuration_s) && slotDuration_s > 0)
    alpha = 0.2;
    source = "doppler_unavailable_default_alpha";
    return;
end
if dopplerHz == 0
    alpha = 0.05;
    source = "doppler_adaptive_zero_doppler_floor";
    return;
end
coherenceTime_s = 0.423 / max(double(dopplerHz), eps);
alpha = 1 - exp(-double(slotDuration_s) / max(coherenceTime_s, eps));
alpha = min(0.85, max(0.05, double(alpha)));
source = "doppler_adaptive_coherence_time";
end

function value = localFirstFiniteConfigValue(cfg, paths, defaultValue)
value = defaultValue;
for i = 1:numel(paths)
    raw = sixgr.util.structGet(cfg, paths(i), []);
    if isempty(raw)
        continue;
    end
    try
        candidate = double(raw);
    catch
        continue;
    end
    candidate = candidate(isfinite(candidate));
    if ~isempty(candidate)
        value = double(candidate(1));
        return;
    end
end
end

function delta = localResolveStaticDeltaMCS(cfg)
delta = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.deltaMCSOffset", 0));
if ~(isfinite(delta))
    delta = 0;
end
end

function threshold = localResolveCQIJumpResetThreshold(cfg)
threshold = double(sixgr.util.structGet(cfg, "phy.linkAdaptation.cqiJumpResetThreshold", 4));
if ~(isfinite(threshold) && threshold >= 1)
    threshold = 4;
end
end

function tf = localMCSJumpResetEnabled(cfg)
tf = logical(sixgr.util.structGet(cfg, "phy.linkAdaptation.resetOnMCSJump", false));
end

function tf = localHasStaleExplicitPDSCHMatrix(cfg, requestedLayers)
tf = false;
requestedLayers = max(1, round(double(requestedLayers)));
paths = ["phy.pdsch.precoding.matrix", "phy.pdsch.precodingMatrix", "phy.pdsch.W"];
for i = 1:numel(paths)
    W = sixgr.util.structGet(cfg, paths(i), []);
    if isempty(W)
        continue;
    end
    sz = size(W);
    if numel(sz) > 2 && all(sz(3:end) == 1)
        W = reshape(W, sz(1), sz(2));
    end
    if ~isnumeric(W) || ~ismatrix(W)
        tf = true;
        return;
    end
    sz = size(W);
    layerCompatible = ...
        (sz(2) == requestedLayers && sz(1) >= requestedLayers) || ...
        (sz(1) == requestedLayers && sz(2) >= requestedLayers);
    if ~layerCompatible
        tf = true;
        return;
    end
end
end
