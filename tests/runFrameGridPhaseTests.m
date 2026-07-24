function [manifest, summary] = runFrameGridPhaseTests(outputDirectory, varargin)
%RUNFRAMEGRIDPHASETESTS Execute frame/grid tests and export acceptance evidence.

parser = inputParser;
parser.FunctionName = "runFrameGridPhaseTests";
addRequired(parser, "outputDirectory", ...
    @(v) ischar(v) || (isstring(v) && isscalar(v)));
addParameter(parser, "RunTests", true, ...
    @(v) islogical(v) && isscalar(v));
addParameter(parser, "TestSummary", table(), @istable);
parse(parser, outputDirectory, varargin{:});

setup6GRSimToolkit("Verbose", false);
outputDirectory = localPrepareOutputDirectory(outputDirectory);

if parser.Results.RunTests
    summary = localRunMandatoryTests(outputDirectory);
else
    summary = parser.Results.TestSummary;
    if isempty(summary)
        error("sixgr:tests:MissingFrameGridTestSummary", ...
            "RunTests=false requires a nonempty TestSummary from actual executions.");
    end
end

manifest = sixgr.phy.frame.exportFrameGridArtifacts( ...
    outputDirectory, "TestSummary", summary, "RequireAllPass", false);
if ~manifest.AllStatusPass
    error("sixgr:tests:FrameGridPhaseFailed", ...
        "Frame/grid artifacts were generated, but one or more evidence rows failed.");
end
fprintf("Frame/grid phase: %d CSVs, %d PNGs, all rows PASS.\n", ...
    manifest.CSVCount, manifest.ImageCount);
end

function outputDirectory = localPrepareOutputDirectory(raw)
outputDirectory = char(string(raw));
if strlength(strtrim(string(outputDirectory))) == 0
    error("sixgr:tests:InvalidFrameGridOutputDirectory", ...
        "Output directory must be nonempty.");
end
if ~isfolder(outputDirectory)
    mkdir(outputDirectory);
end
outputDirectory = char(java.io.File(outputDirectory).getCanonicalPath());
repo = char(java.io.File(pwd).getCanonicalPath());
driveRoot = char(java.io.File(outputDirectory).toPath().getRoot().toString());
if strcmpi(outputDirectory, repo) || strcmpi(outputDirectory, driveRoot)
    error("sixgr:tests:UnsafeFrameGridOutputDirectory", ...
        "Refusing to clean broad path '%s'.", outputDirectory);
end

patterns = ["*.csv", "*.png", ...
    "frame_artifact_verification.json", ...
    "frame_artifact_verification.csv"];
for pattern = patterns
    listing = dir(fullfile(outputDirectory, pattern));
    for index = 1:numel(listing)
        delete(fullfile(listing(index).folder, listing(index).name));
    end
end
logDirectory = fullfile(outputDirectory, "test_logs");
if isfolder(logDirectory)
    listing = dir(fullfile(logDirectory, "*.txt"));
    for index = 1:numel(listing)
        delete(fullfile(listing(index).folder, listing(index).name));
    end
    if isempty(dir(fullfile(logDirectory, "*.*")))
        rmdir(logDirectory);
    end
end
end

function summary = localRunMandatoryTests(outputDirectory)
testNames = [ ...
    "testFrameNumerologyCatalog"
    "testTransmissionBandwidthCatalog"
    "testOFDMSamplingResolver"
    "testTDDCommonPattern"
    "testTDDDedicatedOverride"
    "testTDDMultiNumerologyExpansion"
    "testFlexibleSymbolAllocator"
    "testFDDSeparateFrameGrids"
    "testControlDataAllocationIndependence"
    "testResourceAllocationValidator"
    "testSSBTimingResolver"
    "testPRACHOccasionResolver"
    "testTimingRelationEngine"
    "testMultiBWPFrameGrid"
    "testCarrierAggregationFrameTiming"];
n = numel(testNames);
suite = testNames;
testsRun = ones(n, 1);
passed = zeros(n, 1);
failed = zeros(n, 1);
skipped = zeros(n, 1);
blocked = zeros(n, 1);
status = repmat("FAIL", n, 1);
resultFile = strings(n, 1);
logDirectory = fullfile(outputDirectory, "test_logs");
if ~isfolder(logDirectory)
    mkdir(logDirectory);
end

for index = 1:n
    name = testNames(index);
    logPath = fullfile(logDirectory, name + ".txt");
    resultFile(index) = string(fullfile("test_logs", name + ".txt"));
    fid = fopen(logPath, "wt");
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, "Suite: %s\n", name);
    if exist(name, "file") ~= 2
        blocked(index) = 1;
        fprintf(fid, "BLOCKED: required test function is missing.\n");
        clear cleanup;
        continue;
    end
    try
        tic;
        result = feval(name);
        elapsed = toc;
        if ~(islogical(result) && isscalar(result) && result)
            error("sixgr:tests:MandatoryTestDidNotReturnTrue", ...
                "%s did not return scalar logical true.", name);
        end
        passed(index) = 1;
        status(index) = "PASS";
        fprintf(fid, "PASS in %.6f seconds.\n", elapsed);
    catch cause
        failed(index) = 1;
        fprintf(fid, "FAIL %s: %s\n", cause.identifier, cause.message);
        for stackIndex = 1:numel(cause.stack)
            fprintf(fid, "  at %s (%s:%d)\n", ...
                cause.stack(stackIndex).name, ...
                cause.stack(stackIndex).file, ...
                cause.stack(stackIndex).line);
        end
    end
    clear cleanup;
end
summary = table(suite, testsRun, passed, failed, skipped, blocked, ...
    status, resultFile, 'VariableNames', [ ...
    "Suite","TestsRun","Passed","Failed","Skipped","Blocked", ...
    "Status","ResultFile"]);
end
