function summary = runTwoModeIntegrationAcceptance(varargin)
%RUNTWOMODEINTEGRATIONACCEPTANCE Evaluate full actual-run Phase-16 evidence.
%
% Focused reductions are not accepted here. Every mandatory matrix case
% must bind to a completed production RunID, resolved-config hash,
% artifact-manifest hash, and independently derived metric observation.

p = inputParser;
p.addParameter("RunMatrix","",@(x)ischar(x)||isstring(x));
p.addParameter("OutputDir","",@(x)ischar(x)||isstring(x));
p.addParameter("SeedList",[11 23 47 89 131 197],@isnumeric);
p.addParameter("Strict",true,@(x)islogical(x)&&isscalar(x));
p.addParameter("ActualRunTable",table(),@istable);
p.addParameter("Observations",table(),@istable);
p.addParameter("RulePath","",@(x)ischar(x)||isstring(x));
p.parse(varargin{:});
opt = p.Results;
if ~opt.Strict
    error("sixgr:integration:StrictRequired", ...
        "Phase-16 acceptance requires Strict=true.");
end
matrix = localRead(string(opt.RunMatrix));
mandatory = matrix(upper(matrix.MustRun)=="YES",:);
outputDir = string(opt.OutputDir);
if strlength(strtrim(outputDir)) == 0
    error("sixgr:integration:IncompleteConfiguration", ...
        "OutputDir is required.");
end
actual = localResolveTable(opt.ActualRunTable, fullfile(outputDir, ...
    "reports","csv","integration_actual_run_evidence.csv"));
requiredColumns = ["CaseID","RunID","Status","OutputPath", ...
    "ResolvedConfigSHA256","ArtifactManifestSHA256"];
localValidateActualRuns(actual, mandatory, requiredColumns);

observations = localResolveTable(opt.Observations, fullfile(outputDir, ...
    "reports","csv","integration_acceptance_observations.csv"));
if isempty(observations) || height(observations) == 0
    error("sixgr:integration:MissingActualRunEvidence", ...
        "No runtime-derived Phase-16 acceptance observations are available.");
end
rulePath = string(opt.RulePath);
if strlength(strtrim(rulePath)) == 0
    rulePath = fullfile(fileparts(string(opt.RunMatrix)), ...
        "integration_acceptance_rules.csv");
end
acceptanceRunID = localAcceptanceRunID(actual, mandatory);
results = sixgr.integration.IntegrationAcceptanceRunner.evaluate( ...
    rulePath, observations, acceptanceRunID);
sixgr.integration.IntegrationArtifactExporter.writeTable(outputDir, ...
    "reports/csv/integration_acceptance_results.csv", results);

passed = all(results.Status == "PASS");
summary = struct("Passed",passed, ...
    "Status",localStatus(passed), ...
    "MandatoryRunsExpected",height(mandatory), ...
    "MandatoryRunsObserved",height(actual), ...
    "AcceptanceRulesEvaluated",height(results), ...
    "AcceptanceRulesPassed",sum(results.Status == "PASS"), ...
    "AcceptanceRulesFailed",sum(results.Status ~= "PASS"), ...
    "CSVArtifactsGenerated",1, ...
    "PNGArtifactsGenerated",0, ...
    "OutputDir",outputDir, ...
    "AcceptanceRunID",acceptanceRunID, ...
    "SeedList",double(opt.SeedList(:)).', ...
    "FailureCode",localFailureCode(passed));
if ~passed
    error("sixgr:integration:AcceptanceFailed", ...
        "%d of %d Phase-16 acceptance rules failed.", ...
        summary.AcceptanceRulesFailed, height(results));
end
end

function value = localRead(path)
if ~isfile(path)
    error("sixgr:integration:IncompleteConfiguration", ...
        "RunMatrix does not exist: %s.",path);
end
options = detectImportOptions(path,"Delimiter",",","VariableNamingRule","preserve");
options.DataLines = [2 Inf];
options = setvartype(options,options.VariableNames,"string");
value = readtable(path,options);
end

function value = localResolveTable(value, path)
if ~isempty(value) && height(value) > 0
    return;
end
if ~isfile(path)
    value = table();
    return;
end
options = detectImportOptions(path, ...
    "Delimiter",",","VariableNamingRule","preserve");
value = readtable(path, options);
end

function localValidateActualRuns(actual, mandatory, requiredColumns)
if ~istable(actual) || ~all(ismember(requiredColumns, ...
        string(actual.Properties.VariableNames)))
    error("sixgr:integration:MissingActualRunEvidence", ...
        "Actual-run evidence is missing required columns: %s.", ...
        strjoin(cellstr(setdiff(requiredColumns, ...
        string(actual.Properties.VariableNames))), ", "));
end
caseIDs = string(actual.CaseID);
if numel(unique(caseIDs)) ~= numel(caseIDs)
    error("sixgr:integration:MissingActualRunEvidence", ...
        "Actual-run evidence contains duplicate CaseID rows.");
end
for index = 1:height(mandatory)
    caseID = string(mandatory.CaseID(index));
    match = find(caseIDs == caseID);
    if numel(match) ~= 1
        error("sixgr:integration:MissingActualRunEvidence", ...
            "Mandatory case %s has %d actual-run evidence rows.", ...
            caseID, numel(match));
    end
    row = actual(match,:);
    if upper(strtrim(string(row.Status))) ~= "COMPLETED" || ...
            strlength(strtrim(string(row.RunID))) == 0 || ...
            ~isfolder(string(row.OutputPath)) || ...
            ~localHash(string(row.ResolvedConfigSHA256)) || ...
            ~localHash(string(row.ArtifactManifestSHA256))
        error("sixgr:integration:MissingActualRunEvidence", ...
            "Mandatory case %s is not bound to complete, hash-valid production evidence.", ...
            caseID);
    end
end
end

function tf = localHash(value)
tf = isscalar(value) && ~isempty(regexp(char(value), ...
    "^[0-9a-fA-F]{64}$", "once"));
end

function runID = localAcceptanceRunID(actual, mandatory)
[~, order] = sort(string(mandatory.CaseID));
mandatory = mandatory(order,:);
caseIDs = string(actual.CaseID);
rows = cell(height(mandatory), 1);
for index = 1:height(mandatory)
    row = actual(caseIDs == string(mandatory.CaseID(index)),:);
    rows{index} = struct( ...
        "CaseID",string(row.CaseID), ...
        "RunID",string(row.RunID), ...
        "ResolvedConfigSHA256",string(row.ResolvedConfigSHA256), ...
        "ArtifactManifestSHA256",string(row.ArtifactManifestSHA256));
end
digest = sixgr.integration.IntegrationHash.data(rows);
runID = "INTEGRATION-ACCEPTANCE-" + extractBefore(digest, 17);
end

function value = localStatus(passed)
if passed
    value = "PASS";
else
    value = "FAIL";
end
end

function value = localFailureCode(passed)
if passed
    value = "";
else
    value = "sixgr:integration:AcceptanceFailed";
end
end
