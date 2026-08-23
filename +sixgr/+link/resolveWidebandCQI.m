function feedback = resolveWidebandCQI(sinrInput, cfg, direction)
%RESOLVEWIDEBANDCQI Resolve wideband or per-RB SINR into NR CQI feedback.
%
% This helper is structured so callers can pass the same wideband SINR used
% by the simulator today, while allowing a future per-RB SINR array to slot
% into the same API without redesigning the feedback contract.
%
% Important honesty note:
% 3GPP TS 38.214 specifies the CQI and MCS tables, but not a single
% normative SINR-to-CQI threshold table. This helper therefore keeps the
% threshold-table path as the default lab baseline and exposes the
% effective-SINR plus 10% BLER operating-point LUT path only when it is
% explicitly requested in config:
%   per-RB SINR -> effective SINR (EESM/MIESM lab default) ->
%   CQI operating-point BLER estimate -> highest CQI meeting target BLER.
% This avoids silently changing canonical scenario behavior to an
% uncalibrated BLER-LUT mode just because per-RB SINR samples are present.

if nargin < 2 || isempty(cfg)
    cfg = struct();
end
if nargin < 3 || isempty(direction)
    direction = "DL";
end

tableToken = localResolveCQITable(cfg, direction);
margin_dB = double(sixgr.util.structGet(cfg, "phy.csi.widebandSINRMargin_dB", 0));
if ~isfinite(margin_dB)
    margin_dB = 0;
end

[widebandSINR_dB, perRBSINR_dB, rankIndicator, perLayerSINR_dB] = localExtractSINRInputs(sinrInput);
[sinrInputAccepted, sinrInputRejectionReason, sinrInputSource, sinrInputRole, sinrInputStatus] = ...
    localValidateSINRInputProvenance(sinrInput);
if ~sinrInputAccepted
    widebandSINR_dB = NaN;
    perRBSINR_dB = [];
end
modeToken = localResolveCQIMode(cfg, direction, ~isempty(perRBSINR_dB));
targetBLER = localResolveTargetBLER(cfg, direction);
[thresholds_dB, thresholdInfo] = sixgr.link.cqiRequiredSINRTable(tableToken, cfg, direction, ...
    "TargetBLER", targetBLER);
thresholdSource = string(sixgr.util.structGet(thresholdInfo, "Source", ""));
thresholdRole = string(sixgr.util.structGet(thresholdInfo, "ValueRole", ""));
if modeToken == "effective_sinr_bler_lut" && ...
        ~localConfiguredBLERLUTAvailable(cfg, direction, tableToken, targetBLER) && ...
        ~localAllowUncalibratedBLERLUT(cfg, direction)
    error("sixgr:link:UncalibratedBLERLUT", ...
        "effective_sinr_bler_lut requires a configured CQI BLER LUT. Set phy.csi.allowUncalibratedBLERLUT=true only for explicitly labeled lab-default studies.");
end

widebandEffectiveSINR_dB = double(widebandSINR_dB - margin_dB);
perRBEffectiveSINR_dB = double(perRBSINR_dB - margin_dB);
selectionSINR_dB = double(widebandEffectiveSINR_dB);
effectiveSINRMethod = "wideband_direct";
effectiveSINRBeta_dB = NaN;
effectiveSINRBetaSource = "";
effectiveSINRBetaValueRole = "";
if modeToken == "effective_sinr_bler_lut"
    [selectionSINR_dB, effectiveSINRMethod, effectiveSINRBeta_dB, effectiveSINRBetaSource, effectiveSINRBetaValueRole] = ...
        localComputeEffectiveSINR(perRBEffectiveSINR_dB, widebandEffectiveSINR_dB, cfg, direction);
end
widebandSE = localSINRToSpectralEfficiency(selectionSINR_dB);
perRBSE = localSINRToSpectralEfficiency(perRBEffectiveSINR_dB);
predictedBLER = nan(15, 1);
operatingPoint_dB = nan(15, 1);
blerCurveSlope_dB = NaN;

if ~sinrInputAccepted
    widebandCQI = NaN;
    perRBCQI = NaN(size(perRBEffectiveSINR_dB));
    predictedBLER = nan(15, 1);
    operatingPoint_dB = nan(15, 1);
    feedbackMode = "sinr_input_rejected_non_scheduling_provenance";
elseif modeToken == "effective_sinr_bler_lut"
    [widebandCQI, predictedBLER, operatingPoint_dB, blerCurveSlope_dB] = ...
        localSelectCQIByBLER(selectionSINR_dB, cfg, direction, tableToken, thresholds_dB, targetBLER);
    perRBCQI = double(localSelectCQIByThresholds(perRBEffectiveSINR_dB, operatingPoint_dB));
    feedbackMode = "effective_sinr_bler_target_lut";
elseif modeToken == "threshold_table" && ~isempty(thresholds_dB)
    widebandCQI = double(localSelectCQIByThresholds(widebandEffectiveSINR_dB, thresholds_dB));
    perRBCQI = double(localSelectCQIByThresholds(perRBEffectiveSINR_dB, thresholds_dB));
    feedbackMode = "sinr_threshold_table";
else
    widebandCQI = double(localSelectCQIBySE(widebandSE, tableToken));
    perRBCQI = double(localSelectCQIBySE(perRBSE, tableToken));
    thresholdSource = "";
    thresholdRole = "";
    feedbackMode = "wideband_same_sinr_model";
end

[perCodewordCQI, perCodewordSINR_dB] = localPerCodewordCQI(rankIndicator, perLayerSINR_dB, tableToken);
if ~isempty(perCodewordCQI) && all(isfinite(perCodewordCQI))
    if isfinite(double(widebandCQI))
        widebandCQI = min(double(widebandCQI), min(double(perCodewordCQI)));
    else
        widebandCQI = min(double(perCodewordCQI));
    end
end

feedback = struct( ...
    "Mode", char(feedbackMode), ...
    "Table", char(tableToken), ...
    "AppliedSINRMargin_dB", double(margin_dB), ...
    "WidebandSINR_dB", double(widebandSINR_dB), ...
    "WidebandEffectiveSINR_dB", double(widebandEffectiveSINR_dB), ...
    "EffectiveSINR_dB", double(selectionSINR_dB), ...
    "EffectiveSINRMethod", char(string(effectiveSINRMethod)), ...
    "EffectiveSINRBeta_dB", double(effectiveSINRBeta_dB), ...
    "EffectiveSINRBetaSource", char(string(effectiveSINRBetaSource)), ...
    "EffectiveSINRBetaValueRole", char(string(effectiveSINRBetaValueRole)), ...
    "WidebandSpectralEfficiency", double(widebandSE), ...
    "WidebandCQI", double(widebandCQI), ...
    "PerCodewordCQI", double(perCodewordCQI), ...
    "PerCodewordSINR_dB", double(perCodewordSINR_dB), ...
    "PerRBSINR_dB", double(perRBSINR_dB), ...
    "PerRBEffectiveSINR_dB", double(perRBEffectiveSINR_dB), ...
    "PerRBSpectralEfficiency", double(perRBSE), ...
    "PerRBCQI", double(perRBCQI), ...
    "TargetBLER", double(targetBLER), ...
    "PredictedBLERByCQI", double(predictedBLER), ...
    "CQIOperatingPointSINR_dB", double(operatingPoint_dB), ...
    "BLERCurveSlope_dB", double(blerCurveSlope_dB), ...
    "ThresholdSource", char(string(thresholdSource)), ...
    "ThresholdValueRole", char(string(thresholdRole)), ...
    "SINRThresholds_dB", double(thresholds_dB), ...
    "SINRInputAccepted", logical(sinrInputAccepted), ...
    "SINRInputRejectionReason", char(string(sinrInputRejectionReason)), ...
    "SINRInputSource", char(string(sinrInputSource)), ...
    "SINRInputValueRole", char(string(sinrInputRole)), ...
    "SINRInputValueStatus", char(string(sinrInputStatus)), ...
    "BLERLUTSource", char(string(localResolveBLERLUTSource(cfg, direction, tableToken, thresholds_dB, targetBLER))), ...
    "BLERLUTValueRole", char(string(localResolveBLERLUTValueRole(cfg, direction, tableToken, thresholds_dB, targetBLER))), ...
    "BLERLUTCalibrationID", char(string(localResolveBLERLUTCalibrationID(cfg, direction, tableToken, thresholds_dB, targetBLER))));
end

function [accepted, reason, source, role, status] = localValidateSINRInputProvenance(sinrInput)
accepted = true;
reason = "";
source = "";
role = "";
status = "";
if ~isstruct(sinrInput)
    return;
end
source = string(sixgr.util.structGet(sinrInput, "SINRSource", ...
    sixgr.util.structGet(sinrInput, "WidebandSINRSource", ...
    sixgr.util.structGet(sinrInput, "Source", ""))));
role = string(sixgr.util.structGet(sinrInput, "SINRValueRole", ...
    sixgr.util.structGet(sinrInput, "WidebandSINRValueRole", ...
    sixgr.util.structGet(sinrInput, "ValueRole", ""))));
status = string(sixgr.util.structGet(sinrInput, "SINRValueStatus", ...
    sixgr.util.structGet(sinrInput, "WidebandSINRValueStatus", ...
    sixgr.util.structGet(sinrInput, "ValueStatus", ""))));
provenanceToken = lower(strjoin([source, role], " "));
statusToken = lower(strtrim(string(status)));
if strlength(strtrim(strjoin([source, role, status], " "))) == 0
    return;
end
blocked = ["evm_proxy", "proxy", "fallback", "configured", "sweep", ...
    "oracle", "true_channel", "true-channel", ...
    "diagnostic", "not_scheduling", "not_for_scheduling", ...
    "receiver_hest", "reference_signal_measurement", "pilot_sinr", ...
    "reference_signal_quality", "estimated"];
if any(contains(provenanceToken, blocked))
    accepted = false;
    reason = "sinr_input_role_or_source_is_not_scheduler_eligible";
    return;
end
if contains(statusToken, "unavailable") || contains(statusToken, "failed") || contains(statusToken, "rejected")
    accepted = false;
    reason = "sinr_input_status_is_not_ok";
end
end

function source = localResolveBLERLUTSource(cfg, direction, tableToken, thresholds_dB, targetBLER)
lut = localResolveBLERLUT(cfg, direction, tableToken, thresholds_dB, targetBLER);
source = string(sixgr.util.structGet(lut, "Source", ""));
end

function role = localResolveBLERLUTValueRole(cfg, direction, tableToken, thresholds_dB, targetBLER)
lut = localResolveBLERLUT(cfg, direction, tableToken, thresholds_dB, targetBLER);
role = string(sixgr.util.structGet(lut, "ValueRole", ""));
end

function calibrationID = localResolveBLERLUTCalibrationID(cfg, direction, tableToken, thresholds_dB, targetBLER)
lut = localResolveBLERLUT(cfg, direction, tableToken, thresholds_dB, targetBLER);
calibrationID = string(sixgr.util.structGet(lut, "CalibrationID", ""));
end

function [widebandSINR_dB, perRBSINR_dB, rankIndicator, perLayerSINR_dB] = localExtractSINRInputs(sinrInput)
widebandSINR_dB = [];
perRBSINR_dB = [];
rankIndicator = NaN;
perLayerSINR_dB = [];

if isnumeric(sinrInput)
    widebandSINR_dB = double(sinrInput);
elseif isstruct(sinrInput)
    widebandSINR_dB = double(sixgr.util.structGet(sinrInput, "WidebandSINR_dB", []));
    perRBSINR_dB = double(sixgr.util.structGet(sinrInput, "PerRBSINR_dB", []));
    rankIndicator = double(sixgr.util.structGet(sinrInput, "RankIndicator", ...
        sixgr.util.structGet(sinrInput, "RI", NaN)));
    perLayerSINR_dB = double(sixgr.util.structGet(sinrInput, "PostEqSINRPerLayer_dB", ...
        sixgr.util.structGet(sinrInput, "PerLayerSINR_dB", [])));
end

if isempty(widebandSINR_dB) && ~isempty(perRBSINR_dB)
    try
        widebandSINR_dB = 10 * log10(mean(10 .^ (double(perRBSINR_dB) / 10), 2, "omitnan"));
    catch
        widebandSINR_dB = 10 * log10(mean(10 .^ (double(perRBSINR_dB) / 10), 2));
    end
end

if isempty(widebandSINR_dB)
    widebandSINR_dB = NaN;
end
end

function [perCodewordCQI, perCodewordSINR_dB] = localPerCodewordCQI(ri, perLayerSINR_dB, cqiTable)
perCodewordCQI = [];
perCodewordSINR_dB = [];
ri = double(ri);
if ~(isscalar(ri) && isfinite(ri) && ri >= 1)
    return;
end
ri = max(1, round(ri));
vals = double(perLayerSINR_dB(:).');
vals = vals(isfinite(vals));
if numel(vals) < ri
    return;
end
vals = vals(1:ri);
lin = 10 .^ (vals ./ 10);
if ri <= 4
    % TS 38.211 maps ranks 1--4 to one PDSCH/PUSCH codeword.  Per-layer
    % SINR must therefore reduce to one codeword quality, not two.
    cw0 = 10 * log10(max(mean(lin, "omitnan"), eps));
    perCodewordSINR_dB = cw0;
    perCodewordCQI = sixgr.phy.dl.mapSINRToCQI(cw0, cqiTable);
    return;
end
nCW0 = max(1, floor(ri / 2));
nCW1 = max(1, ri - nCW0);
cw0 = 10 * log10(max(mean(lin(1:nCW0), "omitnan"), eps));
cw1 = 10 * log10(max(mean(lin((nCW0+1):(nCW0+nCW1)), "omitnan"), eps));
perCodewordSINR_dB = [cw0 cw1];
perCodewordCQI = [ ...
    sixgr.phy.dl.mapSINRToCQI(cw0, cqiTable), ...
    sixgr.phy.dl.mapSINRToCQI(cw1, cqiTable)];
end

function spectralEfficiency = localSINRToSpectralEfficiency(sinr_dB)
if isempty(sinr_dB)
    spectralEfficiency = [];
    return;
end
sinrLin = 10 .^ (double(sinr_dB) / 10);
sinrLin(~isfinite(sinrLin)) = 0;
sinrLin = max(sinrLin, 0);
spectralEfficiency = log2(1 + sinrLin);
end

function cqi = localSelectCQIBySE(spectralEfficiency, tableToken)
cqi = zeros(size(spectralEfficiency));
for i = 1:numel(cqi)
    seVal = double(spectralEfficiency(i));
    if ~(isfinite(seVal) && seVal > 0)
        cqi(i) = 0;
        continue;
    end
    bestCQI = 0;
    bestSE = -inf;
    for idx = 1:15
        profile = sixgr.link.resolveCQIProfile(tableToken, idx);
        if ~profile.Valid
            continue;
        end
        if profile.SpectralEfficiency <= seVal + 1e-9 && profile.SpectralEfficiency > bestSE + 1e-9
            bestCQI = idx;
            bestSE = profile.SpectralEfficiency;
        end
    end
    cqi(i) = bestCQI;
end
end

function cqi = localSelectCQIByThresholds(sinr_dB, thresholds_dB)
cqi = zeros(size(sinr_dB));
if isempty(thresholds_dB)
    return;
end
thresholds_dB = double(thresholds_dB(:).');
for i = 1:numel(cqi)
    value = double(sinr_dB(i));
    if ~(isfinite(value))
        cqi(i) = 0;
        continue;
    end
    idx = find(value >= thresholds_dB, 1, "last");
    if isempty(idx)
        cqi(i) = 0;
    else
        cqi(i) = min(15, max(0, round(double(idx))));
    end
end
end

function tableToken = localResolveCQITable(cfg, direction)
tableToken = char(sixgr.link.resolveConfiguredCQITable(cfg, direction));
end

function modeToken = localResolveCQIMode(cfg, direction, hasPerRB)
if nargin < 2 || isempty(direction)
    direction = "DL";
end
if nargin < 3
    hasPerRB = false;
end
dir = upper(string(direction));
if dir == "UL"
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
raw = "";
for i = 1:numel(candidates)
    raw = string(sixgr.util.structGet(cfg, candidates(i), ""));
    if strlength(strtrim(raw)) > 0
        break;
    end
end
raw = lower(strtrim(raw));
switch raw
    case {""}
        modeToken = "threshold_table";
    case {"threshold_table", "thresholds", "lab_default_threshold_table", "sinr_threshold_table"}
        modeToken = "threshold_table";
    case {"effective_sinr_bler_lut", "eesm_bler_lut", "miesm_bler_lut", "effective_sinr"}
        modeToken = "effective_sinr_bler_lut";
    case {"spectral_efficiency", "shannon_proxy", "wideband_same_sinr_model"}
        modeToken = "spectral_efficiency";
    otherwise
        modeToken = "threshold_table";
end
end

function targetBLER = localResolveTargetBLER(cfg, direction)
if nargin < 2 || isempty(direction)
    direction = "DL";
end
dir = upper(string(direction));
if dir == "UL"
    candidates = [ ...
        "phy.pusch.targetBLER"
        "phy.csi.ulTargetBLER"
        "phy.csi.targetBLER"];
else
    candidates = [ ...
        "phy.pdsch.targetBLER"
        "phy.csi.dlTargetBLER"
        "phy.csi.targetBLER"];
end
targetBLER = NaN;
for i = 1:numel(candidates)
    value = double(sixgr.util.structGet(cfg, candidates(i), NaN));
    if isfinite(value) && value > 0 && value < 1
        targetBLER = value;
        break;
    end
end
if ~(isfinite(targetBLER) && targetBLER > 0 && targetBLER < 1)
    targetBLER = 0.1;
end
end

function [effectiveSINR_dB, methodToken, beta_dB, betaSource, betaValueRole] = localComputeEffectiveSINR(perRBSINR_dB, widebandSINR_dB, cfg, direction)
effectiveSINR_dB = double(widebandSINR_dB);
methodToken = "wideband_direct";
beta_dB = NaN;
betaSource = "";
betaValueRole = "";
perRB = double(perRBSINR_dB(:));
perRB = perRB(isfinite(perRB));
if isempty(perRB)
    return;
end
rawMethod = "";
dir = upper(string(direction));
if dir == "UL"
    candidates = [ ...
        "phy.pusch.effectiveSINRMethod"
        "phy.csi.ulEffectiveSINRMethod"
        "phy.csi.effectiveSINRMethod"];
else
    candidates = [ ...
        "phy.pdsch.effectiveSINRMethod"
        "phy.csi.dlEffectiveSINRMethod"
        "phy.csi.effectiveSINRMethod"];
end
for i = 1:numel(candidates)
    rawMethod = string(sixgr.util.structGet(cfg, candidates(i), ""));
    if strlength(strtrim(rawMethod)) > 0
        break;
    end
end
rawMethod = lower(strtrim(rawMethod));
if rawMethod == ""
    rawMethod = "eesm";
end
switch rawMethod
    case {"miesm", "mi", "mutual_information"}
        methodToken = "miesm_shannon_lab_default";
        sinrLin = 10 .^ (perRB / 10);
        mi = log2(1 + max(sinrLin, 0));
        avgMi = mean(mi, "omitnan");
        if isfinite(avgMi)
            effectiveSINR_dB = 10 * log10(max(2.^avgMi - 1, eps));
        end
    otherwise
        methodToken = "eesm";
        [beta_dB, betaSource, betaValueRole] = localResolveEESMBeta(cfg, direction);
        betaLin = 10^(beta_dB / 10);
        sinrLin = 10 .^ (perRB / 10);
        effectiveLin = -betaLin * log(mean(exp(-sinrLin ./ max(betaLin, eps)), "omitnan"));
        if isfinite(effectiveLin) && effectiveLin > 0
            effectiveSINR_dB = 10 * log10(max(effectiveLin, eps));
        end
end
end

function [beta_dB, source, valueRole] = localResolveEESMBeta(cfg, direction)
beta_dB = NaN;
source = "";
valueRole = "";
if nargin < 2 || isempty(direction)
    direction = "DL";
end
dir = upper(string(direction));
[catalogBeta, catalogSource, catalogRole] = localResolveEESMBetaFromMCSCatalog(cfg, dir);
if isfinite(catalogBeta) && catalogBeta > 0
    beta_dB = catalogBeta;
    source = catalogSource;
    valueRole = catalogRole;
    return;
end
if dir == "UL"
    candidates = [ ...
        "phy.pusch.eesmBeta_dB"
        "phy.csi.ulEESMBeta_dB"
        "phy.csi.eesmBeta_dB"];
else
    candidates = [ ...
        "phy.pdsch.eesmBeta_dB"
        "phy.csi.dlEESMBeta_dB"
        "phy.csi.eesmBeta_dB"];
end
for i = 1:numel(candidates)
    value = double(sixgr.util.structGet(cfg, candidates(i), NaN));
    if isfinite(value)
        beta_dB = value;
        source = string(candidates(i));
        valueRole = "configured_scalar_beta";
        break;
    end
end
if ~(isfinite(beta_dB) && beta_dB > 0)
    beta_dB = 1.5;
    source = "resolveWidebandCQI.lab_default_scalar_beta";
    valueRole = "uncalibrated_lab_default";
end
end

function [beta_dB, source, valueRole] = localResolveEESMBetaFromMCSCatalog(cfg, dir)
beta_dB = NaN;
source = "";
valueRole = "";
mcsIndex = localResolveConfiguredMCSForBeta(cfg, dir);
if ~(isfinite(mcsIndex) && mcsIndex >= 0)
    return;
end
if dir == "UL"
    catalogPaths = [ ...
        "phy.pusch.eesmBetaByMCS_dB"
        "phy.csi.ulEESMBetaByMCS_dB"
        "phy.csi.eesmBetaByMCS_dB"];
    indexPaths = [ ...
        "phy.pusch.eesmBetaMCSIndex"
        "phy.csi.ulEESMBetaMCSIndex"
        "phy.csi.eesmBetaMCSIndex"];
else
    catalogPaths = [ ...
        "phy.pdsch.eesmBetaByMCS_dB"
        "phy.csi.dlEESMBetaByMCS_dB"
        "phy.csi.eesmBetaByMCS_dB"];
    indexPaths = [ ...
        "phy.pdsch.eesmBetaMCSIndex"
        "phy.csi.dlEESMBetaMCSIndex"
        "phy.csi.eesmBetaMCSIndex"];
end
for i = 1:numel(catalogPaths)
    betaVec = double(sixgr.util.structGet(cfg, catalogPaths(i), []));
    betaVec = betaVec(:);
    if isempty(betaVec)
        continue;
    end
    indexVec = double(sixgr.util.structGet(cfg, indexPaths(min(i, numel(indexPaths))), []));
    indexVec = indexVec(:);
    if numel(indexVec) == numel(betaVec)
        matchIdx = find(round(indexVec) == round(mcsIndex), 1, "first");
    else
        matchIdx = round(double(mcsIndex)) + 1;
        if matchIdx < 1 || matchIdx > numel(betaVec)
            matchIdx = [];
        end
    end
    if ~isempty(matchIdx)
        candidate = double(betaVec(matchIdx(1)));
        if isfinite(candidate) && candidate > 0
            beta_dB = candidate;
            source = string(catalogPaths(i));
            valueRole = "configured_mcs_index_beta_catalog";
            return;
        end
    end
end
end

function mcsIndex = localResolveConfiguredMCSForBeta(cfg, dir)
if dir == "UL"
    candidates = [ ...
        "phy.pusch.mcsIndex"
        "phy.pusch.configuredMCSIndex"
        "phy.linkAdaptation.configuredULMCSIndex"];
else
    candidates = [ ...
        "phy.pdsch.mcsIndex"
        "phy.pdsch.configuredMCSIndex"
        "phy.linkAdaptation.configuredDLMCSIndex"];
end
mcsIndex = NaN;
for i = 1:numel(candidates)
    raw = double(sixgr.util.structGet(cfg, candidates(i), NaN));
    raw = raw(isfinite(raw));
    if ~isempty(raw)
        mcsIndex = round(double(raw(1)));
        return;
    end
end
end

function [selectedCQI, predictedBLER, operatingPoint_dB, slope_dB] = localSelectCQIByBLER(effectiveSINR_dB, cfg, direction, tableToken, thresholds_dB, targetBLER)
predictedBLER = nan(15, 1);
operatingPoint_dB = nan(15, 1);
slope_dB = nan(15, 1);
selectedCQI = 0;
if ~(isfinite(effectiveSINR_dB))
    return;
end

lut = localResolveBLERLUT(cfg, direction, tableToken, thresholds_dB, targetBLER);
for idx = 1:min(15, numel(lut.Curves))
    curve = lut.Curves{idx};
    if isempty(curve)
        continue;
    end
    predictedBLER(idx) = localPredictBLERFromCurve(effectiveSINR_dB, curve);
    operatingPoint_dB(idx) = double(sixgr.util.structGet(curve, "OperatingPoint_dB", NaN));
    slope_dB(idx) = double(sixgr.util.structGet(curve, "Slope_dB", NaN));
    if isfinite(predictedBLER(idx)) && predictedBLER(idx) <= targetBLER + 1e-12
        selectedCQI = idx;
    end
end
end

function lut = localResolveBLERLUT(cfg, direction, tableToken, thresholds_dB, targetBLER)
lut = struct( ...
    "Curves", {cell(15, 1)}, ...
    "Source", "", ...
    "ValueRole", "", ...
    "CalibrationID", "");

raw = [];
dir = upper(string(direction));
if dir == "UL"
    candidates = [ ...
        "phy.pusch.cqiBLERLUT"
        "phy.csi.ulCQIBLERLUT"
        "phy.csi.cqiBLERLUT"];
else
    candidates = [ ...
        "phy.pdsch.cqiBLERLUT"
        "phy.csi.dlCQIBLERLUT"
        "phy.csi.cqiBLERLUT"];
end
for i = 1:numel(candidates)
    raw = sixgr.util.structGet(cfg, candidates(i), []);
    [curves, meta] = localParseBLERLUT(raw, targetBLER, cfg, direction, tableToken);
    if localHasAnyCurves(curves)
        lut.Curves = curves;
        if strlength(string(meta.Source)) > 0
            lut.Source = char(string(candidates(i)) + ":" + string(meta.Source));
        else
            lut.Source = char(candidates(i));
        end
        if strlength(string(meta.ValueRole)) > 0
            lut.ValueRole = char(string(meta.ValueRole));
        else
            lut.ValueRole = "configured_bler_lut";
        end
        lut.CalibrationID = char(string(meta.CalibrationID));
        return;
    end
end

lut.Curves = localDefaultBLERLUT(tableToken, thresholds_dB, targetBLER, cfg, direction);
lut.Source = "resolveWidebandCQI.lab_default_bler_lut";
lut.ValueRole = "uncalibrated_lab_default";
lut.CalibrationID = "uncalibrated_vendor_style_lab_default_operating_point_grid";
end

function tf = localConfiguredBLERLUTAvailable(cfg, direction, tableToken, targetBLER)
tf = false;
dir = upper(string(direction));
if dir == "UL"
    candidates = [ ...
        "phy.pusch.cqiBLERLUT"
        "phy.csi.ulCQIBLERLUT"
        "phy.csi.cqiBLERLUT"];
else
    candidates = [ ...
        "phy.pdsch.cqiBLERLUT"
        "phy.csi.dlCQIBLERLUT"
        "phy.csi.cqiBLERLUT"];
end
for i = 1:numel(candidates)
    raw = sixgr.util.structGet(cfg, candidates(i), []);
    if localHasAnyCurves(localParseBLERLUT(raw, targetBLER, cfg, direction, tableToken))
        tf = true;
        return;
    end
end
end

function tf = localAllowUncalibratedBLERLUT(cfg, direction)
dir = upper(string(direction));
if dir == "UL"
    candidates = [ ...
        "phy.pusch.allowUncalibratedBLERLUT"
        "phy.csi.ulAllowUncalibratedBLERLUT"
        "phy.csi.allowUncalibratedBLERLUT"];
else
    candidates = [ ...
        "phy.pdsch.allowUncalibratedBLERLUT"
        "phy.csi.dlAllowUncalibratedBLERLUT"
        "phy.csi.allowUncalibratedBLERLUT"];
end
tf = false;
for i = 1:numel(candidates)
    raw = sixgr.util.structGet(cfg, candidates(i), []);
    if isempty(raw)
        continue;
    end
    if ischar(raw) || isstring(raw)
        tf = any(lower(strtrim(string(raw))) == ["true","1","yes","on"]);
    else
        tf = logical(raw);
    end
    return;
end
end

function tf = localHasAnyCurves(curves)
tf = false;
if ~iscell(curves)
    return;
end
for i = 1:numel(curves)
    if ~isempty(curves{i})
        tf = true;
        return;
    end
end
end

function [curves, meta] = localParseBLERLUT(raw, targetBLER, cfg, direction, tableToken)
curves = cell(15, 1);
meta = struct("Source", "", "ValueRole", "", "CalibrationID", "");
if isempty(raw)
    return;
end
if nargin < 3 || isempty(cfg)
    cfg = struct();
end
if nargin < 4 || isempty(direction)
    direction = "DL";
end
if nargin < 5 || isempty(tableToken)
    tableToken = "table1";
end
dir = upper(string(direction));
[T, rawMeta] = localBLERLUTInputTable(raw);
meta = rawMeta;
if isempty(T)
    return;
end

names = string(T.Properties.VariableNames);
if all(ismember(["CQI", "SINR_dB", "BLER"], names))
    [curves, parsedMeta] = localParseExplicitCQIBLERTable(T, targetBLER);
    meta = localMergeBLERLUTMeta(meta, parsedMeta, "configured_cqi_bler_table", "configured_waveform_bler_lut");
    return;
end

[curves, parsedMeta] = localParseFixedLinkCampaignBLERTable(T, targetBLER, cfg, dir, tableToken);
meta = localMergeBLERLUTMeta(meta, parsedMeta, "", "");
end

function [curves, meta] = localParseExplicitCQIBLERTable(T, targetBLER)
curves = cell(15, 1);
meta = localEmptyBLERLUTMeta();
for idx = 1:15
    mask = round(double(T.CQI)) == idx;
    if ~any(mask)
        continue;
    end
    curves{idx} = localFinalizeBLERCurve(double(T.SINR_dB(mask)), double(T.BLER(mask)), targetBLER);
end
end

function [curves, meta] = localParseFixedLinkCampaignBLERTable(T, targetBLER, cfg, direction, tableToken)
curves = cell(15, 1);
meta = localEmptyBLERLUTMeta();
names = string(T.Properties.VariableNames);
dir = upper(string(direction));
blerCol = dir + "_BLER";
trialCol = dir + "_TrialCount";
if ~(ismember("SNR_dB", names) && ismember(blerCol, names))
    return;
end
snr = double(T.SNR_dB);
bler = double(T.(char(blerCol)));
mask = isfinite(snr) & isfinite(bler) & bler > 0 & bler <= 1;
if ismember(trialCol, names)
    trials = double(T.(char(trialCol)));
    mask = mask & isfinite(trials) & trials > 0;
end
if nnz(mask) < 2
    return;
end
cqi = localResolveCampaignCQI(T, mask, cfg, dir, tableToken);
validCQI = isfinite(cqi) & cqi >= 1 & cqi <= 15;
if ~any(validCQI)
    return;
end
for idx = 1:15
    idxMask = mask & round(cqi(:)) == idx;
    if nnz(idxMask) < 2
        continue;
    end
    curves{idx} = localFinalizeBLERCurve(snr(idxMask), bler(idxMask), targetBLER);
end
if ~localHasAnyCurves(curves)
    return;
end
meta.Source = "fixed_link_monte_carlo_campaign";
meta.ValueRole = "fixed_link_waveform_bler_calibration";
meta.CalibrationID = localFixedLinkCalibrationID(T, dir, tableToken, targetBLER);
end

function cqi = localResolveCampaignCQI(T, mask, cfg, direction, tableToken)
n = height(T);
cqi = nan(n, 1);
names = string(T.Properties.VariableNames);
cqiCandidates = ["CQI", "WidebandCQI", "CQIUsed", "ResolvedCQI", "AgedCQI"];
for i = 1:numel(cqiCandidates)
    if ~ismember(cqiCandidates(i), names)
        continue;
    end
    raw = double(T.(char(cqiCandidates(i))));
    raw = raw(:);
    if numel(raw) == n
        cqi(mask) = raw(mask);
        if any(isfinite(cqi(mask)))
            return;
        end
    end
end
mcs = nan(n, 1);
mcsCandidates = ["MCS", "MCSIndex", "ConfiguredMCSIndex", "DominantMCS", "MCS_dominant"];
for i = 1:numel(mcsCandidates)
    if ~ismember(mcsCandidates(i), names)
        continue;
    end
    raw = double(T.(char(mcsCandidates(i))));
    raw = raw(:);
    if numel(raw) == n
        mcs(mask) = raw(mask);
        break;
    end
end
if ~any(isfinite(mcs(mask)))
    cfgMCS = localConfiguredMCSIndex(cfg, direction);
    if isfinite(cfgMCS)
        mcs(mask) = double(cfgMCS);
    end
end
for i = find(mask(:)).'
    if isfinite(mcs(i))
        cqi(i) = localMCSIndexToCQI(round(double(mcs(i))), cfg, direction, tableToken);
    end
end
end

function cqi = localMCSIndexToCQI(mcsIndex, cfg, direction, tableToken)
cqi = NaN;
try
    mcsTable = char(sixgr.link.resolveConfiguredMCSTable(cfg, direction));
catch
    if upper(string(direction)) == "UL"
        mcsTable = char(string(sixgr.util.structGet(cfg, "phy.pusch.mcsTable", "qam64_table1")));
    else
        mcsTable = char(string(sixgr.util.structGet(cfg, "phy.pdsch.mcsTable", "qam64_table1")));
    end
end
targetProfile = sixgr.link.resolveMCSProfile(mcsTable, mcsIndex);
exact = [];
for idx = 1:15
    amc = sixgr.link.resolveMCSFromCQI(idx, mcsTable, tableToken);
    if logical(sixgr.util.structGet(amc, "Valid", false)) && ...
            round(double(sixgr.util.structGet(amc, "MCSIndex", NaN))) == round(double(mcsIndex))
        exact(end + 1) = idx; %#ok<AGROW>
    end
end
if ~isempty(exact)
    cqi = double(max(exact));
    return;
end
if ~logical(sixgr.util.structGet(targetProfile, "Valid", false))
    return;
end
bestIdx = NaN;
bestDistance = inf;
for idx = 1:15
    profile = sixgr.link.resolveCQIProfile(tableToken, idx);
    if ~logical(sixgr.util.structGet(profile, "Valid", false))
        continue;
    end
    qPenalty = 0;
    if double(profile.Qm) < double(targetProfile.Qm)
        qPenalty = 100;
    end
    distance = abs(double(profile.SpectralEfficiency) - double(targetProfile.SpectralEfficiency)) + qPenalty;
    if distance < bestDistance
        bestDistance = distance;
        bestIdx = idx;
    end
end
if isfinite(bestIdx)
    cqi = double(bestIdx);
end
end

function mcsIndex = localConfiguredMCSIndex(cfg, direction)
direction = upper(string(direction));
if direction == "UL"
    candidates = [ ...
        "phy.pusch.mcsIndex"
        "phy.pusch.configuredMCSIndex"
        "phy.linkAdaptation.configuredULMCSIndex"];
else
    candidates = [ ...
        "phy.pdsch.mcsIndex"
        "phy.pdsch.configuredMCSIndex"
        "phy.linkAdaptation.configuredDLMCSIndex"];
end
mcsIndex = NaN;
for i = 1:numel(candidates)
    raw = double(sixgr.util.structGet(cfg, candidates(i), NaN));
    raw = raw(isfinite(raw));
    if ~isempty(raw)
        mcsIndex = round(double(raw(1)));
        return;
    end
end
end

function [T, meta] = localBLERLUTInputTable(raw)
T = table();
meta = localEmptyBLERLUTMeta();
if istable(raw)
    T = raw;
    return;
end
if ~isstruct(raw)
    return;
end
meta.Source = string(sixgr.util.structGet(raw, "Source", ...
    sixgr.util.structGet(raw, "source", "")));
meta.ValueRole = string(sixgr.util.structGet(raw, "ValueRole", ...
    sixgr.util.structGet(raw, "value_role", "")));
meta.CalibrationID = string(sixgr.util.structGet(raw, "CalibrationID", ...
    sixgr.util.structGet(raw, "calibration_id", ...
    sixgr.util.structGet(raw, "CalibrationVersion", ...
    sixgr.util.structGet(raw, "calibration_version", "")))));
if all(isfield(raw, {'CQI','SINR_dB','BLER'}))
    try
        T = table(double(raw.CQI(:)), double(raw.SINR_dB(:)), double(raw.BLER(:)), ...
            'VariableNames', {'CQI','SINR_dB','BLER'});
        return;
    catch
        T = table();
    end
end
tableFields = ["Table", "table", "Curves", "curves", "Summary", "summary", ...
    "SNRSweep", "snr_sweep", "FixedLinkCampaignSummary", "FixedLinkSummary", ...
    "CampaignSummary", "CampaignSummaryTable"];
for i = 1:numel(tableFields)
    candidate = sixgr.util.structGet(raw, tableFields(i), []);
    if istable(candidate)
        T = candidate;
        return;
    end
end
try
    T = struct2table(raw);
catch
    T = table();
end
end

function meta = localEmptyBLERLUTMeta()
meta = struct("Source", "", "ValueRole", "", "CalibrationID", "");
end

function out = localMergeBLERLUTMeta(base, overlay, fallbackSource, fallbackRole)
out = localEmptyBLERLUTMeta();
for field = ["Source", "ValueRole", "CalibrationID"]
    value = string(sixgr.util.structGet(base, field, ""));
    overlayValue = string(sixgr.util.structGet(overlay, field, ""));
    if strlength(strtrim(overlayValue)) > 0
        value = overlayValue;
    end
    out.(char(field)) = char(value);
end
if strlength(strtrim(string(out.Source))) == 0
    out.Source = char(string(fallbackSource));
end
if strlength(strtrim(string(out.ValueRole))) == 0
    out.ValueRole = char(string(fallbackRole));
end
end

function id = localFixedLinkCalibrationID(T, direction, tableToken, targetBLER)
names = string(T.Properties.VariableNames);
for candidate = ["CalibrationID", "CalibrationVersion", "CampaignID", "RunID"]
    if ismember(candidate, names)
        values = string(T.(char(candidate)));
        values = values(strlength(strtrim(values)) > 0);
        if ~isempty(values)
            id = char(values(1));
            return;
        end
    end
end
if ismember("PointSeed", names)
    seedVals = double(T.PointSeed);
    seedVals = seedVals(isfinite(seedVals));
else
    seedVals = [];
end
seedToken = "noseed";
if ~isempty(seedVals)
    seedToken = "seed" + join(string(round(seedVals(:).')), "_");
end
id = char("fixed_link_monte_carlo:" + upper(string(direction)) + ...
    ":cqi_" + lower(string(tableToken)) + ...
    ":target_bler_" + regexprep(string(sprintf("%.3g", double(targetBLER))), "[^0-9A-Za-z]+", "p") + ...
    ":" + seedToken);
end

function curves = localDefaultBLERLUT(tableToken, thresholds_dB, targetBLER, cfg, direction)
curves = cell(15, 1);
operatingPoint_dB = double(thresholds_dB(:));
if numel(operatingPoint_dB) ~= 15
    operatingPoint_dB = double(sixgr.link.cqiRequiredSINRTable(tableToken, cfg, direction));
    operatingPoint_dB = operatingPoint_dB(:);
end
supportOffset_dB = [-6 -4 -3 -2 -1 0 1 2 3 4 6];
blerAnchor = [0.99 0.95 0.85 0.60 0.28 0.10 0.03 0.008 0.002 5e-4 1e-4];
defaultSlope_dB = localResolveBLERSlope(cfg, direction);
for idx = 1:min(15, numel(operatingPoint_dB))
    opPoint = operatingPoint_dB(idx);
    if ~isfinite(opPoint)
        continue;
    end
    sinrAxis = opPoint + supportOffset_dB .* max(defaultSlope_dB / 1.5, eps);
    curve = localFinalizeBLERCurve(sinrAxis, blerAnchor, targetBLER);
    curve.OperatingPoint_dB = double(opPoint);
    curve.Slope_dB = double(defaultSlope_dB);
    curves{idx} = curve;
end
end

function curve = localFinalizeBLERCurve(sinrAxis_dB, blerAxis, targetBLER)
curve = struct("SINR_dB", [], "BLER", [], "OperatingPoint_dB", NaN, "Slope_dB", NaN);
sinrAxis_dB = double(sinrAxis_dB(:));
blerAxis = double(blerAxis(:));
mask = isfinite(sinrAxis_dB) & isfinite(blerAxis) & blerAxis > 0 & blerAxis <= 1;
sinrAxis_dB = sinrAxis_dB(mask);
blerAxis = blerAxis(mask);
if numel(sinrAxis_dB) < 2
    return;
end
[sinrAxis_dB, order] = sort(sinrAxis_dB, "ascend");
blerAxis = blerAxis(order);
blerAxis = max(min(blerAxis, 1), 1e-6);

% Enforce the physical monotonic trend: BLER decreases as effective SINR rises.
for i = 2:numel(blerAxis)
    blerAxis(i) = min(blerAxis(i - 1), blerAxis(i));
end
for i = numel(blerAxis)-1:-1:1
    blerAxis(i) = max(blerAxis(i), blerAxis(i + 1));
end

curve.SINR_dB = sinrAxis_dB(:);
curve.BLER = blerAxis(:);
curve.OperatingPoint_dB = localCurveOperatingPoint(curve, targetBLER);
curve.Slope_dB = localCurveSlope(curve, targetBLER);
end

function opPoint = localCurveOperatingPoint(curve, targetBLER)
opPoint = NaN;
if isempty(curve) || isempty(curve.SINR_dB) || isempty(curve.BLER)
    return;
end
logBLER = log10(max(curve.BLER(:), 1e-6));
targetLog = log10(max(min(double(targetBLER), 1), 1e-6));
[logBLER, order] = sort(logBLER, "ascend");
sinrAxis = double(curve.SINR_dB(order));
if numel(unique(logBLER)) < 2
    return;
end
opPoint = interp1(logBLER, sinrAxis, targetLog, "linear", "extrap");
end

function slope_dB = localCurveSlope(curve, targetBLER)
slope_dB = NaN;
if isempty(curve) || isempty(curve.SINR_dB) || numel(curve.SINR_dB) < 2
    return;
end
opPoint = localCurveOperatingPoint(curve, targetBLER);
if ~isfinite(opPoint)
    return;
end
sinrAxis = double(curve.SINR_dB(:));
blerAxis = max(min(double(curve.BLER(:)), 1), 1e-6);
[~, idx] = min(abs(sinrAxis - opPoint));
idxLo = max(1, idx - 1);
idxHi = min(numel(sinrAxis), idx + 1);
if idxHi == idxLo
    return;
end
deltaSINR = abs(sinrAxis(idxHi) - sinrAxis(idxLo));
deltaLogBLER = abs(log10(blerAxis(idxHi)) - log10(blerAxis(idxLo)));
if deltaLogBLER <= 0
    return;
end
slope_dB = deltaSINR / deltaLogBLER;
end

function slope_dB = localResolveBLERSlope(cfg, direction)
slope_dB = NaN;
if nargin < 2 || isempty(direction)
    direction = "DL";
end
dir = upper(string(direction));
if dir == "UL"
    candidates = [ ...
        "phy.pusch.blerCurveSlope_dB"
        "phy.csi.ulBLERCurveSlope_dB"
        "phy.csi.blerCurveSlope_dB"];
else
    candidates = [ ...
        "phy.pdsch.blerCurveSlope_dB"
        "phy.csi.dlBLERCurveSlope_dB"
        "phy.csi.blerCurveSlope_dB"];
end
for i = 1:numel(candidates)
    value = double(sixgr.util.structGet(cfg, candidates(i), NaN));
    if isfinite(value)
        slope_dB = value;
        break;
    end
end
if ~(isfinite(slope_dB) && slope_dB > 0)
    slope_dB = 1.5;
end
end

function bler = localPredictBLERFromCurve(effectiveSINR_dB, curve)
bler = NaN;
if ~(isfinite(effectiveSINR_dB)) || isempty(curve) || isempty(curve.SINR_dB) || isempty(curve.BLER)
    return;
end
sinrAxis = double(curve.SINR_dB(:));
logBLER = log10(max(min(double(curve.BLER(:)), 1), 1e-6));
if numel(sinrAxis) < 2 || numel(unique(sinrAxis)) < 2
    return;
end
predLog = interp1(sinrAxis, logBLER, double(effectiveSINR_dB), "linear", "extrap");
bler = max(min(10.^predLog, 1), 1e-6);
end
