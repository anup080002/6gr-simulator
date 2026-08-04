function report = restoreCompletedRunTruthArtifacts(runFolder, result)
%RESTORECOMPLETEDRUNTRUTHARTIFACTS Republish saved strict truth tables.
%
% A completed-run re-finalization must be repeatable. Browser sanitization
% may rewrite CSVs, but the immutable scenario_result MAT retains the exact
% strict-validation tables produced during waveform execution. This helper
% republishes those tables before re-evaluation; it never derives rows or
% fills values from configuration.

arguments
    runFolder {mustBeTextScalar}
    result struct
end

runFolder = char(string(runFolder));
rows = repmat(struct("Component", "", "ArtifactCount", 0, ...
    "EvidenceSource", "scenario_result.mat", "RestoreStatus", ""), 0, 1);

strictControl = sixgr.util.structGet(result, "StrictControl", struct());
strictSupplemental = sixgr.util.structGet(result, "StrictSupplemental", struct());

rows = localRunExporter(rows, "pdcch", ...
    sixgr.util.structGet(strictControl, "PDCCH", struct()), ...
    @(value)sixgr.phy.pdcch.exportStrictPDCCHArtifacts(runFolder, value));
rows = localRunExporter(rows, "pucch", ...
    sixgr.util.structGet(strictControl, "PUCCH", struct()), ...
    @(value)sixgr.phy.pucch.exportStrictPUCCHArtifacts(runFolder, value));
rows = localRunExporter(rows, "prach", ...
    sixgr.util.structGet(strictSupplemental, "PRACH", struct()), ...
    @(value)sixgr.phy.prach.exportStrictPRACHArtifacts(runFolder, value));
rows = localRunExporter(rows, "srs", ...
    sixgr.util.structGet(strictSupplemental, "SRS", struct()), ...
    @(value)sixgr.phy.srs.exportStrictSRSArtifacts(runFolder, value));
rows = localRunExporter(rows, "trs", ...
    sixgr.util.structGet(strictSupplemental, "TRS", struct()), ...
    @(value)sixgr.phy.trs.exportStrictTRSArtifacts(runFolder, value));

raTables = sixgr.util.structGet(result, ...
    "Link.Result.RawTrials.CoupledRuntime.ControlTrials.RAEvidenceTables", struct());
if isstruct(raTables) && ~isempty(fieldnames(raTables))
    layout = sixgr.report.resultLayout(runFolder);
    sixgr.util.ensureFolder(layout.ControlCSVDir);
    names = string(fieldnames(raTables));
    count = 0;
    for i = 1:numel(names)
        value = raTables.(char(names(i)));
        if ~istable(value)
            continue;
        end
        sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir, names(i) + ".csv"), value);
        count = count + 1;
        if names(i) == "msg4_contention_resolution"
            sixgr.util.csvWriteTable(fullfile(layout.ControlCSVDir, "msg4_trials.csv"), value);
            count = count + 1;
        end
    end
    rows(end + 1, 1) = localRow("random_access", count, "restored_exact_saved_tables"); %#ok<AGROW>
end

% live_error_rate_summary.csv and both FER mirrors are the same derived
% runtime-trial table.  Recover a damaged mirror only from the intact
% canonical FER report, never from configured or aggregate proxy values.
layout = sixgr.report.resultLayout(runFolder);
ferSource = fullfile(layout.ReportCSVDir, "fer_summary.csv");
if exist(ferSource, "file") == 2
    ferT = readtable(ferSource, "FileType", "text", "Delimiter", ",", ...
        "ReadVariableNames", true, "VariableNamingRule", "preserve");
    if istable(ferT) && ~isempty(ferT) && ...
            ismember("Scope", string(ferT.Properties.VariableNames))
        sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, ...
            "live_error_rate_summary.csv"), ferT);
        sixgr.util.csvWriteTable(fullfile(layout.AirInterfaceCSVDir, ...
            "fer_summary.csv"), ferT);
        row = localRow("fer_summary", 2, "restored_exact_canonical_runtime_table");
        row.EvidenceSource = "reports/csv/fer_summary.csv";
        rows(end + 1, 1) = row; %#ok<AGROW>
    end
end

if isempty(rows)
    report = table(strings(0,1), zeros(0,1), strings(0,1), strings(0,1), ...
        'VariableNames', {'Component','ArtifactCount','EvidenceSource','RestoreStatus'});
else
    report = struct2table(rows, "AsArray", true);
end
end

function rows = localRunExporter(rows, component, value, exporter)
if ~(isstruct(value) && isfield(value, "ArtifactTables"))
    return;
end
manifest = exporter(value);
count = 0;
if istable(manifest)
    count = height(manifest);
elseif isstruct(manifest)
    count = numel(manifest);
end
rows(end + 1, 1) = localRow(component, count, "restored_by_canonical_exporter"); %#ok<AGROW>
end

function row = localRow(component, count, status)
row = struct("Component", string(component), "ArtifactCount", double(count), ...
    "EvidenceSource", "reports/mat/scenario_result.mat", ...
    "RestoreStatus", string(status));
end

function mustBeTextScalar(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error("sixgr:truth:restoreCompletedRunTruthArtifacts:BadRunFolder", ...
        "runFolder must be a character vector or scalar string.");
end
end
