function vis = SpatialNonStationarity(cfg, varargin)
% sixgr.channel.SpatialNonStationarity
%
% Subarray visibility-region metadata for spatial non-stationarity.
% This helper does not claim full runtime cluster geometry unless the
% required inputs exist. It supports:
%   - disabled
%   - legacy_random_mask_placeholder
%   - geometry_based_visibility
%
% The geometry-based mode is still a proxy because the repo does not carry
% full runtime cluster angles into this hook. It is nevertheless more
% truthful than the legacy random-mask path because it only activates when
% runtime array geometry and a relative-bearing input are available.

opt.NumTxAnt = [];
opt.NumRxAnt = [];
opt.NumClusters = 12;
opt.Seed = [];
opt.TransmitAntennaMeta = struct();
opt.ReceiveAntennaMeta = struct();

if mod(numel(varargin),2) ~= 0
    error("SpatialNonStationarity:BadNV","Name-value inputs must come in pairs.");
end
for i = 1:2:numel(varargin)
    name = string(varargin{i});
    val  = varargin{i+1};
    switch lower(name)
        case {"numtxant","ntx"}
            opt.NumTxAnt = double(val);
        case {"numrxant","nrx"}
            opt.NumRxAnt = double(val);
        case {"numclusters","nclusters"}
            opt.NumClusters = double(val);
        case "seed"
            opt.Seed = val;
        case {"transmitantennameta","txantennameta"}
            opt.TransmitAntennaMeta = val;
        case {"receiveantennameta","rxantennameta"}
            opt.ReceiveAntennaMeta = val;
        otherwise
            error("SpatialNonStationarity:UnknownOpt","Unknown option: %s", name);
    end
end

enable = logical(sixgr.util.structGet(cfg, "channel.spatialNonStationary.enable", false));
pVisible = double(sixgr.util.structGet(cfg, "channel.spatialNonStationary.pVisible", 0.6));
nTxSub = double(sixgr.util.structGet(cfg, "channel.spatialNonStationary.numTxSubarrays", 1));
nRxSub = double(sixgr.util.structGet(cfg, "channel.spatialNonStationary.numRxSubarrays", 1));
mode = localResolveMode(cfg, enable);
relativeBearing_deg = double(sixgr.util.structGet(cfg, "channel.spatialNonStationary.relativeBearing_deg", NaN));
stationarityRegion_lambda = double(sixgr.util.structGet(cfg, "channel.spatialNonStationary.stationarityRegion_lambda", 2.5));
clusterAzimuthSpan_deg = double(sixgr.util.structGet(cfg, "channel.spatialNonStationary.clusterAzimuthSpan_deg", 120));

if isempty(opt.NumTxAnt), opt.NumTxAnt = double(sixgr.util.structGet(cfg, "channel.nTxAnt", 1)); end
if isempty(opt.NumRxAnt), opt.NumRxAnt = double(sixgr.util.structGet(cfg, "channel.nRxAnt", 1)); end

nTxSub = max(1, round(nTxSub));
nRxSub = max(1, round(nRxSub));
pVisible = min(max(pVisible,0),1);
opt.NumClusters = max(1, round(double(opt.NumClusters)));

if isempty(opt.Seed)
    seed = sixgr.util.structGet(cfg, "run.seed", 0);
else
    seed = opt.Seed;
end
rs = RandStream("mt19937ar","Seed",double(seed));

txMask = true(opt.NumClusters, nTxSub);
rxMask = true(opt.NumClusters, nRxSub);

vis = struct();
vis.enable = enable;
vis.mode = mode;
vis.pVisible = pVisible;
vis.numTxSubarrays = nTxSub;
vis.numRxSubarrays = nRxSub;
vis.numClusters = opt.NumClusters;
vis.txMask = logical(txMask);
vis.rxMask = logical(rxMask);
vis.note = "";
vis.truthClassification = "";
vis.approximationMode = "";
vis.approximationReason = "";
vis.valueStatus = "";
vis.visibilityMaskSource = "";
vis.geometryInputsUsed = "";
vis.placeholderUsed = false;
vis.complianceStatus = "";

if ~enable || mode == "disabled"
    vis.note = "Spatial non-stationarity is disabled.";
    vis.truthClassification = "disabled_not_requested";
    vis.approximationMode = "disabled";
    vis.approximationReason = "";
    vis.valueStatus = "disabled";
    vis.visibilityMaskSource = "disabled";
    vis.geometryInputsUsed = "none";
    vis.complianceStatus = "disabled";
    return;
end

switch mode
    case "legacy_random_mask_placeholder"
        txMask = rand(rs, opt.NumClusters, nTxSub) <= pVisible;
        rxMask = rand(rs, opt.NumClusters, nRxSub) <= pVisible;
        txMask = localEnsureClusterVisibility(txMask, rs);
        rxMask = localEnsureClusterVisibility(rxMask, rs);

        vis.txMask = logical(txMask);
        vis.rxMask = logical(rxMask);
        vis.note = "Visibility masks are random placeholders; calibrate to geometry for research.";
        vis.truthClassification = "approximate_random_placeholder_visibility_masks";
        vis.approximationMode = "random_visibility_masks_without_geometry_or_angle_coupling";
        vis.approximationReason = "spatial_non_stationarity_masks_are_random_placeholders_not_calibrated_runtime_visibility_regions";
        vis.valueStatus = "approximate_placeholder";
        vis.visibilityMaskSource = "legacy_random_mask_placeholder";
        vis.geometryInputsUsed = "seed_only";
        vis.placeholderUsed = true;
        vis.complianceStatus = "placeholder";

    case "geometry_based_visibility"
        [txCenters_lambda, txOrientation_deg, txOk, txInputs] = localResolveSubarrayGeometry( ...
            opt.TransmitAntennaMeta, nTxSub, "Azimuth_deg");
        [rxCenters_lambda, rxOrientation_deg, rxOk, rxInputs] = localResolveSubarrayGeometry( ...
            opt.ReceiveAntennaMeta, nRxSub, "Heading_deg");
        if ~isfinite(relativeBearing_deg)
            if isfinite(txOrientation_deg) && isfinite(rxOrientation_deg)
                relativeBearing_deg = txOrientation_deg - rxOrientation_deg;
            end
        end

        if ~(txOk && rxOk && isfinite(relativeBearing_deg) && isfinite(stationarityRegion_lambda) && stationarityRegion_lambda > 0)
            vis.txMask = false(opt.NumClusters, nTxSub);
            vis.rxMask = false(opt.NumClusters, nRxSub);
            vis.note = "Geometry-based spatial non-stationarity was requested but required runtime geometry inputs were unavailable.";
            vis.truthClassification = "geometry_requested_but_blocked_missing_runtime_inputs";
            vis.approximationMode = "geometry_based_visibility_requested_without_required_inputs";
            vis.approximationReason = "geometry_based_visibility_requires_runtime_array_geometry_and_relative_bearing_inputs";
            vis.valueStatus = "blocked_missing_geometry_inputs";
            vis.visibilityMaskSource = "blocked_missing_geometry_inputs";
            vis.geometryInputsUsed = strjoin(localNonEmptyStrings([txInputs, rxInputs]), ";");
            vis.placeholderUsed = false;
            vis.complianceStatus = "blocked_missing_geometry_inputs";
            return;
        end

        clusterAngles_deg = linspace(-clusterAzimuthSpan_deg/2, clusterAzimuthSpan_deg/2, opt.NumClusters) + relativeBearing_deg;
        txMask = localGeometryVisibilityMask(clusterAngles_deg, txCenters_lambda, txOrientation_deg, pVisible, stationarityRegion_lambda);
        rxMask = localGeometryVisibilityMask(clusterAngles_deg, rxCenters_lambda, rxOrientation_deg, pVisible, stationarityRegion_lambda);
        txMask = localEnsureNearestVisible(txMask, clusterAngles_deg, txCenters_lambda, txOrientation_deg);
        rxMask = localEnsureNearestVisible(rxMask, clusterAngles_deg, rxCenters_lambda, rxOrientation_deg);

        vis.txMask = logical(txMask);
        vis.rxMask = logical(rxMask);
        vis.note = "Visibility masks are geometry-backed proxies derived from array aperture and relative bearing, not runtime cluster angles.";
        vis.truthClassification = "geometry_backed_visibility_proxy_without_runtime_cluster_angles";
        vis.approximationMode = "deterministic_aperture_bearing_visibility_proxy";
        vis.approximationReason = "runtime_array_geometry_and_relative_bearing_are_used_but_runtime_cluster_angles_and_stationarity_regions_are_not_available";
        vis.valueStatus = "geometry_backed_proxy";
        vis.visibilityMaskSource = "geometry_based_visibility_proxy";
        vis.geometryInputsUsed = strjoin(localNonEmptyStrings([txInputs, rxInputs, "relative_bearing_deg"]), ";");
        vis.placeholderUsed = false;
        vis.complianceStatus = "geometry_based_proxy";

    otherwise
        error("SpatialNonStationarity:UnsupportedMode", ...
            "Unsupported spatial non-stationarity mode '%s'.", char(mode));
end
end

function mode = localResolveMode(cfg, enable)
mode = string(sixgr.util.structGet(cfg, "channel.spatialNonStationary.mode", ""));
mode = lower(strtrim(mode));
if strlength(mode) == 0
    if enable
        mode = "legacy_random_mask_placeholder";
    else
        mode = "disabled";
    end
end
switch mode
    case {"off","none","disabled"}
        mode = "disabled";
    case {"legacy","placeholder","legacy_random_mask_placeholder"}
        mode = "legacy_random_mask_placeholder";
    case {"geometry","geometry_based_visibility"}
        mode = "geometry_based_visibility";
    otherwise
        mode = string(mode);
end
end

function mask = localEnsureClusterVisibility(mask, rs)
for c = 1:size(mask, 1)
    if ~any(mask(c,:))
        mask(c, randi(rs, size(mask, 2))) = true;
    end
end
end

function [centers_lambda, orientation_deg, valid, inputsUsed] = localResolveSubarrayGeometry(meta, nSub, orientationField)
centers_lambda = [];
orientation_deg = NaN;
valid = false;
inputsUsed = "";
if ~(isstruct(meta) && ~isempty(fieldnames(meta)))
    return;
end

nRow = double(sixgr.util.structGet(meta, "NumRows", NaN));
nCol = double(sixgr.util.structGet(meta, "NumCols", NaN));
spacingH = double(sixgr.util.structGet(meta, "SpacingH_lambda", NaN));
spacingV = double(sixgr.util.structGet(meta, "SpacingV_lambda", NaN));
orientation_deg = double(sixgr.util.structGet(meta, orientationField, 0));
if ~isfinite(orientation_deg)
    orientation_deg = 0;
end

if ~(isfinite(nRow) && nRow >= 1 && isfinite(nCol) && nCol >= 1 && isfinite(spacingH) && spacingH > 0 && isfinite(spacingV) && spacingV > 0)
    return;
end

aperture_lambda = max((max(1, round(nCol)) - 1) * spacingH, (max(1, round(nRow)) - 1) * spacingV);
centers_lambda = linspace(-aperture_lambda/2, aperture_lambda/2, max(1, round(nSub)));
valid = all(isfinite(centers_lambda));
inputsUsed = "runtime_array_shape_spacing_orientation";
end

function mask = localGeometryVisibilityMask(clusterAngles_deg, centers_lambda, orientation_deg, pVisible, region_lambda)
nClusters = numel(clusterAngles_deg);
nSub = numel(centers_lambda);
mask = false(nClusters, nSub);
subarrayLook_deg = linspace(-45, 45, max(1, nSub));
baseHalfSpan_deg = max(12, min(80, 18 + 70 * double(pVisible)));
for c = 1:nClusters
    for s = 1:nSub
        angleDiff = abs(localWrapTo180(clusterAngles_deg(c) - (orientation_deg + subarrayLook_deg(s))));
        apertureWeight = exp(-abs(double(centers_lambda(s))) / max(double(region_lambda), eps));
        allowedHalfSpan_deg = baseHalfSpan_deg * (0.55 + 0.45 * apertureWeight);
        mask(c, s) = angleDiff <= allowedHalfSpan_deg;
    end
end
end

function mask = localEnsureNearestVisible(mask, clusterAngles_deg, centers_lambda, orientation_deg)
subarrayLook_deg = linspace(-45, 45, max(1, numel(centers_lambda)));
for c = 1:size(mask, 1)
    if any(mask(c,:))
        continue;
    end
    [~, idx] = min(abs(localWrapTo180(clusterAngles_deg(c) - (orientation_deg + subarrayLook_deg))));
    mask(c, idx) = true;
end
end

function wrapped = localWrapTo180(angle_deg)
wrapped = mod(double(angle_deg) + 180, 360) - 180;
end

function tokens = localNonEmptyStrings(tokensIn)
tokens = string(tokensIn);
tokens = strip(tokens(:));
tokens = tokens(strlength(tokens) > 0);
if isempty(tokens)
    tokens = strings(0,1);
end
end
