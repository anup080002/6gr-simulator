function out = buildPHYPackageExecutionAudit(runFolder, repoRoot)
%BUILDPHYPACKAGEEXECUTIONAUDIT Bind selected PHY source files to profiler truth.
%
% The audit deliberately distinguishes executable runtime libraries from
% validation oracles, impact studies, and artifact publishers.  A file is
% reported as executed only when MATLAB's profiler names that exact source
% file.  Static references, output-file presence, and substring matches are
% not execution evidence.

arguments
    runFolder {mustBeTextScalar}
    repoRoot {mustBeTextScalar} = pwd
end

runFolder = char(string(runFolder));
repoRoot = char(string(repoRoot));
layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ReportCSVDir);

profilePath = fullfile(layout.ReportCSVDir, "runtime_function_profile.csv");
summaryPath = fullfile(layout.ReportCSVDir, "runtime_profiler_summary.csv");
ledgerPath = fullfile(layout.ReportCSVDir, "runtime_call_ledger.csv");
profileT = localReadTable(profilePath);
profilerSummaryT = localReadTable(summaryPath);
ledgerT = localReadTable(ledgerPath);
[ledgerAvailable, ledgerIdentityComplete] = localLedgerState(ledgerT);
[profileAvailable, profileComplete, exportedFunctions, capturedFunctions] = ...
    localProfilerState(profileT, profilerSummaryT);

inventory = sixgr.monitor.StaticInventory.scan(repoRoot);
roots = [ ...
    "+sixgr/+pdsch/"
    "+sixgr/+phy/+ul/+pusch/"
    "+sixgr/+phy/+pucch/"
    "+sixgr/+phy/+pdcch/"
    "+sixgr/+phy/+ra/"
    "+sixgr/+phy/+srs/"
    "+sixgr/+phy/+trs/"
    "+sixgr/+mimo/"
    "+sixgr/+phy/+rx/"];
rel = lower(replace(string(inventory.file_path), "\", "/"));
selected = false(height(inventory), 1);
for root = roots(:).'
    selected = selected | startsWith(rel, lower(root));
end
% The canonical data/control facades live beside, rather than beneath, the
% feature packages.  Omitting them can make a profile appear complete while
% failing to prove that the actual Tx/Rx trust-boundary wrappers ran.
criticalFacades = [ ...
    "+sixgr/+phy/+dl/pdsch_tx.m"
    "+sixgr/+phy/+dl/pdsch_rx.m"
    "+sixgr/+phy/+dl/pdcch_tx.m"
    "+sixgr/+phy/+dl/pdcch_rx.m"
    "+sixgr/+phy/+ul/pusch_tx.m"
    "+sixgr/+phy/+ul/pusch_rx.m"
    "+sixgr/+link/runpucchwaveformtrial.m"
    "+sixgr/+link/runprachdetection.m"];
selected = selected | ismember(rel, criticalFacades);
inventory = inventory(selected, :);

rows = repmat(localEmptyRow(), height(inventory), 1);
for i = 1:height(inventory)
    relativePath = replace(string(inventory.file_path(i)), "\", "/");
    absolutePath = localNormalizePath(fullfile(repoRoot, char(relativePath)));
    profileMask = localExactProfileFileMask(profileT, absolutePath);
    qualifiedName = localQualifiedName(relativePath);
    ledgerMask = localExactLedgerFunctionMask(ledgerT, qualifiedName);
    called = any(profileMask) || any(ledgerMask);
    role = localSourceRole(relativePath, string(inventory.primary_function_or_class(i)));
    rows(i).FilePath = relativePath;
    rows(i).QualifiedName = qualifiedName;
    rows(i).Package = localAuditPackage(relativePath);
    rows(i).PrimaryFunctionOrClass = string(inventory.primary_function_or_class(i));
    rows(i).SourceRole = role;
    rows(i).RuntimeLibraryCandidate = role == "runtime_library";
    rows(i).ActuallyCalled = called;
    rows(i).CallCount = localExactCallCount(profileT, profileMask, ledgerMask);
    rows(i).TotalTime_s = localProfileSum(profileT, profileMask, "TotalTime_s");
    rows(i).ProfilerAvailable = profileAvailable;
    rows(i).ProfilerComplete = profileComplete;
    rows(i).ProfilerExportedFunctionCount = exportedFunctions;
    rows(i).ProfilerCapturedFunctionCount = capturedFunctions;
    rows(i).ExecutionEvidence = localExecutionEvidence(called, ledgerAvailable, profileAvailable, profileComplete);
    rows(i).UsageAssessment = localUsageAssessment(role, called, profileAvailable, profileComplete);
    rows(i).SourceSHA256 = localFileSHA256(fullfile(repoRoot, char(relativePath)));
    rows(i).EvidenceSource = localEvidenceSource(any(ledgerMask), any(profileMask));
end

detailT = struct2table(rows);
if height(detailT) > 0
    detailT = sortrows(detailT, {'Package','SourceRole','FilePath'});
end
summaryT = localBuildSummary(detailT, ledgerAvailable, profileAvailable, profileComplete, ...
    exportedFunctions, capturedFunctions);
gateT = localBuildEvidenceGate(detailT, ledgerAvailable, ledgerIdentityComplete, ...
    profileAvailable, profileComplete, exportedFunctions, capturedFunctions);

detailPath = fullfile(layout.ReportCSVDir, "phy_package_execution_audit.csv");
summaryOutPath = fullfile(layout.ReportCSVDir, "phy_package_execution_summary.csv");
gatePath = fullfile(layout.ReportCSVDir, "phy_package_execution_evidence_gate.csv");
sixgr.util.csvWriteTable(detailPath, detailT);
sixgr.util.csvWriteTable(summaryOutPath, summaryT);
sixgr.util.csvWriteTable(gatePath, gateT);

out = struct( ...
    "DetailTable", detailT, ...
    "SummaryTable", summaryT, ...
    "GateTable", gateT, ...
    "DetailPath", string(detailPath), ...
    "SummaryPath", string(summaryOutPath), ...
    "GatePath", string(gatePath), ...
    "ProfilerAvailable", profileAvailable, ...
    "ProfilerComplete", profileComplete);
end

function row = localEmptyRow()
row = struct( ...
    "FilePath", "", ...
    "QualifiedName", "", ...
    "Package", "", ...
    "PrimaryFunctionOrClass", "", ...
    "SourceRole", "", ...
    "RuntimeLibraryCandidate", false, ...
    "ActuallyCalled", false, ...
    "CallCount", 0, ...
    "TotalTime_s", 0, ...
    "ProfilerAvailable", false, ...
    "ProfilerComplete", false, ...
    "ProfilerExportedFunctionCount", 0, ...
    "ProfilerCapturedFunctionCount", 0, ...
    "ExecutionEvidence", "", ...
    "UsageAssessment", "", ...
    "SourceSHA256", "", ...
    "EvidenceSource", "");
end

function [available, complete, exportedCount, capturedCount] = localProfilerState(profileT, summaryT)
available = height(profileT) > 0 && ismember("FileName", string(profileT.Properties.VariableNames));
exportedCount = height(profileT);
capturedCount = NaN;
if height(summaryT) > 0
    capturedCount = localScalar(summaryT, "FunctionCount", NaN);
    exportedCount = localScalar(summaryT, "ExportedFunctionCount", exportedCount);
end
complete = available && isfinite(capturedCount) && capturedCount > 0 && exportedCount >= capturedCount;
end

function mask = localExactProfileFileMask(profileT, absolutePath)
mask = false(height(profileT), 1);
if height(profileT) == 0 || ~ismember("FileName", string(profileT.Properties.VariableNames))
    return;
end
paths = strings(height(profileT), 1);
for i = 1:height(profileT)
    paths(i) = localNormalizePath(string(profileT.FileName(i)));
end
mask = strcmpi(paths, absolutePath);
end

function path = localNormalizePath(path)
path = replace(string(path), "\", "/");
while contains(path, "//")
    path = replace(path, "//", "/");
end
path = lower(path);
end

function role = localSourceRole(path, primaryName)
token = lower(replace(string(path), "\", "/"));
name = lower(string(primaryName));
if contains(token, "/+oracle/")
    role = "validation_oracle";
elseif contains(token, "/+analysis/") || contains(name, "impact")
    role = "offline_impact_analysis";
elseif contains(name, "phasevalidation") || contains(name, "focusedtest") || ...
        contains(name, "negativecase") || startsWith(name, "runstrict")
    role = "validation_campaign";
elseif contains(name, "artifact") || contains(name, "evidencebuilder") || ...
        contains(name, "publisher") || startsWith(name, "export")
    role = "artifact_reporting";
elseif contains(name, "study") || contains(name, "coverageexecutor")
    role = "offline_study";
elseif contains(token, "/+legacy/") || contains(name, "legacy")
    role = "legacy";
else
    role = "runtime_library";
end
end

function name = localQualifiedName(path)
parts = split(erase(replace(string(path), "\", "/"), ".m"), "/");
parts = erase(parts, "+");
name = strjoin(parts, ".");
end

function name = localAuditPackage(path)
path = replace(string(path), "\", "/");
pathLower = lower(path);
if startsWith(path, "+sixgr/+pdsch/")
    name = "PDSCH";
elseif any(path == ["+sixgr/+phy/+dl/PDSCH_Tx.m", ...
        "+sixgr/+phy/+dl/PDSCH_Rx.m"])
    name = "PDSCH";
elseif startsWith(path, "+sixgr/+phy/+ul/+pusch/")
    name = "PUSCH";
elseif any(path == ["+sixgr/+phy/+ul/PUSCH_Tx.m", ...
        "+sixgr/+phy/+ul/PUSCH_Rx.m"])
    name = "PUSCH";
elseif startsWith(path, "+sixgr/+phy/+pucch/")
    name = "PUCCH";
elseif startsWith(path, "+sixgr/+phy/+pdcch/")
    name = "PDCCH";
elseif pathLower == "+sixgr/+link/runpucchwaveformtrial.m"
    name = "PUCCH";
elseif pathLower == "+sixgr/+link/runprachdetection.m" || startsWith(pathLower, "+sixgr/+phy/+ra/")
    name = "INITIAL_ACCESS";
elseif startsWith(pathLower, "+sixgr/+phy/+srs/")
    name = "SRS";
elseif startsWith(pathLower, "+sixgr/+phy/+trs/")
    name = "TRS";
elseif any(path == ["+sixgr/+phy/+dl/PDCCH_Tx.m", ...
        "+sixgr/+phy/+dl/PDCCH_Rx.m"])
    name = "PDCCH";
elseif startsWith(path, "+sixgr/+mimo/")
    name = "MIMO";
elseif startsWith(path, "+sixgr/+phy/+rx/")
    name = "RX";
else
    name = "OTHER";
end
end

function value = localProfileSum(profileT, mask, variableName)
value = 0;
if ~any(mask) || ~ismember(variableName, string(profileT.Properties.VariableNames))
    return;
end
raw = profileT.(variableName)(mask);
if ~isnumeric(raw)
    raw = str2double(string(raw));
end
value = sum(double(raw), "omitnan");
end

function value = localExactCallCount(profileT, profileMask, ledgerMask)
% A profiler row and a call-ledger row are two observations of the same
% execution, not independent calls. Prefer the profiler's measured call
% count when present; otherwise use the number of exact ledger entries.
if any(profileMask)
    value = localProfileSum(profileT, profileMask, "NumCalls");
else
    value = sum(ledgerMask);
end
end

function state = localExecutionEvidence(called, ledgerAvailable, available, complete)
if called
    state = "exact_runtime_entry_or_profiler_match";
elseif ledgerAvailable
    state = "not_called_in_runtime_call_ledger";
elseif ~available
    state = "profiler_unavailable";
elseif ~complete
    state = "not_present_in_truncated_profiler_export";
else
    state = "not_called_in_profiled_scenario";
end
end

function state = localUsageAssessment(role, called, available, complete)
if called
    state = "executed_in_profiled_scenario";
elseif role ~= "runtime_library"
    state = "not_required_in_runtime_chain:" + role;
elseif ~available
    state = "unknown_profiler_unavailable";
elseif ~complete
    state = "unknown_profiler_export_truncated";
else
    state = "runtime_library_not_exercised_in_this_scenario";
end
end

function T = localBuildSummary(detailT, ledgerAvailable, available, complete, exportedCount, capturedCount)
packages = ["PDSCH";"PUSCH";"PUCCH";"PDCCH";"MIMO";"RX";"INITIAL_ACCESS";"SRS";"TRS"];
roles = ["ALL";"runtime_library";"validation_oracle";"validation_campaign"; ...
    "offline_impact_analysis";"offline_study";"artifact_reporting";"legacy"];
rows = repmat(struct("Package","","SourceRole","","FileCount",0, ...
    "ExecutedFileCount",0,"NotExecutedFileCount",0,"ProfilerAvailable",false, ...
    "ProfilerComplete",false,"ProfilerExportedFunctionCount",0, ...
    "ProfilerCapturedFunctionCount",0,"Assessment",""), 0, 1);
for p = packages(:).'
    for role = roles(:).'
        mask = detailT.Package == p;
        if role ~= "ALL"
            mask = mask & detailT.SourceRole == role;
        end
        if ~any(mask) && role ~= "ALL"
            continue;
        end
        rows(end+1,1) = struct( ... %#ok<AGROW>
            "Package", p, "SourceRole", role, "FileCount", sum(mask), ...
            "ExecutedFileCount", sum(detailT.ActuallyCalled(mask)), ...
            "NotExecutedFileCount", sum(~detailT.ActuallyCalled(mask)), ...
            "ProfilerAvailable", available, "ProfilerComplete", complete, ...
            "ProfilerExportedFunctionCount", exportedCount, ...
            "ProfilerCapturedFunctionCount", capturedCount, ...
            "Assessment", localSummaryAssessment(ledgerAvailable, available, complete));
    end
end
T = struct2table(rows);
end

function state = localSummaryAssessment(ledgerAvailable, available, complete)
if ledgerAvailable
    state = "RUNTIME_CALL_LEDGER_AVAILABLE";
elseif ~available
    state = "NO_RUNTIME_PROFILE";
elseif ~complete
    state = "PARTIAL_RUNTIME_PROFILE_DO_NOT_TREAT_ABSENCE_AS_UNUSED";
else
    state = "COMPLETE_RUNTIME_PROFILE";
end
end

function T = localBuildEvidenceGate(detailT, ledgerAvailable, ledgerIdentityComplete, available, complete, exportedCount, capturedCount)
T = table( ...
    ["runtime_call_ledger_available";"runtime_call_ledger_identity_complete"; ...
     "selected_source_inventory_nonempty";"runtime_profiler_available";"runtime_profiler_export_complete"], ...
    [true;true;true;false;false], ...
    [ledgerAvailable;ledgerIdentityComplete;height(detailT) > 0;available;complete], ...
    ["runtime_call_ledger.csv contains canonical entry observations"; ...
     "every runtime ledger row carries execution and config identity"; ...
     "requested production PHY roots contain source files"; ...
     "runtime_function_profile.csv contains exact source paths"; ...
     "all captured MATLAB profiler functions are exported"], ...
    ["ledger_available=" + string(ledgerAvailable); ...
     "identity_complete=" + string(ledgerIdentityComplete); ...
     "files=" + string(height(detailT)); ...
     "exported=" + string(exportedCount); ...
     "exported=" + string(exportedCount) + ";captured=" + string(capturedCount)], ...
    'VariableNames', {'Gate','Required','Pass','Definition','Observed'});
end

function [available, identityComplete] = localLedgerState(T)
required = ["FunctionName","ExecutionID","ConfigHash","EvidenceClass"];
available = height(T) > 0 && all(ismember(required,string(T.Properties.VariableNames)));
identityComplete = available && all(strlength(strtrim(string(T.FunctionName))) > 0) && ...
    all(strlength(strtrim(string(T.ExecutionID))) > 0) && ...
    all(strlength(strtrim(string(T.ConfigHash))) == 64) && ...
    all(string(T.EvidenceClass) == "ACTUAL_RUNTIME_ENTRY");
end

function mask = localExactLedgerFunctionMask(T, qualifiedName)
mask = false(height(T),1);
if isempty(T) || ~ismember("FunctionName",string(T.Properties.VariableNames)), return; end
mask = strcmpi(strtrim(string(T.FunctionName)),strtrim(string(qualifiedName)));
end

function source = localEvidenceSource(ledgerMatch, profilerMatch)
if ledgerMatch && profilerMatch
    source = "runtime_call_ledger+exact_profiler_file_match";
elseif ledgerMatch
    source = "reports/csv/runtime_call_ledger.csv:exact_qualified_name_match";
elseif profilerMatch
    source = "reports/csv/runtime_function_profile.csv:exact_FileName_match";
else
    source = "no_runtime_entry_evidence";
end
end

function digest = localFileSHA256(path)
fid = fopen(path, "rb");
if fid < 0
    digest = "";
    return;
end
cleanup = onCleanup(@()fclose(fid)); %#ok<NASGU>
digest = sixgr.util.sha256Hex(fread(fid, Inf, "*uint8"));
end

function value = localScalar(T, name, defaultValue)
value = defaultValue;
if height(T) == 0 || ~ismember(name, string(T.Properties.VariableNames))
    return;
end
raw = T.(name)(1);
if isnumeric(raw) || islogical(raw)
    value = double(raw);
else
    value = str2double(string(raw));
end
end

function T = localReadTable(path)
if exist(path, "file") ~= 2
    T = table();
    return;
end
try
    T = readtable(path, "VariableNamingRule", "preserve", "TextType", "string");
catch
    T = table();
end
end

function mustBeTextScalar(value)
if ~(ischar(value) || (isstring(value) && isscalar(value)))
    error("sixgr:analytics:buildPHYPackageExecutionAudit:InvalidPath", ...
        "Paths must be character vectors or string scalars.");
end
end
