function gate = buildPDCCHGrantBindingEvidence(controlTrials, cfg, dlTrials, ulTrials, requiredDataDirections)
if nargin < 5 || ~isstruct(requiredDataDirections)
    requiredDataDirections = struct("DL", true, "UL", true);
end
controlRows = localPDCCHGrantBindingRowsFromControlTrials(controlTrials, cfg);
dataRows = localPDCCHGrantBindingRowsFromDataTrials(dlTrials, ulTrials, cfg);
dataRows = localEnforcePDCCHGrantBindingEvidenceCompleteness(dataRows);

if height(controlRows) > 0 && height(dataRows) > 0
    controlKeys = localPDCCHGrantBindingEvidenceKeys(controlRows);
    dataKeys = localPDCCHGrantBindingEvidenceKeys(dataRows);
    [duplicate,controlIndex] = ismember(dataKeys,controlKeys);
    for dataIndex = find(duplicate).'
        targetIndex = controlIndex(dataIndex);
        % Deduplicate counts, never contradictory receiver evidence. A
        % valid control row cannot rescue a data row that lost its CRC.
        if string(dataRows.BindingStatus(dataIndex)) ~= "bound"
            failures = localSplitBindingFailureCodes(controlRows.FailureCode(targetIndex));
            failures(end+1,1) = "data_trial_" + string(dataRows.FailureCode(dataIndex));
            controlRows.BindingStatus(targetIndex) = "failed";
            controlRows.FailureCode(targetIndex) = strjoin(unique(failures,'stable'),'|');
        elseif string(controlRows.BindingStatus(targetIndex)) == "bound"
            names = {'DCIId','DCIFieldsHash','GrantFieldsHash','RNTI','UeId','CellId'};
            for fieldIndex = 1:numel(names)
                name = names{fieldIndex};
                if ~isequaln(controlRows.(name)(targetIndex),dataRows.(name)(dataIndex))
                    controlRows.BindingStatus(targetIndex) = "failed";
                    controlRows.FailureCode(targetIndex) = "control_data_evidence_identity_mismatch";
                    break;
                end
            end
        end
    end
    dataRows = dataRows(~ismember(dataKeys, controlKeys), :);
end
rows = [controlRows; dataRows];
if ~(istable(rows) && height(rows) > 0)
    rows = localEmptyPDCCHGrantBindingEvidenceTable();
end
rows = localEnforcePDCCHGrantBindingEvidenceCompleteness(rows);

requiredDirections = strings(0, 1);
if logical(sixgr.util.structGet(requiredDataDirections, "DL", false)) && ...
        sixgr.control.isPDCCHGrantBindingRequired(cfg, "DL")
    requiredDirections(end+1, 1) = "DL"; %#ok<AGROW>
end
if logical(sixgr.util.structGet(requiredDataDirections, "UL", false)) && ...
        sixgr.control.isPDCCHGrantBindingRequired(cfg, "UL")
    requiredDirections(end+1, 1) = "UL"; %#ok<AGROW>
end
boundMask = lower(strtrim(string(localColumnOrDefault(rows, "BindingStatus", "")))) == "bound";
failingMask = ~boundMask;
failureReasons = unique(string(localColumnOrDefault(rows(failingMask, :), "FailureCode", "")), "stable");
failureReasons = failureReasons(strlength(strtrim(failureReasons)) > 0);
if isempty(failureReasons) && any(failingMask)
    failureReasons = "grant_binding_failed";
end
rowDirections = upper(strtrim(string(localColumnOrDefault(rows, "Direction", ""))));
directionEvidenceCounts = zeros(numel(requiredDirections), 1);
for requiredDirectionIdx = 1:numel(requiredDirections)
    directionEvidenceCounts(requiredDirectionIdx) = nnz( ...
        rowDirections == requiredDirections(requiredDirectionIdx));
end
missingRequiredDirections = requiredDirections(directionEvidenceCounts == 0);
for missingDirectionIdx = 1:numel(missingRequiredDirections)
    failureReasons(end+1, 1) = ...
        "missing_required_grant_binding_evidence_" + ...
        lower(missingRequiredDirections(missingDirectionIdx)); %#ok<AGROW>
end
failureReasons = unique(failureReasons, "stable");

gate = struct();
gate.Required = ~isempty(requiredDirections);
gate.RequiredDirections = requiredDirections;
gate.RequiredDirectionEvidenceCounts = directionEvidenceCounts;
gate.MissingRequiredDirections = missingRequiredDirections;
gate.RequiredGrantCount = double(height(rows));
gate.FailingGrantCount = double(nnz(failingMask));
gate.BindingGateOk = ~gate.Required || ...
    (gate.RequiredGrantCount > 0 && gate.FailingGrantCount == 0 && ...
    isempty(gate.MissingRequiredDirections));
if gate.Required && gate.RequiredGrantCount == 0
    failureReasons = "missing_required_grant_binding_evidence";
end
gate.FailureReasons = failureReasons(:);
gate.Rows = rows;
gate.Summary = struct( ...
    "Required", logical(gate.Required), ...
    "RequiredDirections", requiredDirections, ...
    "RequiredDirectionEvidenceCounts", directionEvidenceCounts, ...
    "MissingRequiredDirections", missingRequiredDirections, ...
    "RequiredGrantCount", double(gate.RequiredGrantCount), ...
    "FailingGrantCount", double(gate.FailingGrantCount), ...
    "BindingGateOk", logical(gate.BindingGateOk), ...
    "FailureReasons", gate.FailureReasons, ...
    "EvidenceSource", "reports/csv/pdcch_grant_binding_evidence.csv");
end


function T = localEnforcePDCCHGrantBindingEvidenceCompleteness(T)
if ~(istable(T) && height(T) > 0)
    return;
end

bindingStatus = lower(strtrim(string(localColumnOrDefault(T, "BindingStatus", ""))));
failureCode = string(localColumnOrDefault(T, "FailureCode", ""));
grantIds = localFirstStringOrNumericAsString(T, ["GrantId"]);
dciIds = localFirstStringOrNumericAsString(T, ["DCIId"]);
dciHashes = localFirstStringOrNumericAsString(T, ["DCIFieldsHash"]);
grantHashes = localFirstStringOrNumericAsString(T, ["GrantFieldsHash"]);
decodedCrcOk = localColumnBoolDefault(T, "DecodedPDCCHCRCOK", false);

for ii = 1:height(T)
    failures = localSplitBindingFailureCodes(failureCode(ii));
    if strlength(strtrim(grantIds(ii))) == 0
        failures(end+1, 1) = "grant_id_missing"; %#ok<AGROW>
    end
    if strlength(strtrim(dciIds(ii))) == 0
        failures(end+1, 1) = "decoded_dci_missing"; %#ok<AGROW>
    end
    if ~decodedCrcOk(ii)
        failures(end+1, 1) = "decoded_dci_crc_failed"; %#ok<AGROW>
    end
    if strlength(strtrim(dciHashes(ii))) == 0
        failures(end+1, 1) = "decoded_dci_fields_hash_missing"; %#ok<AGROW>
    end
    if strlength(strtrim(grantHashes(ii))) == 0
        failures(end+1, 1) = "grant_fields_hash_missing"; %#ok<AGROW>
    end
    if strlength(strtrim(dciHashes(ii))) > 0 && strlength(strtrim(grantHashes(ii))) > 0 && ...
            string(dciHashes(ii)) ~= string(grantHashes(ii))
        failures(end+1, 1) = "dci_grant_fields_hash_mismatch"; %#ok<AGROW>
    end

    failures = unique(failures(strlength(strtrim(failures)) > 0), "stable");
    if isempty(failures)
        if strlength(bindingStatus(ii)) == 0
            bindingStatus(ii) = "bound";
        end
        if bindingStatus(ii) ~= "bound"
            failures = "grant_binding_failed";
        end
    end
    if ~isempty(failures)
        bindingStatus(ii) = "failed";
        failureCode(ii) = strjoin(failures, "|");
    end
end

T.BindingStatus = bindingStatus;
T.FailureCode = failureCode;
end

function failures = localSplitBindingFailureCodes(raw)
raw = strtrim(string(raw));
if strlength(raw) == 0
    failures = strings(0, 1);
else
    failures = split(raw, "|");
    failures = failures(strlength(strtrim(failures)) > 0);
end
failures = string(failures(:));
end

function T = localPDCCHGrantBindingRowsFromControlTrials(controlT, cfg)
T = localEmptyPDCCHGrantBindingEvidenceTable();
if ~(istable(controlT) && height(controlT) > 0)
    return;
end

directions = upper(localFirstStringColumn(controlT, ["LinkedPDSCHOrPUSCH", "Direction"]));
grantIds = localFirstStringOrNumericAsString(controlT, ["GrantContextId", "LinkedGrantId", "GrantId"]);
explicitRequired = localColumnBoolDefault(controlT, "GrantBindingRequired", false);
requiredMask = localPDCCHGrantBindingRequiredMask(cfg, directions, explicitRequired);
bindingOk = localColumnBoolDefault(controlT, "GrantBindingOk", false);
bindingStatus = localFirstStringOrNumericAsString(controlT, ["GrantBindingStatus"]);
bindingStatus(bindingOk & strlength(strtrim(bindingStatus)) == 0) = "bound";
bindingStatus(~bindingOk & strlength(strtrim(bindingStatus)) == 0) = "failed";
failureCode = localFirstStringOrNumericAsString(controlT, ["GrantBindingFailureCode"]);
failureCode(~bindingOk & strlength(strtrim(failureCode)) == 0 & strlength(strtrim(grantIds)) == 0) = "grant_id_missing";
failureCode(~bindingOk & strlength(strtrim(failureCode)) == 0 & strlength(strtrim(grantIds)) > 0) = "grant_binding_failed";

% Standalone PDCCH positive/negative conformance trials share this table but
% do not schedule PDSCH/PUSCH and therefore are not grant-binding evidence.
% Only rows explicitly marked by the runtime binding producer, or rows with
% a concrete linked grant identity, belong in this gate. Configuration-level
% PDCCH requirements must not turn every blind-search trial into a missing
% scheduler grant.
schedulerBindingRow = explicitRequired | strlength(strtrim(grantIds)) > 0;
linkedDataDirection = ismember(directions, ["DL","UL"]);
% A scheduler candidate that was conclusively blocked before transmission
% is a control-resource disposition, not a decoded-DCI/grant binding trial.
% Exclude only rows whose receiver observation is known not to have run.
% Observed trials remain in the gate even when decoding was not attempted or
% failed, so a real receiver failure cannot be hidden by this distinction.
execution = sixgr.link.pdcchTrialExecutionState(controlT);
mask = requiredMask & schedulerBindingRow & linkedDataDirection & ...
    logical(execution.ObservationAvailable);
if ~any(mask)
    return;
end

cellId = localFirstNumericColumn(controlT, ["BaseStationID", "ServingCell"]);
ueId = localFirstNumericColumn(controlT, ["UEID", "UEIndex"]);
canonicalSlot = localFirstNumericColumn(controlT, ["GrantSlot", "Slot", "ControlSlot"]);
harqProcessId = localFirstNumericColumn(controlT, ["HARQProcessId", "HARQProcess"]);
rnti = localFirstNumericColumn(controlT, ["PDCCHDCICrcRNTI", "RNTI"]);
searchSpaceId = localFirstNumericColumn(controlT, ["SearchSpaceId"]);
coresetId = localFirstNumericColumn(controlT, ["CORESETId"]);
aggregationLevel = localFirstNumericColumn(controlT, ["AggregationLevel"]);
candidateIndex = localFirstNumericColumn(controlT, ["CandidateIndex", "PDCCHCandidateIndex"]);
dciFormat = localFirstStringOrNumericAsString(controlT, ["DCIFormat"]);
dciFieldsHash = localFirstStringOrNumericAsString(controlT, ["DCIFieldsHash"]);
grantFieldsHash = localFirstStringOrNumericAsString(controlT, ["GrantFieldsHash"]);
dciId = localFirstStringOrNumericAsString(controlT, ["DCIId", "PayloadHash"]);
decodedCrcOk = localColumnBoolDefault(controlT, "DCICrcPass", false);

T = table( ...
    directions(mask), ...
    cellId(mask), ...
    ueId(mask), ...
    canonicalSlot(mask), ...
    grantIds(mask), ...
    dciId(mask), ...
    harqProcessId(mask), ...
    rnti(mask), ...
    searchSpaceId(mask), ...
    coresetId(mask), ...
    aggregationLevel(mask), ...
    candidateIndex(mask), ...
    dciFormat(mask), ...
    dciFieldsHash(mask), ...
    grantFieldsHash(mask), ...
    decodedCrcOk(mask), ...
    bindingStatus(mask), ...
    failureCode(mask), ...
    'VariableNames', localPDCCHGrantBindingEvidenceVariableNames());
end

function T = localPDCCHGrantBindingRowsFromDataTrials(dlTrials, ulTrials, cfg)
dlRows = localPDCCHGrantBindingRowsFromDataTrialTable(dlTrials, cfg, "DL");
ulRows = localPDCCHGrantBindingRowsFromDataTrialTable(ulTrials, cfg, "UL");
T = [dlRows; ulRows];
if ~(istable(T) && height(T) > 0)
    T = localEmptyPDCCHGrantBindingEvidenceTable();
end
end

function T = localPDCCHGrantBindingRowsFromDataTrialTable(trialT, cfg, defaultDirection)
T = localEmptyPDCCHGrantBindingEvidenceTable();
if ~(istable(trialT) && height(trialT) > 0)
    return;
end

warmupMask = localColumnBoolDefault(trialT, "IsWarmupFrame", false);
directions = upper(localFirstStringColumn(trialT, ["Direction"]));
directions(strlength(strtrim(directions)) == 0) = string(defaultDirection);
grantIds = localFirstStringOrNumericAsString(trialT, ["GrantContextId", "GrantId"]);
requiredMask = localPDCCHGrantBindingRequiredMask(cfg, directions, localColumnBoolDefault(trialT, "PDCCHGrantBindingRequired", false));
bindingOk = localColumnBoolDefault(trialT, "PDCCHGrantBindingOk", false);
bindingStatus = localFirstStringOrNumericAsString(trialT, ["PDCCHGrantBindingStatus"]);
bindingStatus(bindingOk & strlength(strtrim(bindingStatus)) == 0) = "bound";
bindingStatus(~bindingOk & strlength(strtrim(bindingStatus)) == 0) = "failed";
failureCode = localFirstStringOrNumericAsString(trialT, ["PDCCHGrantBindingFailureCode"]);
failureCode(~bindingOk & strlength(strtrim(failureCode)) == 0 & strlength(strtrim(grantIds)) == 0) = "grant_id_missing";
failureCode(~bindingOk & strlength(strtrim(failureCode)) == 0 & strlength(strtrim(grantIds)) > 0) = "grant_binding_failed";

mask = requiredMask & ~warmupMask;
if ~any(mask)
    return;
end

cellId = localFirstNumericColumn(trialT, ["BaseStationID", "ServingCell"]);
ueId = localFirstNumericColumn(trialT, ["UEID", "UEIndex"]);
canonicalSlot = localFirstNumericColumn(trialT, ["Slot"]);
harqProcessId = localFirstNumericColumn(trialT, ["HARQProcessId", "HARQProcess"]);
rnti = localFirstNumericColumn(trialT, ["RNTI"]);
searchSpaceId = localFirstNumericColumn(trialT, ["PDCCHGrantSearchSpaceId"]);
coresetId = localFirstNumericColumn(trialT, ["PDCCHGrantCORESETId"]);
aggregationLevel = localFirstNumericColumn(trialT, ["PDCCHGrantAggregationLevel"]);
candidateIndex = localFirstNumericColumn(trialT, ["PDCCHGrantCandidateIndex"]);
dciFormat = localFirstStringOrNumericAsString(trialT, ["PDCCHGrantDCIFormat"]);
dciFieldsHash = localFirstStringOrNumericAsString(trialT, ["PDCCHGrantDCIFieldsHash"]);
grantFieldsHash = localFirstStringOrNumericAsString(trialT, ["PDCCHGrantFieldsHash"]);
dciId = localFirstStringOrNumericAsString(trialT, ["PDCCHGrantDCIId"]);
decodedCrcOk = localColumnBoolDefault(trialT, "DCICrcPass", false);

shared = localFirstStringColumn(trialT,"ExecutionBackend") == "scheduler_shared_stream_receiver";
for evidenceField = ["PDCCHGrantBindingRequired","ControlDecodeOk", ...
        "PDCCHPayloadMatch","PDCCHCausalGrantDecodeOk"]
    missing = shared & ~localColumnBoolDefault(trialT,evidenceField,false);
    for rowIndex = find(missing).'
        failures = localSplitBindingFailureCodes(failureCode(rowIndex));
        failures(end+1,1) = "received_evidence_missing_" + evidenceField;
        failureCode(rowIndex) = strjoin(unique(failures,'stable'),'|');
        bindingStatus(rowIndex) = "failed";
    end
end

T = table( ...
    directions(mask), ...
    cellId(mask), ...
    ueId(mask), ...
    canonicalSlot(mask), ...
    grantIds(mask), ...
    dciId(mask), ...
    harqProcessId(mask), ...
    rnti(mask), ...
    searchSpaceId(mask), ...
    coresetId(mask), ...
    aggregationLevel(mask), ...
    candidateIndex(mask), ...
    dciFormat(mask), ...
    dciFieldsHash(mask), ...
    grantFieldsHash(mask), ...
    decodedCrcOk(mask), ...
    bindingStatus(mask), ...
    failureCode(mask), ...
    'VariableNames', localPDCCHGrantBindingEvidenceVariableNames());
end

function mask = localPDCCHGrantBindingRequiredMask(cfg, directions, explicitRequired)
directions = upper(strtrim(string(directions(:))));
mask = logical(explicitRequired(:));
for ii = 1:numel(mask)
    if mask(ii)
        continue;
    end
    direction = directions(ii);
    if strlength(direction) == 0
        mask(ii) = sixgr.control.isPDCCHGrantBindingRequired(cfg, "");
    else
        mask(ii) = sixgr.control.isPDCCHGrantBindingRequired(cfg, direction);
    end
end
end

function keys = localPDCCHGrantBindingEvidenceKeys(T)
if ~(istable(T) && height(T) > 0)
    keys = strings(0, 1);
    return;
end
keys = localFirstStringOrNumericAsString(T, ["Direction"]) + "|" + ...
    localFirstStringOrNumericAsString(T, ["GrantId"]) + "|" + ...
    localFirstStringOrNumericAsString(T, ["CanonicalSlot"]);
end

function T = localEmptyPDCCHGrantBindingEvidenceTable()
names = localPDCCHGrantBindingEvidenceVariableNames();
types = {'string','double','double','double','string','string','double','double','double','double','double','double','string','string','string','logical','string','string'};
T = table('Size', [0 numel(names)], 'VariableTypes', types, 'VariableNames', names);
end

function names = localPDCCHGrantBindingEvidenceVariableNames()
names = {'Direction','CellId','UeId','CanonicalSlot','GrantId','DCIId','HARQProcessId','RNTI', ...
    'SearchSpaceId','CORESETId','AggregationLevel','CandidateIndex','DCIFormat','DCIFieldsHash', ...
    'GrantFieldsHash','DecodedPDCCHCRCOK','BindingStatus','FailureCode'};
end

function values = localColumnOrDefault(T, name, defaultValue)
if istable(T) && localHasColumn(T, name)
    values = T.(char(string(name)));
    return;
end
n = 0;
if istable(T)
    n = height(T);
end
if isstring(defaultValue) || ischar(defaultValue)
    values = localExpandDefaultColumn(string(defaultValue), n);
elseif islogical(defaultValue)
    values = localExpandDefaultColumn(logical(defaultValue), n);
else
    values = localExpandDefaultColumn(defaultValue, n);
end
end

function values = localExpandDefaultColumn(defaultValue, n)
if n <= 0
    values = defaultValue([]);
    values = values(:);
    return;
end
if ischar(defaultValue)
    values = repmat(string(defaultValue), n, 1);
    return;
end
if isscalar(defaultValue)
    values = repmat(defaultValue, n, 1);
    return;
end
if numel(defaultValue) == n
    values = defaultValue(:);
    return;
end
values = repmat(defaultValue(1), n, 1);
end

function tf = localHasColumn(T, name)
tf = istable(T) && ismember(string(name), string(T.Properties.VariableNames));
end

function values = localToLogical(raw)
if islogical(raw)
    values = raw(:);
elseif isnumeric(raw)
    values = raw(:) ~= 0;
else
    text = lower(strtrim(string(raw(:))));
    values = ismember(text, ["true", "1", "yes", "on", "pass", "ok", "completed", "success"]);
end
end

function values = localColumnBoolDefault(T, name, defaultValue)
if localHasColumn(T, name)
    values = localToLogical(T.(char(string(name))));
else
    values = repmat(logical(defaultValue), height(T), 1);
end
end

function values = localFirstNumericColumn(T, names)
values = NaN(height(T), 1);
for name = string(names(:)).'
    if ~localHasColumn(T, name)
        continue;
    end
    raw = T.(char(name));
    if isnumeric(raw)
        nums = double(raw);
    else
        nums = str2double(string(raw));
    end
    mask = isnan(values) & isfinite(nums);
    values(mask) = nums(mask);
end
end

function values = localFirstStringColumn(T, names)
values = repmat("", height(T), 1);
for name = string(names(:)).'
    if ~localHasColumn(T, name)
        continue;
    end
    raw = strtrim(string(T.(char(name))));
    mask = strlength(values) == 0 & strlength(raw) > 0 & ~ismissing(raw);
    values(mask) = raw(mask);
end
end

function values = localFirstStringOrNumericAsString(T, names)
values = localFirstStringColumn(T, names);
for name = string(names(:)).'
    if ~localHasColumn(T, name)
        continue;
    end
    raw = T.(char(name));
    if isnumeric(raw)
        text = string(raw);
    else
        text = strtrim(string(raw));
    end
    mask = strlength(values) == 0 & strlength(text) > 0 & ~ismissing(text);
    values(mask) = text(mask);
end
end
