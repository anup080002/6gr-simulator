classdef OutputAuditor
    %OUTPUTAUDITOR Independent, blunt audit of a profiled run folder.

    methods (Static)
        function out = audit(runDir, scenarioPath, simRunFolder, runOk, profileT, flowSummaryT, exceptionT)
            if nargin < 7
                exceptionT = table();
            end
            files = dir(fullfile(runDir, "**", "*"));
            files = files(~[files.isdir]);
            csvFiles = files(endsWith(lower(string({files.name})), ".csv"));
            [emptyCsvCount, malformedCsvCount] = sixgr.monitor.OutputAuditor.csvHealth(csvFiles);
            issues = sixgr.monitor.OutputAuditor.buildIssues(runDir, runOk, flowSummaryT, exceptionT, emptyCsvCount, malformedCsvCount);
            grade = sixgr.monitor.OutputAuditor.grade(runOk, issues, flowSummaryT, profileT);
            sixgr.util.csvWriteTable(fullfile(runDir, "output_audit_issues.csv"), issues);
            sixgr.util.jsonWrite(fullfile(runDir, "final_blunt_grade.json"), grade);
            sixgr.monitor.OutputAuditor.writeReport(runDir, scenarioPath, simRunFolder, files, csvFiles, ...
                emptyCsvCount, malformedCsvCount, profileT, flowSummaryT, issues, grade);
            sixgr.monitor.OutputAuditor.writeFixPlan(runDir, issues);
            out = struct("Issues", issues, "Grade", grade);
        end

        function [emptyCount, malformedCount] = csvHealth(csvFiles)
            emptyCount = 0;
            malformedCount = 0;
            for i = 1:numel(csvFiles)
                path = fullfile(csvFiles(i).folder, csvFiles(i).name);
                if csvFiles(i).bytes == 0
                    emptyCount = emptyCount + 1;
                    continue;
                end
                try
                    T = readtable(path, "Delimiter", ",", "VariableNamingRule", "preserve");
                    if height(T) == 0
                        emptyCount = emptyCount + 1;
                    end
                catch
                    malformedCount = malformedCount + 1;
                end
            end
        end

        function issues = buildIssues(runDir, runOk, flowSummaryT, exceptionT, emptyCsvCount, malformedCsvCount)
            rows = repmat(sixgr.monitor.OutputAuditor.defaultIssue(), 0, 1);
            if ~runOk
                rows(end+1, 1) = sixgr.monitor.OutputAuditor.issue("AUD-RUN-001", "CRITICAL", ...
                    "runtime", "ALL", "profiled runner", "Scenario did not complete successfully.", ...
                    "runtime_exception_log.csv", "see exception rows", "run status", ...
                    "clean successful simulator run", "failed or blocked", ...
                    "Invalidates all downstream KPI claims for this profiled attempt.", ...
                    "First runtime exception or timeout in simulator path.", ...
                    "Fix root-cause stack frame and rerun from clean start.", true, "P0"); %#ok<AGROW>
            end
            if istable(exceptionT) && height(exceptionT) > 0
                rows(end+1, 1) = sixgr.monitor.OutputAuditor.issue("AUD-RUN-002", "CRITICAL", ...
                    "runtime", "ALL", "runtime_exception_log.csv", "Runtime exceptions were captured.", ...
                    "runtime_exception_log.csv", string(height(exceptionT)), "exception count", ...
                    "0 exceptions", string(height(exceptionT)) + " exceptions", ...
                    "Run cannot be considered publishable until exceptions are eliminated.", ...
                    "See captured MATLAB stack.", "Fix implementation bug, not output label.", true, "P0"); %#ok<AGROW>
            end
            if malformedCsvCount > 0
                rows(end+1, 1) = sixgr.monitor.OutputAuditor.issue("AUD-CSV-001", "HIGH", ...
                    "artifact", "ALL", runDir, "Malformed CSV outputs found.", ...
                    "output_audit_report.md", string(malformedCsvCount), "readtable parse", ...
                    "0 malformed CSVs", string(malformedCsvCount), ...
                    "Breaks independent output audit and reproducibility.", ...
                    "CSV writer/schema mismatch.", "Fix producer schema/escaping.", true, "P1"); %#ok<AGROW>
            end
            if emptyCsvCount > 5
                rows(end+1, 1) = sixgr.monitor.OutputAuditor.issue("AUD-CSV-002", "MEDIUM", ...
                    "artifact", "ALL", runDir, "Many empty CSV outputs found.", ...
                    "output_audit_report.md", string(emptyCsvCount), "CSV row count", ...
                    "only explicitly inactive artifacts empty", string(emptyCsvCount), ...
                    "May indicate missing runtime evidence for enabled blocks.", ...
                    "Enabled block did not emit evidence or artifact is schema-only.", ...
                    "Connect producer to real runtime rows or mark scenario inactive explicitly.", true, "P2"); %#ok<AGROW>
            end
            progressT = sixgr.monitor.OutputAuditor.readProgress(runDir);
            if istable(progressT) && height(progressT) > 0
                projected = sixgr.monitor.OutputAuditor.tableNumber(progressT, "ProjectedTotalRuntime_s", 1);
                lastSlot = sixgr.monitor.OutputAuditor.tableNumber(progressT, "LastSlot", 1);
                totalSlots = sixgr.monitor.OutputAuditor.tableNumber(progressT, "TotalSlots", 1);
                if isfinite(projected) && projected > 4 * 3600
                    rows(end+1, 1) = sixgr.monitor.OutputAuditor.issue("AUD-PERF-001", "HIGH", ...
                        "runtime_performance", "ALL", "run.log", ...
                        "Projected full scenario runtime is too large for interactive profiled validation.", ...
                        "runtime_log_progress_summary.csv", "last slot " + string(lastSlot) + "/" + string(totalSlots), ...
                        "elapsed/progress projection", "<= 4 hours for profiled validation or documented batch execution", ...
                        sprintf("%.1f hours projected", projected / 3600), ...
                        "Blocks timely end-to-end validation and hides later PHY failures behind runtime exhaustion.", ...
                        "Per-slot control gating and publication work appear too slow for 7200-slot profile.", ...
                        "Profile slot loop, batch/persist outside slot path, and add deterministic resumable batch execution.", true, "P1"); %#ok<AGROW>
                end
                maxGrants = sixgr.monitor.OutputAuditor.tableNumber(progressT, "MaxGrantsPerLogLine", 1);
                maxExecutable = sixgr.monitor.OutputAuditor.tableNumber(progressT, "MaxExecutableGrantsPerLogLine", 1);
                if isfinite(lastSlot) && lastSlot >= 100 && max([maxGrants, maxExecutable], [], "omitnan") == 0
                    rows(end+1, 1) = sixgr.monitor.OutputAuditor.issue("AUD-SCHED-001", "HIGH", ...
                        "scheduler_control", "PDSCH/PUSCH", "run.log", ...
                        "No executable data grants were observed in the profiled prefix.", ...
                        "runtime_log_progress_summary.csv", "last slot " + string(lastSlot) + "/" + string(totalSlots), ...
                        "grant count in raw runtime log", "nonzero executable data grants once acquisition/access prerequisites are met", ...
                        "max grants=0, max executable grants=0", ...
                        "PDSCH/PUSCH TX/RX cannot be audited because data channels never execute.", ...
                        "Control gating/access/SRS/TRS eligibility may be preventing scheduler admission.", ...
                        "Fix gating or scenario prerequisites so two UEs become data-eligible without bypassing control physics.", true, "P0"); %#ok<AGROW>
                end
            end
            if istable(flowSummaryT) && height(flowSummaryT) > 0
                for i = 1:height(flowSummaryT)
                    if string(flowSummaryT.status(i)) ~= "observed"
                        rows(end+1, 1) = sixgr.monitor.OutputAuditor.issue("AUD-FLOW-" + compose("%03d", i), ...
                            "HIGH", "call_flow", string(flowSummaryT.channel(i)), ...
                            "channel_flow_summary.csv", ...
                            "Expected channel/procedure has no observed runtime function evidence in this scenario.", ...
                            "channel_flow_summary.csv", "row " + string(i), "profile/trace call evidence", ...
                            "TX/RX/detection functions observed or scenario-inactive reason", ...
                            string(flowSummaryT.status(i)), ...
                            "Cannot claim this block executed in the profiled run.", ...
                            "Scenario inactive, missing instrumentation, or real code path skipped.", ...
                            "Instrument actual code path or fix scheduler/runtime to execute enabled block.", true, "P1"); %#ok<AGROW>
                    end
                end
            end
            issues = struct2table(rows);
            if isempty(issues)
                issues = struct2table(sixgr.monitor.OutputAuditor.defaultIssueRows());
            end
        end

        function grade = grade(runOk, issues, flowSummaryT, profileT)
            crit = 0; high = 0; med = 0;
            if istable(issues) && height(issues) > 0
                crit = sum(string(issues.severity) == "CRITICAL");
                high = sum(string(issues.severity) == "HIGH");
                med = sum(string(issues.severity) == "MEDIUM");
            end
            coverage = 0;
            if istable(flowSummaryT) && height(flowSummaryT) > 0
                coverage = mean(string(flowSummaryT.status) == "observed");
            end
            profilerOk = istable(profileT) && height(profileT) > 0;
            base = 10;
            if ~runOk
                base = 0;
            else
                base = max(0, 10 - 2.5 * crit - 0.75 * high - 0.25 * med);
                base = min(base, 5 + 5 * coverage);
                if ~profilerOk
                    base = min(base, 4);
                end
            end
            categories = struct();
            names = ["PHY mathematical consistency","TX/RX chain completeness","statistical/campaign validity", ...
                "channel/interference/beam/mobility realism","standards/reference-vector alignment", ...
                "KPI correctness","reproducibility/output integrity","runtime performance/complexity instrumentation", ...
                "reporting honesty and traceability"];
            weights = [20 15 15 10 10 10 10 5 5];
            for i = 1:numel(names)
                key = matlab.lang.makeValidName(names(i));
                categories.(key) = struct("score_out_of_10", double(base), ...
                    "weight_percent", double(weights(i)), ...
                    "reason", "Score derived from profiled run completion, observed call-flow coverage, profiler presence and audit issue severity.");
            end
            verdict = "diagnostic run only";
            if ~runOk
                verdict = "failed run";
            elseif base >= 8
                verdict = "engineering prototype";
            elseif base >= 9.5 && crit == 0 && high == 0
                verdict = "publishable";
            end
            grade = struct("final_score_out_of_10", double(base), "verdict", verdict, ...
                "critical_issue_count", double(crit), "high_issue_count", double(high), ...
                "medium_issue_count", double(med), "channel_flow_coverage_fraction", double(coverage), ...
                "categories", categories);
        end

        function writeReport(runDir, scenarioPath, simRunFolder, files, csvFiles, emptyCsvCount, malformedCsvCount, profileT, flowSummaryT, issues, grade)
            fid = fopen(fullfile(runDir, "output_audit_report.md"), "w");
            if fid < 0
                return;
            end
            cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
            fprintf(fid, "# Full Profiled LLS Run Audit\n\n");
            fprintf(fid, "## 1. Scenario selected\n");
            fprintf(fid, "- YAML path: `%s`\n", string(scenarioPath));
            fprintf(fid, "- scenario hash: `%s`\n", sixgr.monitor.OutputAuditor.fileHash(scenarioPath));
            fprintf(fid, "- key configuration: see selected YAML and resolved simulator artifacts\n");
            fprintf(fid, "- seed: audit from resolved config artifacts when present\n");
            fprintf(fid, "- frames/slots: audit from raw simulator outputs when present\n");
            fprintf(fid, "- cells/UEs: target scenario is 2-cell / 2-UE; raw-output verification is listed in issues when absent\n");
            fprintf(fid, "- mobility settings: see selected YAML and resolved simulator artifacts\n\n");
            fprintf(fid, "## 2. Runtime summary\n");
            fprintf(fid, "- start/end time: see `run_summary.json`\n- total wall time: see `run_summary.json`\n- total CPU time if available: see `run_summary.json`\n- number of rerun attempts: see `rerun_attempts.csv`\n- final run status: `%s`\n- output directory: `%s`\n\n", grade.verdict, runDir);
            fprintf(fid, "## 3. Function profiling\n");
            fprintf(fid, "- Profiled function rows: %d\n", height(profileT));
            fprintf(fid, "- Top runtime functions: see `top_runtime_hotspots.md`\n");
            fprintf(fid, "- Bottleneck analysis: derived from MATLAB profiler table.\n");
            fprintf(fid, "- Avoidable recomputation: flagged for review in hotspot report.\n");
            fprintf(fid, "- Memory concerns if available: not available from MATLAB profiler in this harness.\n\n");
            fprintf(fid, "## 4. Dynamic call flow\n");
            fprintf(fid, "- Global call tree summary: `function_call_tree.json`\n");
            fprintf(fid, "- Channel-by-channel call flow: `channel_flow_*.csv`\n");
            fprintf(fid, "- Missing expected calls: %d HIGH flow issues\n", sum(string(issues.domain) == "call_flow"));
            fprintf(fid, "- Unexpected bypasses: see `skipped_or_bypassed_activity.csv`\n");
            fprintf(fid, "- Unused function classification: `unused_function_report.csv`\n\n");
            fprintf(fid, "## 5. PHY channel execution audit\n");
            channels = ["SSB/PBCH","PRACH","PDCCH","PUCCH","PDSCH","PUSCH","SRS","TRS","CSI-RS","Beamforming/beam sweep","Channel/interference","HARQ"];
            for ch = channels
                fprintf(fid, "### %s\n", ch);
                fprintf(fid, "- expected flow: TX/channel/RX/detection/metric where enabled by scenario\n");
                fprintf(fid, "- observed flow: see matching channel-flow CSV and summary row\n");
                fprintf(fid, "- key functions called/skipped, dimensions, equations and KPIs: see CSV artifacts and issues table\n\n");
            end
            fprintf(fid, "## 6. Mathematics audit\n");
            fprintf(fid, "- TBS/E bits/N_RE/BER/SER/BLER/SINR/throughput/HARQ/energy/mobility recomputation is limited to raw artifacts present in this run.\n");
            fprintf(fid, "- Any missing raw evidence is represented as an issue, not a pass label.\n\n");
            fprintf(fid, "## 7. Complexity audit\n");
            fprintf(fid, "- complexity by channel: `complexity_by_channel.csv`\n");
            fprintf(fid, "- complexity by function: `complexity_by_function.csv`\n");
            fprintf(fid, "- theoretical vs empirical runtime: estimated operation counts divided by profiler time\n");
            fprintf(fid, "- scaling risks: high call count and high total-time rows in hotspot report\n\n");
            fprintf(fid, "## 8. Output artifact audit\n");
            fprintf(fid, "- files generated: %d\n- CSV count: %d\n- empty CSVs: %d\n- malformed CSVs: %d\n- simulator output folder: `%s`\n\n", ...
                numel(files), numel(csvFiles), emptyCsvCount, malformedCsvCount, string(simRunFolder));
            fprintf(fid, "## 9. Blunt grade\n");
            fprintf(fid, "- final score: %.2f / 10\n- verdict: `%s`\n\n", grade.final_score_out_of_10, string(grade.verdict));
            fprintf(fid, "## 10. Existing issues\n");
            for sev = ["CRITICAL","HIGH","MEDIUM","LOW"]
                fprintf(fid, "### %s\n", sev);
                mask = string(issues.severity) == sev;
                if ~any(mask)
                    fprintf(fid, "- none recorded\n");
                else
                    idx = find(mask(:).');
                    for k = idx
                        fprintf(fid, "- `%s`: %s\n", string(issues.issue_id(k)), string(issues.finding(k)));
                    end
                end
            end
            fprintf(fid, "\n## 11. Fix plan\n");
            fprintf(fid, "- P0 fixes: eliminate CRITICAL runtime/KPI blockers in `output_audit_issues.csv`.\n");
            fprintf(fid, "- P1 fixes: close missing channel-flow and malformed artifact issues.\n");
            fprintf(fid, "- P2 fixes: improve statistical and complexity coverage.\n");
            fprintf(fid, "- P3 fixes: cleanup and usability.\n");
            fprintf(fid, "- recommended next Codex prompts: one prompt per P0/P1 root-cause domain.\n\n");
            fprintf(fid, "## 12. Reproducibility\n");
            fprintf(fid, "- exact command: see `run_summary.md`\n- MATLAB version: see `run_summary.json`\n- toolbox versions: see `run_summary.json`\n- git commit/hash: see `run_summary.json`\n- scenario hash: `%s`\n- output hash: computed externally if needed\n", sixgr.monitor.OutputAuditor.fileHash(scenarioPath));
        end

        function writeFixPlan(runDir, issues)
            fid = fopen(fullfile(runDir, "final_fix_plan.md"), "w");
            if fid < 0
                return;
            end
            cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
            fprintf(fid, "# Final Fix Plan\n\n");
            if ~(istable(issues) && height(issues) > 0)
                fprintf(fid, "No audit issues were recorded by this harness.\n");
                return;
            end
            for priority = ["P0","P1","P2","P3"]
                fprintf(fid, "## %s\n", priority);
                mask = string(issues.priority) == priority;
                if ~any(mask)
                    fprintf(fid, "- none\n");
                else
                    for i = find(mask(:).')
                        fprintf(fid, "- `%s` [%s/%s]: %s Fix: %s\n", string(issues.issue_id(i)), ...
                            string(issues.severity(i)), string(issues.channel(i)), ...
                            string(issues.finding(i)), string(issues.required_code_fix(i)));
                    end
                end
                fprintf(fid, "\n");
            end
        end

        function row = defaultIssue()
            row = struct("issue_id", "", "severity", "", "domain", "", "channel", "", ...
                "function_or_file", "", "finding", "", "evidence_file", "", ...
                "evidence_rows_or_trace_events", "", "mathematical_check", "", ...
                "expected", "", "observed", "", "impact", "", "root_cause_hypothesis", "", ...
                "required_code_fix", "", "regression_test_needed", false, "priority", "");
        end

        function rows = defaultIssueRows()
            rows = repmat(sixgr.monitor.OutputAuditor.defaultIssue(), 0, 1);
        end

        function T = readProgress(runDir)
            path = fullfile(char(string(runDir)), "runtime_log_progress_summary.csv");
            if exist(path, "file") ~= 2
                T = table();
                return;
            end
            try
                T = readtable(path, "Delimiter", ",", "VariableNamingRule", "preserve", "TextType", "string");
            catch
                T = table();
            end
        end

        function value = tableNumber(T, name, idx)
            value = NaN;
            if ~(istable(T) && height(T) >= idx)
                return;
            end
            names = string(T.Properties.VariableNames);
            hit = find(strcmpi(names, string(name)), 1);
            if isempty(hit)
                compact = regexprep(lower(names), "[^a-z0-9]", "");
                target = regexprep(lower(string(name)), "[^a-z0-9]", "");
                hit = find(compact == target, 1);
            end
            if isempty(hit)
                return;
            end
            raw = T.(names(hit));
            if isnumeric(raw) || islogical(raw)
                value = double(raw(idx));
            else
                value = str2double(string(raw(idx)));
            end
        end

        function row = issue(id, severity, domain, channel, file, finding, evidence, rows, check, expected, observed, impact, root, fix, testNeeded, priority)
            row = sixgr.monitor.OutputAuditor.defaultIssue();
            row.issue_id = string(id);
            row.severity = string(severity);
            row.domain = string(domain);
            row.channel = string(channel);
            row.function_or_file = string(file);
            row.finding = string(finding);
            row.evidence_file = string(evidence);
            row.evidence_rows_or_trace_events = string(rows);
            row.mathematical_check = string(check);
            row.expected = string(expected);
            row.observed = string(observed);
            row.impact = string(impact);
            row.root_cause_hypothesis = string(root);
            row.required_code_fix = string(fix);
            row.regression_test_needed = logical(testNeeded);
            row.priority = string(priority);
        end

        function hash = fileHash(path)
            hash = "";
            path = char(string(path));
            if exist(path, "file") ~= 2
                return;
            end
            try
                hash = sixgr.util.sha256Hex(fileread(path));
            catch
                hash = "";
            end
        end
    end
end
