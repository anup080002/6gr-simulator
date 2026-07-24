function ok = testNumerologyCallerMigration()
%TESTNUMEROLOGYCALLERMIGRATION Guard active callers against rounded SCS timing.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

cfg = struct("phy", struct("carrier", struct( ...
    "SubcarrierSpacing", 120, "CyclicPrefix", "normal")));
T = table([1; 81], 'VariableNames', {'Slot'});
T = sixgr.util.enrichResultTableContext(T, cfg);
assert(isequal(T.Frame, [1; 2]), ...
    "Result enrichment must use the canonical 80 slots/frame at 120 kHz.");

invalidCfg = struct("phy", struct("carrier", struct( ...
    "SubcarrierSpacing", 25, "CyclicPrefix", "normal")));
localAssertThrows(@() sixgr.util.enrichResultTableContext(T, invalidCfg), ...
    "sixgr:phy:frame:UnsupportedSubcarrierSpacing");
localAssertThrows(@() sixgr.l3.rrc.RACHProcedure(invalidCfg), ...
    "sixgr:phy:frame:UnsupportedSubcarrierSpacing");

paths = [ ...
    "+sixgr/+analytics/buildPhysicsAuditTable.m"
    "+sixgr/+analytics/buildMobilityAdequacyReport.m"
    "+sixgr/+ctrl/ControlChannelConfig.m"
    "+sixgr/+ctrl/PDCCHBlindDetector.m"
    "+sixgr/+ctrl/PDCCHCandidateGenerator.m"
    "+sixgr/+ctrl/PDCCHDMRS.m"
    "+sixgr/+l3/+rrc/RACHProcedure.m"
    "+sixgr/+link/deriveModulationTrackingMetrics.m"
    "+sixgr/+link/computeLinkAdaptationDecision.m"
    "+sixgr/+link/runDLPDSCHThroughput.m"
    "+sixgr/+link/exportLinkKPIs.m"
    "+sixgr/+link/runPRACHDetection.m"
    "+sixgr/+link/runULPUSCHThroughput.m"
    "+sixgr/+l2/+mac/SchedulerBase.m"
    "+sixgr/+l2/+mac/SchedulerPF.m"
    "+sixgr/+truth/exportLLSEnergyDiagnostics.m"
    "+sixgr/+truth/exportLLSLiveDerivedTables.m"
    "+sixgr/+truth/exportLLSLiveMobilityTables.m"
    "+sixgr/+truth/exportLLSHARQDiagnostics.m"
    "+sixgr/+truth/exportLLSOutputCoverageArtifacts.m"
    "+sixgr/+truth/recoverLLSRunArtifacts.m"
    "+sixgr/+truth/exportSystemLevelCanonicalArtifacts.m"
    "+sixgr/+truth/runWaveformLinkBundle.m"
    "+sixgr/+phy/+refsig/trs.m"
    "+sixgr/+time/canonicalSlotToFrameSlot.m"
    "+sixgr/+util/enrichResultTableContext.m"
    "+sixgr/+lls6g/+runners/runSingle.m"
    "+sixgr/+phy/+frame/TDDCommonConfig.m"
    "+sixgr/+phy/+frame/PRACHOccasionResolver.m"
    "+sixgr/+phy/+ra/runFourStepRA.m"
    "+sixgr/+system/SystemLevelRunner.m"
    "+sixgr/+truth/CoupledTruthRuntime.m"];
root = fileparts(fileparts(mfilename("fullpath")));
for i = 1:numel(paths)
    source = splitlines(string(fileread(fullfile(root, paths(i)))));
    physicalShortcut = contains(source, "log2", "IgnoreCase", true) & ...
        (contains(source, "/ 15") | contains(source, "/15") | ...
         contains(source, "/ 15e3", "IgnoreCase", true) | ...
         contains(source, "/15e3", "IgnoreCase", true));
    physicalShortcut = physicalShortcut | ...
        contains(source, "15 * 2^", "IgnoreCase", true) | ...
        contains(source, "15*2^", "IgnoreCase", true) | ...
        contains(source, "10 * 2^", "IgnoreCase", true) | ...
        contains(source, "10*2^", "IgnoreCase", true) | ...
        contains(source, "1e-3 / 2^", "IgnoreCase", true);
    assert(~any(physicalShortcut), ...
        "Active SCS-to-mu logarithmic shortcut remains in %s: %s", ...
        paths(i), strjoin(strtrim(source(physicalShortcut)), " | "));
end

pdschPaths = [ ...
    "+sixgr/+pdsch/CarrierConfig6GR.m"
    "+sixgr/+pdsch/PDSCHReceiver.m"
    "+sixgr/+pdsch/PDSCHWaveformBuilder.m"
    "+sixgr/+pdsch/runPDSCHStudyLLS.m"];
for i = 1:numel(pdschPaths)
    source = string(fileread(fullfile(root, pdschPaths(i))));
    assert(~contains(source, "15 * 2^", "IgnoreCase", true) && ...
        ~contains(source, "15*2^", "IgnoreCase", true) && ...
        ~contains(source, "10 * 2^", "IgnoreCase", true) && ...
        ~contains(source, "10*2^", "IgnoreCase", true) && ...
        ~contains(source, "1e-3 / 2^", "IgnoreCase", true), ...
        "PDSCH study caller still derives physical timing from mu: %s", ...
        pdschPaths(i));
end

% Production runners must obtain grid and frame dimensions from the same
% canonical facade. These exact shortcut signatures previously allowed
% missing configuration to become 52 RB, 10 slots/frame, or a bandwidth /
% SCS quotient.
runtimePaths = [ ...
    "+sixgr/+system/SystemLevelRunner.m"
    "+sixgr/+truth/CoupledTruthRuntime.m"
    "+sixgr/+truth/runWaveformLinkBundle.m"
    "+sixgr/+truth/exportLLSLiveDerivedTables.m"
    "+sixgr/+truth/exportLLSOutputCoverageArtifacts.m"
    "+sixgr/+truth/exportSystemLevelCanonicalArtifacts.m"
    "+sixgr/+truth/recoverLLSRunArtifacts.m"
    "+sixgr/+lls6g/+runners/runSingle.m"
    "+sixgr/+phy/+refsig/trs.m"
    "+sixgr/+time/canonicalSlotToFrameSlot.m"];
for i = 1:numel(runtimePaths)
    source = string(fileread(fullfile(root, runtimePaths(i))));
    forbidden = [ ...
        "nRB = 52"
        "NumRB"", 52"
        "slots = round(0.01 / slotDuration"
        "SlotsPerFrame"", 10"
        "SlotsPerFrame"", 1"
        "slotsPerFrame = 10"
        "symbolsPerSlot = 14"
        "SymbolsPerSlot = 14"
        "SymbolsPerSlot"", 14"
        "floor(double(bw_Hz) / (12 * scs_Hz)"];
    for token = forbidden.'
        assert(~contains(source, token), ...
            "Production-local frame/grid fallback remains in %s: %s", ...
            runtimePaths(i), token);
    end
end

tddSource = string(fileread(fullfile(root, ...
    "+sixgr/+phy/+frame/TDDCommonConfig.m")));
assert(contains(tddSource, "NumerologyCatalog.resolve") && ...
    contains(tddSource, "AbsoluteTime"), ...
    "TDD common timing must use canonical numerology and exact Tc time.");
assert(~contains(tddSource, "activeSCS / refSCS") && ...
    ~contains(tddSource, "activeSCS / 15") && ...
    ~contains(tddSource, "refSCS / 15"), ...
    "TDD common timing still contains a local SCS-derived time mapping.");

configBuilderSource = string(fileread(fullfile(root, ...
    "+sixgr/+lls6g/buildInternalConfig.m")));
assert(~contains(configBuilderSource, ...
    "round(double(startSymbol))") && ...
    ~contains(configBuilderSource, ...
    "round(double(numSymbols))") && ...
    ~contains(configBuilderSource, ...
    "[round(startValue) round(numValue)]"), ...
    "buildInternalConfig still mutates configured TDRA symbol values.");

ok = true;
end

function localAssertThrows(fn, expectedID)
try
    fn();
catch ME
    assert(string(ME.identifier) == string(expectedID), ...
        "Expected %s, received %s: %s", expectedID, ME.identifier, ME.message);
    return;
end
error("sixgr:test:ExpectedErrorNotThrown", ...
    "Expected error %s was not thrown.", expectedID);
end
