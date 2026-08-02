function [enabled, portSet, source] = resolveScheduledPTRSPortSet( ...
        cfg, direction, dmrsPortSet, grant)
%RESOLVESCHEDULEDPTRSPORTSET Resolve YAML-owned PT-RS port association.
% PT-RS presence remains a scenario feature decision. When enabled, this
% resolver binds the configured association policy to the exact scheduled
% DM-RS ports and returns the value that must be frozen into the PHYGrant.

if nargin < 4 || ~isstruct(grant)
    grant = struct();
end
direction = upper(strtrim(string(direction)));
if direction == "UL"
    root = "phy.pusch";
elseif direction == "DL"
    root = "phy.pdsch";
else
    error("sixgr:phy:grant:InvalidPTRSDirection", ...
        "Scheduled PT-RS direction must be DL or UL.");
end

enabled = logical(sixgr.util.structGet(cfg, root + ".enablePTRS", ...
    sixgr.util.structGet(cfg, "phy.ptrs.enable", false)));
sixgr.config.assertRuntimeFeatureUse(cfg, "ptrs", enabled, ...
    "freezePHYGrant:" + direction + ":PTRS");
portSet = zeros(1,0);
if ~enabled
    source = "yaml_feature_disabled";
    return;
end

dmrsPortSet = localPortVector(dmrsPortSet, ...
    "sixgr:phy:grant:InvalidScheduledDMRSPortSet", ...
    "Scheduled PT-RS requires a finite non-empty DM-RS port set.");
policy = lower(strtrim(string(sixgr.util.structGet(cfg, ...
    root + ".ptrs.portAssociationPolicy", sixgr.util.structGet(cfg, ...
    "phy.ptrs.portAssociationPolicy", sixgr.util.structGet(cfg, ...
    "referenceSignals.ptrsPortAssociationPolicy", ""))))));
if policy == "first_scheduled_dmrs_port"
    % A top-level grant can carry a port copied from an earlier frozen
    % opportunity. It is evidence, not a second configuration authority.
    % Re-derive the current port from the YAML policy and current DM-RS set.
    portSet = double(dmrsPortSet(1));
    source = "yaml_policy_first_scheduled_dmrs_port";
    return;
end
if strlength(policy) > 0 && policy ~= "configured_absolute_port"
    error("sixgr:phy:grant:InvalidPTRSPortAssociationPolicy", ...
        "Unsupported PT-RS port association policy '%s'.", char(policy));
end

configuredPorts = sixgr.util.structGet(cfg, root + ".ptrs.portSet", []);
if isempty(configuredPorts) && direction == "DL"
    configuredPorts = sixgr.util.structGet(cfg, ...
        "pdsch6gr.PTRSPortSet", []);
end
if isempty(configuredPorts)
    error("sixgr:phy:grant:MissingPTRSPortAssociation", ...
        ['YAML enables %s PT-RS with configured_absolute_port but does not ' ...
         'provide an absolute PT-RS port.'], char(direction));
end
portSet = localAssociatedPort(configuredPorts, dmrsPortSet, ...
    "configured_absolute_port");
source = "yaml_configured_absolute_port";
end

function portSet = localAssociatedPort(raw, dmrsPortSet, source)
portSet = localPortVector(raw, ...
    "sixgr:phy:grant:InvalidPTRSPortSet", ...
    "PT-RS port set must contain one finite nonnegative integer.");
if numel(portSet) ~= 1 || ~ismember(portSet, dmrsPortSet)
    error("sixgr:phy:grant:PTRSPortNotInScheduledDMRS", ...
        ['PT-RS association from %s is %s, but the scheduled DM-RS ports ' ...
         'are %s. Configure first_scheduled_dmrs_port for disjoint MU ports ' ...
         'or provide an exact compatible absolute port.'], ...
        char(source), mat2str(portSet), mat2str(dmrsPortSet));
end
end

function values = localPortVector(raw, id, message)
if ~(isnumeric(raw) || islogical(raw)) || isempty(raw)
    error(id, "%s", message);
end
values = double(raw(:).');
if any(~isfinite(values)) || any(values ~= fix(values)) || ...
        any(values < 0) || numel(unique(values)) ~= numel(values)
    error(id, "%s", message);
end
end
