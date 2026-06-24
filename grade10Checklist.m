function result = grade10Checklist(runDir)
%GRADE10CHECKLIST Fail-closed Prompt 9 publication-readiness checklist.

runDir = char(string(runDir));
if exist(runDir, "dir") ~= 7
    error("sixgr:grade10Checklist:RunDirMissing", "Run directory does not exist: %s", runDir);
end

checks = {
    "SSB/PBCH/MIB", "control/csv/sib1_conformance_summary.csv", "DCI_Found", 1
    "SIB1", "control/csv/sib1_conformance_summary.csv", "StrictOk", 1
    "PRACH", "control/csv/prach_config_strict.csv", "StrictOk", 1
    "RAR/MSG3/MSG4", "control/csv/ra_attempts.csv", "RACHSuccess", 1
    "PDCCH", "control/csv/pdcch_config_strict.csv", "StrictOk", 1
    "PDSCH", "air_interface/csv/dl_pdsch_trials.csv", "CRCPass", NaN
    "PUSCH", "air_interface/csv/ul_pusch_trials.csv", "CRCPass", NaN
    "PUCCH", "air_interface/csv/pucch_trials.csv", "StrictOk", 1
    "SRS", "control/csv/srs_config_strict.csv", "StrictOk", 1
    "TRS", "control/csv/trs_config_strict.csv", "StrictOk", 1
    "ChannelRF", "reports/csv/channel_rf_strict_summary.csv", "StrictOk", 1
    "HARQ", "air_interface/csv/harq_combining_gain.csv", "Exercised", 1
    "MIMO", "beamforming/csv/mimo_config_strict.csv", "StrictOk", 1
    "Scheduler", "packet_flow/csv/scheduler_decision_log.csv", "", NaN
    };

rows = repmat(struct("CheckName", "", "Artifact", "", "ColumnName", "", ...
    "Exists", false, "ObservedValue", NaN, "ExpectedValue", NaN, "Ok", false, "Status", ""), size(checks, 1), 1);
for i = 1:size(checks, 1)
    name = string(checks{i, 1});
    rel = string(checks{i, 2});
    col = string(checks{i, 3});
    expected = double(checks{i, 4});
    path = fullfile(runDir, strrep(char(rel), "/", filesep));
    existsFlag = exist(path, "file") == 2;
    observed = NaN;
    ok = false;
    status = "missing";
    if existsFlag
        if strlength(col) == 0
            ok = true;
            status = "present";
        else
            try
                T = readtable(path, "TextType", "string", "VariableNamingRule", "preserve");
                if any(strcmpi(string(T.Properties.VariableNames), col))
                    vals = localColumnDouble(T, col);
                    observed = mean(vals, "omitnan");
                    if isnan(expected)
                        ok = any(isfinite(vals));
                        status = localTernary(ok, "present_with_values", "present_without_numeric_values");
                    else
                        ok = isfinite(observed) && observed >= expected * 0.99;
                        status = localTernary(ok, "threshold_pass", "threshold_fail");
                    end
                else
                    status = "column_missing";
                end
            catch ME
                status = "unreadable:" + string(ME.identifier);
            end
        end
    end
    rows(i) = struct("CheckName", name, "Artifact", rel, "ColumnName", col, ...
        "Exists", existsFlag, "ObservedValue", observed, "ExpectedValue", expected, ...
        "Ok", ok, "Status", status);
end

audit = sixgr.audit.verifyMeasurementOnly(runDir, "ErrorOnViolation", false);
rows(end+1, 1) = struct("CheckName", "MeasurementOnlyAudit", ...
    "Artifact", "reports/csv/measurement_only_audit.csv", "ColumnName", "ViolationCount", ...
    "Exists", true, "ObservedValue", double(audit.ViolationCount), "ExpectedValue", 0, ...
    "Ok", logical(audit.Ok), "Status", localTernary(logical(audit.Ok), "pass", "fail")); %#ok<AGROW>

T = struct2table(rows, "AsArray", true);
result = struct();
result.Ok = all(logical(T.Ok));
result.Table = T;
result.FailedChecks = string(T.CheckName(~logical(T.Ok)));
result.Summary = localTernary(result.Ok, "GRADE_10_CHECKLIST_PASS", "GRADE_10_CHECKLIST_FAIL");

layout = sixgr.report.resultLayout(runDir);
sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "grade10_checklist.csv"), T);
sixgr.util.jsonWrite(fullfile(layout.ReportDir, "json", "grade10_checklist.json"), ...
    struct("Ok", logical(result.Ok), "Summary", string(result.Summary), "FailedChecks", result.FailedChecks));

fprintf("\nGrade 10 checklist: %s\n", result.Summary);
if ~result.Ok
    fprintf("Failed checks: %s\n", strjoin(result.FailedChecks, ", "));
end
end

function vals = localColumnDouble(T, name)
idx = find(strcmpi(string(T.Properties.VariableNames), string(name)), 1, "first");
raw = T.(T.Properties.VariableNames{idx});
if islogical(raw)
    vals = double(raw);
elseif isnumeric(raw)
    vals = double(raw);
else
    txt = lower(strtrim(string(raw)));
    vals = str2double(txt);
    vals(txt == "true" | txt == "pass" | txt == "passed" | txt == "ok") = 1;
    vals(txt == "false" | txt == "fail" | txt == "failed") = 0;
end
vals = vals(:);
end

function out = localTernary(cond, a, b)
if logical(cond)
    out = string(a);
else
    out = string(b);
end
end
