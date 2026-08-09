function ok = testArtifactContractEngine()
%TESTARTIFACTCONTRACTENGINE Contract normalization and runtime-only publish.

catalog = sixgr.artifact.ContractCatalog.load();
assert(height(catalog) == 1350, "Expected the complete 1,350-row artifact catalog.");
assert(nnz(catalog.ArtifactType == "CSV") == 659, "CSV contract count drifted.");
assert(nnz(catalog.ArtifactType == "PNG") == 691, "PNG contract count drifted.");
assert(numel(unique(catalog.Domain)) == 15, "Expected all 15 technical domains.");
assert(all(endsWith(lower(catalog.FileName(catalog.ArtifactType == "PNG")), ".png")), ...
    "Image contracts must be PNG-only.");
assert(~any(contains(catalog.SourceContract, "pdsch_dlsch_codex_pack")), ...
    "The duplicate legacy PDSCH pack must not enter the production catalog.");
prachRows = catalog.Domain == "initial_access" & ...
    contains(lower(catalog.FileName), "prach");
assert(any(prachRows) && all(catalog.Component(prachRows) == "prach"), ...
    "PRACH evidence must publish in its own component folder.");
phasePrachDetection = catalog.Domain == "initial_access" & ...
    catalog.Profile == "base" & catalog.ArtifactType == "CSV" & ...
    catalog.FileName == "prach_detection_trials.csv";
assert(nnz(phasePrachDetection) == 1 && ...
    catalog.MinimumRows(phasePrachDetection) == 100, ...
    "The phase-pack PRACH qualification minimum must remain 100 trials.");
runtimeCatalog = sixgr.artifact.ContractCatalog.load( ...
    sixgr.artifact.ContractCatalog.repositoryRoot(), "runtime_in_path");
assert(height(runtimeCatalog) == 6 && ...
    nnz(runtimeCatalog.ArtifactType == "CSV") == 3 && ...
    nnz(runtimeCatalog.ArtifactType == "PNG") == 3, ...
    "Same-execution runtime publication must contain exactly 3 CSV/3 PNG contracts.");
assert(all(endsWith(runtimeCatalog.ContractID, "|runtime_in_path")), ...
    "Runtime contracts require their own evidence-scope identity.");
assert(all(runtimeCatalog.MinimumRows( ...
    runtimeCatalog.ArtifactType == "CSV") == 1));
assert(all(runtimeCatalog.MinimumFinitePoints( ...
    runtimeCatalog.ArtifactType == "PNG") == 1));
assert(isequal(sort(unique(runtimeCatalog.Domain)), ...
    ["initial_access";"pdsch";"pusch"]), ...
    "Runtime contracts must be limited to currently registered in-path domains.");

% Conflicting authoring aliases must fail during normalization.  The
% finalizer consumes the single normalized output authority only.
authorityRoot = tempname();
mkdir(authorityRoot);
authorityCleanup = onCleanup(@() localRemove(authorityRoot)); %#ok<NASGU>
authorityCfg = struct();
authorityCfg.meta = struct("scenario_id", "artifact_authority_unit");
authorityCfg.output = struct("artifact_contract_engine", ...
    localEnginePolicy(false));
authorityCfg.canonical_control = struct( ...
    "integration", struct("run_mode", "FIXED_SNR_SWEEP"), ...
    "output", struct("artifact_contract_engine", localEnginePolicy(true)));
try
    sixgr.lls6g.config.normalizeScenarioAliases(authorityCfg);
    error("testArtifactContractEngine:ExpectedAuthorityConflict", ...
        "Contradictory output authorities must fail normalization.");
catch ME
    assert(strcmp(ME.identifier, ...
        "sixgr:lls6g:config:ConflictingCanonicalOutputAuthority"), ...
        "Unexpected output authority error: %s | %s", ME.identifier, ME.message);
end
authorityCfg = rmfield(authorityCfg, "canonical_control");
authorityCfg.output.artifact_contract_engine = localEnginePolicy(true);
authorityCfg.integration = struct("run_mode", "FIXED_SNR_SWEEP");
try
    sixgr.artifact.finalizeConfiguredRun(authorityRoot, ...
        sixgr.artifact.EvidenceRegistry(), authorityCfg);
    error("testArtifactContractEngine:ExpectedMissingEvidence", ...
        "Enabled output authority with no evidence must fail closed.");
catch ME
    assert(strcmp(ME.identifier, "sixgr:artifact:RequiredArtifactGenerationFailed"), ...
        "Unexpected fail-closed finalization error: %s | %s", ...
        ME.identifier, ME.message);
end
try
    sixgr.artifact.removeLegacyGeneratedResults(tempname(), "Execute", true);
    error("testArtifactContractEngine:ExpectedCleanupSafetyFailure", ...
        "Legacy cleanup must reject every path except the exact results root.");
catch ME
    assert(strcmp(ME.identifier, "sixgr:artifact:UnsafeLegacyCleanupRoot"));
end

runRoot = tempname();
mkdir(runRoot);
cleanup = onCleanup(@() localRemove(runRoot)); %#ok<NASGU>
miniCatalog = localCatalog();
evidence = sixgr.artifact.EvidenceRegistry();
runtimeT = table((1:4).', [-5; 0; 5; 10], [0.9; 0.4; 0.08; 0.01], ...
    repmat("waveform_truth", 4, 1), ...
    'VariableNames', {'CaseID', 'SNRdB', 'BLER', 'Source'});
payload = struct();
payload.Tables = struct("pdsch_runtime_bler", runtimeT);
payload.Renderers = struct("pdsch_runtime_bler", @localRenderBLER);
registration = sixgr.artifact.registerContractEvidence(evidence, ...
    "pdsch", "base", payload, "sixgr.phy.dl.PDSCH_Rx", ...
    "Catalog", miniCatalog, "RequireComplete", true);
assert(all(registration.Registered));
result = sixgr.artifact.ContractArtifactGenerator.generate(runRoot, evidence, ...
    "Catalog", miniCatalog);
assert(result.Ok && result.CSVCount == 1 && result.PNGCount == 1);
csvPath = fullfile(runRoot, "components", "pdsch", "csv", ...
    "pdsch_runtime_bler.csv");
pngPath = fullfile(runRoot, "components", "pdsch", "png", ...
    "pdsch_runtime_bler.png");
assert(isfile(csvPath) && isfile(pngPath));
assert(isfile(fullfile(runRoot, "artifact_generation", ...
    "artifact_generation_summary.csv")));
assert(isfile(fullfile(runRoot, "artifact_generation", ...
    "canonical_component_manifest.csv")));
generationSummary = readtable(fullfile(runRoot, "artifact_generation", ...
    "artifact_generation_summary.csv"), "TextType", "string");
assert(sum(generationSummary.GeneratedCount) == 2);
assert(sum(generationSummary.RequiredFailureCount) == 0);
canonicalManifest = readtable(fullfile(runRoot, "artifact_generation", ...
    "canonical_component_manifest.csv"), "TextType", "string");
assert(height(canonicalManifest) == 2);
assert(all(startsWith(replace(canonicalManifest.PublishedRelativePath, ...
    string(filesep), "/"), "components/pdsch/")));
assert(all(canonicalManifest.ByteSize > 0));
assert(~isfile(fullfile(runRoot, "components", "pdsch", "png", ...
    "pdsch_runtime_bler.svg")), "The publisher must not create SVG output.");
publishedT = readtable(csvPath, "TextType", "string");
assert(isequal(publishedT.CaseID, runtimeT.CaseID));
info = imfinfo(pngPath);
assert(info.Width >= 640 && info.Height >= 480);
assert(all(strlength(result.Audit.SourceSHA256) == 64));

% A quick diagnostic is allowed to contain a single measured operating
% point, including BLER=0 with a non-zero exact confidence interval.  The
% production BLER renderer uses an ErrorBar object for this case.  Count
% that object as the required data series instead of rejecting a valid
% measured chart merely because no Line object is present.
onePointRoot = tempname();
mkdir(onePointRoot);
onePointCleanup = onCleanup(@() localRemove(onePointRoot)); %#ok<NASGU>
onePointCatalog = localOnePointErrorbarCatalog();
onePointEvidence = sixgr.artifact.EvidenceRegistry();
onePointT = table(20, 0, 0, 0.1089, "waveform_truth", ...
    'VariableNames', {'SNRdB','BLER','CILower','CIUpper','Source'});
onePointEvidence.registerTable("pdsch", "base", ...
    "one_point_bler.csv", onePointT, "waveform_truth unit evidence");
onePointEvidence.registerRenderer("pdsch", "base", ...
    "one_point_bler.png", @localRenderOnePointErrorbar, ...
    "tests.localRenderOnePointErrorbar");
onePointResult = sixgr.artifact.ContractArtifactGenerator.generate( ...
    onePointRoot, onePointEvidence, "Catalog", onePointCatalog);
assert(onePointResult.Ok && onePointResult.PNGCount == 1, ...
    "A finite one-point ErrorBar BLER chart must satisfy the figure contract.");
assert(isfile(fullfile(onePointRoot, "components", "pdsch", "png", ...
    "one_point_bler.png")));

% Re-running publication from the same immutable runtime evidence must
% atomically replace the component tree with identical CSV/PNG bytes.
firstCSVHash = localFileHash(csvPath);
firstPNGHash = localFileHash(pngPath);
firstPNGPixels = imread(pngPath);
repeatResult = sixgr.artifact.ContractArtifactGenerator.generate(runRoot, evidence, ...
    "Catalog", miniCatalog);
assert(repeatResult.Ok);
repeatCSVHash = localFileHash(csvPath);
repeatPNGHash = localFileHash(pngPath);
repeatPNGPixels = imread(pngPath);
assert(repeatCSVHash == firstCSVHash, ...
    "Repeated CSV finalization must produce a deterministic hash (%s vs %s).", ...
    firstCSVHash, repeatCSVHash);
assert(repeatPNGHash == firstPNGHash, ...
    "Repeated PNG finalization must produce a deterministic hash (%s vs %s; equal_pixels=%d; changed_values=%d).", ...
    firstPNGHash, repeatPNGHash, isequal(firstPNGPixels, repeatPNGPixels), ...
    nnz(firstPNGPixels ~= repeatPNGPixels));

duplicateRoot = tempname();
mkdir(duplicateRoot);
duplicateCleanup = onCleanup(@() localRemove(duplicateRoot)); %#ok<NASGU>
duplicateEvidence = sixgr.artifact.EvidenceRegistry();
duplicateEvidence.registerTable("pdsch", "base", "pdsch_runtime_bler.csv", ...
    [runtimeT; runtimeT(1, :)], "sixgr.phy.dl.PDSCH_Rx");
duplicateEvidence.registerRenderer("pdsch", "base", "pdsch_runtime_bler.png", ...
    @localRenderBLER, "tests.localRenderBLER");
try
    sixgr.artifact.ContractArtifactGenerator.generate(duplicateRoot, ...
        duplicateEvidence, "Catalog", miniCatalog);
    error("testArtifactContractEngine:ExpectedDuplicateFailure", ...
        "Exact duplicate runtime rows must fail canonical publication.");
catch ME
    assert(strcmp(ME.identifier, "sixgr:artifact:RequiredArtifactGenerationFailed"));
end
duplicateFailure = readtable(fullfile(duplicateRoot, "artifact_generation", ...
    "artifact_generation_failures.csv"), "TextType", "string");
assert(any(contains(duplicateFailure.Message, "ExactDuplicateRows")));

missingRoot = tempname();
mkdir(missingRoot);
missingCleanup = onCleanup(@() localRemove(missingRoot)); %#ok<NASGU>
try
    sixgr.artifact.ContractArtifactGenerator.generate(missingRoot, ...
        sixgr.artifact.EvidenceRegistry(), "Catalog", miniCatalog);
    error("testArtifactContractEngine:ExpectedFailure", ...
        "Missing production evidence must fail closed.");
catch ME
    assert(strcmp(ME.identifier, "sixgr:artifact:RequiredArtifactGenerationFailed"), ...
        "Unexpected missing-evidence error: %s | %s", ME.identifier, ME.message);
end
assert(~isfolder(fullfile(missingRoot, "components")), ...
    "A failed generation must not publish a partial component tree.");
assert(isfile(fullfile(missingRoot, "artifact_generation", ...
    "artifact_generation_failures.csv")));
missingSummary = readtable(fullfile(missingRoot, "artifact_generation", ...
    "artifact_generation_summary.csv"), "TextType", "string");
assert(sum(missingSummary.GeneratedCount) == 0);
assert(sum(missingSummary.RequiredFailureCount) == 2);
assert(~isfile(fullfile(missingRoot, "artifact_generation", ...
    "canonical_component_manifest.csv")));

proxyRoot = tempname();
mkdir(proxyRoot);
proxyCleanup = onCleanup(@() localRemove(proxyRoot)); %#ok<NASGU>
proxyEvidence = sixgr.artifact.EvidenceRegistry();
proxyEvidence.registerTable("pdsch", "base", "pdsch_runtime_bler.csv", ...
    runtimeT, "fast_proxy regression lookup");
proxyEvidence.registerRenderer("pdsch", "base", "pdsch_runtime_bler.png", ...
    @localRenderBLER, "tests.localRenderBLER");
try
    sixgr.artifact.ContractArtifactGenerator.generate(proxyRoot, ...
        proxyEvidence, "Catalog", miniCatalog);
    error("testArtifactContractEngine:ExpectedProxyFailure", ...
        "Proxy evidence must not enter truth-only artifacts.");
catch ME
    assert(strcmp(ME.identifier, "sixgr:artifact:RequiredArtifactGenerationFailed"), ...
        "Unexpected proxy-evidence error: %s | %s", ME.identifier, ME.message);
end
failureT = readtable(fullfile(proxyRoot, "artifact_generation", ...
    "artifact_generation_failures.csv"), "TextType", "string");
assert(any(contains(failureT.Message, "ProxyEvidenceRejected")));

statusRoot = tempname();
mkdir(statusRoot);
statusCleanup = onCleanup(@() localRemove(statusRoot)); %#ok<NASGU>
statusEvidence = sixgr.artifact.EvidenceRegistry();
incompleteT = runtimeT;
incompleteT.Status = repmat("STATISTICALLY_QUALIFIED", height(incompleteT), 1);
incompleteT.Incomplete = false(height(incompleteT), 1);
incompleteT.Status(1) = "MEASURED_NOT_QUALIFIED";
statusEvidence.registerTable("pdsch", "base", "pdsch_runtime_bler.csv", ...
    incompleteT, "sixgr.phy.dl.PDSCH_Rx");
statusEvidence.registerRenderer("pdsch", "base", "pdsch_runtime_bler.png", ...
    @localRenderBLER, "tests.localRenderBLER");
try
    sixgr.artifact.ContractArtifactGenerator.generate(statusRoot, ...
        statusEvidence, "Catalog", miniCatalog);
    error("testArtifactContractEngine:ExpectedStatusFailure", ...
        "An unqualified required runtime row must fail publication.");
catch ME
    assert(strcmp(ME.identifier, "sixgr:artifact:RequiredArtifactGenerationFailed"));
end
statusFailure = readtable(fullfile(statusRoot, "artifact_generation", ...
    "artifact_generation_failures.csv"), "TextType", "string");
assert(any(contains(statusFailure.Message, "NonPassingRuntimeStatus")), ...
    "Artifact audit must identify the non-passing runtime status.");

% Runtime mode selection is exact: ALL and BOTH apply to each run, while
% FIXED_SNR_SWEEP and GEOMETRY_NETWORK never cross-publish.
modeCatalog = localModeCatalog();
modeEvidence = sixgr.artifact.EvidenceRegistry();
for modeName = ["all", "both", "fixed", "geometry"]
    fileName = "mode_" + modeName + ".csv";
    modeEvidence.registerTable("pdsch", "base", fileName, ...
        table(1, "waveform_truth", 'VariableNames', {'CaseID','Source'}), ...
        "tests.mode_selection.waveform_truth");
end
fixedRoot = tempname();
mkdir(fixedRoot);
fixedCleanup = onCleanup(@() localRemove(fixedRoot)); %#ok<NASGU>
fixedResult = sixgr.artifact.ContractArtifactGenerator.generate( ...
    fixedRoot, modeEvidence, "Catalog", modeCatalog, ...
    "Mode", "FIXED_SNR_SWEEP");
assert(fixedResult.CSVCount == 3);
fixedSnapshot = readtable(fullfile(fixedRoot, "artifact_generation", ...
    "contract_catalog_snapshot.csv"), "TextType", "string");
assert(all(ismember(upper(fixedSnapshot.Mode), ...
    ["ALL", "BOTH", "FIXED_SNR_SWEEP"])));
assert(any(upper(fixedSnapshot.Mode) == "BOTH") && ...
    ~any(upper(fixedSnapshot.Mode) == "GEOMETRY_NETWORK"));

geometryRoot = tempname();
mkdir(geometryRoot);
geometryCleanup = onCleanup(@() localRemove(geometryRoot)); %#ok<NASGU>
geometryResult = sixgr.artifact.ContractArtifactGenerator.generate( ...
    geometryRoot, modeEvidence, "Catalog", modeCatalog, ...
    "Mode", "GEOMETRY_NETWORK");
assert(geometryResult.CSVCount == 3);
geometrySnapshot = readtable(fullfile(geometryRoot, "artifact_generation", ...
    "contract_catalog_snapshot.csv"), "TextType", "string");
assert(all(ismember(upper(geometrySnapshot.Mode), ...
    ["ALL", "BOTH", "GEOMETRY_NETWORK"])));
assert(any(upper(geometrySnapshot.Mode) == "BOTH") && ...
    ~any(upper(geometrySnapshot.Mode) == "FIXED_SNR_SWEEP"));

ok = true;
fprintf("PASS testArtifactContractEngine: 659 CSV + 691 PNG contracts normalized; runtime-only publication verified.\n");
end

function catalog = localCatalog()
base = struct( ...
    "ContractID", "", "Domain", "pdsch", "Component", "pdsch", ...
    "Profile", "base", "Mode", "ALL", "ContractSection", "pdsch", ...
    "ArtifactType", "", "FileName", "", "ContractArtifactPath", "", ...
    "OutputRelativePath", "", "Required", true, "MinimumRows", 0, ...
    "RequiredColumns", "", "PrimaryKey", "", "SourceCSV", "", ...
    "MinimumWidth", 0, "MinimumHeight", 0, "MinimumAxes", 0, ...
    "MinimumSeries", 0, "MinimumFinitePoints", 0, ...
    "ExpectedTitle", "", "ExpectedXLabel", "", "ExpectedYLabel", "", ...
    "Description", "", "PassCondition", "", "ProductionSource", "", ...
    "SourceContract", "tests/testArtifactContractEngine.m");
csvRow = base;
csvRow.ContractID = "pdsch|base|csv|pdsch_runtime_bler.csv|all";
csvRow.ArtifactType = "CSV";
csvRow.FileName = "pdsch_runtime_bler.csv";
csvRow.ContractArtifactPath = csvRow.FileName;
csvRow.OutputRelativePath = fullfile("pdsch", "csv", csvRow.FileName);
csvRow.MinimumRows = 4;
csvRow.RequiredColumns = "CaseID|SNRdB|BLER|Source";
csvRow.PrimaryKey = "CaseID";
pngRow = base;
pngRow.ContractID = "pdsch|base|png|pdsch_runtime_bler.png|all";
pngRow.ArtifactType = "PNG";
pngRow.FileName = "pdsch_runtime_bler.png";
pngRow.ContractArtifactPath = pngRow.FileName;
pngRow.OutputRelativePath = fullfile("pdsch", "png", pngRow.FileName);
pngRow.SourceCSV = csvRow.FileName;
pngRow.MinimumWidth = 640;
pngRow.MinimumHeight = 480;
pngRow.MinimumAxes = 1;
pngRow.MinimumSeries = 1;
pngRow.MinimumFinitePoints = 8;
pngRow.ExpectedTitle = "Runtime BLER";
pngRow.ExpectedXLabel = "SNR";
pngRow.ExpectedYLabel = "BLER";
catalog = struct2table([csvRow; pngRow], 'AsArray', true);
end

function catalog = localModeCatalog()
template = localCatalog();
template = template(1, :);
modes = ["ALL"; "BOTH"; "FIXED_SNR_SWEEP"; "GEOMETRY_NETWORK"];
names = ["mode_all.csv"; "mode_both.csv"; "mode_fixed.csv"; ...
    "mode_geometry.csv"];
catalog = repmat(template, numel(modes), 1);
for index = 1:numel(modes)
    catalog.Mode(index) = modes(index);
    catalog.FileName(index) = names(index);
    catalog.ContractArtifactPath(index) = names(index);
    catalog.OutputRelativePath(index) = string(fullfile( ...
        "pdsch", "csv", names(index)));
    catalog.ContractID(index) = "pdsch|base|csv|" + names(index) + ...
        "|" + lower(modes(index));
    catalog.MinimumRows(index) = 1;
    catalog.RequiredColumns(index) = "CaseID|Source";
    catalog.PrimaryKey(index) = "CaseID";
end
end

function catalog = localOnePointErrorbarCatalog()
catalog = localCatalog();
catalog.MinimumRows(:) = 1;
catalog.MinimumFinitePoints(:) = 1;
catalog.RequiredColumns(1) = "SNRdB|BLER|CILower|CIUpper|Source";
catalog.PrimaryKey(1) = "SNRdB";
catalog.FileName(1) = "one_point_bler.csv";
catalog.ContractArtifactPath(1) = catalog.FileName(1);
catalog.OutputRelativePath(1) = string(fullfile( ...
    "pdsch", "csv", catalog.FileName(1)));
catalog.ContractID(1) = "pdsch|base|csv|one_point_bler.csv|all";
catalog.FileName(2) = "one_point_bler.png";
catalog.ContractArtifactPath(2) = catalog.FileName(2);
catalog.OutputRelativePath(2) = string(fullfile( ...
    "pdsch", "png", catalog.FileName(2)));
catalog.SourceCSV(2) = catalog.FileName(1);
catalog.MinimumFinitePoints(2) = 1;
catalog.ExpectedTitle(2) = "One-point BLER";
catalog.ExpectedXLabel(2) = "SNR";
catalog.ExpectedYLabel(2) = "BLER";
catalog.ContractID(2) = "pdsch|base|png|one_point_bler.png|all";
end

function fig = localRenderBLER(bundle, ~)
T = bundle.Tables{1};
fig = figure("Visible", "off", "Color", "white");
plot(T.SNRdB, T.BLER, "-o", "LineWidth", 1.5);
grid on;
title("Runtime BLER");
xlabel("SNR (dB)");
ylabel("BLER");
end

function fig = localRenderOnePointErrorbar(bundle, ~)
T = bundle.Tables{1};
fig = figure("Visible", "off", "Color", "white");
lowerError = T.BLER - T.CILower;
upperError = T.CIUpper - T.BLER;
errorbar(T.SNRdB, T.BLER, lowerError, upperError, "o", ...
    "LineWidth", 1.5);
grid on;
title("One-point BLER");
xlabel("SNR (dB)");
ylabel("BLER");
end

function localRemove(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end

function hash = localFileHash(pathValue)
fid = fopen(pathValue, "rb");
assert(fid >= 0);
cleanup = onCleanup(@() fclose(fid)); %#ok<NASGU>
hash = sixgr.util.sha256Hex(fread(fid, Inf, "*uint8"));
end

function engine = localEnginePolicy(enabled)
engine = struct( ...
    "enabled", logical(enabled), ...
    "contract_root", "tests/vectors", ...
    "legacy_reference_root", "artifacts", ...
    "legacy_reference_usage", "coverage_inventory_only", ...
    "profiles", "base", ...
    "domains", "pdsch", ...
    "publish_root", "components", ...
    "source_policy", "runtime_memory_only", ...
    "truth_only", true, ...
    "fail_on_missing_required", true, ...
    "evidence_scope", "in_path", ...
    "require_identity_columns", true, ...
    "require_radio_identity_columns", true, ...
    "atomic_replace", true, ...
    "image_format", "png", ...
    "allow_svg", false, ...
    "allow_placeholder_evidence", false);
end
