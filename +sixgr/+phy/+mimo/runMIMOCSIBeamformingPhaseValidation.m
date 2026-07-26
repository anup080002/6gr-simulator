function result = runMIMOCSIBeamformingPhaseValidation(options)
%RUNMIMOCSIBEAMFORMINGPHASEVALIDATION Execute the strict Phase-07 gate.
%
% This runner deliberately fails closed. Contracted MIMO CSV/PNG artifacts
% are only eligible after every mandatory production test and every frozen
% independent codebook matrix pack is present. Component/vector evidence is
% never promoted to waveform truth merely to satisfy an artifact shape.

arguments
    options.VectorRoot (1,1) string = fullfile(pwd,"tests","vectors","mimo")
    options.OutputDir (1,1) string = ...
        fullfile(pwd,"artifacts","mimo_csi_beamforming_phase")
    options.SeedList (1,:) double {mustBeInteger,mustBeNonnegative} = [11 23 47 89]
    options.ConfidenceLevel (1,1) double {mustBeGreaterThan(options.ConfidenceLevel,0), ...
        mustBeLessThan(options.ConfidenceLevel,1)} = 0.95
    options.Strict (1,1) logical = true
end

if ~options.Strict
    error("sixgr:mimo:StrictValidationRequired", ...
        "Phase-07 qualification requires Strict=true.");
end
vectorRoot = localExistingFolder(options.VectorRoot,"VectorRoot");
outputDir = localPrepareOutputFolder(options.OutputDir);
repoRoot = fileparts(fileparts(fileparts(fileparts(mfilename("fullpath")))));
testsRoot = fullfile(repoRoot,"tests");
callerPath = path;
pathCleanup = onCleanup(@()path(callerPath)); %#ok<NASGU>
addpath(testsRoot);

vectorResults = sixgr.phy.mimo.runIndependentVectorValidation(vectorRoot);
negativeResults = sixgr.phy.mimo.runNegativeVectorValidation(vectorRoot);
productionResults = runtests(fullfile(repoRoot, ...
    "tests","testMIMOCSIBeamformingPhase07Core.m"));
yamlPassed = testMIMOPhase07YAMLAuthority();

testPlan = localReadCSV(fullfile(vectorRoot,"mimo_matlab_test_plan.csv"));
executedNames = localExecutedNames(productionResults);
mandatoryNames = string(testPlan.TestName);
missingTests = setdiff(mandatoryNames,executedNames,"stable");

capability = localReadCSV(fullfile(vectorRoot, ...
    "mimo_capability_profile_matrix.csv"));
positiveCapability = capability(localTruth(capability.Supported),:);
profileAuthority = sixgr.phy.mimo.MIMOCapabilityProfile();
matrixReady = false(height(positiveCapability),1);
for row = 1:height(positiveCapability)
    request = localCapabilityRequest(positiveCapability(row,:));
    resolved = profileAuthority.resolve(request);
    matrixReady(row) = logical(resolved.IndependentMatrixPackReady) || ...
        ~localRequiresIndependentCodebookMatrix(resolved.ProfileID);
end
missingMatrixProfiles = unique(string( ...
    positiveCapability.ProfileID(~matrixReady)),"stable");

contract = localReadCSV(fullfile(vectorRoot,"desired_mimo_csv_contract.csv"));
imageContract = localReadCSV(fullfile(vectorRoot, ...
    "desired_mimo_image_contract.csv"));
contractedCSVPresent = isfile(fullfile(outputDir,string(contract.FileName)));
contractedPNGPresent = isfile(fullfile(outputDir,string(imageContract.ImageFile)));

gate = table( ...
    ["independent_vector_pack";"typed_negative_contract"; ...
     "bounded_production_tests";"yaml_authority"; ...
     "mandatory_test_contract";"independent_codebook_matrix_packs"; ...
     "base_csv_contract";"base_png_contract"], ...
    [double(vectorResults.TotalCases);height(negativeResults); ...
     numel(productionResults);1;height(testPlan); ...
     height(positiveCapability);height(contract);height(imageContract)], ...
    [double(vectorResults.MismatchCount); ...
     sum(~negativeResults.Passed);sum(~[productionResults.Passed]); ...
     ~logical(yamlPassed);numel(missingTests);sum(~matrixReady); ...
     sum(~contractedCSVPresent);sum(~contractedPNGPresent)], ...
    ["independent specification/vector calculations"; ...
     "typed planning rejection before waveform/state/grant"; ...
     "executed bounded production components"; ...
     "operator YAML materialization and validation"; ...
     "mandatory tests named by mimo_matlab_test_plan.csv"; ...
     "frozen independent matrices required before strict enumeration"; ...
     "contracted production CSVs (not generated before gates pass)"; ...
     "contracted production PNGs (not generated before gates pass)"], ...
    VariableNames=["Gate","ExpectedOrExecuted","MissingOrFailed", ...
    "EvidenceClass"]);
gate.Passed = gate.MissingOrFailed == 0;
gate.Status = repmat("PASS",height(gate),1);
gate.Status(~gate.Passed) = "BLOCKED";

gatePath = fullfile(outputDir,"mimo_phase07_gate_report.csv");
writetable(gate,gatePath);

missingTestsPath = fullfile(outputDir,"mimo_phase07_missing_tests.csv");
writetable(table(missingTests(:),VariableNames="TestName"), ...
    missingTestsPath);
missingMatricesPath = fullfile(outputDir, ...
    "mimo_phase07_missing_independent_matrix_profiles.csv");
writetable(table(missingMatrixProfiles(:), ...
    VariableNames="ProfileID"),missingMatricesPath);

result = struct();
result.Passed = all(gate.Passed);
result.Status = localStatus(result.Passed);
result.Strict = true;
result.VectorRoot = vectorRoot;
result.OutputDir = outputDir;
result.SeedList = double(options.SeedList);
result.ConfidenceLevel = double(options.ConfidenceLevel);
result.GateTable = gate;
result.GateReport = string(gatePath);
result.IndependentVectorCases = double(vectorResults.TotalCases);
result.IndependentVectorMismatches = double(vectorResults.MismatchCount);
result.NegativeCases = height(negativeResults);
result.NegativeFailures = sum(~negativeResults.Passed);
result.ProductionTests = numel(productionResults)+1;
result.ProductionTestFailures = sum(~[productionResults.Passed]) + ...
    ~logical(yamlPassed);
result.MandatoryTestsExpected = height(testPlan);
result.MandatoryTestsMissing = missingTests;
result.MissingIndependentMatrixProfiles = missingMatrixProfiles;
result.ContractedCSVMissing = string(contract.FileName(~contractedCSVPresent));
result.ContractedPNGMissing = string(imageContract.ImageFile(~contractedPNGPresent));
result.ContractedArtifactsGenerated = false;
result.ArtifactEligibility = "blocked_until_all_truth_gates_pass";

if ~result.Passed
    warning("sixgr:mimo:PhaseValidationIncomplete", ...
        "Phase-07 remains blocked: %d mandatory tests, %d independent " + ...
        "matrix profiles, %d contracted CSVs, and %d contracted PNGs are " + ...
        "missing. No component/proxy evidence was relabeled as waveform truth.", ...
        numel(missingTests),numel(missingMatrixProfiles), ...
        sum(~contractedCSVPresent),sum(~contractedPNGPresent));
end
end

function folder = localExistingFolder(value,label)
folder = string(java.io.File(char(value)).getCanonicalPath());
if ~isfolder(folder)
    error("sixgr:mimo:MissingVectorRoot", ...
        "%s does not exist: %s",label,folder);
end
end

function folder = localPrepareOutputFolder(value)
folder = string(java.io.File(char(value)).getCanonicalPath());
if ~isfolder(folder)
    [ok,message] = mkdir(folder);
    if ~ok
        error("sixgr:mimo:ArtifactWriteFailed", ...
            "Unable to create output directory %s: %s",folder,message);
    end
end
end

function names = localExecutedNames(results)
names = strings(numel(results),1);
for index = 1:numel(results)
    token = string(results(index).Name);
    parts = split(token,"/");
    names(index) = parts(end);
end
end

function data = localReadCSV(path)
importOptions = detectImportOptions(path, ...
    FileType="text",Delimiter=",",VariableNamingRule="preserve");
importOptions = setvartype(importOptions, ...
    importOptions.VariableNames,"string");
data = readtable(path,importOptions);
end

function request = localCapabilityRequest(row)
request = struct( ...
    "ProfileID",string(row.ProfileID), ...
    "Direction",string(row.Direction), ...
    "CodebookType",string(row.CodebookType), ...
    "Ports",double(row.Ports), ...
    "Panels",double(row.Panels), ...
    "Rank",double(row.Rank));
for field = ["N1","N2","O1","O2"]
    if ismember(field,string(row.Properties.VariableNames))
        value = str2double(string(row.(field)));
        if isfinite(value)
            request.(field) = value;
        end
    end
end
end

function tf = localRequiresIndependentCodebookMatrix(profileID)
profileID = lower(string(profileID));
tf = contains(profileID,"typei") || contains(profileID,"typeii");
end

function values = localTruth(values)
values = upper(strtrim(string(values)));
values = ismember(values,["1","TRUE","YES","PASS"]);
end

function status = localStatus(passed)
if passed
    status = "PASS";
else
    status = "BLOCKED";
end
end
