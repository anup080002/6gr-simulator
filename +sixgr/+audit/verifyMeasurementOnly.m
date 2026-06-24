function report = verifyMeasurementOnly(runDir, varargin)
%VERIFYMEASUREMENTONLY Audit trial artifacts for Prompt 9 oracle contracts.

p = inputParser;
p.addParameter("ErrorOnViolation", true, @(x)islogical(x) || isnumeric(x));
p.addParameter("StrictMissingArtifacts", false, @(x)islogical(x) || isnumeric(x));
p.addParameter("WriteArtifacts", true, @(x)islogical(x) || isnumeric(x));
p.parse(varargin{:});
opt = p.Results;

runDir = char(string(runDir));
if exist(runDir, "dir") ~= 7
    error("sixgr:audit:verifyMeasurementOnly:RunDirMissing", "Run directory does not exist: %s", runDir);
end

files = localOracleFiles();
rows = repmat(localEmptyRow(), 0, 1);
presentFiles = 0;
for i = 1:numel(files)
    rel = files(i);
    path = fullfile(runDir, strrep(char(rel), "/", filesep));
    if exist(path, "file") ~= 2
        if logical(opt.StrictMissingArtifacts)
            rows(end+1, 1) = localRow(rel, false, 0, "artifact_presence", "fail", ...
                "violation", 1, "required measurement artifact missing"); %#ok<AGROW>
        else
            rows(end+1, 1) = localRow(rel, false, 0, "artifact_presence", "missing_skipped", ...
                "info", 0, "artifact not present in this run"); %#ok<AGROW>
        end
        continue;
    end
    presentFiles = presentFiles + 1;
    try
        T = readtable(path, "TextType", "string", "VariableNamingRule", "preserve");
    catch ME
        rows(end+1, 1) = localRow(rel, true, NaN, "readability", "fail", ...
            "violation", 1, "unreadable CSV: " + string(ME.identifier)); %#ok<AGROW>
        continue;
    end
    rows = [rows; localAuditTable(rel, T)]; %#ok<AGROW>
end

if presentFiles == 0
    rows(end+1, 1) = localRow("run", false, 0, "measurement_artifact_inventory", ...
        "fail", "violation", 1, "no Prompt 9 measurement trial artifacts were found"); %#ok<AGROW>
end

T = struct2table(rows, "AsArray", true);
violationMask = strcmpi(string(T.Severity), "violation") & double(T.ViolationCount) > 0;
warningMask = strcmpi(string(T.Severity), "warning") & double(T.ViolationCount) > 0;

report = struct();
report.Ok = ~any(violationMask);
report.ViolationCount = sum(double(T.ViolationCount(violationMask)));
report.WarningCount = sum(double(T.ViolationCount(warningMask)));
report.PresentArtifactCount = presentFiles;
report.Table = T;

if logical(opt.WriteArtifacts)
    layout = sixgr.report.resultLayout(runDir);
    sixgr.analytics.writeAnalysisTable(fullfile(layout.ReportCSVDir, "measurement_only_audit.csv"), T);
    jsonSafe = rmfield(report, "Table");
    sixgr.util.jsonWrite(fullfile(layout.ReportDir, "json", "measurement_only_audit.json"), jsonSafe);
end

if logical(opt.ErrorOnViolation) && ~report.Ok
    bad = string(T.Artifact(violationMask)) + ":" + string(T.CheckName(violationMask));
    error("sixgr:audit:verifyMeasurementOnly:OracleViolation", ...
        "Measurement-only audit failed with %d violation(s): %s", ...
        report.ViolationCount, strjoin(bad, ", "));
end
end

function rows = localAuditTable(rel, T)
rows = repmat(localEmptyRow(), 0, 1);
rows(end+1, 1) = localRow(rel, true, height(T), "artifact_presence", "pass", "info", 0, "artifact present"); %#ok<AGROW>

rows = [rows; localBlankColumnCheck(rel, T, "UsedOracleFields", ...
    "used_oracle_fields_blank", "UsedOracleFields must be blank")]; %#ok<AGROW>
rows = [rows; localBadTokenCheck(rel, T, ["NoiseVarSource","DecoderNoiseVarSource","SINRSource"], ...
    ["configured_snr","snr_configured","configured_snr_noise","snr_db_config","10^(-snr"], ...
    "decoder_noise_not_from_configured_snr", "decoder noise or SINR source uses configured SNR")]; %#ok<AGROW>
rows = [rows; localBadTokenCheck(rel, T, ["ChannelEstMethod","ChannelEstimateMethod","HestSource","ChannelEstimateSource"], ...
    ["nrperfectchannelestimate","perfect_channel","perfect"], ...
    "no_perfect_channel_estimate", "channel estimate source is perfect/oracle")]; %#ok<AGROW>
rows = [rows; localBadTokenCheck(rel, T, ["GrantSource","DLGrantSource","ULGrantSource","GrantDecodeSource"], ...
    ["scheduler_struct","configured_grant","oracle_grant","predecoded"], ...
    "grant_from_waveform_decode", "grant source bypasses waveform DCI decode")]; %#ok<AGROW>
rows = [rows; localBadTokenCheck(rel, T, ["TimingAdvanceSource","TASource"], ...
    ["channel_model","geometry_oracle","configured_ta"], ...
    "timing_advance_from_receiver", "timing advance source bypasses receiver measurement")]; %#ok<AGROW>
rows = [rows; localBadTokenCheck(rel, T, ["CQISource","WidebandCQISource"], ...
    ["configured_cqi","static_cqi","oracle_cqi"], ...
    "cqi_from_measurement", "CQI source bypasses CSI measurement")]; %#ok<AGROW>

if localHasVar(T, "RNTI") && localHasVar(T, "UEIndex")
    rnti = localColumnDouble(T, "RNTI");
    ue = localColumnDouble(T, "UEIndex");
    suspicious = sum(ue > 1 & rnti == 1);
    if suspicious > 0
        rows(end+1, 1) = localRow(rel, true, height(T), "rnti_not_default_for_nonfirst_ue", ...
            "warn", "warning", suspicious, "non-first UE rows have RNTI=1; verify RA assignment evidence"); %#ok<AGROW>
    else
        rows(end+1, 1) = localRow(rel, true, height(T), "rnti_not_default_for_nonfirst_ue", ...
            "pass", "info", 0, "no default RNTI pattern detected"); %#ok<AGROW>
    end
end
end

function row = localBlankColumnCheck(rel, T, varName, checkName, details)
if ~localHasVar(T, varName)
    row = localRow(rel, true, height(T), checkName, "not_applicable", "info", 0, "column absent");
    return;
end
txt = localColumnText(T, varName);
bad = strlength(strtrim(txt)) > 0 & ~ismissing(txt);
count = sum(bad);
if count > 0
    row = localRow(rel, true, height(T), checkName, "fail", "violation", count, details);
else
    row = localRow(rel, true, height(T), checkName, "pass", "info", 0, details);
end
end

function rows = localBadTokenCheck(rel, T, varNames, badTokens, checkName, details)
rows = repmat(localEmptyRow(), 0, 1);
matchedAny = false;
totalBad = 0;
for name = string(varNames)
    if ~localHasVar(T, name)
        continue;
    end
    matchedAny = true;
    txt = lower(localColumnText(T, name));
    bad = false(size(txt));
    for token = string(badTokens)
        bad = bad | contains(txt, lower(token));
    end
    totalBad = totalBad + sum(bad);
end
if ~matchedAny
    rows(end+1, 1) = localRow(rel, true, height(T), checkName, "not_applicable", "info", 0, "columns absent"); %#ok<AGROW>
elseif totalBad > 0
    rows(end+1, 1) = localRow(rel, true, height(T), checkName, "fail", "violation", totalBad, details); %#ok<AGROW>
else
    rows(end+1, 1) = localRow(rel, true, height(T), checkName, "pass", "info", 0, details); %#ok<AGROW>
end
end

function files = localOracleFiles()
files = unique([
    "air_interface/csv/dl_pdsch_trials.csv"
    "air_interface/csv/ul_pusch_trials.csv"
    "air_interface/csv/pdcch_trials.csv"
    "air_interface/csv/pucch_trials.csv"
    "air_interface/csv/prach_trials.csv"
    "air_interface/csv/srs_trials.csv"
    "air_interface/csv/trs_trials.csv"
    "control/csv/pdcch_trials.csv"
    "control/csv/pucch_trials.csv"
    "control/csv/prach_trials.csv"
    "control/csv/srs_trials.csv"
    "control/csv/trs_trials.csv"
    "control/csv/ra_attempts.csv"
    "control/csv/msg2_rar_trials.csv"
    "control/csv/sib1_conformance_summary.csv"
    ]);
end

function row = localEmptyRow()
row = struct("Artifact", "", "Exists", false, "RowCount", NaN, "CheckName", "", ...
    "Status", "", "Severity", "", "ViolationCount", 0, "Details", "");
end

function row = localRow(artifact, existsFlag, rowCount, checkName, status, severity, violationCount, details)
row = struct("Artifact", string(artifact), "Exists", logical(existsFlag), ...
    "RowCount", double(rowCount), "CheckName", string(checkName), ...
    "Status", string(status), "Severity", string(severity), ...
    "ViolationCount", double(violationCount), "Details", string(details));
end

function tf = localHasVar(T, varName)
tf = istable(T) && any(strcmpi(string(T.Properties.VariableNames), string(varName)));
end

function values = localColumnText(T, varName)
idx = find(strcmpi(string(T.Properties.VariableNames), string(varName)), 1, "first");
raw = T.(T.Properties.VariableNames{idx});
if iscell(raw)
    values = strings(numel(raw), 1);
    for i = 1:numel(raw)
        values(i) = string(raw{i});
    end
else
    values = string(raw);
end
values = values(:);
values(ismissing(values)) = "";
end

function values = localColumnDouble(T, varName)
idx = find(strcmpi(string(T.Properties.VariableNames), string(varName)), 1, "first");
raw = T.(T.Properties.VariableNames{idx});
try
    values = double(raw);
catch
    values = str2double(string(raw));
end
values = values(:);
end
