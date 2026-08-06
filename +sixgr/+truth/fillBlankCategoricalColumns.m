function T = fillBlankCategoricalColumns(T, scopeToken)
%FILLBLANKCATEGORICALCOLUMNS Decorate semantics without altering identity.

if ~(istable(T) && ~isempty(T))
    return;
end
scopeToken = lower(regexprep(char(string(scopeToken)), "[^a-z0-9]+", "_"));
names = string(T.Properties.VariableNames);
for index = 1:numel(names)
    fieldName = char(names(index));
    if sixgr.truth.isImmutableIdentityField(fieldName)
        % Blank identity remains blank so fail-closed validation can see it.
        continue;
    end
    rawColumn = T.(fieldName);
    if ~(isstring(rawColumn) || ischar(rawColumn) || iscell(rawColumn) || ...
            iscategorical(rawColumn) || localSemanticCategoricalField(fieldName, rawColumn))
        continue;
    end
    values = string(rawColumn);
    normalized = lower(strtrim(fillmissing(values, "constant", "")));
    blank = ismissing(values) | strlength(normalized) == 0 | ...
        normalized == "nan" | normalized == "<missing>";
    if ~any(blank)
        continue;
    end
    token = localBlankToken(fieldName, scopeToken);
    if strlength(token) == 0
        continue;
    end
    values(blank) = token;
    T.(fieldName) = values;
end
end

function token = localBlankToken(fieldName, scopeToken)
name = lower(char(string(fieldName)));
if strcmp(name, "usedoraclefields")
    token = "";
elseif endsWith(name, "source")
    token = "not_emitted_by_active_" + string(scopeToken) + "_runtime";
elseif endsWith(name, "valuerole")
    token = "not_available";
elseif endsWith(name, "valuestatus")
    token = "not_emitted_by_active_" + string(scopeToken) + "_runtime";
elseif endsWith(name, "nareason") || strcmp(name, "nareason") || ...
        strcmp(name, "unavailablereason")
    token = "field_not_emitted_by_active_" + string(scopeToken) + "_runtime";
elseif contains(name, "blocker")
    token = "not_blocked_in_active_" + string(scopeToken) + "_runtime";
elseif contains(name, "definition")
    token = "not_emitted_by_active_" + string(scopeToken) + "_runtime";
elseif contains(name, "authority")
    token = "not_recorded_by_active_" + string(scopeToken) + "_runtime";
else
    token = "not_applicable_for_active_" + string(scopeToken) + "_runtime";
end
end

function tf = localSemanticCategoricalField(fieldName, rawColumn)
if isstring(rawColumn) || ischar(rawColumn) || iscell(rawColumn) || iscategorical(rawColumn)
    tf = true;
    return;
end
if ~(isnumeric(rawColumn) || islogical(rawColumn))
    tf = false;
    return;
end
name = lower(char(string(fieldName)));
numericHints = ["_db", "db", "_hz", "hz", "_deg", "deg", "_ms", ...
    "ms", "_s", "_bits", "bits", "_bytes", "bytes", "count", ...
    "index", "slot", "frame", "time", "cellid", "ueid", "ueindex", ...
    "rnti", "rank", "layers", "ports", "prb", "rb", "resourceid", ...
    "setid", "iterations", "power", "gain", "ratio", "correlation", ...
    "probability", "rate", "latency", "throughput", "error"];
if any(contains(name, numericHints))
    tf = false;
    return;
end
semanticHints = ["source", "valuerole", "valuestatus", "nareason", ...
    "unavailablereason", "definition", "availability", "modulation", ...
    "mode", "policy", "strategy", "table", "type", "hex", "consumer", ...
    "classification", "materialization", "gating", "blocker", "authority", ...
    "beam", "precoder", "interferer", "tracking", "outcome"];
semanticExact = ["cqitable", "mcstable", "pmitype", "pmicodebookmode", ...
    "csireportmode", "csipayloadhex", "iqimbalancemodel", ...
    "iqimbalancemeasurementsource", "iqimbalancemeasurementstatus", ...
    "measuredtrialsinrsource", "largescalesinrsource", "servingrsrpsource", ...
    "csi_rsrpsource", "appliedlargescalegainsource", "interferencemode", ...
    "requestedvsappliedprecoderpmimatchstatus"];
tf = any(strcmp(name, semanticExact)) || any(contains(name, semanticHints));
end
