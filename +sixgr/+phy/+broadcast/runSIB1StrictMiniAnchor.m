function out = runSIB1StrictMiniAnchor(runFolder, cfg, varargin)
%RUNSIB1STRICTMINIANCHOR Execute and export the AUD-015 strict mini-run.

p = inputParser;
p.addParameter("RunNegativeSuite", true, ...
    @(x) (islogical(x) || isnumeric(x)) && isscalar(x));
p.addParameter("RunId", "sib1_strict_mini_anchor", ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));
p.addParameter("ScenarioName", "sib1_strict_mini_anchor", ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));
p.addParameter("ExecutionID", "", ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));
p.addParameter("ScenarioConfigHash", "", ...
    @(x) ischar(x) || (isstring(x) && isscalar(x)));
p.parse(varargin{:});
runNegativeSuite = logical(p.Results.RunNegativeSuite);
runId = strtrim(string(p.Results.RunId));
scenarioName = strtrim(string(p.Results.ScenarioName));
executionId = strtrim(string(p.Results.ExecutionID));
scenarioConfigHash = lower(strtrim(string(p.Results.ScenarioConfigHash)));
if strlength(runId) == 0 || strlength(scenarioName) == 0
    error("sixgr:phy:broadcast:SIB1RunIdentityRequired", ...
        "Strict SIB1 execution requires non-empty RunId and ScenarioName.");
end

if nargin < 1 || strlength(string(runFolder)) == 0
    runFolder = fullfile(tempdir, "sixgr_sib1_strict_mini_anchor");
end
if nargin < 2 || isempty(cfg)
    cfg = sixgr.config.defaultConfig();
end
cfg.run.strictMode = true;
sib1Enabled = logical(sixgr.util.structGet(cfg, "phy.sib1.enable", false));
if isfield(cfg, "runtime") && isfield(cfg.runtime, "features")
    sixgr.config.assertRuntimeFeatureUse(cfg, "sib1", sib1Enabled, ...
        "runSIB1StrictMiniAnchor");
end
if ~sib1Enabled
    error("sixgr:phy:broadcast:SIB1DisabledByYAML", ...
        "The strict SIB1 mini-anchor cannot run because configuration disabled SIB1.");
end
cfg.phy.sib1.ssbObservationSubframes = double(sixgr.util.structGet(cfg, ...
    "phy.sib1.ssbObservationSubframes", sixgr.util.structGet(cfg, ...
    "initial_access.ssb.observation_subframes", 5)));
cfg.phy.carrier.NCellID = double(sixgr.util.structGet(cfg, "phy.carrier.NCellID", 17));
cfg.phy.carrier.SubcarrierSpacing = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", 30));
cfg.phy.carrier.SubcarrierSpacing_kHz = cfg.phy.carrier.SubcarrierSpacing;
cfg.phy.carrier.NSizeGrid = double(sixgr.util.structGet(cfg, ...
    "phy.carrier.NSizeGrid", 51));
cfg.phy.sib1.coreset0Index = double(sixgr.util.structGet(cfg, "phy.sib1.coreset0Index", 0));
cfg.phy.sib1.searchSpaceZero = double(sixgr.util.structGet(cfg, "phy.sib1.searchSpaceZero", 0));
raRequested = localRandomAccessRequested(cfg);
[runRandomAccess, raSkipReason] = localShouldRunRandomAccess(cfg, raRequested);
if runRandomAccess
    cfg = localMirrorRandomAccessIntoSIB1Prach(cfg);
end

snrDB = double(sixgr.util.structGet(cfg, ...
    "initial_access.validation_snr_db", 35));
seed = double(sixgr.util.structGet(cfg, ...
    "initial_access.validation_seed", ...
    sixgr.util.structGet(cfg, "run.seed", 1501)));
tx = sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg, ...
    "SNRdB", snrDB, "Seed", seed);
rx = sixgr.phy.broadcast.recoverSIB1FromWaveform(tx.Waveform, cfg);
rx = sixgr.phy.broadcast.attachSIB1ValidationComparison(tx, rx);
negatives = repmat(struct(), 0, 1);
if runNegativeSuite
    negatives = localRunNegatives(tx, cfg);
end
artifactIdentity = struct();
if strlength(executionId) > 0
    artifactIdentity = struct("RunID", runId, ...
        "ExecutionID", executionId, ...
        "ScenarioID", scenarioName, ...
        "ConfigHash", scenarioConfigHash);
end
artifacts = sixgr.phy.broadcast.exportSIB1EvidenceArtifacts( ...
    runFolder, tx, rx, "NegativeResults", negatives, ...
    "Identity", artifactIdentity);
ra = struct();
raOk = false;
raArtifacts = struct();
if runRandomAccess && logical(rx.StrictOk)
    ra = sixgr.phy.ra.runFourStepRA(cfg, ...
        "RunFolder", runFolder, ...
        "RunId", runId, ...
        "ScenarioName", scenarioName, ...
        "UEId", 1, ...
        "CellId", double(sixgr.util.structGet(cfg, "phy.carrier.NCellID", 1)), ...
        "AttemptId", 1, ...
        "SIB1Recovery", rx, ...
        "RequireDecodedSIB1", true, ...
        "WriteArtifacts", true);
    raOk = logical(sixgr.util.structGet(ra, "StrictOk", false));
    raArtifacts = sixgr.util.structGet(ra, "Artifacts", struct());
end
lifecycleArtifacts = localExportInitialAccessLifecycle( ...
    runFolder, rx, runRandomAccess, ra, artifactIdentity);
out = struct("Ok", logical(rx.StrictOk) && (~runRandomAccess || raOk), ...
    "RunFolder", string(runFolder), "RunId", runId, ...
    "ScenarioName", scenarioName, "Tx", tx, "Rx", rx, ...
    "ExecutionID", executionId, ...
    "ScenarioConfigHash", scenarioConfigHash, ...
    "RandomAccessRequested", logical(raRequested), ...
    "RandomAccessRunnable", logical(runRandomAccess), ...
    "RandomAccessSkipReason", string(raSkipReason), ...
    "RAOk", logical(raOk), ...
    "NegativeSuiteRequested", runNegativeSuite, ...
    "RandomAccess", ra, "NegativeResults", negatives, "Artifacts", artifacts, ...
    "RAArtifacts", raArtifacts, "LifecycleArtifacts", lifecycleArtifacts);
end

function requested = localRandomAccessRequested(cfg)
requested = false;
if isfield(cfg, "random_access") && isstruct(cfg.random_access)
    raw = sixgr.util.structGet(cfg, "random_access.enabled", false);
    if islogical(raw) || isnumeric(raw)
        requested = ~isempty(raw) && isscalar(raw) && logical(raw);
    elseif ischar(raw) || isstring(raw)
        requested = any(strcmpi(strtrim(string(raw)), ["true", "1", "yes", "enabled"]));
    end
end
end

function [enabled, skipReason] = localShouldRunRandomAccess(cfg, requested)
enabled = false;
skipReason = "";
if ~logical(requested)
    return;
end
try
    sixgr.mac.ra.RAConfig(cfg, "RunId", "sib1_strict_mini_anchor_preflight");
    enabled = true;
catch ME
    switch string(ME.identifier)
        case {"sixgr:mac:ra:MissingRandomAccessConfig", ...
                "sixgr:mac:ra:MissingMandatoryRACHFields", ...
                "sixgr:mac:ra:RestrictedSetUnsupportedStrict"}
            skipReason = "supplemental_sib1_ra_skipped:" + string(ME.message);
        otherwise
            rethrow(ME);
    end
end
end

function cfg = localMirrorRandomAccessIntoSIB1Prach(cfg)
ra = cfg.random_access;
cfg = sixgr.util.structSet(cfg, "phy.prach.configurationIndex", ...
    double(sixgr.util.structGet(ra, "configuration_index", ...
    sixgr.util.structGet(cfg, "phy.prach.configurationIndex", 16))));
cfg = sixgr.util.structSet(cfg, "phy.prach.rootSeqIndex", ...
    double(sixgr.util.structGet(ra, "root_sequence_index", ...
    sixgr.util.structGet(cfg, "phy.prach.rootSeqIndex", 1))));
cfg = sixgr.util.structSet(cfg, "phy.prach.zeroCorrelationZone", ...
    double(sixgr.util.structGet(ra, "zero_correlation_zone", ...
    sixgr.util.structGet(cfg, "phy.prach.zeroCorrelationZone", 8))));
cfg = sixgr.util.structSet(cfg, "phy.prach.nPreambles", ...
    double(sixgr.util.structGet(ra, "preamble_count", ...
    sixgr.util.structGet(cfg, "phy.prach.nPreambles", 64))));
cfg = sixgr.util.structSet(cfg, "phy.prach.preambleFormat", ...
    string(sixgr.util.structGet(ra, "prach_format", ...
    sixgr.util.structGet(cfg, "phy.prach.preambleFormat", "0"))));
cfg = sixgr.util.structSet(cfg, "phy.prach.restrictedSet", ...
    string(sixgr.util.structGet(ra, "restricted_set", ...
    sixgr.util.structGet(cfg, "phy.prach.restrictedSet", "UnrestrictedSet"))));
cfg = sixgr.util.structSet(cfg, "phy.prach.subcarrierSpacing_kHz", ...
    double(sixgr.util.structGet(ra, "subcarrier_spacing_khz", ...
    sixgr.util.structGet(cfg, "phy.prach.subcarrierSpacing_kHz", cfg.phy.carrier.SubcarrierSpacing))));
end

function artifacts = localExportInitialAccessLifecycle(runFolder, rx, runRandomAccess, ra, identity)
layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ControlCSVDir);
rows = localLifecycleRow("SSB_PBCH_MIB_SIB1", true, logical(rx.StrictOk), ...
    "control/csv/sib1_recovery_trials.csv", string(sixgr.util.structGet(rx, "FailureReason", "")));
if runRandomAccess && isstruct(ra) && ~isempty(fieldnames(ra))
    rows(end+1, 1) = localLifecycleRow("RA_MSG1_PRACH", true, logical(sixgr.util.structGet(ra, "PreambleDetected", false)), ...
        "control/csv/msg1_prach_detection.csv", string(sixgr.util.structGet(ra, "FailureReason", ""))); %#ok<AGROW>
    rows(end+1, 1) = localLifecycleRow("RA_MSG2_RAR", true, logical(sixgr.util.structGet(ra, "Msg2RARNTIDetected", false)) && ...
        logical(sixgr.util.structGet(ra, "RARULGrantValid", false)), "control/csv/msg2_rar_trials.csv", ...
        string(sixgr.util.structGet(ra, "FailureReason", ""))); %#ok<AGROW>
    rows(end+1, 1) = localLifecycleRow("RA_MSG3_PUSCH", true, logical(sixgr.util.structGet(ra, "Msg3PUSCHCrcPass", false)), ...
        "control/csv/msg3_pusch_trials.csv", string(sixgr.util.structGet(ra, "FailureReason", ""))); %#ok<AGROW>
    rows(end+1, 1) = localLifecycleRow("RA_MSG4_CONTENTION_RESOLUTION", true, logical(sixgr.util.structGet(ra, "RACompleted", false)), ...
        "control/csv/msg4_contention_resolution.csv", string(sixgr.util.structGet(ra, "FailureReason", ""))); %#ok<AGROW>
    if logical(sixgr.util.structGet(ra, "RequireRRCSetupComplete", false))
        rows(end+1, 1) = localLifecycleRow( ...
            "RRC_SETUP_COMPLETE_SRB1", true, ...
            logical(sixgr.util.structGet(ra, "RRCConnected", false)), ...
            "control/csv/rrc_connection_events.csv", ...
            string(sixgr.util.structGet( ...
            ra, "FailureReason", ""))); %#ok<AGROW>
    end
end
T = struct2table(rows, "AsArray", true);
T.StageOrder = (1:height(T)).';
if isstruct(identity) && isscalar(identity) && ~isempty(fieldnames(identity))
    T = sixgr.runtime.bindInPathArtifactIdentity(T, identity);
end
artifacts = sixgr.phy.broadcast.publishStrictInitialAccessLifecycle(runFolder, T);
end

function row = localLifecycleRow(stage, attempted, completed, sourceArtifact, failureReason)
row = struct("StageOrder", NaN, "StageName", string(stage), "Attempted", logical(attempted), ...
    "Completed", logical(completed), "SourceArtifact", string(sourceArtifact), ...
    "FailureReason", string(failureReason));
end

function negatives = localRunNegatives(tx, cfg)
negatives = repmat(struct(), 0, 1);
wrong = sixgr.phy.broadcast.recoverSIB1FromWaveform( ...
    tx.Waveform, cfg, "ReceiverRNTI", 4660);
wrong.NegativeTrialType = "wrong_si_rnti";
wrong.InjectedFault = "receiver_attempted_wrong_rnti_4660";
wrong.ExpectedFailureStage = "pdcch_decode_failed";
negatives = localAppendNegative(negatives, wrong);

nosig = sixgr.phy.broadcast.recoverSIB1FromWaveform( ...
    tx.Waveform, cfg, "FaultMode", "nosignal");
nosig.NegativeTrialType = "no_signal_coreset0";
nosig.InjectedFault = "zeroed_sib1_slot";
nosig.ExpectedFailureStage = "pdcch_decode_failed";
negatives = localAppendNegative(negatives, nosig);

cpdcch = sixgr.phy.broadcast.recoverSIB1FromWaveform( ...
    tx.Waveform, cfg, "FaultMode", "corruptpdcch");
cpdcch.NegativeTrialType = "corrupted_pdcch";
cpdcch.InjectedFault = "pdcch_and_dmrs_resource_elements_zeroed";
cpdcch.ExpectedFailureStage = "pdcch_decode_failed";
negatives = localAppendNegative(negatives, cpdcch);

cpdsch = sixgr.phy.broadcast.recoverSIB1FromWaveform( ...
    tx.Waveform, cfg, "FaultMode", "corruptpdsch");
cpdsch.NegativeTrialType = "corrupted_pdsch";
cpdsch.InjectedFault = "pdsch_and_dmrs_resource_elements_zeroed";
cpdsch.ExpectedFailureStage = "pdsch_dlsch_crc_failed";
negatives = localAppendNegative(negatives, cpdsch);

casn1 = sixgr.phy.broadcast.recoverSIB1FromWaveform( ...
    tx.Waveform, cfg, "FaultMode", "corruptasn1");
casn1.NegativeTrialType = "corrupted_asn1_payload";
casn1.InjectedFault = "post_dlsch_payload_bit_flip";
casn1.ExpectedFailureStage = "sib1_asn1_decode_or_tree_match_failed";
negatives = localAppendNegative(negatives, casn1);
end

function negatives = localAppendNegative(negatives, item)
if isempty(negatives)
    negatives = item;
    return;
end
allFields = unique([fieldnames(negatives); fieldnames(item)]);
for i = 1:numel(allFields)
    f = allFields{i};
    if ~isfield(negatives, f)
        [negatives.(f)] = deal([]);
    end
    if ~isfield(item, f)
        item.(f) = [];
    end
end
negatives(end+1, 1) = orderfields(item, fieldnames(negatives)); %#ok<AGROW>
end
