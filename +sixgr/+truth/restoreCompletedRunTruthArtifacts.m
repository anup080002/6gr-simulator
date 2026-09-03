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
        name = names(i);
        value = raTables.(char(name));
        if ~istable(value)
            continue;
        end
        % Older completed Result MAT files can contain a zero-column table
        % for an optional campaign that was disabled.  Restoring that
        % object verbatim destroys the producer-owned CSV schema and leaves
        % a two-byte file.  A typed zero-row table is schema metadata, not a
        % fabricated observation, so normalize only these two optional
        % interfaces before publishing the immutable completed-run result.
        if ismember(name, ["ra_negative_trials", "ra_collision_trials"]) && ...
                height(value) == 0 && width(value) == 0
            value = sixgr.phy.ra.emptyOptionalEvidenceTable(name);
        end
        sixgr.util.csvWriteTable( ...
            fullfile(layout.ControlCSVDir, name + ".csv"), value, ...
            "PreserveSchema", height(value) == 0);
        count = count + 1;
        if name == "msg4_contention_resolution"
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
tables = value.ArtifactTables;
requiredTables = localRequiredArtifactTables(component);
presentTables = strings(0, 1);
if isstruct(tables)
    presentTables = string(fieldnames(tables));
end
missingTables = setdiff(requiredTables, presentTables, "stable");
if ~isempty(missingTables)
    row = localRow(component, 0, "not_restored_incomplete_saved_strict_bundle");
    row.EvidenceSource = "reports/mat/scenario_result.mat missing ArtifactTables: " + ...
        strjoin(missingTables, "|");
    rows(end + 1, 1) = row; %#ok<AGROW>
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

function names = localRequiredArtifactTables(component)
switch lower(string(component))
    case "pdcch"
        names = ["pdcch_config_strict"; "pdcch_trials"; "pdcch_candidates"; ...
            "pdcch_dci_fields"; "pdcch_grant_validation"; ...
            "pdcch_wrong_rnti_trials"; "pdcch_no_signal_trials"; ...
            "pdcch_corruption_trials"; "pdcch_false_alarm_sweep"; ...
            "pdcch_low_snr_sweep"; "pdcch_oracle_guard"];
    case "pucch"
        names = ["pucch_trials"; "pucch_resource_mapping"; ...
            "pucch_false_alarm_trials"; "pucch_summary"];
    case "prach"
        names = ["prach_config_strict"; "prach_trials"; ...
            "prach_detection_candidates"; "prach_restricted_set_mapping"; ...
            "prach_root_sequence_budget"; "prach_zcz_cyclic_shift_mapping"; ...
            "prach_missed_detection_sweep"; "prach_false_alarm_sweep"; ...
            "prach_timing_offset_sweep"; "prach_frequency_offset_sweep"; ...
            "prach_collision_trials"; "prach_multi_occasion_trials"; ...
            "prach_negative_trials"; "prach_oracle_guard"];
    case "srs"
        names = ["srs_config_strict"; "srs_resource_sets"; "srs_resources"; ...
            "srs_resource_mapping"; "srs_tx_waveform"; "srs_rx_extraction"; ...
            "srs_detection_metrics"; "srs_channel_estimation"; ...
            "srs_channel_estimation_per_prb"; "srs_channel_estimation_per_port"; ...
            "srs_timing_tracking"; "srs_coverage"; "srs_trigger_events"; ...
            "srs_trials"; "srs_negative_trials"; "srs_low_snr_sweep"; ...
            "srs_timing_offset_sweep"; "srs_multi_ue_trials"; "srs_oracle_guard"];
    case "trs"
        names = ["trs_config_strict"; "trs_trials"; "trs_resource_mapping"; ...
            "trs_detection_metrics"; "trs_timing_tracking"; ...
            "trs_frequency_tracking"; "trs_channel_estimation"; "trs_coverage"; ...
            "trs_negative_trials"; "trs_low_snr_sweep"; ...
            "trs_timing_offset_sweep"; "trs_frequency_offset_sweep"; ...
            "trs_oracle_guard"; "trs_tracking_summary"];
    otherwise
        names = strings(0, 1);
end
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
