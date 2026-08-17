function T = applyMeasuredDLMUMIMOReceiverEvidence(T)
%APPLYMEASUREDDLMUMIMORECEIVEREVIDENCE Bind DL MU processing to Rx evidence.
% A PDSCH receiver performs the DL MU suppression inside its joint,
% resource-selective MMSE-IRC equalizer.  That is not a separate frozen
% receive-combiner matrix.  This adapter records the applied receiver
% processing only when the persisted PDSCH_Rx measurements prove that the
% shared-slot interference covariance and IRC equalizer were actually used.
% It never promotes configured grant intent into runtime evidence.

if ~(istable(T) && ~isempty(T))
    return;
end

n = height(T);
T = localLogicalColumn(T, "MUMIMOReceiveProcessingApplied", false(n, 1));
T = localTextColumn(T, "MUMIMOReceiveProcessingStatus", strings(n, 1));
T = localTextColumn(T, "MUMIMOReceiveProcessingSource", strings(n, 1));
T = localTextColumn(T, "MUMIMOReceiveProcessingModeApplied", strings(n, 1));
T = localTextColumn(T, "MUMIMOReceiverAlgorithmApplied", strings(n, 1));
T = localLogicalColumn(T, "MUMIMOReceiveCombinerApplied", false(n, 1));
T = localTextColumn(T, "MUMIMOReceiveCombinerStatus", strings(n, 1));
T = localTextColumn(T, "MUMIMOReceiveCombinerSource", strings(n, 1));

direction = upper(strtrim(localText(T, "Direction", n)));
muEnabled = localLogical(T, "MUMIMOEnabled", n);
dlRows = direction == "DL";
notApplicable = dlRows & ~muEnabled;
T.MUMIMOReceiveProcessingApplied(notApplicable) = false;
T.MUMIMOReceiveProcessingStatus(notApplicable) = "not_applicable_mu_mimo_disabled";
T.MUMIMOReceiveProcessingSource(notApplicable) = "not_applicable";
T.MUMIMOReceiveProcessingModeApplied(notApplicable) = "not_applicable";
T.MUMIMOReceiverAlgorithmApplied(notApplicable) = "not_applicable";

required = dlRows & muEnabled;
if ~any(required)
    return;
end

covarianceAvailable = localLogical(T, "InterferenceCovarianceAvailable", n);
equalizationAvailable = localLogical(T, "EqualizationAvailable", n);
fullInterfererTruth = localLogical(T, "FullInterfererChannelTruthUsed", n);
contributors = localNumeric(T, "InterferenceContributorCount", n);
equalizerType = upper(strtrim(localText(T, "EqualizerType", n)));
equalizerEngine = strtrim(localText(T, "EqualizerEngine", n));
covarianceSource = lower(strtrim(localText(T, "InterferenceCovarianceSource", n)));

valid = covarianceAvailable & equalizationAvailable & fullInterfererTruth & ...
    contributors >= 1 & contains(equalizerType, "IRC") & ...
    strlength(equalizerEngine) > 0 & ...
    covarianceSource == "shared_slot_contribution_grid_covariance";
invalid = required & ~valid;
if any(invalid)
    rows = find(invalid);
    error("sixgr:link:MissingMeasuredDLMUMIMOReceiverEvidence", ...
        "DL MU-MIMO rows %s do not prove shared-slot covariance-backed per-RE MMSE-IRC receiver execution.", ...
        mat2str(rows(:).'));
end

T.MUMIMOReceiveProcessingApplied(required) = true;
T.MUMIMOReceiveProcessingStatus(required) = ...
    "applied_shared_slot_covariance_resource_selective_per_re_mmse_irc";
T.MUMIMOReceiveProcessingSource(required) = ...
    "sixgr.phy.dl.PDSCH_Rx.EqualizationInfo";
T.MUMIMOReceiveProcessingModeApplied(required) = ...
    "resource_selective_per_re_mmse_irc";
T.MUMIMOReceiverAlgorithmApplied(required) = "MMSE-IRC";

% Preserve the semantic distinction: the DL implementation did not apply a
% separate receive-combiner matrix before the joint equalizer.
noSeparateCombiner = required & ~logical(T.MUMIMOReceiveCombinerApplied);
T.MUMIMOReceiveCombinerStatus(noSeparateCombiner) = ...
    "not_applicable_joint_per_re_mmse_irc_equalizer_no_separate_combiner";
T.MUMIMOReceiveCombinerSource(noSeparateCombiner) = ...
    "not_applicable_receiver_joint_equalizer_path";
end

function T = localLogicalColumn(T, name, defaultValue)
if ~ismember(name, string(T.Properties.VariableNames))
    T.(char(name)) = logical(defaultValue);
else
    T.(char(name)) = logical(T.(char(name)));
end
end

function T = localTextColumn(T, name, defaultValue)
if ~ismember(name, string(T.Properties.VariableNames))
    T.(char(name)) = string(defaultValue);
else
    T.(char(name)) = string(T.(char(name)));
end
end

function values = localText(T, name, n)
if ismember(name, string(T.Properties.VariableNames))
    values = string(T.(char(name)));
else
    values = strings(n, 1);
end
end

function values = localLogical(T, name, n)
if ismember(name, string(T.Properties.VariableNames))
    values = logical(T.(char(name)));
else
    values = false(n, 1);
end
end

function values = localNumeric(T, name, n)
if ismember(name, string(T.Properties.VariableNames))
    values = double(T.(char(name)));
else
    values = nan(n, 1);
end
end
