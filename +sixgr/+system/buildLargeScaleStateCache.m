function state = buildLargeScaleStateCache(cfg, layout, ue, beamIdx, beamGain_dB, plModel, varargin)
% sixgr.system.buildLargeScaleStateCache
% Build or refresh the shared large-scale link-state cache used by SLS.

opt = struct();
opt.NumRB = 1;
opt.PreviousState = struct();
opt.ReusePropagation = false;
opt.IndoorDistance_m = [];

if mod(numel(varargin), 2) ~= 0
    error("sixgr:system:buildLargeScaleStateCache:BadNV", "Name-value inputs must come in pairs.");
end
for i = 1:2:numel(varargin)
    name = string(varargin{i}); value = varargin{i+1};
    switch lower(name)
        case "numrb", opt.NumRB = double(value);
        case "previousstate", opt.PreviousState = value;
        case "reusepropagation", opt.ReusePropagation = logical(value);
        case {"indoordistance_m","dindoor_m","dindoor"}, opt.IndoorDistance_m = double(value);
        otherwise, error("sixgr:system:buildLargeScaleStateCache:UnknownOpt", "Unknown option: %s", name);
    end
end

K = size(ue.pos_m, 1); nCells = size(layout.bs.pos_m, 1);
state = struct();
state.NumUE = K; state.NumCells = nCells;
state.PropagationScenario = string(sixgr.util.structGet(cfg, "channel.propagationScenario", sixgr.util.structGet(cfg, "run.scenario", "UMa")));
state.PathlossEnabled = logical(sixgr.util.structGet(cfg, "channel.pathlossEnabled", false));
state.ShadowFadingEnabled = logical(sixgr.util.structGet(cfg, "channel.shadowFadingEnabled", false));
state.LOSEnabled = logical(sixgr.util.structGet(cfg, "channel.losEnabled", false));
state.ChannelComplianceMode = localObjectStringProp(plModel, "ChannelComplianceMode", string(sixgr.util.structGet(cfg, "channel.complianceMode", "approximate_38901_plus")));
state.PathlossModelSource = ""; state.PathlossComplianceStatus = ""; state.FallbackUsedForPathloss = false;
state.O2IModelSource = ""; state.O2IComplianceStatus = ""; state.O2IComplianceReason = "";
state.LOSProbabilitySource = ""; state.LOSComplianceStatus = ""; state.LOSComplianceReason = "";
state.PropagationReused = logical(opt.ReusePropagation);

txPower_dBm = reshape(double(layout.bs.txPower_dBm), 1, []);
if numel(txPower_dBm) ~= nCells, txPower_dBm = repmat(txPower_dBm(1), 1, nCells); end
state.TxPower_dBm = repmat(txPower_dBm, K, 1);
if isempty(beamIdx), beamIdx = ones(K, nCells); end
if isempty(beamGain_dB), beamGain_dB = zeros(K, nCells); end
state.BeamIndex = double(beamIdx); state.BeamGain_dB = double(beamGain_dB);

geom = sixgr.system.GeometryEngine.buildLargeScaleState(cfg, layout, ue, plModel, ...
    "PreviousState", opt.PreviousState, "ReusePropagation", opt.ReusePropagation, "IndoorDistance_m", opt.IndoorDistance_m);
geomFields = fieldnames(geom);
for i = 1:numel(geomFields)
    state.(geomFields{i}) = geom.(geomFields{i});
end

rsrpRECount = max(12 * max(1, round(double(opt.NumRB))), 1);
state.RxPower_dBm = state.TxPower_dBm + state.BeamGain_dB - state.Pathloss_dB;
state.RSRP_dBm = state.RxPower_dBm - 10*log10(rsrpRECount);
state.RSRPPerRE_dBm = state.RSRP_dBm;
state.WidebandRxPower_dBm = state.RxPower_dBm;
state.RSRPNormalizationRECount = repmat(double(rsrpRECount), K, nCells);
state.RSRPConvention = "per_reference_resource_element_power";
state.RSRPPerREConvention = "per_reference_resource_element_power";
state.PathlossModelSource = localObjectStringProp(plModel, "PathlossModelSource", string(sixgr.util.structGet(opt.PreviousState, "PathlossModelSource", string(sixgr.util.structGet(state, "PathlossModelSource", "")))));
state.PathlossComplianceStatus = localObjectStringProp(plModel, "PathlossComplianceStatus", string(sixgr.util.structGet(opt.PreviousState, "PathlossComplianceStatus", string(sixgr.util.structGet(state, "PathlossComplianceStatus", "")))));
state.FallbackUsedForPathloss = localObjectLogicalProp(plModel, "FallbackUsedForPathloss", logical(sixgr.util.structGet(opt.PreviousState, "FallbackUsedForPathloss", logical(sixgr.util.structGet(state, "FallbackUsedForPathloss", false)))));
state.O2IModelSource = localObjectStringProp(plModel, "O2IModelSource", string(sixgr.util.structGet(opt.PreviousState, "O2IModelSource", string(sixgr.util.structGet(state, "O2IModelSource", "")))));
state.O2IComplianceStatus = localObjectStringProp(plModel, "O2IComplianceStatus", string(sixgr.util.structGet(opt.PreviousState, "O2IComplianceStatus", string(sixgr.util.structGet(state, "O2IComplianceStatus", "")))));
state.O2IComplianceReason = localObjectStringProp(plModel, "O2IComplianceReason", string(sixgr.util.structGet(opt.PreviousState, "O2IComplianceReason", string(sixgr.util.structGet(state, "O2IComplianceReason", "")))));
state.LOSProbabilitySource = localObjectStringProp(plModel, "LOSProbabilitySource", string(sixgr.util.structGet(opt.PreviousState, "LOSProbabilitySource", string(sixgr.util.structGet(state, "LOSProbabilitySource", "")))));
state.LOSComplianceStatus = localObjectStringProp(plModel, "LOSComplianceStatus", string(sixgr.util.structGet(opt.PreviousState, "LOSComplianceStatus", string(sixgr.util.structGet(state, "LOSComplianceStatus", "")))));
state.LOSComplianceReason = localObjectStringProp(plModel, "LOSComplianceReason", string(sixgr.util.structGet(opt.PreviousState, "LOSComplianceReason", string(sixgr.util.structGet(state, "LOSComplianceReason", "")))));
end

function value = localObjectStringProp(obj, propName, fallback)
value = string(fallback);
if ~isempty(obj) && isobject(obj) && isprop(obj, propName), value = string(obj.(propName)); end
end

function value = localObjectLogicalProp(obj, propName, fallback)
value = logical(fallback);
if ~isempty(obj) && isobject(obj) && isprop(obj, propName), value = logical(obj.(propName)); end
end
