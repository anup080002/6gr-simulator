function ok = testInitialAccessArtifactEvidence()
%TESTINITIALACCESSARTIFACTEVIDENCE Prove runtime-only PRACH CSV binding.

scenarioID = "artifact_prereq_prach";
configHash = repmat('a', 1, 64);
runID = "run_prach_runtime_001";
n = 100;
trialID = compose("%s|trial=%03d", runID, (1:n).');
occasionID = compose("frame=%d|slot=0|symbol=0|frequency=0", (0:n-1).');
preambleTx = mod((0:n-1).', 64);
preambleRx = preambleTx;
detected = true(n, 1);
peak = linspace(0.7, 1.1, n).';
threshold = 0.35 * ones(n, 1);
timing = mod((0:n-1).', 5);
timingError = timing;
frequency = linspace(-20, 20, n).';
falseAlarm = false(n, 1);
missed = false(n, 1);
ambiguous = false(n, 1);

raw = table(trialID, occasionID, preambleTx, preambleRx, detected, peak, ...
    threshold, timing, timingError, true(n,1), frequency, true(n,1), ...
    ambiguous, falseAlarm, missed, true(n,1), ...
    repmat("real_lls_evidence", n, 1), repmat(scenarioID, n, 1), ...
    repmat(string(configHash), n, 1), true(n,1), false(n,1), false(n,1), ...
    'VariableNames', {'RARunId','PRACHOccasionID','PreambleIndexTx', ...
    'PreambleIndexDetected','PreambleDetected','PreambleDetectionMetric', ...
    'PreambleDetectionThreshold','PRACHPropagationTimingEstimate_samples', ...
    'PRACHTimingError_samples','PRACHFrequencyEstimationEnabled', ...
    'PRACHFrequencyEstimate_Hz','PRACHFrequencyEstimateValid', ...
    'PreambleAmbiguityDetected','FalseAlarm','MissedDetection', ...
    'DetectionAttempted','TruthStatus','ScenarioID','ConfigHash', ...
    'FinalizedFlag','FallbackFlag','PlaceholderFlag'});

result = struct("Link", struct("RawTrials", struct("PRACH", raw)));
scfg = struct("scenario_id", scenarioID, "ConfigHash", configHash);
cfg = struct();
cfg.frequency.center_frequency_hz = 3.5e9;
cfg.frequency.bandwidth_hz = 100e6;
cfg.channel.subcarrierSpacing_kHz = 30;
cfg.random_access.enable_frequency_estimation_metric = true;
cfg.run.runTag = runID;
identity = struct("RunID", runID, "ExecutionID", "exec_prach_001");

registry = sixgr.artifact.EvidenceRegistry();
coverage = sixgr.artifact.registerInitialAccessEvidence( ...
    registry, result, scfg, cfg, identity);
assert(height(coverage) == 1 && all(coverage.Registered), ...
    "Only the PRACH runtime table may be registered in the MATLAB path.");
assert(all(coverage.SourceRows == n), ...
    "The adapter must preserve the exact runtime trial count.");

catalog = sixgr.artifact.ContractCatalog.load();
selected = lower(catalog.Domain) == "initial_access" & ...
    catalog.Profile == "base" & ...
    catalog.FileName == "prach_detection_trials.csv";
catalog = catalog(selected, :);
assert(height(catalog) == 1, ...
    "Focused runtime PRACH contract selection must contain only the CSV row.");
root = tempname;
mkdir(root);
cleanup = onCleanup(@() localCleanup(root)); %#ok<NASGU>
generated = sixgr.artifact.ContractArtifactGenerator.generate(root, registry, ...
    "Catalog", catalog, "ExpectedIdentity", struct( ...
    "ScenarioID", scenarioID, "ConfigHash", configHash, "RunID", runID, ...
    "CenterFrequencyHz", 3.5e9, "BandwidthHz", 100e6, ...
    "SubcarrierSpacingHz", 30e3), ...
    "RequireIdentityColumns", true, "RequireRadioIdentityColumns", true);
assert(generated.Ok && generated.CSVCount == 1 && generated.PNGCount == 0, ...
    "Focused runtime PRACH artifact generation must publish only CSV evidence.");
assert(all(generated.Audit.Status == "PASS"), ...
    "Focused PRACH artifact audit must contain only PASS rows.");
[rendererFound, ~] = registry.resolveRenderer( ...
    "initial_access", "base", "prach_preamble_correlation.png");
assert(~rendererFound, ...
    "The retired MATLAB PRACH raster renderer must not be registered.");

bad = raw;
bad.PRACHFrequencyEstimate_Hz(1) = NaN;
bad.PRACHFrequencyEstimateValid(1) = false;
badResult = struct("Link", struct("RawTrials", struct("PRACH", bad)));
badRegistry = sixgr.artifact.EvidenceRegistry();
badCoverage = sixgr.artifact.registerInitialAccessEvidence( ...
    badRegistry, badResult, scfg, cfg, identity);
assert(~any(badCoverage.Registered) && ...
    contains(badCoverage.Reason(1), "MissingEnabledPRACHFrequencyEstimate"), ...
    "YAML-enabled CFO measurement must fail closed when receiver evidence is missing.");

% A receiver miss is itself a measured outcome.  Timing and CFO cannot be
% estimated from an absent preamble and must remain unavailable rather
% than being backfilled with configured or zero values.
missedRuntime = raw;
missedRuntime.PreambleDetected(1) = false;
missedRuntime.MissedDetection(1) = true;
missedRuntime.PreambleIndexDetected(1) = NaN;
missedRuntime.PRACHPropagationTimingEstimate_samples(1) = NaN;
missedRuntime.PRACHTimingError_samples(1) = NaN;
missedRuntime.PRACHFrequencyEstimate_Hz(1) = NaN;
missedRuntime.PRACHFrequencyEstimateValid(1) = false;
missedRegistry = sixgr.artifact.EvidenceRegistry();
missedCoverage = sixgr.artifact.registerInitialAccessEvidence( ...
    missedRegistry, struct("Link", struct("RawTrials", struct( ...
        "PRACH", missedRuntime))), scfg, cfg, identity);
assert(all(missedCoverage.Registered), ...
    "Measured PRACH misses with unavailable timing/CFO must remain publishable truth rows.");
[missedFound, missedTable] = missedRegistry.resolveTable( ...
    "initial_access", "base", "prach_detection_trials.csv");
assert(missedFound && ~missedTable.Detected(1) && ...
    missedTable.MissedDetection(1) && ...
    isnan(missedTable.TimingEstimate_samples(1)) && ...
    isnan(missedTable.FrequencyEstimate_Hz(1)) && ...
    ~missedTable.FrequencyEstimateValid(1), ...
    "PRACH miss rows must retain their physically unavailable receiver estimates.");

% A historical raw-trial schema can omit the PRACH-specific alias when the
% receiver CFO estimator was disabled.  Preserve that unavailable state as
% NaN; do not invent a configured or zero-Hz measurement.
disabled = raw;
disabled.PRACHFrequencyEstimationEnabled(:) = false;
disabled.PRACHFrequencyEstimateValid(:) = false;
disabled.PRACHFrequencyEstimate_Hz = [];
disabledResult = struct("Link", struct("RawTrials", struct("PRACH", disabled)));
disabledRegistry = sixgr.artifact.EvidenceRegistry();
disabledCoverage = sixgr.artifact.registerInitialAccessEvidence( ...
    disabledRegistry, disabledResult, scfg, cfg, identity);
assert(all(disabledCoverage.Registered), ...
    "A missing estimate alias is valid only when runtime PRACH CFO estimation was disabled.");
[disabledFound, disabledTable] = disabledRegistry.resolveTable( ...
    "initial_access", "base", "prach_detection_trials.csv");
assert(disabledFound && all(isnan(disabledTable.FrequencyEstimate_Hz)) && ...
    ~any(disabledTable.FrequencyEstimationEnabled) && ...
    ~any(disabledTable.FrequencyEstimateValid), ...
    "Disabled PRACH CFO evidence must remain explicitly unavailable, never substituted from configuration.");

missingEnabled = raw;
missingEnabled.PRACHFrequencyEstimate_Hz = [];
missingEnabledRegistry = sixgr.artifact.EvidenceRegistry();
missingEnabledCoverage = sixgr.artifact.registerInitialAccessEvidence( ...
    missingEnabledRegistry, struct("Link", struct("RawTrials", struct("PRACH", missingEnabled))), ...
    scfg, cfg, identity);
assert(~any(missingEnabledCoverage.Registered) && ...
    contains(missingEnabledCoverage.Reason(1), "PRACHRawEvidenceMissingColumns"), ...
    "An enabled estimator with no measured estimate column must still fail closed.");

% One actual shared observation can contain both UE targets even when only
% the other UE is the strongest candidate. This is not a false alarm.
shared = raw(1:2,:);
shared.PRACHOccasionID(:) = "frame=1|slot=4|symbol=7|frequency=0";
shared.PreambleIndexTx = [0;1]; shared.PreambleIndexDetected(:) = 1;
shared.DetectedPreambleSet = ["1|0";"1|0"];
shared.DetectedPreambleSetAvailable = true(2,1);
shared.PreambleAmbiguityDetected(:) = true;
shared.FalseAlarm = NaN(2,1);
shared.FalseAlarmClassification = repmat("unavailable_complete_transmitted_occasion_set_not_retained",2,1);
shared.Msg1ScheduledSlot = [14;14];
sharedRegistry = sixgr.artifact.EvidenceRegistry();
sharedCoverage = sixgr.artifact.registerInitialAccessEvidence(sharedRegistry, ...
    struct('Link',struct('RawTrials',struct('PRACH',shared))),scfg,cfg,identity);
assert(all(sharedCoverage.Registered), strjoin(sharedCoverage.Reason,' | '));
[found, sharedTable] = sharedRegistry.resolveTable('initial_access','base','prach_detection_trials.csv');
assert(found && all(isnan(sharedTable.FalseAlarm)) && all(sharedTable.DetectedPreambleSet=="1|0") ...
    && ~any(sharedTable.MissedDetection) && all(sharedTable.Msg1ScheduledSlot==14));
[missed,wrong,scope] = sixgr.report.prachTargetDetectionEvidence(shared);
assert(all(missed==0) && all(wrong==0) && all(scope=="per_target_shared_occasion_not_independent_trials"));
absent = shared(1,:); absent.PreambleIndexTx=2; absent.MissedDetection=true;
[missed,wrong] = sixgr.report.prachTargetDetectionEvidence(absent);
assert(missed==1 && wrong==1,'A genuinely absent target must remain a miss.');
empty = shared(1,:); empty.DetectedPreambleSet=""; empty.PreambleDetected=false;
empty.PreambleIndexDetected=NaN;
[missed,wrong] = sixgr.report.prachTargetDetectionEvidence(empty);
assert(missed==1 && isnan(wrong),'Known empty detection is not a wrong-identity trial.');
for invalidSet = ["1|1","64","-1","1|NaN","1|0.5","1|"]
    bad = shared; bad.DetectedPreambleSet(1)=invalidSet;
    badRegistry = sixgr.artifact.EvidenceRegistry();
    c = sixgr.artifact.registerInitialAccessEvidence(badRegistry, ...
        struct('Link',struct('RawTrials',struct('PRACH',bad))),scfg,cfg,identity);
    assert(~any(c.Registered) && contains(c.Reason,'InvalidPRACHDetectionSet'));
end
bad=shared; bad.FalseAlarm(:)=0;
c=sixgr.artifact.registerInitialAccessEvidence(sixgr.artifact.EvidenceRegistry(), ...
    struct('Link',struct('RawTrials',struct('PRACH',bad))),scfg,cfg,identity);
assert(~any(c.Registered) && contains(c.Reason,'InvalidPRACHFalseAlarm'), ...
    'Unknown false alarms must not be coerced to zero.');
ok = true;
end

function localCleanup(pathValue)
if isfolder(pathValue)
    rmdir(pathValue, "s");
end
end
