function state = buildLargeScaleStateCache(cfg, layout, ue, beamIdx, beamGain_dB, plModel, varargin)
% sixgr.system.buildLargeScaleStateCache
% Build or refresh the shared large-scale link-state cache used by SLS.

opt = struct();
opt.NumRB = 1;
opt.PreviousState = struct();
opt.ReusePropagation = false;
opt.IndoorDistance_m = [];

if mod(numel(varargin), 2) ~= 0
    error("sixgr:system:buildLargeScaleStateCache:BadNV", ...
        "Name-value inputs must come in pairs.");
end
for i = 1:2:numel(varargin)
    name = string(varargin{i});
    value = varargin{i+1};
    switch lower(name)
        case "numrb"
            opt.NumRB = double(value);
        case "previousstate"
            opt.PreviousState = value;
        case "reusepropagation"
            opt.ReusePropagation = logical(value);
        case {"indoordistance_m","dindoor_m","dindoor"}
            opt.IndoorDistance_m = double(value);
        otherwise
            error("sixgr:system:buildLargeScaleStateCache:UnknownOpt", ...
                "Unknown option: %s", name);
    end
end

K = size(ue.pos_m, 1);
nCells = size(layout.bs.pos_m, 1);
state = struct();
state.NumUE = K;
state.NumCells = nCells;
state.PropagationScenario = string(sixgr.util.structGet(cfg, "channel.propagationScenario", ...
    sixgr.util.structGet(cfg, "run.scenario", "UMa")));
state.PathlossEnabled = logical(sixgr.util.structGet(cfg, "channel.pathlossEnabled", true));
state.ShadowFadingEnabled = logical(sixgr.util.structGet(cfg, "channel.shadowFadingEnabled", true));
state.LOSEnabled = logical(sixgr.util.structGet(cfg, "channel.losEnabled", true));
state.ChannelComplianceMode = localObjectStringProp(plModel, "ChannelComplianceMode", ...
    string(sixgr.util.structGet(cfg, "channel.complianceMode", "approximate_38901_plus")));
state.PathlossModelSource = "";
state.PathlossComplianceStatus = "";
state.FallbackUsedForPathloss = false;
state.O2IModelSource = "";
state.O2IComplianceStatus = "";
state.O2IComplianceReason = "";
state.LOSProbabilitySource = "";
state.LOSComplianceStatus = "";
state.LOSComplianceReason = "";
state.PropagationReused = logical(opt.ReusePropagation);

txPower_dBm = reshape(double(layout.bs.txPower_dBm), 1, []);
if numel(txPower_dBm) ~= nCells
    txPower_dBm = repmat(txPower_dBm(1), 1, nCells);
end
state.TxPower_dBm = repmat(txPower_dBm, K, 1);

if isempty(beamIdx)
    beamIdx = ones(K, nCells);
end
if isempty(beamGain_dB)
    beamGain_dB = zeros(K, nCells);
end
state.BeamIndex = double(beamIdx);
state.BeamGain_dB = double(beamGain_dB);

indoorUE = localColumnLogical(sixgr.util.structGet(ue, "indoor", false(K, 1)), K);
state.IndoorRx = repmat(indoorUE, 1, nCells);

if isempty(opt.IndoorDistance_m)
    indoorDistance_m = double(sixgr.util.structGet(cfg, "channel.o2i.indoorDistance_m", 10));
else
    indoorDistance_m = double(opt.IndoorDistance_m);
end
if isscalar(indoorDistance_m)
    indoorDistance_m = repmat(indoorDistance_m, K, 1);
else
    indoorDistance_m = reshape(indoorDistance_m, [], 1);
    if numel(indoorDistance_m) ~= K
        error("sixgr:system:buildLargeScaleStateCache:BadIndoorDistance", ...
            "IndoorDistance_m must be scalar or Kx1.");
    end
end
state.IndoorDistance_m = repmat(indoorDistance_m .* double(indoorUE), 1, nCells);

if opt.ReusePropagation
    prev = opt.PreviousState;
    state.d2d_m = double(localRequireSize(prev, "d2d_m", K, nCells));
    state.d3d_m = double(localRequireSize(prev, "d3d_m", K, nCells));
    state.dxy_m = double(localRequireSize(prev, "dxy_m", K, nCells, 2));
    state.LOS = logical(localRequireSize(prev, "LOS", K, nCells));
    state.Shadow_dB = double(localRequireSize(prev, "Shadow_dB", K, nCells));
    state.O2I_dB = double(localRequireSize(prev, "O2I_dB", K, nCells));
    state.BasePathloss_dB = double(localRequireSize(prev, "BasePathloss_dB", K, nCells));
    state.Pathloss_dB = double(localRequireSize(prev, "Pathloss_dB", K, nCells));
else
    [d2d_m, dxy_m] = localDistanceAndDelta(ue.pos_m, layout);
    dz_m = ue.pos_m(:,3) - layout.bs.pos_m(:,3).';
    state.d2d_m = double(d2d_m);
    state.d3d_m = double(sqrt(max(d2d_m.^2 + dz_m.^2, 0)));
    state.dxy_m = double(dxy_m);

    state.LOS = false(K, nCells);
    state.Shadow_dB = zeros(K, nCells);
    state.O2I_dB = zeros(K, nCells);
    state.BasePathloss_dB = zeros(K, nCells);
    state.Pathloss_dB = zeros(K, nCells);

    rxPos = double(ue.pos_m.');
    indoorRow = double(indoorUE(:).');
    indoorDistanceRow = double(indoorDistance_m(:).');
    for c = 1:nCells
        txPos = repmat(double(layout.bs.pos_m(c, :).'), 1, K);
        [pl_dB, los, ex] = plModel.pathloss(txPos, rxPos, ...
            "Scenario", state.PropagationScenario, ...
            "IndoorRx", indoorRow, ...
            "IndoorDistance_m", indoorDistanceRow, ...
            "PathlossEnabled", state.PathlossEnabled, ...
            "ShadowFadingEnabled", state.ShadowFadingEnabled, ...
            "LOSEnabled", state.LOSEnabled);
        state.Pathloss_dB(:, c) = double(pl_dB(:));
        state.LOS(:, c) = logical(los(:));
        state.Shadow_dB(:, c) = double(ex.shadow_dB(:));
        state.O2I_dB(:, c) = double(ex.o2i_dB(:));
        state.BasePathloss_dB(:, c) = double(ex.base_dB(:));
    end
end

state.RxPower_dBm = state.TxPower_dBm + state.BeamGain_dB - state.Pathloss_dB;
state.RSRP_dBm = state.RxPower_dBm - 10*log10(max(12 * max(1, round(double(opt.NumRB))), 1));
state.PathlossModelSource = localObjectStringProp(plModel, "PathlossModelSource", ...
    string(sixgr.util.structGet(opt.PreviousState, "PathlossModelSource", "")));
state.PathlossComplianceStatus = localObjectStringProp(plModel, "PathlossComplianceStatus", ...
    string(sixgr.util.structGet(opt.PreviousState, "PathlossComplianceStatus", "")));
state.FallbackUsedForPathloss = localObjectLogicalProp(plModel, "FallbackUsedForPathloss", ...
    logical(sixgr.util.structGet(opt.PreviousState, "FallbackUsedForPathloss", false)));
state.O2IModelSource = localObjectStringProp(plModel, "O2IModelSource", ...
    string(sixgr.util.structGet(opt.PreviousState, "O2IModelSource", "")));
state.O2IComplianceStatus = localObjectStringProp(plModel, "O2IComplianceStatus", ...
    string(sixgr.util.structGet(opt.PreviousState, "O2IComplianceStatus", "")));
state.O2IComplianceReason = localObjectStringProp(plModel, "O2IComplianceReason", ...
    string(sixgr.util.structGet(opt.PreviousState, "O2IComplianceReason", "")));
state.LOSProbabilitySource = localObjectStringProp(plModel, "LOSProbabilitySource", ...
    string(sixgr.util.structGet(opt.PreviousState, "LOSProbabilitySource", "")));
state.LOSComplianceStatus = localObjectStringProp(plModel, "LOSComplianceStatus", ...
    string(sixgr.util.structGet(opt.PreviousState, "LOSComplianceStatus", "")));
state.LOSComplianceReason = localObjectStringProp(plModel, "LOSComplianceReason", ...
    string(sixgr.util.structGet(opt.PreviousState, "LOSComplianceReason", "")));
end

function [d2d_m, dxy_m] = localDistanceAndDelta(uePos_m, layout)
bsPos_m = double(layout.bs.pos_m);
wrapEn = logical(sixgr.util.structGet(layout, "wraparoundEnabled", false));
area_m = double(sixgr.util.structGet(layout, "area_m", [0 0]));
wrapMode = string(sixgr.util.structGet(layout, "wraparoundMode", "rectangular_torus"));
if wrapEn && wrapMode ~= "disabled"
    [d2d_m, dxy_m] = sixgr.scenario.wraparoundDistance(uePos_m, bsPos_m, area_m, ...
        "Mode", wrapMode, "ISD_m", double(sixgr.util.structGet(layout, "isd_m", NaN)));
    return;
end

dx = uePos_m(:,1) - bsPos_m(:,1).';
dy = uePos_m(:,2) - bsPos_m(:,2).';
d2d_m = sqrt(dx.^2 + dy.^2);
dxy_m = zeros(size(dx,1), size(dx,2), 2);
dxy_m(:,:,1) = dx;
dxy_m(:,:,2) = dy;
end

function value = localRequireSize(s, fieldName, varargin)
if ~isstruct(s) || ~isfield(s, fieldName)
    error("sixgr:system:buildLargeScaleStateCache:MissingPreviousState", ...
        "PreviousState.%s is required when ReusePropagation=true.", fieldName);
end
value = s.(fieldName);
expected = cell2mat(varargin);
if ~isequal(size(value), expected)
    error("sixgr:system:buildLargeScaleStateCache:BadPreviousStateShape", ...
        "PreviousState.%s must have size %s.", fieldName, mat2str(expected));
end
end

function out = localColumnLogical(value, K)
if isscalar(value)
    out = repmat(logical(value), K, 1);
    return;
end
out = reshape(logical(value), [], 1);
if numel(out) ~= K
    error("sixgr:system:buildLargeScaleStateCache:BadIndoorMask", ...
        "UE indoor mask must be scalar or Kx1.");
end
end

function value = localObjectStringProp(obj, propName, fallback)
value = string(fallback);
if ~isempty(obj) && isobject(obj) && isprop(obj, propName)
    value = string(obj.(propName));
end
end

function value = localObjectLogicalProp(obj, propName, fallback)
value = logical(fallback);
if ~isempty(obj) && isobject(obj) && isprop(obj, propName)
    value = logical(obj.(propName));
end
end
