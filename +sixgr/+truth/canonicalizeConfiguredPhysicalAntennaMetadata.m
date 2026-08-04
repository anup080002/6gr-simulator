function T = canonicalizeConfiguredPhysicalAntennaMetadata(T, cfg, direction)
%CANONICALIZECONFIGUREDPHYSICALANTENNAMETADATA Bind rows to physical arrays.
% ConfiguredTxAntennas/ConfiguredRxAntennas are physical-element metadata.
% Logical NR ports, RF chains, post-combining branches, and decoded layers
% are reported by their own columns and must never overwrite these fields.

arguments
    T table
    cfg (1,1) struct
    direction {mustBeTextScalar}
end

if isempty(T)
    return;
end

direction = upper(strtrim(string(direction)));
if ~any(direction == ["DL", "UL"])
    error("sixgr:truth:InvalidAntennaMetadataDirection", ...
        "Configured physical antenna metadata requires DL or UL direction.");
end

if direction == "UL"
    txRuntimeColumn = "UEAntennaElements";
    rxRuntimeColumn = "BSAntennaElements";
    txFallback = localFirstCount(cfg, [ ...
        "antenna.ue.numElements", "scenario.ue.nTxAnt", ...
        "channel.ul.nTxAnt", "phy.ul.nTxAnt"]);
    rxFallback = localFirstCount(cfg, [ ...
        "antenna.bs.numElements", "scenario.bs.nRxAnt", ...
        "channel.ul.nRxAnt", "phy.ul.nRxAnt", ...
        "scenario.bs.nTxAnt"]);
else
    txRuntimeColumn = "BSAntennaElements";
    rxRuntimeColumn = "UEAntennaElements";
    txFallback = localFirstCount(cfg, [ ...
        "antenna.bs.numElements", "scenario.bs.nTxAnt", ...
        "channel.nTxAnt", "phy.nTxAnt"]);
    rxFallback = localFirstCount(cfg, [ ...
        "antenna.ue.numElements", "scenario.ue.nRxAnt", ...
        "channel.nRxAnt", "phy.nRxAnt"]);
end

T = localBindColumn(T, "ConfiguredTxAntennas", txRuntimeColumn, txFallback);
T = localBindColumn(T, "ConfiguredRxAntennas", rxRuntimeColumn, rxFallback);
end

function T = localBindColumn(T, targetName, runtimeName, fallback)
n = height(T);
if ismember(targetName, string(T.Properties.VariableNames))
    existing = localNumericColumn(T.(char(targetName)), n);
else
    existing = NaN(n, 1);
end

runtime = NaN(n, 1);
if ismember(runtimeName, string(T.Properties.VariableNames))
    runtime = localNumericColumn(T.(char(runtimeName)), n);
end

resolved = existing;
runtimeMask = isfinite(runtime) & runtime >= 1 & runtime == round(runtime);
resolved(runtimeMask) = runtime(runtimeMask);
fallbackMask = ~runtimeMask & isfinite(fallback) & fallback >= 1;
resolved(fallbackMask) = round(double(fallback));
T.(char(targetName)) = resolved;
end

function values = localNumericColumn(raw, n)
try
    values = double(raw(:));
catch
    values = str2double(string(raw(:)));
end
if numel(values) ~= n
    values = NaN(n, 1);
end
end

function count = localFirstCount(cfg, paths)
count = NaN;
for path = string(paths)
    value = double(sixgr.util.structGet(cfg, path, NaN));
    if isscalar(value) && isfinite(value) && value >= 1 && value == round(value)
        count = value;
        return;
    end
end
end
