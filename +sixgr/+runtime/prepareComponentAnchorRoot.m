function anchorRoot = prepareComponentAnchorRoot(runFolder, component, scfg, cfg)
%PREPARECOMPONENTANCHORROOT Isolate supplemental evidence from in-path truth.

runFolder = char(string(runFolder));
component = lower(strtrim(string(component)));
if ~isscalar(component) || strlength(component) == 0 || ...
        isempty(regexp(char(component), '^[a-z0-9_]+$', 'once'))
    error("sixgr:runtime:InvalidComponentAnchorName", ...
        "Component anchor names must match [a-z0-9_]+.");
end
anchorRoot = fullfile(runFolder, "component_anchors", char(component));
sixgr.util.ensureFolder(anchorRoot);

scenarioId = string(sixgr.util.structGet(cfg, "meta.scenarioID", ...
    sixgr.util.structGet(cfg, "run.scenarioID", "")));
configHash = string(sixgr.util.structGet(cfg, "meta.configHash", ""));
if isobject(scfg)
    if isprop(scfg, "ScenarioID")
        scenarioId = string(scfg.ScenarioID);
    end
    if isprop(scfg, "ConfigHash")
        configHash = string(scfg.ConfigHash);
    end
end
identity = struct( ...
    "SchemaName", "sixgr.component_anchor_identity", ...
    "SchemaVersion", "1.0.0", ...
    "Component", char(component), ...
    "EvidenceScope", "component_anchor", ...
    "SameScenarioInPathEligible", false, ...
    "ParentScenarioID", char(scenarioId), ...
    "ParentConfigHash", char(configHash), ...
    "CenterFrequencyHz", localFirstFinite(cfg, [ ...
        "frequency.center_frequency_hz", "carrier_frequency_hz", ...
        "channel.center_frequency_hz", "phy.carrier.CarrierFrequencyHz"]), ...
    "BandwidthHz", localFirstFiniteScaled(cfg, [ ...
        "frequency.channel_bandwidth_hz", "channel_bandwidth_hz"], [1 1]), ...
    "SubcarrierSpacingHz", localFirstFiniteScaled(cfg, [ ...
        "numerology.subcarrier_spacing_hz", "subcarrier_spacing_hz", ...
        "phy.carrier.SubcarrierSpacing"], [1 1 1e3]));
if ~isfinite(identity.BandwidthHz)
    identity.BandwidthHz = localFirstFiniteScaled(cfg, [ ...
        "frequency.channel_bandwidth_mhz", "channel_bandwidth_mhz", ...
        "bandwidth_mhz"], [1e6 1e6 1e6]);
end
sixgr.util.jsonWrite(fullfile(anchorRoot, "component_anchor_identity.json"), identity);
end

function value = localFirstFinite(cfg, paths)
value = NaN;
for path = string(paths(:)).'
    candidate = double(sixgr.util.structGet(cfg, path, NaN));
    if isscalar(candidate) && isfinite(candidate)
        value = candidate;
        return;
    end
end
end

function value = localFirstFiniteScaled(cfg, paths, scales)
value = NaN;
paths = string(paths(:));
scales = double(scales(:));
for index = 1:numel(paths)
    candidate = double(sixgr.util.structGet(cfg, paths(index), NaN));
    if isscalar(candidate) && isfinite(candidate)
        value = candidate * scales(index);
        return;
    end
end
end
