function [portSet, source] = resolveScheduledDMRSPortSet(cfg, direction, numLayers, grant)
%RESOLVESCHEDULEDDMRSPORTSET Resolve the exact logical ports for a scheduled rank.

if nargin < 4 || ~isstruct(grant)
    grant = struct();
end
direction = upper(string(direction));
numLayers = double(numLayers);
if ~(isscalar(numLayers) && isfinite(numLayers) && ...
        numLayers >= 1 && numLayers == fix(numLayers))
    error("sixgr:phy:grant:InvalidScheduledLayerCount", ...
        "Scheduled NumLayers must be a positive integer.");
end
if direction == "UL"
    root = "phy.pusch";
    errorID = "sixgr:pusch:InvalidDMRSPortSet";
else
    root = "phy.pdsch";
    errorID = "sixgr:pdsch:InvalidDMRSPortSet";
end

explicitGrantPorts = localFirstNonemptyNumeric( ...
    sixgr.util.structGet(grant, "DMRSPortSet", []), ...
    sixgr.util.structGet(grant, "DMRSPorts", []), ...
    sixgr.util.structGet(grant, "PHYGrant.CodingLayout.DMRSPortSet", []));
if ~isempty(explicitGrantPorts)
    portSet = localValidateExact(explicitGrantPorts, numLayers, errorID);
    source = "explicit_scheduler_grant";
    return;
end

frozenScheduledPorts = localFirstNonemptyNumeric( ...
    sixgr.util.structGet(cfg, root + ".dmrs.scheduledPortSet", []));
if ~isempty(frozenScheduledPorts)
    portSet = localValidateExact(frozenScheduledPorts, numLayers, errorID);
    source = "frozen_phy_grant_dmrs_port_set";
    return;
end

configuredPorts = localFirstNonemptyNumeric( ...
    sixgr.util.structGet(cfg, root + ".dmrs.availablePortSet", []), ...
    sixgr.util.structGet(cfg, root + ".dmrs.portSet", []), ...
    sixgr.util.structGet(cfg, root + ".dmrs.DMRSPortSet", []), ...
    sixgr.util.structGet(cfg, root + ".DMRSPortSet", []));
if isempty(configuredPorts) && direction == "DL"
    configuredPorts = localFirstNonemptyNumeric( ...
        sixgr.util.structGet(cfg, "pdsch6gr.DMRSPortSet", []));
end
if ~isempty(configuredPorts)
    configuredPorts = localValidatePool(configuredPorts, numLayers, errorID);
    portSet = configuredPorts(1:numLayers);
    source = "configured_active_dmrs_port_pool";
    return;
end

configuredPortCount = localFirstFiniteScalar( ...
    sixgr.util.structGet(cfg, root + ".dmrs.nPorts", []), ...
    sixgr.util.structGet(cfg, root + ".numPorts", []), ...
    sixgr.util.structGet(cfg, root + ".nPorts", []), NaN);
if isfinite(configuredPortCount) && configuredPortCount >= numLayers
    portSet = 0:(numLayers - 1);
    source = "configured_dmrs_port_count_standard_logical_order";
    return;
end

strict = logical(sixgr.util.structGet(cfg, "run.strictMode", false)) || ...
    logical(sixgr.util.structGet(cfg, "validation.strict", false));
if strict
    error(errorID, ...
        "Strict scheduled waveform execution requires an explicit DM-RS port set or configured DM-RS port count.");
end
portSet = 0:(numLayers - 1);
source = "non_strict_standard_logical_port_default";
end

function values = localValidateExact(values, numLayers, errorID)
values = localValidatePool(values, numLayers, errorID);
if numel(values) ~= numLayers
    error(errorID, ...
        "An explicit grant DM-RS port set must contain exactly one unique logical port per scheduled layer.");
end
end

function values = localValidatePool(values, numLayers, errorID)
values = double(values(:).');
if any(~isfinite(values)) || any(values ~= fix(values)) || ...
        any(values < 0) || numel(unique(values)) ~= numel(values) || ...
        numel(values) < numLayers
    error(errorID, ...
        "The configured DM-RS port pool must contain at least one unique nonnegative logical port per scheduled layer.");
end
end

function value = localFirstNonemptyNumeric(varargin)
value = [];
for index = 1:nargin
    candidate = varargin{index};
    if isnumeric(candidate) && ~isempty(candidate)
        value = double(candidate);
        return;
    end
end
end

function value = localFirstFiniteScalar(varargin)
value = NaN;
for index = 1:nargin
    candidate = varargin{index};
    if isnumeric(candidate) && isscalar(candidate) && isfinite(double(candidate))
        value = double(candidate);
        return;
    end
end
end
