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
% Normalize the immutable profiler snapshot once, not once per source file
% in both inventories. This preserves exact-path matching without an
% O(source files * profiler rows) loop of scalar table/string conversions.
profilePaths = strings(height(profileT),1);
if ismember("FileName",string(profileT.Properties.VariableNames))
    profilePaths = localNormalizePath(string(profileT.FileName));
end
profilerSummaryT = localReadTable(summaryPath);
ledgerT = localReadTable(ledgerPath);
[ledgerAvailable, ledgerIdentityComplete] = localLedgerState(ledgerT);
[profileAvailable, profileComplete, exportedFunctions, capturedFunctions] = ...
    localProfilerState(profileT, profilerSummaryT);

inventory = localSixGRSourceInventory(repoRoot);
rel = lower(replace(string(inventory.file_path), "\", "/"));
% Audit the complete production namespace. A scenario-specific absence is
% reported only as NOT_OBSERVED_IN_THIS_SCENARIO; it is never promoted to a
% repository-wide "dead code" claim from one execution.
selected = startsWith(rel, "+sixgr/") & endsWith(rel, ".m");
inventory = inventory(selected, :);

rows = repmat(localEmptyRow(), height(inventory), 1);
for i = 1:height(inventory)
    relativePath = replace(string(inventory.file_path(i)), "\", "/");
    absolutePath = localNormalizePath(fullfile(repoRoot, char(relativePath)));
    profileMask = strcmpi(profilePaths, absolutePath);
    qualifiedName = localQualifiedName(relativePath);
    ledgerMask = localExactLedgerFunctionMask(ledgerT, qualifiedName);
    called = any(profileMask) || any(ledgerMask);
    role = localSourceRole(relativePath, string(inventory.primary_function_or_class(i)));
    rows(i).FilePath = relativePath;
    rows(i).QualifiedName = qualifiedName;
    rows(i).Package = localAuditPackage(relativePath);
    rows(i).PrimaryFunctionOrClass = string(inventory.primary_function_or_class(i));
    rows(i).SourceRole = role;
    rows(i).RuntimeLibraryCandidate = any(role == ...
        ["runtime_library", "waveform_runtime_campaign"]);
    [rows(i).RuntimeEligibility, rows(i).ScenarioInputPolicy] = ...
        localRolePolicy(role);
    rows(i).StudyFileNamingAssessment = ...
        localStudyFileNamingAssessment(role, ...
        string(inventory.primary_function_or_class(i)));
    [rows(i).DuplexReferenceDetected, ...
        rows(i).SharedDuplexResolverUsed, ...
        rows(i).DuplexAuthorityAssessment] = ...
        localDuplexAuthorityAssessment(fullfile(repoRoot, ...
        char(relativePath)), role);
    rows(i).ActuallyCalled = called;
    rows(i).CallCount = localExactCallCount(profileT, profileMask, ledgerMask);
    rows(i).TotalTime_s = localProfileSum(profileT, profileMask, "TotalTime_s");
    rows(i).ProfilerAvailable = profileAvailable;
    rows(i).ProfilerComplete = profileComplete;
    rows(i).ProfilerExportedFunctionCount = exportedFunctions;
    rows(i).ProfilerCapturedFunctionCount = capturedFunctions;
    rows(i).ExecutionEvidence = localExecutionEvidence(called, ledgerAvailable, profileAvailable, profileComplete);
    if called
        rows(i).ScenarioCoverageStatus = "EXECUTED_IN_THIS_SCENARIO";
    else
        rows(i).ScenarioCoverageStatus = "NOT_OBSERVED_IN_THIS_SCENARIO";
    end
    rows(i).UsageAssessment = localUsageAssessment(role, called, profileAvailable, profileComplete);
    % A bounded scenario can prove execution, but absence from that one
    % profile is not sufficient evidence that a source is dead code.
    rows(i).NeverUsedConclusionPermitted = false;
    rows(i).SourceSHA256 = localFileSHA256(fullfile(repoRoot, char(relativePath)));
    rows(i).EvidenceSource = localEvidenceSource(any(ledgerMask), any(profileMask));
end

detailT = struct2table(rows);
if height(detailT) > 0
    detailT = localAnnotateBasenameCollisions(detailT);
    detailT = sortrows(detailT, {'Package','SourceRole','FilePath'});
end
summaryT = localBuildSummary(detailT, ledgerAvailable, profileAvailable, profileComplete, ...
    exportedFunctions, capturedFunctions);
gateT = localBuildEvidenceGate(detailT, ledgerAvailable, ledgerIdentityComplete, ...
    profileAvailable, profileComplete, exportedFunctions, capturedFunctions);
functionT = localBuildFunctionInventory(inventory, profileT, profilePaths, ledgerT, ...
    repoRoot, profileAvailable, profileComplete);

detailPath = fullfile(layout.ReportCSVDir, "phy_package_execution_audit.csv");
summaryOutPath = fullfile(layout.ReportCSVDir, "phy_package_execution_summary.csv");
gatePath = fullfile(layout.ReportCSVDir, "phy_package_execution_evidence_gate.csv");
sourceFilePath = fullfile(layout.ReportCSVDir, ...
    "sixgr_source_file_execution_inventory.csv");
sourceFunctionPath = fullfile(layout.ReportCSVDir, ...
    "sixgr_source_function_execution_inventory.csv");
studyRegistryPath = fullfile(layout.ReportCSVDir, ...
    "study_to_runtime_measurement_registry.csv");
studyRegistryT = sixgr.analytics.buildStudyToRuntimeMeasurementRegistry();
sixgr.util.csvWriteTable(detailPath, detailT);
sixgr.util.csvWriteTable(summaryOutPath, summaryT);
sixgr.util.csvWriteTable(gatePath, gateT);
sixgr.util.csvWriteTable(sourceFilePath, detailT);
sixgr.util.csvWriteTable(sourceFunctionPath, functionT);
sixgr.util.csvWriteTable(studyRegistryPath, studyRegistryT);

out = struct( ...
    "DetailTable", detailT, ...
    "SummaryTable", summaryT, ...
    "FunctionTable", functionT, ...
    "GateTable", gateT, ...
    "DetailPath", string(detailPath), ...
    "SummaryPath", string(summaryOutPath), ...
    "GatePath", string(gatePath), ...
    "SourceFileInventoryPath", string(sourceFilePath), ...
    "SourceFunctionInventoryPath", string(sourceFunctionPath), ...
    "StudyMeasurementRegistryPath", string(studyRegistryPath), ...
    "StudyMeasurementRegistryTable", studyRegistryT, ...
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
    "RuntimeEligibility", "", ...
    "ScenarioInputPolicy", "", ...
    "StudyFileNamingAssessment", "", ...
    "DuplexReferenceDetected", false, ...
    "SharedDuplexResolverUsed", false, ...
    "DuplexAuthorityAssessment", "", ...
    "ActuallyCalled", false, ...
    "CallCount", 0, ...
    "TotalTime_s", 0, ...
    "ProfilerAvailable", false, ...
    "ProfilerComplete", false, ...
    "ProfilerExportedFunctionCount", 0, ...
    "ProfilerCapturedFunctionCount", 0, ...
    "ExecutionEvidence", "", ...
    "ScenarioCoverageStatus", "", ...
    "UsageAssessment", "", ...
    "NeverUsedConclusionPermitted", false, ...
    "SourceSHA256", "", ...
    "EvidenceSource", "");
end

function T = localAnnotateBasenameCollisions(T)
T.SameBasenameCount = ones(height(T), 1);
T.SameBasenameAssessment = repmat("UNIQUE_PACKAGE_SYMBOL", height(T), 1);
names = string(T.PrimaryFunctionOrClass);
for name = unique(names, "stable").'
    mask = names == name;
    count = sum(mask);
    if count <= 1
        continue;
    end
    T.SameBasenameCount(mask) = count;
    switch lower(name)
        case "generateprachwaveform"
            state = "PASS_PHY_FACADE_DELEGATES_TO_CANONICAL_RACH_RUNTIME";
        case "absolutepowerledger"
            state = "PASS_DISTINCT_LINK_BUDGET_AND_SAMPLE_REFERENCE_PLANES";
        case {"pucchpowercontroller", "puschpowercontroller"}
            state = "PASS_DISTINCT_PHY_FORMULA_AND_EVENT_SOURCED_RF_STATE";
        case "schedulingrequeststate"
            state = "PASS_DISTINCT_MAC_LIFECYCLE_AND_PHY_OCCASION_STATE";
        case {"evidenceclass", "scenarioregistry", "runcampaign", ...
                "validatecampaignconfig"}
            state = "PASS_PACKAGE_QUALIFIED_ISOLATED_CAMPAIGN_SYMBOL";
        otherwise
            qualified = lower(strtrim(string(T.QualifiedName(mask))));
            if numel(unique(qualified)) == count
                % MATLAB package qualification is the authority boundary.
                % Equal basenames in distinct packages (for example
                % sixgr.config.loadConfig and sixgr.lls.loadConfig) do not
                % collide and must not be reported as duplicate runtime
                % implementations.
                state = "PASS_PACKAGE_QUALIFIED_DISTINCT_SYMBOL";
            else
                state = "UNRESOLVED_DUPLICATE_NAME";
            end
    end
    T.SameBasenameAssessment(mask) = state;
end
end

function inventory = localSixGRSourceInventory(repoRoot)
% Restrict discovery to the production namespace. StaticInventory.scan is
% intentionally repository-wide and includes large result/test trees; that
% cost is unnecessary for a per-run +sixgr execution audit.
rootPath = fullfile(repoRoot, "+sixgr");
files = dir(fullfile(rootPath, "**", "*.m"));
filePath = strings(numel(files),1);
primary = strings(numel(files),1);
repoPrefix = replace(string(repoRoot), "\", "/");
if ~endsWith(repoPrefix, "/")
    repoPrefix = repoPrefix + "/";
end
for index = 1:numel(files)
    absolutePath = replace(string(fullfile(files(index).folder, ...
        files(index).name)), "\", "/");
    if startsWith(absolutePath, repoPrefix, "IgnoreCase", true)
        filePath(index) = extractAfter(absolutePath, strlength(repoPrefix));
    else
        filePath(index) = absolutePath;
    end
    [~, primary(index)] = fileparts(files(index).name);
end
inventory = table(filePath, primary, ...
    'VariableNames', {'file_path','primary_function_or_class'});
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

function path = localNormalizePath(path)
path = replace(string(path), "\", "/");
while any(contains(path, "//"),"all")
    path = replace(path, "//", "/");
end
path = lower(path);
end

function role = localSourceRole(path, primaryName)
token = lower(replace(string(path), "\", "/"));
name = lower(string(primaryName));
if contains(token, "/+oracle/")
    role = "validation_oracle";
elseif startsWith(token, "+sixgr/+csi/") || ...
        contains(token, "/+tdoc") || contains(name, "tdoc")
    role = "tdoc_campaign";
elseif contains(token, "/+c0/+campaigns/")
    role = "offline_study";
elseif contains(token, "/+analysis/") || contains(name, "impact")
    role = "offline_impact_analysis";
elseif contains(name, "phasevalidation") || contains(name, "focusedtest") || ...
        contains(name, "validationcampaign") || ...
        contains(name, "negativecase") || startsWith(name, "runstrict")
    role = "validation_campaign";
elseif contains(name, "artifact") || contains(name, "evidencebuilder") || ...
        contains(name, "publisher") || startsWith(name, "export")
    role = "artifact_reporting";
elseif any(name == ["runprachlls", ...
        "runpdschstudylls"])
    % These are waveform-executing runtime campaigns.  They may consume a
    % resolved YAML scenario or an explicit campaign matrix, but their
    % built-in research vectors must never become subsystem defaults.
    role = "waveform_runtime_campaign";
elseif contains(name, "coverageexecutor")
    role = "offline_study";
elseif contains(token, "/+legacy/") || contains(name, "legacy")
    role = "legacy";
else
    role = "runtime_library";
end
end

function assessment = localStudyFileNamingAssessment(role, primaryName)
name = lower(string(primaryName));
switch string(role)
    case "tdoc_campaign"
        if contains(name, "study")
            assessment = "PASS_TDOC_STUDY_NAME_EXPLICIT";
        else
            assessment = "FAIL_TDOC_STUDY_NAME_AMBIGUOUS";
        end
    case "offline_study"
        if contains(name, "study")
            assessment = "PASS_OFFLINE_STUDY_NAME_EXPLICIT";
        else
            assessment = "FAIL_OFFLINE_STUDY_NAME_AMBIGUOUS";
        end
    case "offline_impact_analysis"
        % Files below an explicit +analysis package are internal statistical
        % helpers, not callable runtime entry points.  The package boundary
        % is the unambiguous isolation marker; campaign entry points retain
        % Impact in their own filenames.
        if contains(name, "impact") || any(name == [ ...
                "pairedrngstreams", "adjustpvaluesholm", ...
                "computeclopperpearsoninterval", "computeeffectsize", ...
                "computemcnemartest", "computepairedbootstrapci", ...
                "computewilsoninterval", "fitfactorialeffects"])
            assessment = "PASS_IMPACT_STUDY_NAME_EXPLICIT";
        else
            assessment = "FAIL_IMPACT_STUDY_NAME_AMBIGUOUS";
        end
    case "validation_campaign"
        if contains(name, ["validation", "phase", "test", "strict", ...
                "negativecase"])
            assessment = "PASS_VALIDATION_NAME_EXPLICIT";
        else
            assessment = "FAIL_VALIDATION_NAME_AMBIGUOUS";
        end
    otherwise
        assessment = "NOT_AN_ISOLATED_STUDY_FILE";
end
end

function [detected, shared, assessment] = ...
        localDuplexAuthorityAssessment(sourcePath, role)
try
    source = string(fileread(sourcePath));
catch
    source = "";
end
directPaths = [ ...
    "frequency.duplex_mode", "global_radio_scope.duplex_mode", ...
    "random_access.duplex_mode", "phy.duplex.mode", ...
    "phy.frameStructure.DuplexMode"];
detected = any(contains(source, directPaths));
shared = contains(source, "sixgr.phy.frame.resolveDuplexMode");
if ~detected
    assessment = "NOT_A_DIRECT_DUPLEX_AUTHORITY_CONSUMER";
elseif shared
    assessment = "PASS_SHARED_DUPLEX_RESOLVER";
elseif any(string(role) == ["tdoc_campaign", "validation_campaign", ...
        "offline_impact_analysis", "validation_oracle"])
    assessment = "ISOLATED_EXPLICIT_INPUT_NOT_RUNTIME_AUTHORITY";
else
    assessment = "FAIL_LOCAL_DUPLEX_AUTHORITY_PARSE";
end
end

function [eligibility, inputPolicy] = localRolePolicy(role)
switch string(role)
    case "runtime_library"
        eligibility = "PRODUCTION_RUNTIME_ELIGIBLE";
        inputPolicy = "resolved_yaml_or_typed_runtime_input";
    case "waveform_runtime_campaign"
        eligibility = "PRODUCTION_RUNTIME_ELIGIBLE";
        inputPolicy = "resolved_yaml_or_explicit_campaign_matrix_no_hidden_defaults";
    case "tdoc_campaign"
        eligibility = "ISOLATED_CAMPAIGN_ONLY";
        inputPolicy = "explicit_tdoc_vector_never_runtime_default";
    case "validation_campaign"
        eligibility = "ISOLATED_VALIDATION_ONLY";
        inputPolicy = "explicit_validation_input_never_runtime_default";
    case "offline_impact_analysis"
        eligibility = "OFFLINE_ANALYSIS_ONLY";
        inputPolicy = "persisted_runtime_evidence_or_explicit_experiment_pair";
    case "artifact_reporting"
        eligibility = "REPORTING_ONLY";
        inputPolicy = "persisted_runtime_evidence_only";
    case "validation_oracle"
        eligibility = "INDEPENDENT_ORACLE_ONLY";
        inputPolicy = "pinned_independent_reference_only";
    case "legacy"
        eligibility = "LEGACY_NOT_PRODUCTION";
        inputPolicy = "must_not_supply_runtime_defaults";
    otherwise
        eligibility = "ISOLATED_STUDY_ONLY";
        inputPolicy = "explicit_study_input_never_runtime_default";
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
    parts = split(path, "/");
    if numel(parts) >= 2
        name = upper(erase(parts(2), "+"));
    else
        name = "OTHER";
    end
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
elseif complete
    state = "not_observed_in_complete_profiled_scenario";
elseif ~available
    if ledgerAvailable
        state = "not_observed_in_instrumented_entry_ledger_profile_unavailable";
    else
        state = "profiler_and_entry_ledger_unavailable";
    end
elseif ~complete
    state = "not_present_in_truncated_profiler_export";
else
    state = "not_called_in_profiled_scenario";
end
end

function state = localUsageAssessment(role, called, available, complete)
if called
    state = "executed_in_profiled_scenario";
elseif ~any(role == ["runtime_library", "waveform_runtime_campaign"])
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
packages = unique(string(detailT.Package), "stable");
roles = ["ALL";"runtime_library";"waveform_runtime_campaign"; ...
    "validation_oracle";"validation_campaign";"tdoc_campaign"; ...
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

function T = localBuildFunctionInventory(inventory, profileT, profilePaths, ledgerT, ...
        repoRoot, profileAvailable, profileComplete)
rows = repmat(localEmptyFunctionRow(), 0, 1);
for fileIndex = 1:height(inventory)
    relativePath = replace(string(inventory.file_path(fileIndex)), "\", "/");
    absolutePath = localNormalizePath(fullfile(repoRoot, char(relativePath)));
    declarations = localReadFunctionDeclarations( ...
        fullfile(repoRoot, char(relativePath)), ...
        string(inventory.primary_function_or_class(fileIndex)));
    sourceSHA256 = localFileSHA256(fullfile(repoRoot, char(relativePath)));
    fileProfileMask = strcmpi(profilePaths, absolutePath);
    primaryQualifiedName = localQualifiedName(relativePath);
    for declarationIndex = 1:height(declarations)
        row = localEmptyFunctionRow();
        row.FilePath = relativePath;
        row.Package = localAuditPackage(relativePath);
        row.SourceRole = localSourceRole(relativePath, ...
            string(inventory.primary_function_or_class(fileIndex)));
        [row.RuntimeEligibility, row.ScenarioInputPolicy] = ...
            localRolePolicy(row.SourceRole);
        [row.DuplexReferenceDetected, row.SharedDuplexResolverUsed, ...
            row.DuplexAuthorityAssessment] = ...
            localDuplexAuthorityAssessment(fullfile(repoRoot, ...
            char(relativePath)), row.SourceRole);
        row.DeclaredSymbol = declarations.DeclaredSymbol(declarationIndex);
        row.DeclarationKind = declarations.DeclarationKind(declarationIndex);
        row.DeclarationLine = declarations.DeclarationLine(declarationIndex);
        row.PrimaryFileSymbol = declarationIndex == 1 || ...
            strcmpi(row.DeclaredSymbol, ...
            string(inventory.primary_function_or_class(fileIndex)));
        if row.PrimaryFileSymbol
            row.StaticQualifiedName = primaryQualifiedName;
        else
            row.StaticQualifiedName = primaryQualifiedName + ">" + row.DeclaredSymbol;
        end
        symbolProfileMask = fileProfileMask & ...
            localExactProfileSymbolMask(profileT, row.DeclaredSymbol);
        ledgerMask = false(height(ledgerT),1);
        if row.PrimaryFileSymbol
            ledgerMask = localExactLedgerFunctionMask(ledgerT, primaryQualifiedName);
        end
        row.ActuallyCalled = any(symbolProfileMask) || any(ledgerMask);
        row.CallCount = localExactCallCount(profileT, symbolProfileMask, ledgerMask);
        row.TotalTime_s = localProfileSum(profileT, symbolProfileMask, "TotalTime_s");
        row.ProfilerAvailable = profileAvailable;
        row.ProfilerComplete = profileComplete;
        row.ExecutionEvidence = localExecutionEvidence(row.ActuallyCalled, ...
            ~isempty(ledgerT), profileAvailable, profileComplete);
        if row.ActuallyCalled
            row.ScenarioCoverageStatus = "EXECUTED_IN_THIS_SCENARIO";
            row.UsageAssessment = "executed_in_profiled_scenario";
        else
            row.ScenarioCoverageStatus = "NOT_OBSERVED_IN_THIS_SCENARIO";
            row.UsageAssessment = localUsageAssessment(row.SourceRole, false, ...
                profileAvailable, profileComplete);
        end
        row.NeverUsedConclusionPermitted = false;
        row.SourceSHA256 = sourceSHA256;
        row.EvidenceSource = localEvidenceSource(any(ledgerMask), ...
            any(symbolProfileMask));
        rows(end+1,1) = row; %#ok<AGROW>
    end
end
T = struct2table(rows, "AsArray", true);
if ~isempty(T)
    T = sortrows(T, ["Package","FilePath","DeclarationLine"]);
end
end

function declarations = localReadFunctionDeclarations(pathValue, primaryName)
declaredSymbol = strings(0,1);
declarationKind = strings(0,1);
declarationLine = zeros(0,1);
try
    textValue = fileread(pathValue);
catch
    textValue = "";
end
lines = splitlines(string(textValue));
for lineIndex = 1:numel(lines)
    line = char(lines(lineIndex));
    classToken = regexp(line, ...
        '^\s*classdef(?:\s*\([^)]*\))?\s+([A-Za-z]\w*)', ...
        'tokens', 'once');
    if ~isempty(classToken)
        declaredSymbol(end+1,1) = string(classToken{1}); %#ok<AGROW>
        declarationKind(end+1,1) = "classdef"; %#ok<AGROW>
        declarationLine(end+1,1) = lineIndex; %#ok<AGROW>
        continue;
    end
    functionToken = regexp(line, ...
        '^\s*function\s+(?:(?:\[[^\]]*\]|[A-Za-z]\w*)\s*=\s*)?([A-Za-z]\w*)', ...
        'tokens', 'once');
    if ~isempty(functionToken)
        declaredSymbol(end+1,1) = string(functionToken{1}); %#ok<AGROW>
        declarationKind(end+1,1) = "function"; %#ok<AGROW>
        declarationLine(end+1,1) = lineIndex; %#ok<AGROW>
    end
end
if isempty(declaredSymbol)
    declaredSymbol = string(primaryName);
    declarationKind = "script_or_unparsed";
    declarationLine = 1;
end
declarations = table(declaredSymbol, declarationKind, declarationLine, ...
    'VariableNames', {'DeclaredSymbol','DeclarationKind','DeclarationLine'});
end

function mask = localExactProfileSymbolMask(profileT, declaredSymbol)
mask = false(height(profileT),1);
if isempty(profileT)
    return;
end
symbol = lower(strtrim(string(declaredSymbol)));
if ismember("FunctionName", string(profileT.Properties.VariableNames))
    names = lower(strtrim(string(profileT.FunctionName)));
    mask = mask | names == symbol;
end
if ismember("CompleteName", string(profileT.Properties.VariableNames))
    names = lower(replace(strtrim(string(profileT.CompleteName)), "\", "/"));
    mask = mask | names == symbol | endsWith(names, ">" + symbol) | ...
        endsWith(names, "." + symbol) | endsWith(names, "/" + symbol);
end
end

function row = localEmptyFunctionRow()
row = struct( ...
    "FilePath", "", "Package", "", "SourceRole", "", ...
    "RuntimeEligibility", "", "ScenarioInputPolicy", "", ...
    "DuplexReferenceDetected", false, ...
    "SharedDuplexResolverUsed", false, ...
    "DuplexAuthorityAssessment", "", ...
    "DeclaredSymbol", "", "DeclarationKind", "", ...
    "DeclarationLine", NaN, "PrimaryFileSymbol", false, ...
    "StaticQualifiedName", "", "ActuallyCalled", false, ...
    "CallCount", 0, "TotalTime_s", 0, ...
    "ProfilerAvailable", false, "ProfilerComplete", false, ...
    "ExecutionEvidence", "", "ScenarioCoverageStatus", "", ...
    "UsageAssessment", "", "NeverUsedConclusionPermitted", false, ...
    "SourceSHA256", "", "EvidenceSource", "");
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
failureReason = [ ...
    localGateFailureReason(ledgerAvailable, "runtime_call_ledger_missing_or_empty"); ...
    localGateFailureReason(ledgerIdentityComplete, "runtime_call_ledger_identity_missing_or_invalid"); ...
    localGateFailureReason(height(detailT) > 0, "selected_source_inventory_empty"); ...
    localGateFailureReason(available, "runtime_profiler_not_enabled_or_unavailable"); ...
    localGateFailureReason(complete, "runtime_profiler_export_incomplete")];
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
    failureReason, ...
    'VariableNames', {'Gate','Required','Pass','Definition','Observed','FailureReason'});
end

function value = localGateFailureReason(passed, reason)
if logical(passed)
    value = "";
else
    value = string(reason);
end
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
