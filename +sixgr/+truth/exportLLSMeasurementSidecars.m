function out = exportLLSMeasurementSidecars(runFolder)
%EXPORTLLSMEASUREMENTSIDECARS Split measured values from provenance labels.
%
% Legacy raw/debug tables intentionally carry rich provenance needed for
% root-cause analysis. This exporter publishes consumer-facing measurement
% views with numeric/boolean measured columns only, and companion provenance
% sidecars with status/source/reason text.

layout = sixgr.report.resultLayout(runFolder);
measurementDir = fullfile(layout.ReportCSVDir, "measurements");
provenanceDir = fullfile(layout.ReportCSVDir, "provenance_sidecars");
sixgr.util.ensureFolder(measurementDir);
sixgr.util.ensureFolder(provenanceDir);

specs = localSourceSpecs();
manifestRows = repmat(localManifestRow(), 0, 1);
auditRows = repmat(localAuditRow(), 0, 1);
for i = 1:numel(specs)
    spec = specs(i);
    sourcePath = fullfile(runFolder, char(spec.Source));
    if exist(sourcePath, "file") ~= 2
        continue;
    end
    try
        T = readtable(sourcePath, "VariableNamingRule", "preserve", "TextType", "string");
    catch
        continue;
    end
    if ~(istable(T) && ~isempty(T))
        continue;
    end

    if spec.Kind == "traceability"
        [measurementT, provenanceT] = localSplitTraceabilityTable(T, spec);
    else
        [measurementT, provenanceT] = localSplitMeasurementTable(T, spec);
    end
    if isempty(measurementT) && isempty(provenanceT)
        continue;
    end

    measurementRel = "reports/csv/measurements/" + spec.MeasurementFile;
    provenanceRel = "reports/csv/provenance_sidecars/" + spec.ProvenanceFile;
    measurementPath = fullfile(runFolder, char(measurementRel));
    provenancePath = fullfile(runFolder, char(provenanceRel));
    if istable(measurementT) && ~isempty(measurementT)
        sixgr.util.csvWriteTable(measurementPath, measurementT);
    end
    if istable(provenanceT) && ~isempty(provenanceT)
        sixgr.util.csvWriteTable(provenancePath, provenanceT);
    end

    manifestRows(end+1, 1) = localManifestRow(spec, T, measurementT, provenanceT, measurementRel, provenanceRel); %#ok<AGROW>
    auditRows(end+1, 1) = localAuditRow(measurementRel, measurementT, spec.Kind); %#ok<AGROW>
end

manifestT = struct2table(manifestRows, "AsArray", true);
auditT = struct2table(auditRows, "AsArray", true);
manifestPath = fullfile(layout.ReportCSVDir, "measurement_sidecar_manifest.csv");
auditPath = fullfile(layout.ReportCSVDir, "measurement_output_integrity_audit.csv");
sixgr.util.csvWriteTable(manifestPath, manifestT);
sixgr.util.csvWriteTable(auditPath, auditT);

out = struct();
out.Manifest = manifestT;
out.Audit = auditT;
out.ManifestPath = string(manifestPath);
out.AuditPath = string(auditPath);
out.Ok = isempty(auditT) || all(logical(auditT.MeasurementViewClean));
out.IssueCount = double(sum(double(auditT.LabelTokenCellCount) + double(auditT.ProvenanceColumnCount)));
end

function specs = localSourceSpecs()
rows = [ ...
    localSpec("air_interface/csv/dl_pdsch_trials.csv", "dl_pdsch_measurements.csv", "dl_pdsch_provenance.csv", "measurement"); ...
    localSpec("air_interface/csv/ul_pusch_trials.csv", "ul_pusch_measurements.csv", "ul_pusch_provenance.csv", "measurement"); ...
    localSpec("air_interface/csv/pbch_trials.csv", "pbch_measurements.csv", "pbch_provenance.csv", "measurement"); ...
    localSpec("air_interface/csv/prach_trials.csv", "prach_measurements.csv", "prach_provenance.csv", "measurement"); ...
    localSpec("air_interface/csv/pdcch_trials.csv", "pdcch_measurements.csv", "pdcch_provenance.csv", "measurement"); ...
    localSpec("air_interface/csv/pucch_trials.csv", "pucch_measurements.csv", "pucch_provenance.csv", "measurement"); ...
    localSpec("air_interface/csv/srs_trials.csv", "srs_measurements.csv", "srs_provenance.csv", "measurement"); ...
    localSpec("air_interface/csv/trs_trials.csv", "trs_measurements.csv", "trs_provenance.csv", "measurement"); ...
    localSpec("reports/csv/pdsch_runtime_event_table.csv", "pdsch_runtime_event_measurements.csv", "pdsch_runtime_event_provenance.csv", "measurement"); ...
    localSpec("reports/csv/pusch_runtime_event_table.csv", "pusch_runtime_event_measurements.csv", "pusch_runtime_event_provenance.csv", "measurement"); ...
    localSpec("reports/csv/pdcch_dci_table.csv", "pdcch_dci_measurements.csv", "pdcch_dci_provenance.csv", "measurement"); ...
    localSpec("reports/csv/pucch_uci_table.csv", "pucch_uci_measurements.csv", "pucch_uci_provenance.csv", "measurement"); ...
    localSpec("reports/csv/prach_detection_table.csv", "prach_detection_measurements.csv", "prach_detection_provenance.csv", "measurement"); ...
    localSpec("reports/csv/srs_measurement_table.csv", "srs_public_measurements.csv", "srs_public_provenance.csv", "measurement"); ...
    localSpec("reports/csv/noise_variance_evidence_table.csv", "noise_variance_measurements.csv", "noise_variance_provenance.csv", "measurement"); ...
    localSpec("control/csv/timing_synchronization_table.csv", "timing_synchronization_measurements.csv", "timing_synchronization_provenance.csv", "measurement"); ...
    localSpec("beamforming/csv/beam_precoder_table.csv", "beam_precoder_measurements.csv", "beam_precoder_provenance.csv", "measurement"); ...
    localSpec("reports/csv/parameter_binding_matrix.csv", "parameter_binding_runtime_values.csv", "parameter_binding_provenance.csv", "traceability"); ...
    localSpec("reports/csv/browser_config_surface_matrix.csv", "browser_config_runtime_values.csv", "browser_config_surface_provenance.csv", "traceability")];
specs = rows;
end

function spec = localSpec(source, measurementFile, provenanceFile, kind)
spec = struct( ...
    "Source", string(source), ...
    "MeasurementFile", string(measurementFile), ...
    "ProvenanceFile", string(provenanceFile), ...
    "Kind", string(kind));
end

function [measurementT, provenanceT] = localSplitMeasurementTable(T, spec)
vars = string(T.Properties.VariableNames);
keyMask = arrayfun(@(v)localIsKeyColumn(v), vars);
measurementMask = false(size(vars));
provenanceMask = false(size(vars));
for i = 1:numel(vars)
    name = vars(i);
    if keyMask(i)
        continue;
    end
    if localIsProvenanceColumn(name)
        provenanceMask(i) = true;
    elseif localIsMeasuredColumn(T.(char(name)))
        measurementMask(i) = true;
    else
        provenanceMask(i) = true;
    end
end
measurementVars = vars(keyMask | measurementMask);
provenanceVars = vars(keyMask | provenanceMask);
measurementT = localSelectColumns(T, measurementVars);
provenanceT = localSelectColumns(T, provenanceVars);
measurementT = localDropRowsWithoutMeasurements(measurementT, vars(measurementMask));
provenanceT.SourceArtifact = repmat(string(spec.Source), height(provenanceT), 1);
end

function [measurementT, provenanceT] = localSplitTraceabilityTable(T, spec)
vars = string(T.Properties.VariableNames);
if any(vars == "ParameterId")
    id = string(T.ParameterId);
else
    id = strings(height(T), 1);
end
rows = repmat(struct("ParameterId","", "ValueKind","", "Value",""), 0, 1);
% Keep the public traceability value view limited to runtime evidence.
% Scenario defaults, browser display strings, policies, and support labels
% remain in the provenance sidecar.
valueFields = ["RuntimeObservedValue","RuntimeAppliedEvidenceValue","RuntimeMeasuredEvidenceValue", ...
    "RuntimeAppliedValue","RuntimeMeasuredValue"];
for i = 1:height(T)
    for f = valueFields
        if ~any(vars == f)
            continue;
        end
        value = string(T.(char(f))(i));
        if localIsBlankString(value)
            continue;
        end
        rows(end+1, 1) = struct( ... %#ok<AGROW>
            "ParameterId", id(i), ...
            "ValueKind", string(f), ...
            "Value", value);
    end
end
if isempty(rows)
    measurementT = table();
else
    measurementT = struct2table(rows, "AsArray", true);
end
provenanceT = T;
provenanceT.SourceArtifact = repmat(string(spec.Source), height(T), 1);
end

function T = localSelectColumns(Tin, vars)
vars = string(vars(:)).';
vars = vars(ismember(vars, string(Tin.Properties.VariableNames)));
if isempty(vars)
    T = table();
else
    T = Tin(:, cellstr(vars));
end
end

function T = localDropRowsWithoutMeasurements(T, measurementVars)
if ~(istable(T) && ~isempty(T)) || isempty(measurementVars)
    return;
end
mask = false(height(T), 1);
for v = string(measurementVars(:)).'
    if ~ismember(v, string(T.Properties.VariableNames))
        continue;
    end
    mask = mask | localColumnHasMeasuredValue(T.(char(v)));
end
T = T(mask, :);
end

function tf = localIsKeyColumn(name)
name = regexprep(lower(string(name)), "[^a-z0-9]", "");
keys = ["runid","scenarioid","confighash","runtag","runnerprofile","outputid", ...
    "direction","sfn","frame","slot","tti","times","trialid","ueid","ueindex", ...
    "rnti","basestationid","cellid","bwpid","carrierid","grantcontextid", ...
    "parameterid","nodeindex","nodetype","siteid","sectorid"];
tf = any(name == keys);
end

function tf = localIsProvenanceColumn(name)
name = regexprep(lower(string(name)), "[^a-z0-9]", "");
patterns = ["status","source","role","reason","definition","mode","policy", ...
    "authority","classification","backend","note","artifact","producer", ...
    "runtimeevidence","nareason","fallback","placeholder","semantic", ...
    "lifecycle","config","configured","requested","submitted","resolved", ...
    "display","browser","internal","mapping","consumer","support", ...
    "shared","applies","hash","profile","path","label","section", ...
    "family","available","availability","executed","reused","active", ...
    "backed","observation","applicable","attempted","usable","finalized", ...
    "blocking","successflag","failureflag","applied","proxy","truth", ...
    "systemlevel","largescale","runtime","assumption","ideal","clipped", ...
    "partialrow","secondaryfield"];
tf = any(contains(name, patterns));
if any(name == ["crcpass","crash","decodesuccess","falsealarmflag", ...
        "misseddetectionflag","collisionflag","dtxflag","ucicontentmatch", ...
        "beamhit","topkbeamhit"])
    tf = false;
end
end

function tf = localIsMeasuredColumn(col)
if isnumeric(col) || islogical(col)
    tf = true;
    return;
end
try
    vals = string(col);
catch
    tf = false;
    return;
end
trimmed = strtrim(vals);
if all(localIsBlankString(trimmed))
    tf = false;
    return;
end
numericVals = str2double(trimmed);
numericMask = isfinite(numericVals) | localIsBlankString(trimmed);
boolMask = ismember(lower(trimmed), ["true","false","0","1","yes","no"]) | localIsBlankString(trimmed);
tf = all(numericMask) || all(boolMask);
end

function mask = localColumnHasMeasuredValue(col)
if isnumeric(col)
    mask = isfinite(double(col));
elseif islogical(col)
    mask = true(numel(col), 1);
else
    try
        vals = strtrim(string(col));
        mask = ~localIsBlankString(vals);
    catch
        mask = false(numel(col), 1);
    end
end
mask = reshape(logical(mask), [], 1);
end

function tf = localIsBlankString(value)
raw = string(value);
tf = ismissing(raw);
value = lower(strtrim(raw));
tf = tf | strlength(value) == 0 | value == "nan" | value == "<missing>" | value == "missing";
tf = logical(tf);
end

function row = localManifestRow(spec, sourceT, measurementT, provenanceT, measurementRel, provenanceRel)
if nargin == 0
    row = struct("SourceArtifact","", "MeasurementArtifact","", "ProvenanceArtifact","", ...
        "SourceRows", NaN, "MeasurementRows", NaN, "ProvenanceRows", NaN, ...
        "MeasurementColumnCount", NaN, "ProvenanceColumnCount", NaN, "SplitKind", "");
    return;
end
row = struct( ...
    "SourceArtifact", string(spec.Source), ...
    "MeasurementArtifact", string(measurementRel), ...
    "ProvenanceArtifact", string(provenanceRel), ...
    "SourceRows", double(height(sourceT)), ...
    "MeasurementRows", double(localHeight(measurementT)), ...
    "ProvenanceRows", double(localHeight(provenanceT)), ...
    "MeasurementColumnCount", double(localWidth(measurementT)), ...
    "ProvenanceColumnCount", double(localWidth(provenanceT)), ...
    "SplitKind", string(spec.Kind));
end

function row = localAuditRow(measurementRel, measurementT, kind)
if nargin == 0
    row = struct("MeasurementArtifact","", "MeasurementRows", NaN, ...
        "MeasurementColumnCount", NaN, "ProvenanceColumnCount", NaN, ...
        "LabelTokenCellCount", NaN, "MeasurementViewClean", false, "SplitKind", "");
    return;
end
[provColCount, tokenCount] = localMeasurementViewIssues(measurementT);
row = struct( ...
    "MeasurementArtifact", string(measurementRel), ...
    "MeasurementRows", double(localHeight(measurementT)), ...
    "MeasurementColumnCount", double(localWidth(measurementT)), ...
    "ProvenanceColumnCount", double(provColCount), ...
    "LabelTokenCellCount", double(tokenCount), ...
    "MeasurementViewClean", logical(provColCount == 0 && tokenCount == 0), ...
    "SplitKind", string(kind));
end

function n = localHeight(T)
if istable(T)
    n = height(T);
else
    n = 0;
end
end

function n = localWidth(T)
if istable(T)
    n = width(T);
else
    n = 0;
end
end

function [provColCount, tokenCount] = localMeasurementViewIssues(T)
provColCount = 0;
tokenCount = 0;
if ~(istable(T) && ~isempty(T))
    return;
end
vars = string(T.Properties.VariableNames);
for v = vars
    if ~localIsKeyColumn(v) && localIsProvenanceColumn(v)
        provColCount = provColCount + 1;
    end
end
tokens = ["available_runtime","unavailable","active_integrated","active_but_simplified", ...
    "proxy","fallback","synthetic","abstraction","truth_contract","not_available"];
for v = vars
    if localIsKeyColumn(v)
        continue;
    end
    try
        vals = lower(string(T.(char(v))));
    catch
        continue;
    end
    for token = tokens
        tokenCount = tokenCount + sum(contains(vals, token));
    end
end
end
