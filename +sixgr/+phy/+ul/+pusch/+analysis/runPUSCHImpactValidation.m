function summary = runPUSCHImpactValidation(options)
%RUNPUSCHIMPACTVALIDATION Execute the frozen PUSCH component-impact pack.
%
% This runner executes production PUSCH components for every registered
% experiment.  It intentionally reports TruthQualified=false: the impact
% campaign is component evidence, not a replacement for the separately
% verified PUSCH/UL-SCH waveform-truth phase.

arguments
    options.ExperimentMatrix (1,1) string
    options.PairingContract (1,1) string
    options.AcceptanceRules (1,1) string
    options.AnalyticalFloor (1,1) string
    options.OutputDir (1,1) string
    options.Tier (1,1) string {mustBeMember(options.Tier, ...
        ["smoke","full"])} = "full"
    options.Strict (1,1) logical = true
    options.SeedList (1,:) double {mustBeInteger,mustBeNonnegative} = ...
        [11 23 47 89 131 197 263 331]
    options.ConfidenceLevel (1,1) double ...
        {mustBeGreaterThan(options.ConfidenceLevel,0), ...
         mustBeLessThan(options.ConfidenceLevel,1)} = 0.95
    options.StudyConfig (1,1) string = ""
end

if ~options.Strict
    error("sixgr:pusch:StrictValidationRequired", ...
        "PUSCH impact execution requires Strict=true.");
end
inputs = [options.ExperimentMatrix, options.PairingContract, ...
    options.AcceptanceRules, options.AnalyticalFloor];
for path = inputs
    if ~isfile(path)
        error("sixgr:pusch:ImpactInputMissing", ...
            "Required PUSCH impact input is missing: %s.", path);
    end
end

repoRoot = localRepositoryRoot();
vectorRoot = string(fileparts(options.ExperimentMatrix));
if strlength(options.StudyConfig) == 0
    options.StudyConfig = fullfile(repoRoot, "simulator", "configs", ...
        "validation", "pusch_ulsch_impact.yaml");
end
cfg = sixgr.lls6g.config.readConfigFile(options.StudyConfig);
localValidateStudyConfig(cfg);

matrix = localReadStrings(options.ExperimentMatrix);
if options.Tier == "smoke"
    matrix = matrix(lower(string(matrix.Tier)) == "smoke", :);
    if isempty(matrix)
        error("sixgr:pusch:ImpactSmokeMissing", ...
            "The frozen PUSCH matrix contains no smoke experiments.");
    end
    % Smoke tier validates executability and returns without claiming the
    % complete artifact contract.
    records = repmat(localSmokeRecord(), height(matrix), 1);
    for index = 1:height(matrix)
        records(index) = localSmokeResult( ...
            sixgr.phy.ul.pusch.analysis.PUSCHImpactExperimentExecutor.execute( ...
                matrix(index, :), cfg, options.SeedList));
    end
    passed = all([records.CorrectnessGatePass]);
    summary = struct("Passed", logical(passed), ...
        "Status", localStatus(passed), "Strict", true, ...
        "Tier", "smoke", "ExperimentCount", height(matrix), ...
        "CompletedCount", numel(records), "OutputDir", "", ...
        "ExecutionBackend", string(cfg.evidence.execution_backend), ...
        "ApproximationMode", string(cfg.evidence.approximation_mode), ...
        "TruthQualified", false);
    if ~passed
        error("sixgr:pusch:ImpactSmokeFailed", ...
            "A PUSCH impact smoke experiment failed its component gate.");
    end
    return;
end

% Execute one registered smoke row before the full campaign.  This is a
% fail-fast production-component probe; the builder subsequently executes
% the frozen 705-row matrix once to preserve exact contract lineage.
smokeIndex = find(lower(string(matrix.Tier)) == "smoke", 1);
if isempty(smokeIndex)
    error("sixgr:pusch:ImpactSmokeMissing", ...
        "The frozen PUSCH matrix contains no smoke experiments.");
end
smoke = sixgr.phy.ul.pusch.analysis.PUSCHImpactExperimentExecutor.execute( ...
    matrix(smokeIndex, :), cfg, options.SeedList);
if ~smoke.CorrectnessGatePass
    error("sixgr:pusch:ImpactSmokeFailed", ...
        "The pre-campaign PUSCH component smoke gate failed.");
end

csvContract = localReadStrings(fullfile( ...
    vectorRoot, "desired_pusch_impact_csv_contract.csv"));
imageContract = localReadStrings(fullfile( ...
    vectorRoot, "desired_pusch_impact_image_contract.csv"));
outputDir = string(java.io.File(char(options.OutputDir)).getCanonicalPath());
if ~isfolder(outputDir)
    [ok, message] = mkdir(outputDir);
    if ~ok
        error("sixgr:pusch:ImpactArtifactWriteFailed", ...
            "Unable to create %s: %s.", outputDir, message);
    end
end
localCleanContracted(outputDir, csvContract, imageContract);

runID = "pusch_impact_" + string(datetime("now", TimeZone="UTC", ...
    Format="yyyyMMdd'T'HHmmss'Z'"));
[tables, evidence] = ...
    sixgr.phy.ul.pusch.analysis.PUSCHImpactEvidenceBuilder.build( ...
        options.ExperimentMatrix, options.PairingContract, ...
        options.AcceptanceRules, options.AnalyticalFloor, vectorRoot, ...
        cfg, runID, options.SeedList, options.ConfidenceLevel);

names = string(fieldnames(tables));
rowCounts = struct();
csvHashes = struct();
for index = 1:numel(names)
    fileName = names(index) + ".csv";
    sixgr.phy.ul.pusch.analysis.PUSCHImpactArtifactExporter.writeTable( ...
        outputDir, fileName, tables.(names(index)));
    rowCounts.(names(index)) = height(tables.(names(index)));
    csvHashes.(names(index)) = ...
        sixgr.phy.ul.pusch.analysis.PUSCHImpactArtifactExporter.fileHash( ...
            fullfile(outputDir, fileName));
end

auditRows = repmat(localAuditRow(), height(imageContract), 1);
for index = 1:height(imageContract)
    auditRows(index) = ...
        sixgr.phy.ul.pusch.analysis.PUSCHImpactArtifactExporter. ...
        writeSemanticFigure(outputDir, ...
            table2struct(imageContract(index, :)), cfg);
end
audit = struct2table(auditRows, AsArray=true);
sixgr.phy.ul.pusch.analysis.PUSCHImpactArtifactExporter.writeTable( ...
    outputDir, "pusch_impact_image_semantic_audit.csv", audit);
rowCounts.pusch_impact_image_semantic_audit = height(audit);
csvHashes.pusch_impact_image_semantic_audit = ...
    sixgr.phy.ul.pusch.analysis.PUSCHImpactArtifactExporter.fileHash( ...
        fullfile(outputDir, "pusch_impact_image_semantic_audit.csv"));

expectedCSV = string(csvContract.FileName);
expectedPNG = string(imageContract.ImageFile);
csvPresent = arrayfun(@(name) isfile(fullfile(outputDir, name)), ...
    expectedCSV);
pngPresent = arrayfun(@(name) isfile(fullfile(outputDir, name)), ...
    expectedPNG);
passed = all(csvPresent) && all(pngPresent) && ...
    evidence.ExperimentCount == 705 && ...
    evidence.CompletedCount == 705 && evidence.RuleCount == 70 && ...
    evidence.IncompleteCount == 0 && evidence.HardRulesPassed;

summary = struct( ...
    "Passed", logical(passed), "Status", localStatus(passed), ...
    "Strict", true, "Tier", "full", "RunID", runID, ...
    "OutputDir", outputDir, "StudyConfig", options.StudyConfig, ...
    "ExperimentCount", evidence.ExperimentCount, ...
    "CompletedCount", evidence.CompletedCount, ...
    "PairCount", evidence.PairCount, ...
    "RuleCount", evidence.RuleCount, ...
    "HardRuleCount", evidence.HardRuleCount, ...
    "HardRulePassCount", evidence.HardRulePassCount, ...
    "IncompleteCount", evidence.IncompleteCount, ...
    "CSVCount", sum(csvPresent), "PNGCount", sum(pngPresent), ...
    "RowCounts", rowCounts, "CSVHashes", csvHashes, ...
    "ExecutionBackend", evidence.ExecutionBackend, ...
    "ApproximationMode", evidence.ApproximationMode, ...
    "TruthQualified", false);
if ~summary.Passed
    error("sixgr:pusch:IncompleteImpactCampaign", ...
        "The PUSCH component-impact campaign did not satisfy its contract.");
end
end

function localValidateStudyConfig(cfg)
required = [ ...
    "evidence.execution_backend","evidence.approximation_mode", ...
    "evidence.truth_qualified","monte_carlo.symbols_per_experiment", ...
    "monte_carlo.covariance_samples", ...
    "monte_carlo.minimum_covariance_samples", ...
    "statistics.bootstrap_replicates", ...
    "images.width_pixels","images.height_pixels", ...
    "images.resolution_dpi"];
for path = required
    if isempty(sixgr.util.structGet(cfg, path, []))
        error("sixgr:pusch:ImpactStudyConfigInvalid", ...
            "StudyConfig requires field %s.", path);
    end
end
if logical(cfg.evidence.truth_qualified)
    error("sixgr:pusch:ImpactTruthRelabelForbidden", ...
        "The component campaign cannot set truth_qualified=true.");
end
mode = lower(string(cfg.evidence.approximation_mode));
if contains(mode, "truth") && ~contains(mode, ["not_","not "])
    error("sixgr:pusch:ImpactTruthRelabelForbidden", ...
        "ApproximationMode must not claim full waveform truth.");
end
end

function localCleanContracted(outputDir, csvContract, imageContract)
targets = [string(csvContract.FileName); string(imageContract.ImageFile)];
for target = targets.'
    path = fullfile(outputDir, target);
    if isfile(path)
        delete(path);
    end
end
end

function value = localReadStrings(path)
options = detectImportOptions(path, FileType="text", Delimiter=",", ...
    VariableNamingRule="preserve");
options = setvartype(options, options.VariableNames, "string");
value = readtable(path, options);
for index = 1:width(value)
    name = value.Properties.VariableNames{index};
    column = string(value.(name));
    column(ismissing(column)) = "";
    value.(name) = column;
end
end

function row = localAuditRow()
row = struct( ...
    "ImageFile", "", "SourceCSV", "", "Width", NaN, "Height", NaN, ...
    "AxesCount", NaN, "SeriesCount", NaN, "FinitePointCount", NaN, ...
    "ExpectedXLabel", "", "ActualXLabel", "", ...
    "ExpectedYLabel", "", "ActualYLabel", "", ...
    "ExpectedTitleToken", "", "ActualTitle", "", ...
    "SourceCSV_SHA256", "", "PNG_SHA256", "", "Status", "");
end

function row = localSmokeResult(record)
row = struct("ExperimentID", record.ExperimentID, ...
    "CorrectnessGatePass", record.CorrectnessGatePass);
end

function row = localSmokeRecord()
row = struct("ExperimentID", "", "CorrectnessGatePass", false);
end

function value = localStatus(tf)
if tf
    value = "PASS";
else
    value = "FAIL";
end
end

function root = localRepositoryRoot()
root = fileparts(mfilename("fullpath"));
for index = 1:5
    root = fileparts(root);
end
end
