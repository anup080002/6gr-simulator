function nPorts = resolveDLLogicalPortCount(cfg, grant, nLayers)
%RESOLVEDLLOGICALPORTCOUNT Resolve the authoritative NR PDSCH port domain.
%
% Logical ports and transmitted layers are different dimensions. A
% two-user rank-2 MU occasion, for example, uses four logical ports while
% each member still carries two layers. A finalized grant is authoritative;
% otherwise an explicit PDSCH port configuration precedes layer ceilings.

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if nargin < 2 || ~isstruct(grant)
    grant = struct();
end
if nargin < 3 || ~(isnumeric(nLayers) && isscalar(nLayers) && ...
        isfinite(double(nLayers)) && double(nLayers) >= 1)
    nLayers = 1;
end
nLayers = max(1, round(double(nLayers)));
maxPorts = 32;

[grantPorts, grantPath] = localFirstConfiguredPort(grant, ...
    ["NumLogicalPorts", "PortCount"]);
if isfinite(grantPorts)
    nPorts = localValidatePortCount(grantPorts, nLayers, maxPorts, ...
        "finalized grant " + grantPath, ...
        "sixgr:phy:grant:GrantLogicalPortCountOutOfRange");
    return;
end

% Exact logical-port declarations must precede rank/layer capability
% fields: maxDLLayers=2 does not reduce an explicit four-port MU baseband
% architecture to two ports.
[configuredPorts, configuredPath] = localFirstConfiguredPort(cfg, [ ...
    "phy.pdsch.numPorts", ...
    "phy.pdsch.nPorts", ...
    "phy.pdsch.NumAntennaPorts", ...
    "phy.pdsch.numAntennaPorts", ...
    "phy.pdsch.dmrs.nPorts"]);
if isfinite(configuredPorts)
    nPorts = localValidatePortCount(configuredPorts, nLayers, maxPorts, ...
        "configuration " + configuredPath, ...
        "sixgr:phy:grant:ConfiguredLogicalPortCountOutOfRange");
    return;
end

% A layer ceiling is only a compatibility fallback when no exact logical
% port declaration exists.
[capabilityPorts, ~] = localFirstConfiguredPort(cfg, [ ...
    "phy.maxDLLayers", ...
    "phy.pdsch.maxLayers", ...
    "phy.pdsch.numLayers", ...
    "phy.pdsch.nLayers"]);
if isfinite(capabilityPorts) && capabilityPorts >= nLayers && ...
        capabilityPorts <= maxPorts
    nPorts = round(double(capabilityPorts));
else
    nPorts = nLayers;
end
end

function [value, source] = localFirstConfiguredPort(data, paths)
value = NaN;
source = "";
for index = 1:numel(paths)
    candidate = sixgr.util.structGet(data, paths(index), []);
    if isnumeric(candidate) && isscalar(candidate) && ...
            isfinite(double(candidate))
        value = double(candidate);
        source = string(paths(index));
        return;
    end
end
end

function value = localValidatePortCount(value, nLayers, maxPorts, source, errorId)
value = double(value);
if value ~= fix(value) || value < nLayers || value > maxPorts
    error(char(errorId), ...
        "%s declares %.17g logical port(s); expected an integer in [%d,%d].", ...
        char(source), value, nLayers, maxPorts);
end
value = round(value);
end
