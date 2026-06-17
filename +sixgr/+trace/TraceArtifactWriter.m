classdef TraceArtifactWriter
%SIXGR.TRACE.TRACEARTIFACTWRITER Materialize study-support artifacts and audits.

    methods (Static)
        function support = materializeSupportArtifacts(runFolder, inputConfigPath, requestedWorkers)
            layout = sixgr.report.resultLayout(runFolder);
            support = struct();
            support.Config = localWriteConfigMirrors(runFolder, inputConfigPath);
            support.Profiling = localWriteProfilingAliases(layout);
            support.Parallel = localWriteParallelAliases(layout, requestedWorkers);
            support.StageTiming = localWriteStageTimingAliases(layout);
        end

        function summary = auditOutputs(runFolder, runId)
            layout = sixgr.report.resultLayout(runFolder);
            files = localRecursiveFiles(runFolder);
            inventoryRows = repmat(localEmptyInventoryRow(), 0, 1);
            csvAuditRows = repmat(localEmptyCSVAuditRow(), 0, 1);
            jsonAuditRows = repmat(localEmptySimpleAuditRow("json"), 0, 1);
            logAuditRows = repmat(localEmptySimpleAuditRow("log"), 0, 1);
            matAuditRows = repmat(localEmptySimpleAuditRow("mat"), 0, 1);
            findingRows = repmat(localEmptyFindingRow(), 0, 1);
            csvReportLines = ["# All CSV Deep Readback Report", ""];
            totalCsv = 0;
            csvOk = 0;
            csvFail = 0;

            for i = 1:numel(files)
                filePath = string(files{i});
                relPath = localNormalizeRel(runFolder, filePath);
                ext = lower(string(localFileExt(filePath)));
                byteSize = double(localFileSize(filePath));
                sha256 = string(localFileSHA256(filePath));
                inventoryRows(end+1, 1) = struct( ... %#ok<AGROW>
                    "RunId", string(runId), ...
                    "RelativePath", relPath, ...
                    "AbsolutePath", filePath, ...
                    "Extension", ext, ...
                    "ByteSize", byteSize, ...
                    "SHA256", sha256, ...
                    "ReadStatus", "pending", ...
                    "FileKind", localFileKind(ext));

                switch ext
                    case ".csv"
                        totalCsv = totalCsv + 1;
                        [auditRow, summaryText, finding] = localAuditCSV(filePath, relPath, runId, sha256, byteSize);
                        csvAuditRows(end+1, 1) = auditRow; %#ok<AGROW>
                        localWriteCSVSummary(layout, relPath, summaryText);
                        csvReportLines(end+1, 1) = "## " + relPath; %#ok<AGROW>
                        csvReportLines(end+1, 1) = summaryText; %#ok<AGROW>
                        csvReportLines(end+1, 1) = ""; %#ok<AGROW>
                        if logical(auditRow.ReadOk)
                            csvOk = csvOk + 1;
                            inventoryRows(end).ReadStatus = "read_ok";
                        else
                            csvFail = csvFail + 1;
                            inventoryRows(end).ReadStatus = "read_failed";
                        end
                        if ~isempty(finding)
                            findingRows(end+1, 1) = finding; %#ok<AGROW>
                        end
                    case ".json"
                        [auditRow, finding] = localAuditJSON(filePath, relPath, runId, sha256, byteSize);
                        jsonAuditRows(end+1, 1) = auditRow; %#ok<AGROW>
                        inventoryRows(end).ReadStatus = auditRow.ReadStatus;
                        if ~isempty(finding)
                            findingRows(end+1, 1) = finding; %#ok<AGROW>
                        end
                    case {".log", ".txt", ".md", ".html"}
                        auditRow = localAuditTextLike(filePath, relPath, runId, sha256, byteSize, "log");
                        logAuditRows(end+1, 1) = auditRow; %#ok<AGROW>
                        inventoryRows(end).ReadStatus = auditRow.ReadStatus;
                    case ".mat"
                        auditRow = localAuditMAT(filePath, relPath, runId, sha256, byteSize);
                        matAuditRows(end+1, 1) = auditRow; %#ok<AGROW>
                        inventoryRows(end).ReadStatus = auditRow.ReadStatus;
                    otherwise
                        inventoryRows(end).ReadStatus = "inventory_only";
                end
            end

            inventoryT = struct2table(inventoryRows, "AsArray", true);
            csvAuditT = localStructTable(csvAuditRows, localEmptyCSVAuditRow());
            jsonAuditT = localStructTable(jsonAuditRows, localEmptySimpleAuditRow("json"));
            logAuditT = localStructTable(logAuditRows, localEmptySimpleAuditRow("log"));
            matAuditT = localStructTable(matAuditRows, localEmptySimpleAuditRow("mat"));
            findingsT = localStructTable(findingRows, localEmptyFindingRow());

            sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "exhaustive_file_inventory.csv"), inventoryT);
            sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "exhaustive_csv_audit.csv"), csvAuditT);
            sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "exhaustive_json_audit.csv"), jsonAuditT);
            sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "exhaustive_log_audit.csv"), logAuditT);
            sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "exhaustive_binary_mat_audit.csv"), matAuditT);
            sixgr.util.csvWriteTable(fullfile(layout.ReportCSVDir, "e2e_output_readback_findings.csv"), findingsT);
            sixgr.util.jsonWrite(fullfile(layout.ReportDir, "json", "e2e_output_readback_findings.json"), struct("findings", table2struct(findingsT)));
            localWriteText(fullfile(layout.ReportDir, "md", "all_csv_deep_readback_report.md"), strjoin(csvReportLines, newline));
            localWriteText(fullfile(layout.ReportDir, "html", "all_csv_deep_readback_report.html"), localMarkdownToHTML(csvReportLines));

            summary = struct();
            summary.TotalGeneratedFiles = height(inventoryT);
            summary.TotalCSVFiles = totalCsv;
            summary.TotalCSVReadSuccessfully = csvOk;
            summary.TotalCSVReadFailed = csvFail;
            summary.InventoryCSV = string(fullfile(layout.ReportCSVDir, "exhaustive_file_inventory.csv"));
            summary.CSVAuditCSV = string(fullfile(layout.ReportCSVDir, "exhaustive_csv_audit.csv"));
            summary.ReadbackReportMD = string(fullfile(layout.ReportDir, "md", "all_csv_deep_readback_report.md"));
            summary.ReadbackReportHTML = string(fullfile(layout.ReportDir, "html", "all_csv_deep_readback_report.html"));
        end

        function report = writeStudyReport(runFolder, runId, validationSummary, readbackSummary, fixActions)
            layout = sixgr.report.resultLayout(runFolder);
            resultStatus = localReadOptionalTable(fullfile(layout.ReportCSVDir, "result_status_summary.csv"));
            truthSummary = localReadOptionalTable(fullfile(layout.ReportCSVDir, "truth_contract_summary.csv"));
            issueRegistry = localReadOptionalTable(fullfile(layout.ReportCSVDir, "result_issue_registry.csv"));
            fnTrace = localReadOptionalTable(fullfile(layout.ReportCSVDir, "runtime_function_block_trace.csv"));
            perf = localReadOptionalTable(fullfile(layout.ReportCSVDir, "live_user_performance_snapshot.csv"));

            verdict = localStudyVerdict(resultStatus, validationSummary, fnTrace);
            criticalFindings = localTopIssues(issueRegistry, "critical");
            majorFindings = localTopIssues(issueRegistry, "high");
            resultOk = localScalarLogical(resultStatus, "ResultOk", false);
            runCompleted = localScalarLogical(resultStatus, "RunCompleted", false);
            scenarioObjectiveOk = localScalarLogical(resultStatus, "ScenarioObjectiveOk", false);
            standardsOk = localScalarLogical(resultStatus, "StandardsConformanceOk", false);
            claimProfile = localScalarText(resultStatus, "ClaimProfile", "");

            summaryPayload = struct( ...
                "RunId", string(runId), ...
                "ActualLLSVerdict", verdict, ...
                "RunCompleted", runCompleted, ...
                "ResultOk", resultOk, ...
                "ScenarioObjectiveOk", scenarioObjectiveOk, ...
                "StandardsConformanceOk", standardsOk, ...
                "ClaimProfile", claimProfile, ...
                "CriticalFindings", cellstr(criticalFindings), ...
                "MajorFindings", cellstr(majorFindings), ...
                "ReadbackSummary", readbackSummary, ...
                "ValidationSummary", validationSummary);

            report = struct();
            report.SummaryJSON = fullfile(runFolder, "study_report", "summary.json");
            report.StudyHTML = fullfile(runFolder, "study_report", "study_report.html");
            report.IssueLogCSV = fullfile(runFolder, "study_report", "issue_log.csv");
            report.FixLogCSV = fullfile(runFolder, "study_report", "fix_log.csv");
            report.PerSlotKPICSV = fullfile(runFolder, "study_report", "per_slot_kpi_timeseries.csv");
            report.MainMD = fullfile(layout.ReportDir, "md", "e2e_1sector_2ue_fullphy_study_report.md");
            report.MainHTML = fullfile(layout.ReportDir, "html", "e2e_1sector_2ue_fullphy_study_report.html");
            report.MainJSON = fullfile(layout.ReportDir, "json", "e2e_1sector_2ue_fullphy_study_report.json");

            sixgr.util.jsonWrite(report.SummaryJSON, summaryPayload);
            sixgr.util.jsonWrite(report.MainJSON, summaryPayload);
            if isempty(issueRegistry)
                issueRegistry = table();
            end
            sixgr.util.csvWriteTable(report.IssueLogCSV, issueRegistry);
            if nargin < 5 || isempty(fixActions)
                fixActions = table();
            end
            sixgr.util.csvWriteTable(report.FixLogCSV, fixActions);
            if isempty(perf)
                perf = table();
            end
            sixgr.util.csvWriteTable(report.PerSlotKPICSV, perf);

            mdLines = [ ...
                "# Actual LLS Implementation Verdict", ...
                "", ...
                "- Verdict: `" + verdict + "`", ...
                "- RunCompleted: `" + string(runCompleted) + "`", ...
                "- ResultOk: `" + string(resultOk) + "`", ...
                "- ScenarioObjectiveOk: `" + string(scenarioObjectiveOk) + "`", ...
                "- StandardsConformanceOk: `" + string(standardsOk) + "`", ...
                "- ClaimProfile: `" + claimProfile + "`", ...
                "", ...
                "## Critical Findings", ...
                localBulletLines(criticalFindings), ...
                "", ...
                "## Major Findings", ...
                localBulletLines(majorFindings), ...
                "", ...
                "## Readback Summary", ...
                "- Total generated files: `" + string(readbackSummary.TotalGeneratedFiles) + "`", ...
                "- Total CSV files: `" + string(readbackSummary.TotalCSVFiles) + "`", ...
                "- Total CSV files read successfully: `" + string(readbackSummary.TotalCSVReadSuccessfully) + "`", ...
                "- Total CSV files failed to read: `" + string(readbackSummary.TotalCSVReadFailed) + "`" ...
                ];
            localWriteText(report.MainMD, strjoin(mdLines, newline));
            localWriteText(report.MainHTML, localMarkdownToHTML(mdLines));
            localWriteText(report.StudyHTML, localMarkdownToHTML(mdLines));
        end
    end
end

function configInfo = localWriteConfigMirrors(runFolder, inputConfigPath)
layout = sixgr.report.resultLayout(runFolder);
configDir = fullfile(runFolder, "config");
sixgr.util.ensureFolder(configDir);
configInfo = struct();
configInfo.InputConfig = fullfile(configDir, "input_config.yaml");
if exist(inputConfigPath, "file") == 2
    copyfile(inputConfigPath, configInfo.InputConfig);
end

resolvedYaml = fullfile(layout.MetaDir, "scenario_config_resolved.yaml");
resolvedJson = fullfile(layout.MetaDir, "scenario_config_resolved.json");
sourceTrace = fullfile(layout.MetaDir, "scenario_source_chain.csv");
configInfo.ResolvedConfig = fullfile(configDir, "resolved_config.yaml");
configInfo.SourceTrace = fullfile(configDir, "config_source_trace.csv");
configInfo.ResolvedDiff = fullfile(configDir, "resolved_config_diff.csv");
if exist(resolvedYaml, "file") == 2
    copyfile(resolvedYaml, configInfo.ResolvedConfig);
end
if exist(sourceTrace, "file") == 2
    copyfile(sourceTrace, configInfo.SourceTrace);
end

rows = repmat(struct("Field", "", "ConfiguredValue", "", "ResolvedValue", "", "Changed", false, "Reason", ""), 0, 1);
configured = localReadConfigStruct(configInfo.InputConfig);
resolved = localReadConfigStruct(resolvedJson);
rows(end+1, 1) = localDiffRow("frequency.n_size_grid", localPathValue(configured, "frequency.n_size_grid"), localPathValue(resolved, "resolved_runtime_view.configured_grid_num_rbs"), "configured_grid_traceability"); %#ok<AGROW>
rows(end+1, 1) = localDiffRow("resolved_runtime_view.active_grid_num_rbs", localPathValue(configured, "resource_grid.num_rbs"), localPathValue(resolved, "resolved_runtime_view.active_grid_num_rbs"), "frame_structure_engine_runtime_grid"); %#ok<AGROW>
rows(end+1, 1) = localDiffRow("global_radio_scope.channel_bandwidth_hz", localPathValue(configured, "global_radio_scope.channel_bandwidth_hz"), localPathValue(resolved, "frequency.bandwidthHz"), "configured_bandwidth"); %#ok<AGROW>
rows(end+1, 1) = localDiffRow("global_radio_scope.sample_rate_hz", localPathValue(configured, "global_radio_scope.sample_rate_hz"), localPathValue(resolved, "waveform.sample_rate_hz"), "runtime_waveform_sample_rate"); %#ok<AGROW>
sixgr.util.csvWriteTable(configInfo.ResolvedDiff, struct2table(rows, "AsArray", true));
end

function row = localDiffRow(fieldName, configuredValue, resolvedValue, reason)
row = struct( ...
    "Field", string(fieldName), ...
    "ConfiguredValue", string(localValueText(configuredValue)), ...
    "ResolvedValue", string(localValueText(resolvedValue)), ...
    "Changed", ~strcmp(string(localValueText(configuredValue)), string(localValueText(resolvedValue))), ...
    "Reason", string(reason));
end

function profilingInfo = localWriteProfilingAliases(layout)
profilingDir = fullfile(layout.ReportDir, "profiling");
sixgr.util.ensureFolder(profilingDir);
summaryCsv = fullfile(layout.ReportCSVDir, "runtime_profiler_summary.csv");
funcCsv = fullfile(layout.ReportCSVDir, "runtime_function_profile.csv");
edgeCsv = fullfile(layout.ReportCSVDir, "runtime_function_call_edges.csv");

summaryT = localReadOptionalTable(summaryCsv);
funcT = localReadOptionalTable(funcCsv);
edgeT = localReadOptionalTable(edgeCsv);

profilingInfo = struct();
profilingInfo.ProfileMAT = fullfile(profilingDir, "matlab_profile_info.mat");
profilingInfo.ProfileSummaryTXT = fullfile(profilingDir, "matlab_profile_summary.txt");
profilingInfo.ProfileSummaryHTML = fullfile(profilingDir, "matlab_profile_summary.html");
profilingInfo.ProfileFunctionsCSV = fullfile(profilingDir, "matlab_profile_functions.csv");
profilingInfo.ProfileCallgraphCSV = fullfile(profilingDir, "matlab_profile_callgraph.csv");
profilingInfo.ProfileHotspotsCSV = fullfile(profilingDir, "matlab_profile_hotspots.csv");

save(profilingInfo.ProfileMAT, "summaryT", "funcT", "edgeT");
if ~isempty(funcT)
    sixgr.util.csvWriteTable(profilingInfo.ProfileFunctionsCSV, funcT);
    vars = string(funcT.Properties.VariableNames);
    sortVar = localFirstExistingVar(vars, ["TotalTimeSeconds","TotalTime_s","TotalTime","Seconds"]);
    if strlength(sortVar) > 0
        funcT = sortrows(funcT, sortVar, "descend");
    end
    sixgr.util.csvWriteTable(profilingInfo.ProfileHotspotsCSV, funcT(1:min(height(funcT), 64), :));
end
if ~isempty(edgeT)
    sixgr.util.csvWriteTable(profilingInfo.ProfileCallgraphCSV, edgeT);
end

txt = "MATLAB profile summary" + newline + newline + ...
    "Summary rows: " + string(height(summaryT)) + newline + ...
    "Function rows: " + string(height(funcT)) + newline + ...
    "Edge rows: " + string(height(edgeT)) + newline;
    localWriteText(profilingInfo.ProfileSummaryTXT, txt);
    localWriteText(profilingInfo.ProfileSummaryHTML, "<html><body><pre>" + txt + "</pre></body></html>");
end

function parallelInfo = localWriteParallelAliases(layout, requestedWorkers)
runtimeSummary = localReadJSON(fullfile(layout.MetaDir, "runtime_summary.json"));
parallelInfo = struct();
parallelInfo.CSV = fullfile(layout.ReportCSVDir, "parallel_execution_summary.csv");
parallelInfo.JSON = fullfile(layout.ReportDir, "json", "parallel_execution_summary.json");
parallelInfo.TimelineCSV = fullfile(layout.ReportCSVDir, "parallel_task_timeline.csv");
parallelInfo.ErrorsCSV = fullfile(layout.ReportCSVDir, "parallel_worker_errors.csv");

T = table( ...
        double(requestedWorkers), ...
        double(localJSONValue(runtimeSummary, "AvailableWorkers", NaN)), ...
        double(localJSONValue(runtimeSummary, "EffectiveWorkers", NaN)), ...
        logical(localJSONValue(runtimeSummary, "UseParallel", false)), ...
        string(localJSONValue(runtimeSummary, "ParallelDisabledReason", "")), ...
        logical(double(requestedWorkers) ~= double(localJSONValue(runtimeSummary, "EffectiveWorkers", NaN))), ...
        'VariableNames', {'RequestedWorkers','AvailableWorkers','WorkersUsed','UseParallel','ParallelDisabledReason','ParallelDegraded'});
sixgr.util.csvWriteTable(parallelInfo.CSV, T);
sixgr.util.jsonWrite(parallelInfo.JSON, table2struct(T));
sixgr.util.csvWriteTable(parallelInfo.TimelineCSV, table(strings(0,1), strings(0,1), strings(0,1), 'VariableNames', {'Stage','StartedAt','EndedAt'}));
sixgr.util.csvWriteTable(parallelInfo.ErrorsCSV, table(strings(0,1), strings(0,1), 'VariableNames', {'Worker','Error'}));
end

function stageInfo = localWriteStageTimingAliases(layout)
stageInfo = struct();
stageInfo.CSV = fullfile(layout.ReportDir, "profiling", "stage_timing_summary.csv");
stageInfo.JSON = fullfile(layout.ReportDir, "profiling", "stage_timing_summary.json");
source = localReadOptionalTable(fullfile(layout.ReportCSVDir, "runtime_stage_profile.csv"));
if isempty(source)
    source = localReadOptionalTable(fullfile(layout.ReportCSVDir, "time_profile_summary.csv"));
end
if isempty(source)
    source = table();
end
sixgr.util.csvWriteTable(stageInfo.CSV, source);
sixgr.util.jsonWrite(stageInfo.JSON, struct("rows", table2struct(source)));
end

function [row, summaryText, finding] = localAuditCSV(pathStr, relPath, runId, sha256, byteSize)
finding = struct([]);
try
    T = readtable(pathStr, "VariableNamingRule", "preserve");
    rows = height(T);
    cols = width(T);
    numericSummary = localSafeAuditText(@() localNumericSummary(T), "summary_unavailable");
    issueIds = localSafeAuditText(@() localColumnCounts(T, ["IssueId","IssueID"]), "summary_unavailable");
    failureReasons = localSafeAuditText(@() localColumnCounts(T, ["FailureReason","Reason","Notes"]), "summary_unavailable");
    statusCounts = localSafeAuditText(@() localColumnCounts(T, ["Status"]), "summary_unavailable");
    strictCounts = localSafeAuditText(@() localColumnCounts(T, ["StrictOk"]), "summary_unavailable");
    resultCounts = localSafeAuditText(@() localColumnCounts(T, ["ResultOk"]), "summary_unavailable");
    proxyCounts = localSafeAuditText(@() localColumnCounts(T, ["ProxyUsed"]), "summary_unavailable");
    skippedCounts = localSafeAuditText(@() localColumnCounts(T, ["Skipped"]), "summary_unavailable");
    fallbackCounts = localSafeAuditText(@() localColumnCounts(T, ["FallbackUsed"]), "summary_unavailable");
    suspicious = localSafeAuditText(@() localSuspiciousSummary(T), "summary_unavailable");
    recommended = localSafeAuditText(@() localRecommendedFix(T, suspicious), "inspect_audit_summary_helpers");
    firstExcerpt = localSafeAuditText(@() localExcerpt(T, "head"), "[excerpt unavailable]");
    lastExcerpt = localSafeAuditText(@() localExcerpt(T, "tail"), "[excerpt unavailable]");
    summaryText = sprintf([ ...
        'Path: %s\nSize: %d\nSHA256: %s\nRows: %d\nColumns: %d\nFirst5: %s\nLast5: %s\n' ...
        'NumericStats: %s\nStatusCounts: %s\nStrictOkCounts: %s\nResultOkCounts: %s\nProxyUsedCounts: %s\n' ...
        'SkippedCounts: %s\nFallbackUsedCounts: %s\nIssueIds: %s\nFailureReasons: %s\nSuspiciousValues: %s\nRecommendedNextFix: %s\n'], ...
        char(relPath), byteSize, char(sha256), rows, cols, char(firstExcerpt), char(lastExcerpt), ...
        char(numericSummary), char(statusCounts), char(strictCounts), char(resultCounts), char(proxyCounts), ...
        char(skippedCounts), char(fallbackCounts), char(issueIds), char(failureReasons), char(suspicious), char(recommended));
    row = struct( ...
        "RunId", string(runId), ...
        "RelativePath", string(relPath), ...
        "SHA256", string(sha256), ...
        "ByteSize", double(byteSize), ...
        "Rows", double(rows), ...
        "Columns", double(cols), ...
        "ReadOk", true, ...
        "ErrorMessage", "", ...
        "NumericSummary", string(numericSummary), ...
        "StatusCounts", string(statusCounts), ...
        "StrictOkCounts", string(strictCounts), ...
        "ResultOkCounts", string(resultCounts), ...
        "ProxyUsedCounts", string(proxyCounts), ...
        "SkippedCounts", string(skippedCounts), ...
        "FallbackUsedCounts", string(fallbackCounts), ...
        "IssueIds", string(issueIds), ...
        "FailureReasonCounts", string(failureReasons), ...
        "SuspiciousValues", string(suspicious), ...
        "RecommendedNextFix", string(recommended));
    if ~strcmp(string(suspicious), "none")
        finding = localFinding(runId, relPath, "READBACK-02", "medium", "suspicious_csv_values_detected", suspicious);
    end
catch ME
    summaryText = sprintf("Path: %s\nRead failure: %s\n", char(relPath), char(ME.message));
    errorDetail = string(ME.message);
    if strlength(string(ME.identifier)) > 0
        errorDetail = string(ME.identifier) + ": " + errorDetail;
    end
    if ~isempty(ME.stack)
        errorDetail = errorDetail + " @ " + string(ME.stack(1).name) + ":" + string(ME.stack(1).line);
    end
    row = struct( ...
        "RunId", string(runId), ...
        "RelativePath", string(relPath), ...
        "SHA256", string(sha256), ...
        "ByteSize", double(byteSize), ...
        "Rows", NaN, ...
        "Columns", NaN, ...
        "ReadOk", false, ...
        "ErrorMessage", errorDetail, ...
        "NumericSummary", "", ...
        "StatusCounts", "", ...
        "StrictOkCounts", "", ...
        "ResultOkCounts", "", ...
        "ProxyUsedCounts", "", ...
        "SkippedCounts", "", ...
        "FallbackUsedCounts", "", ...
        "IssueIds", "", ...
        "FailureReasonCounts", "", ...
        "SuspiciousValues", "read_failure", ...
        "RecommendedNextFix", "inspect_csv_schema_and_encoding");
    finding = localFinding(runId, relPath, "READBACK-01", "high", "csv_read_failed", string(ME.message));
end
end

function text = localSafeAuditText(fn, fallback)
try
    text = string(fn());
catch ME
    text = string(fallback) + " (" + string(ME.message) + ")";
end
if ismissing(text)
    text = string(fallback);
end
if ~isscalar(text)
    text = strjoin(text(:), "; ");
end
end

function [row, finding] = localAuditJSON(pathStr, relPath, runId, sha256, byteSize)
finding = struct([]);
try
    data = jsondecode(fileread(pathStr));
    row = localSimpleAuditRow(runId, relPath, sha256, byteSize, "json", "read_ok", localJSONSummary(data));
catch ME
    row = localSimpleAuditRow(runId, relPath, sha256, byteSize, "json", "read_failed", ME.message);
    finding = localFinding(runId, relPath, "READBACK-01", "medium", "json_read_failed", string(ME.message));
end
end

function row = localAuditTextLike(pathStr, relPath, runId, sha256, byteSize, kind)
try
    raw = fileread(pathStr);
    raw = string(raw);
    raw = extractBefore(raw + newline, newline + newline + newline + newline + newline + newline);
    row = localSimpleAuditRow(runId, relPath, sha256, byteSize, kind, "read_ok", raw);
catch ME
    row = localSimpleAuditRow(runId, relPath, sha256, byteSize, kind, "read_failed", ME.message);
end
end

function row = localAuditMAT(pathStr, relPath, runId, sha256, byteSize)
try
    vars = whos("-file", pathStr);
    names = string({vars.name});
    row = localSimpleAuditRow(runId, relPath, sha256, byteSize, "mat", "read_ok", strjoin(names, "|"));
catch ME
    row = localSimpleAuditRow(runId, relPath, sha256, byteSize, "mat", "read_failed", ME.message);
end
end

function row = localSimpleAuditRow(runId, relPath, sha256, byteSize, kind, status, note)
row = struct( ...
    "RunId", string(runId), ...
    "RelativePath", string(relPath), ...
    "SHA256", string(sha256), ...
    "ByteSize", double(byteSize), ...
    "Kind", string(kind), ...
    "ReadStatus", string(status), ...
    "Note", string(note));
end

function tableOut = localStructTable(rows, emptyRow)
if isempty(rows)
    tableOut = struct2table(repmat(emptyRow, 0, 1), "AsArray", true);
else
    tableOut = struct2table(rows, "AsArray", true);
end
end

function files = localRecursiveFiles(rootDir)
D = dir(fullfile(rootDir, "**", "*"));
mask = ~[D.isdir];
files = fullfile({D(mask).folder}, {D(mask).name});
end

function sizeBytes = localFileSize(pathStr)
info = dir(pathStr);
sizeBytes = info.bytes;
end

function ext = localFileExt(pathStr)
[~, ~, ext] = fileparts(char(pathStr));
end

function out = localFileKind(ext)
switch ext
    case ".csv"
        out = "csv";
    case ".json"
        out = "json";
    case ".mat"
        out = "mat";
    otherwise
        out = "other";
end
end

function sha = localFileSHA256(pathStr)
fid = fopen(pathStr, "r");
if fid < 0
    sha = "";
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
data = fread(fid, Inf, "*uint8");
sha = string(sixgr.rrc.asn1.sha256Hex(data));
end

function rel = localNormalizeRel(rootDir, absPath)
rel = string(strrep(char(absPath), [char(rootDir) filesep], ""));
rel = replace(rel, "\", "/");
end

function localWriteCSVSummary(layout, relPath, textValue)
safeName = regexprep(char(relPath), '[^A-Za-z0-9._-]', '_');
outPath = fullfile(layout.ReportDir, "text", "csv_summaries", [safeName ".summary.txt"]);
localWriteText(outPath, textValue);
end

function summary = localNumericSummary(T)
vars = string(T.Properties.VariableNames);
parts = strings(0, 1);
for i = 1:numel(vars)
    raw = T.(vars(i));
    if isnumeric(raw) || islogical(raw)
        values = double(raw(:));
        values = values(isfinite(values));
        if isempty(values)
            continue;
        end
        parts(end+1, 1) = vars(i) + ":min=" + string(min(values)) + ",max=" + string(max(values)) + ... %#ok<AGROW>
            ",mean=" + string(mean(values)) + ",std=" + string(std(values, 0));
    end
end
if isempty(parts)
    summary = "none";
else
    summary = strjoin(parts, "; ");
end
end

function out = localColumnCounts(T, candidateNames)
out = "none";
candidateNames = string(candidateNames(:));
for i = 1:numel(candidateNames)
    if ismember(candidateNames(i), string(T.Properties.VariableNames))
        values = string(T.(candidateNames(i)));
        [grp, ~, idx] = unique(values);
        counts = accumarray(idx, 1);
        parts = grp + "=" + string(counts);
        out = strjoin(parts, "; ");
        return;
    end
end
end

function out = localSuspiciousSummary(T)
vars = string(T.Properties.VariableNames);
parts = strings(0, 1);
for i = 1:numel(vars)
    raw = T.(vars(i));
    if isnumeric(raw) || islogical(raw)
        values = double(raw(:));
        if any(~isfinite(values))
            parts(end+1, 1) = vars(i) + ":nonfinite"; %#ok<AGROW>
        end
    end
end
if any(ismember("ProxyUsed", vars))
    if any(logical(T.ProxyUsed))
        parts(end+1, 1) = "ProxyUsed=true"; %#ok<AGROW>
    end
end
if any(ismember("FallbackUsed", vars))
    if any(logical(T.FallbackUsed))
        parts(end+1, 1) = "FallbackUsed=true"; %#ok<AGROW>
    end
end
if isempty(parts)
    out = "none";
else
    out = strjoin(parts, "; ");
end
end

function out = localRecommendedFix(T, suspicious)
if ~strcmp(string(suspicious), "none")
    out = "inspect upstream writer and issue registry before claiming success";
elseif any(ismember("ResultOk", string(T.Properties.VariableNames))) && ~all(logical(T.ResultOk))
    out = "inspect failing result rows and truth-contract blockers";
else
    out = "none";
end
end

function excerpt = localExcerpt(T, modeName)
if isempty(T)
    excerpt = "[]";
    return;
end
switch lower(string(modeName))
    case "head"
        slice = T(1:min(5, height(T)), :);
    otherwise
        slice = T(max(1, height(T) - 4):height(T), :);
end
excerpt = string(jsonencode(table2struct(slice)));
end

function finding = localFinding(runId, relPath, issueId, severity, message, detail)
finding = struct( ...
    "RunId", string(runId), ...
    "RelativePath", string(relPath), ...
    "IssueId", string(issueId), ...
    "Severity", string(severity), ...
    "Message", string(message), ...
    "Detail", string(detail));
end

function report = localMarkdownToHTML(lines)
body = strjoin("<p>" + replace(string(lines), newline, "<br/>") + "</p>", newline);
report = "<html><body>" + body + "</body></html>";
end

function localWriteText(pathStr, textValue)
if iscell(pathStr)
    pathStr = string(pathStr{1});
else
    pathStr = string(pathStr);
end
if ~isscalar(pathStr)
    pathStr = pathStr(1);
end
sixgr.util.ensureDir(pathStr);
fid = fopen(char(pathStr), "w");
if fid < 0
    return;
end
cleanupObj = onCleanup(@() fclose(fid)); %#ok<NASGU>
textValue = string(textValue);
textValue(ismissing(textValue)) = "";
if ~isscalar(textValue)
    textValue = strjoin(textValue, newline);
end
fprintf(fid, "%s", char(textValue));
end

function cfg = localReadConfigStruct(pathStr)
cfg = struct();
if exist(pathStr, "file") ~= 2
    return;
end
try
    cfg = sixgr.lls6g.config.readConfigFile(pathStr);
catch
    try
        cfg = jsondecode(fileread(pathStr));
    catch
        cfg = struct();
    end
end
end

function value = localPathValue(s, pathStr)
value = sixgr.util.structGet(s, pathStr, "");
end

function text = localValueText(value)
if ischar(value) || isstring(value)
    text = string(value);
elseif isnumeric(value) || islogical(value)
    text = string(mat2str(value));
else
    try
        text = string(jsonencode(value));
    catch
        text = "";
    end
end
end

function data = localReadJSON(pathStr)
data = struct();
if exist(pathStr, "file") ~= 2
    return;
end
try
    data = jsondecode(fileread(pathStr));
catch
    data = struct();
end
end

function value = localJSONValue(s, fieldName, defaultValue)
if isstruct(s) && isfield(s, fieldName)
    value = s.(fieldName);
else
    value = defaultValue;
end
end

function vars = localFirstExistingVar(vars, candidates)
vars = string(vars(:));
candidates = string(candidates(:));
hit = vars(ismember(vars, candidates));
if isempty(hit)
    vars = "";
else
    vars = hit(1);
end
end

function summary = localJSONSummary(data)
if isstruct(data)
    summary = "fields=" + strjoin(string(fieldnames(data)), "|");
elseif iscell(data)
    summary = "cell_count=" + string(numel(data));
else
    summary = "type=" + string(class(data));
end
end

function verdict = localStudyVerdict(resultStatus, validationSummary, fnTrace)
runCompleted = localScalarLogical(resultStatus, "RunCompleted", false);
resultOk = localScalarLogical(resultStatus, "ResultOk", false);
if isstruct(validationSummary) && isfield(validationSummary, "ActualLLSVerdict")
    baseVerdict = string(validationSummary.ActualLLSVerdict);
else
    baseVerdict = "";
end
if ~runCompleted
    verdict = "failed evidence run";
elseif resultOk && baseVerdict == "full_actual_lls"
    verdict = "full actual LLS";
elseif ~isempty(fnTrace) && any(logical(fnTrace.MeasurementEvidence))
    verdict = "partial actual LLS";
elseif any(contains(lower(string(fnTrace.FailureReason)), ["proxy","fallback","config_only"]))
    verdict = "label-proxy simulator";
else
    verdict = "partial actual LLS";
end
end

function items = localTopIssues(T, severity)
items = strings(0, 1);
if isempty(T)
    items = "none";
    return;
end
sevVar = localExistingVar(T, ["Severity","IssueSeverity"]);
msgVar = localExistingVar(T, ["Message","IssueMessage","Reason","FailureReason"]);
if strlength(sevVar) == 0 || strlength(msgVar) == 0
    items = "none";
    return;
end
mask = strcmpi(string(T.(sevVar)), string(severity));
msgs = string(T.(msgVar)(mask));
if isempty(msgs)
    items = "none";
else
    items = unique(msgs);
end
end

function varName = localExistingVar(T, candidates)
vars = string(T.Properties.VariableNames);
candidates = string(candidates(:));
hit = vars(ismember(lower(vars), lower(candidates)));
if isempty(hit)
    varName = "";
else
    varName = string(hit(1));
end
end

function tf = localScalarLogical(T, varName, defaultValue)
tf = defaultValue;
if isempty(T) || ~ismember(string(varName), string(T.Properties.VariableNames))
    return;
end
try
    tf = logical(T.(varName)(1));
catch
    tf = any(strcmpi(string(T.(varName)(1)), ["true","1","yes","pass"]));
end
end

function text = localScalarText(T, varName, defaultValue)
text = string(defaultValue);
if isempty(T) || ~ismember(string(varName), string(T.Properties.VariableNames))
    return;
end
text = string(T.(varName)(1));
end

function lines = localBulletLines(items)
if isempty(items)
    lines = "- none";
else
    lines = "- " + string(items(:));
end
end

function row = localEmptyInventoryRow()
row = struct( ...
    "RunId", "", ...
    "RelativePath", "", ...
    "AbsolutePath", "", ...
    "Extension", "", ...
    "ByteSize", NaN, ...
    "SHA256", "", ...
    "ReadStatus", "", ...
    "FileKind", "");
end

function row = localEmptyCSVAuditRow()
row = struct( ...
    "RunId", "", ...
    "RelativePath", "", ...
    "SHA256", "", ...
    "ByteSize", NaN, ...
    "Rows", NaN, ...
    "Columns", NaN, ...
    "ReadOk", false, ...
    "ErrorMessage", "", ...
    "NumericSummary", "", ...
    "StatusCounts", "", ...
    "StrictOkCounts", "", ...
    "ResultOkCounts", "", ...
    "ProxyUsedCounts", "", ...
    "SkippedCounts", "", ...
    "FallbackUsedCounts", "", ...
    "IssueIds", "", ...
    "FailureReasonCounts", "", ...
    "SuspiciousValues", "", ...
    "RecommendedNextFix", "");
end

function row = localEmptySimpleAuditRow(kind)
row = struct( ...
    "RunId", "", ...
    "RelativePath", "", ...
    "SHA256", "", ...
    "ByteSize", NaN, ...
    "Kind", string(kind), ...
    "ReadStatus", "", ...
    "Note", "");
end

function row = localEmptyFindingRow()
row = struct( ...
    "RunId", "", ...
    "RelativePath", "", ...
    "IssueId", "", ...
    "Severity", "", ...
    "Message", "", ...
    "Detail", "");
end

function T = localReadOptionalTable(pathStr)
if exist(pathStr, "file") ~= 2
    T = table();
    return;
end
T = readtable(pathStr, "VariableNamingRule", "preserve");
end
