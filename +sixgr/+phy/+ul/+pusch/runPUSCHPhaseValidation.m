function summary = runPUSCHPhaseValidation(varargin)
%RUNPUSCHPHASEVALIDATION Execute the bounded Prompt-03 PUSCH phase.

ip = inputParser;
ip.FunctionName = "sixgr.phy.ul.pusch.runPUSCHPhaseValidation";
ip.addParameter("VectorRoot", fullfile(pwd, "tests", "vectors", "pusch"), ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));
ip.addParameter("OutputDir", fullfile(pwd, "artifacts", "pusch_ulsch_phase"), ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));
ip.addParameter("SeedList", [11 23 47 89], ...
    @(x) isnumeric(x) && isvector(x) && ~isempty(x));
ip.addParameter("ConfidenceLevel", 0.95, ...
    @(x) isnumeric(x) && isscalar(x) && isfinite(x) ...
    && x > 0 && x < 1);
ip.addParameter("Strict", true, ...
    @(x) islogical(x) && isscalar(x));
ip.parse(varargin{:});
opt = ip.Results;

vectorRoot = char(string(opt.VectorRoot));
outputDir = char(string(opt.OutputDir));
seedList = double(opt.SeedList(:).');
if ~isfolder(vectorRoot)
    error("sixgr:pusch:PhaseVectorRootMissing", ...
        "VectorRoot must identify the frozen PUSCH vector pack.");
end
if strlength(strtrim(string(outputDir))) == 0
    error("sixgr:pusch:PhaseOutputMissing", ...
        "OutputDir must be nonempty.");
end
if isfile(outputDir) || isfolder(outputDir)
    error("sixgr:pusch:PhaseOutputAlreadyExists", ...
        "OutputDir must not already exist; phase publication is transactional.");
end
if any(~isfinite(seedList) | seedList ~= fix(seedList))
    error("sixgr:pusch:PhaseSeedListInvalid", ...
        "SeedList must contain finite integers.");
end

started = tic;
[vectorStatus, vectorOutput, vectorCommand] = ...
    localRunPython(fullfile(vectorRoot, "verify_pusch_vector_pack.py"), "");
if vectorStatus ~= 0
    error("sixgr:pusch:VectorPackVerificationFailed", ...
        "PUSCH vector verification failed:\n%s", vectorOutput);
end

setup6GRSimToolkit("Verbose", false);
testSummary = localRunFocusedTests();

parentDir = fileparts(outputDir);
if isempty(parentDir)
    parentDir = pwd;
end
if ~isfolder(parentDir)
    [ok, message] = mkdir(parentDir);
    if ~ok
        error("sixgr:pusch:PhaseOutputParentCreateFailed", "%s", message);
    end
end
stageDir = fullfile(parentDir, ".pusch-stage-" + ...
    string(java.util.UUID.randomUUID()));
if isfile(stageDir) || isfolder(stageDir)
    error("sixgr:pusch:PhaseStageCollision", ...
        "Unique transactional stage already exists: %s",stageDir);
end
[ok, message] = mkdir(stageDir);
if ~ok
    error("sixgr:pusch:PhaseStageCreateFailed", "%s", message);
end
cleanup = onCleanup(@() localRemoveStage(stageDir));

evidence = sixgr.phy.ul.pusch.PUSCHPhaseEvidenceBuilder.build( ...
    vectorRoot, seedList, double(opt.ConfidenceLevel), testSummary);
exported = sixgr.phy.ul.pusch.PUSCHArtifactExporter.export( ...
    evidence, stageDir, vectorRoot);
if exported.CSVCount ~= 20 || exported.PNGCount ~= 11
    error("sixgr:pusch:PhaseArtifactCountMismatch", ...
        "Contracted output is %d CSV and %d PNG, expected 20 and 11.", ...
        exported.CSVCount, exported.PNGCount);
end
if ~isfolder(stageDir)
    error("sixgr:pusch:PhaseStageLostBeforeVerification", ...
        "Transactional PUSCH stage disappeared before verification: %s", ...
        stageDir);
end
verificationDir = tempname;
[copied, copyMessage] = copyfile(stageDir, verificationDir);
if ~copied
    error("sixgr:pusch:PhaseVerificationSnapshotFailed", ...
        "Unable to snapshot the PUSCH stage: %s",copyMessage);
end
verificationCleanup = onCleanup(@() localRemoveStage(verificationDir));
[artifactStatus, artifactOutput, artifactCommand] = ...
    localRunPython(fullfile(vectorRoot, "verify_pusch_artifacts.py"), ...
    verificationDir);
verificationAudit = fullfile(verificationDir, ...
    "pusch_artifact_verification.csv");
if isfile(verificationAudit)
    [copied, copyMessage] = copyfile(verificationAudit,stageDir,"f");
    if ~copied
        error("sixgr:pusch:PhaseVerificationAuditPublishFailed", ...
            "Unable to publish the PUSCH verifier audit: %s",copyMessage);
    end
end
clear verificationCleanup
localRemoveStage(verificationDir);
if artifactStatus ~= 0
    error("sixgr:pusch:ArtifactVerificationFailed", ...
        "PUSCH artifact verification failed:\n%s", artifactOutput);
end

inventory = localInventory(stageDir, exported);
[moved, moveMessage] = movefile(stageDir, outputDir);
if ~moved
    error("sixgr:pusch:PhasePublishFailed", ...
        "Unable to publish PUSCH phase output: %s", moveMessage);
end
clear cleanup

summary = struct( ...
    "ContractVersion", "PUSCHPhaseValidation/v1", ...
    "Passed", true, ...
    "VectorRoot", string(vectorRoot), ...
    "OutputDir", string(outputDir), ...
    "SeedList", seedList, ...
    "ConfidenceLevel", double(opt.ConfidenceLevel), ...
    "Strict", logical(opt.Strict), ...
    "MATLABRelease", string(version("-release")), ...
    "VectorPackVerificationCommand", string(vectorCommand), ...
    "VectorPackVerificationExitCode", double(vectorStatus), ...
    "VectorPackVerificationOutput", string(strtrim(vectorOutput)), ...
    "TestSummary", testSummary, ...
    "ContractedCSVCount", double(exported.CSVCount), ...
    "ContractedPNGCount", double(exported.PNGCount), ...
    "CSVFiles", exported.CSVFiles, ...
    "CSVRowCounts", exported.CSVRowCounts, ...
    "PNGFiles", exported.PNGFiles, ...
    "ArtifactVerifierCommand", string(artifactCommand), ...
    "ArtifactVerifierExitCode", double(artifactStatus), ...
    "ArtifactVerifierOutput", string(strtrim(artifactOutput)), ...
    "ArtifactInventory", inventory, ...
    "DurationSeconds", toc(started));
end

function summary = localRunFocusedTests()
repoRoot = localRepositoryRoot();
suiteFiles = [ ...
    fullfile(repoRoot, "tests", "testPUSCHULSCHPhaseCore.m"), ...
    fullfile(repoRoot, "tests", "testUCIPUSCHPhaseCore.m")];
summary = table( ...
    strings(0, 1), zeros(0, 1), zeros(0, 1), ...
    zeros(0, 1), zeros(0, 1), zeros(0, 1), ...
    'VariableNames', { ...
        'TestSuite','Total','Passed','Failed','Skipped','Blocked'});
for index = 1:numel(suiteFiles)
    if ~isfile(suiteFiles(index))
        error("sixgr:pusch:FocusedTestMissing", ...
            "Required focused suite is missing: %s", suiteFiles(index));
    end
    result = runtests(suiteFiles(index));
    failed = nnz([result.Failed]);
    incomplete = nnz([result.Incomplete]);
    passed = nnz([result.Passed]);
    if failed > 0 || incomplete > 0 || passed ~= numel(result)
        error("sixgr:pusch:FocusedTestFailure", ...
            "%s: total=%d passed=%d failed=%d incomplete=%d.", ...
            suiteFiles(index), numel(result), passed, failed, incomplete);
    end
    [~, name] = fileparts(suiteFiles(index));
    summary(end+1, :) = { ... %#ok<AGROW>
        string(name), numel(result), passed, failed, 0, incomplete};
end
end

function root = localRepositoryRoot()
here = fileparts(mfilename("fullpath"));
root = here;
for index = 1:4
    root = fileparts(root);
end
if ~isfile(fullfile(root, "setup6GRSimToolkit.m"))
    error("sixgr:pusch:RepositoryRootNotFound", ...
        "Unable to locate repository root from the PUSCH package.");
end
end

function [status, output, command] = localRunPython(scriptPath, argument)
if ~isfile(scriptPath)
    error("sixgr:pusch:PythonVerifierMissing", ...
        "Python verifier is missing: %s", scriptPath);
end
command = """" + string(localPythonExecutable()) + """ """ ...
    + string(scriptPath) + """";
if strlength(string(argument)) > 0
    command = command + " """ + string(argument) + """";
end
[status, output] = system(char(command));
end

function executable = localPythonExecutable()
executable = "python";
end

function inventory = localInventory(stageDir, exported)
names = [exported.CSVFiles(:); exported.PNGFiles(:); ...
    "pusch_artifact_verification.csv"];
kind = [repmat("CSV", numel(exported.CSVFiles), 1); ...
    repmat("PNG", numel(exported.PNGFiles), 1); "VERIFIER"];
bytes = zeros(numel(names), 1);
sha = strings(numel(names), 1);
width = nan(numel(names), 1);
height = nan(numel(names), 1);
for index = 1:numel(names)
    path = fullfile(stageDir, names(index));
    if ~isfile(path)
        error("sixgr:pusch:PhaseInventoryMissing", ...
            "Expected final artifact is absent: %s", names(index));
    end
    metadata = dir(path);
    bytes(index) = metadata.bytes;
    sha(index) = localFileSHA256(path);
    if kind(index) == "PNG"
        image = imfinfo(path);
        width(index) = image.Width;
        height(index) = image.Height;
    end
end
inventory = table(names, kind, bytes, sha, width, height, ...
    repmat("PASS", numel(names), 1), ...
    'VariableNames', { ...
        'FileName','Kind','Bytes','SHA256','Width','Height','Status'});
end

function hash = localFileSHA256(path)
fid = fopen(path, "rb");
if fid < 0
    error("sixgr:pusch:PhaseArtifactReadFailed", ...
        "Unable to read final artifact: %s", path);
end
cleanup = onCleanup(@() fclose(fid));
bytes = fread(fid, Inf, "*uint8");
hash = string(sixgr.util.sha256Hex(bytes));
clear cleanup
end

function localRemoveStage(path)
if isfolder(path)
    resolved = string(java.io.File(path).getCanonicalPath());
    parent = string(java.io.File(fileparts(path)).getCanonicalPath());
    if startsWith(resolved, parent + string(filesep)) ...
            && resolved ~= parent
        rmdir(path, "s");
    end
end
end
