function out = runFullSINRSameChainSweep(outputRoot, runTag, configuredSNR, existingRunFolder, baseScenarioPath)
%RUNFULLSINRSAMECHAINSWEEP Run and verify the configured full PHY sweep.
%
% This gate accepts only current-run CoupledTruthRuntime rows.  It does not
% use LUT, logistic, synthetic, fallback, configured-value substitution, or
% a separately launched PHY chain as primary evidence.

if nargin < 1 || strlength(string(outputRoot)) == 0
    outputRoot = fullfile(pwd, "results");
end
if nargin < 2 || strlength(string(runTag)) == 0
    runTag = "phase21_full_same_chain_sinr_sweep";
end
if nargin < 3 || isempty(configuredSNR)
    configuredSNR = [-20 0 20];
end
if nargin < 4
    existingRunFolder = "";
end
if nargin < 5 || strlength(strtrim(string(baseScenarioPath))) == 0
    baseScenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
        "webgui_sinr_sweep_64x4_mu_mimo_full.yaml");
end
configuredSNR = double(configuredSNR(:).');
assert(~isempty(configuredSNR) && all(isfinite(configuredSNR)), ...
    "Configured SNR gate values must be finite.");
assert(isfile(baseScenarioPath), "Base scenario YAML does not exist: %s", baseScenarioPath);
scenarioPath = localRuntimeYAML( ...
    baseScenarioPath, outputRoot, runTag, configuredSNR);
executionOptions = struct();
if strlength(strtrim(string(existingRunFolder))) > 0
    executionOptions.ResumeCompletedRuntimeFinalization = true;
    executionOptions.ExistingRunFolder = char(string(existingRunFolder));
end
out = sixgr.lls6g.runners.runSingle( ...
    scenarioPath, outputRoot, runTag, executionOptions);
localVerify(out, configuredSNR, scenarioPath);
end

function scenarioPath = localRuntimeYAML( ...
        baseScenarioPath, outputRoot, runTag, configuredSNR)
% Materialize one complete YAML authority for this executed gate.  The
% repository master remains unchanged; all SNR aliases in the resolved
% scenario are changed together so MATLAB code never overrides the YAML at
% execution time.
% Start from the authored YAML shape, not ScenarioConfig.toStruct().  The
% latter is a resolved runtime view containing derived compatibility mirrors
% (for example scenario.run) that are deliberately rejected when presented
% as authored input.  Keeping the authored shape also makes this file a
% complete, independently reloadable YAML authority.
cfg = sixgr.lls6g.config.readConfigFile(baseScenarioPath);
% The runtime YAML lives under results, so preserve each inherited master's
% identity with an absolute path.  Leaving the authored relative reference
% unchanged would incorrectly resolve it relative to the runtime directory.
if isfield(cfg, "inherits")
    inherited = string(cfg.inherits);
    for i = 1:numel(inherited)
        candidate = char(inherited(i));
        if ~java.io.File(candidate).isAbsolute()
            candidate = fullfile(fileparts(baseScenarioPath), candidate);
        end
        assert(exist(candidate, "file") == 2, ...
            "Inherited master YAML does not exist: %s", candidate);
        inherited(i) = string(char(java.io.File(candidate).getCanonicalPath()));
    end
    if isscalar(inherited)
        cfg.inherits = char(inherited);
    else
        cfg.inherits = cellstr(inherited(:));
    end
end
cfg = sixgr.util.structSet(cfg, ...
    "canonical_control.run.fixed_link_snr_grid_db", configuredSNR);
cfg = sixgr.util.structSet(cfg, ...
    "canonical_control.run.min_campaign_snr_points", numel(configuredSNR));
cfg = sixgr.util.structSet(cfg, ...
    "canonical_control.run.snr_db", configuredSNR(end));
isSweep = numel(configuredSNR) >= 2;
cfg = sixgr.util.structSet(cfg, ...
    "canonical_control.launch.sweep_enabled", isSweep);
cfg = sixgr.util.structSet(cfg, ...
    "validation.fixed_link_campaign.snr_db", configuredSNR);
cfg = sixgr.util.structSet(cfg, ...
    "sweeps_and_matrix.snr_sweep.values_db", configuredSNR);
cfg = sixgr.util.structSet(cfg, ...
    "sweeps_and_matrix.snr_sweep.enabled", isSweep);
cfg = sixgr.util.structSet(cfg, ...
    "sweeps_and_matrix.fixed_link_calibration.snr_db", configuredSNR);
runtimeRoot = fullfile(char(string(outputRoot)), ".runtime_scenarios");
if ~isfolder(runtimeRoot)
    mkdir(runtimeRoot);
end
token = regexprep(char(string(runTag)), "[^A-Za-z0-9_.-]", "_");
scenarioPath = fullfile(runtimeRoot, [token '_executed.yaml']);
sixgr.lls6g.config.writeYAML(scenarioPath, cfg);
% Re-read and validate the exact on-disk YAML before it becomes runtime
% authority. This catches writer/alias drift before any waveform executes.
executed = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
for path = [ ...
        "canonical_control.run.fixed_link_snr_grid_db", ...
        "validation.fixed_link_campaign.snr_db", ...
        "sweeps_and_matrix.snr_sweep.values_db", ...
        "sweeps_and_matrix.fixed_link_calibration.snr_db"]
    value = double(executed.get(path));
    assert(isequal(value(:).', configuredSNR), ...
        "Runtime YAML SNR authority mismatch at %s.", path);
end
assert(logical(executed.get("sweeps_and_matrix.snr_sweep.enabled")) == isSweep, ...
    "Runtime YAML sweep enable does not match the number of operating points.");
end

function localVerify(out, configuredSNR, executedScenarioPath)
executed = sixgr.lls6g.config.loadScenarioConfig(executedScenarioPath);
dlLayers = double(executed.get("pdsch.layer_count", ...
    executed.get("mimo.n_layers")));
ulLayers = double(executed.get("pusch.layer_count", ...
    executed.get("mimo.n_layers")));
bsElements = double(executed.get( ...
    "antenna_and_array.bs_num_antenna_elements"));
ueElements = double(executed.get( ...
    "antenna_and_array.ue_num_antenna_elements"));
dlMURequired = logical(executed.get("mimo.mu_mimo_enable", false));
ulMURequired = logical(executed.get("mimo.ul_mu_mimo_enable", false));
result = sixgr.util.structGet(out, "Result", struct());
link = sixgr.util.structGet(result, "Link", struct());
raw = sixgr.util.structGet(link, "RawTrials", struct());
standalonePUCCHRequired = logical(executed.get("control_gating.pucch_required", false));
puschUCIRequired = logical(executed.get("control_gating.pusch_uci_required", false));
required = ["DL","UL","PBCH","PRACH","PDCCH","SRS","CSIRS","TRS"];
if standalonePUCCHRequired
    required(end+1) = "PUCCH";
end
for name = required
    T = sixgr.util.structGet(raw, name, table());
    assert(istable(T) && ~isempty(T), ...
        "Same-chain sweep is missing current-run %s rows.", name);
    localAssertTruthRows(T, name);
end

if puschUCIRequired
    verificationCfg = struct("users", struct("n_users", ...
        double(executed.get("canonical_control.topology.num_ues", 1))));
    puschUCI = sixgr.truth.evaluateInPathComponentEvidence( ...
        verificationCfg, raw, "pusch_uci");
    assert(logical(puschUCI.StrictOk), ...
        "YAML-required same-waveform PUSCH UCI failed: %s", ...
        char(string(puschUCI.FailureReason)));
end

dl = raw.DL;
ul = raw.UL;
assert(all(double(dl.Layers) == dlLayers) && ...
    all(double(ul.Layers) == ulLayers), ...
    ["Executed PDSCH/PUSCH layers must equal the exact executed-YAML " ...
     "anchors (DL=%g, UL=%g)."], dlLayers, ulLayers);
assert(all(double(dl.TxWaveformColumns) == bsElements) && ...
    all(double(dl.PhysicalTxAntennas) == bsElements) && ...
    all(double(dl.RxWaveformBranches) == ueElements), ...
    ["PDSCH must propagate the executed-YAML physical array (%g gNB " ...
     "elements to %g UE branches)."], bsElements, ueElements);
assert(all(double(ul.TxWaveformColumns) == ueElements) && ...
    all(double(ul.PhysicalTxAntennas) == ueElements) && ...
    all(double(ul.RxWaveformBranches) == bsElements), ...
    ["PUSCH must propagate the executed-YAML physical array (%g UE " ...
     "elements to %g gNB branches)."], ueElements, bsElements);
assert(all(logical(dl.HybridElementDomainApplied)) && ...
    all(logical(ul.HybridElementDomainApplied)) && ...
    all(strcmpi(string(dl.TxWaveformDomain), "element")) && ...
    all(strcmpi(string(ul.TxWaveformDomain), "element")), ...
    "Both links must physically execute the YAML hybrid element-domain architecture.");

for T = {dl, ul}
    trials = T{1};
    assert(all(logical(trials.DecodeAttempted)) && ...
        all(logical(trials.ChannelEstimateAvailable)) && ...
        all(logical(trials.ResourceExtractionAvailable)) && ...
        all(logical(trials.EqualizationAvailable)) && ...
        all(logical(trials.LLRAvailable)) && ...
        all(logical(trials.LLRFinite)), ...
        "Data trials must traverse channel estimation, extraction, equalization and finite LLR decoding.");
    assert(all(logical(trials.PDCCHGrantBindingRequired)) && ...
        all(logical(trials.PDCCHGrantBindingOk)), ...
        "Every data waveform must be caused by its CRC-valid decoded PDCCH grant.");
    assert(all(isfinite(double(trials.PostEqSINR_dB))) && ...
        all(logical(trials.PostEqSINRReceiverDerived)), ...
        "Post-equalization SINR must be finite receiver-derived evidence.");
end

muDL = dl(logical(dl.MUMIMOEnabled) & double(dl.MUMIMOGroupSize) >= 2, :);
muUL = ul(logical(ul.MUMIMOEnabled) & double(ul.MUMIMOGroupSize) >= 2, :);
if dlMURequired
    assert(height(muDL) >= 2, ...
        "YAML-enabled DL MU-MIMO produced no two-user shared-PRB trial pair.");
    assert(all(string(muDL.InterferenceMode) == ...
        "shared_slot_waveform_superposition") && ...
        all(double(muDL.InterferenceContributorCount) >= 1), ...
        "DL MU-MIMO must be measured from the shared desired-plus-peer waveform, not a scalar proxy.");
end
if ulMURequired
    assert(height(muUL) >= 2, ...
        "YAML-enabled UL MU-MIMO produced no two-user shared-PRB trial pair.");
    assert(all(string(muUL.InterferenceMode) == ...
        "shared_slot_waveform_superposition") && ...
        all(double(muUL.InterferenceContributorCount) >= 1), ...
        "UL MU-MIMO must be measured from the shared desired-plus-peer waveform, not a scalar proxy.");
end

assert(any(double(dl.PTRSRECount) > 0) && any(double(ul.PTRSRECount) > 0), ...
    "YAML-enabled PTRS must occupy real PDSCH and PUSCH REs.");
assert(any(logical(raw.CSIRS.RuntimeEventObserved)) && ...
    any(logical(raw.CSIRS.ResourceExtractionAvailable)) && ...
    any(logical(raw.SRS.SRSRuntimeEvidenceUsable)) && ...
    any(logical(raw.TRS.TRSRuntimeEvidenceUsable)), ...
    "CSI-RS, SRS and TRS must each have a consumed receiver observation.");

runtime = sixgr.util.structGet(raw, "CoupledRuntime", struct());
slotTrace = sixgr.util.structGet(runtime, "SlotTraceTable", table());
assert(istable(slotTrace) && ~isempty(slotTrace), ...
    "The sweep requires the canonical coupled slot trace.");
snrValues = localFirstFiniteColumn(slotTrace, ...
    ["ConfiguredSNR_dB","SNR_dB","OperatingPoint_dB"]);
assert(all(ismember(configuredSNR(:), unique(snrValues))), ...
    "The coupled slot trace does not contain every YAML SNR point.");

% An adaptive point that reaches its YAML-owned post-feedback scheduling
% opportunity must consume real feedback instead of leaving every
% allocation at bootstrap. This is a causal-chain check, not a demand that
% MCS equal a configured maximum.
status = lower(string(dl.MCSValueStatus));
assert(any(~contains(status, "bootstrap")), ...
    "All PDSCH allocations remained at bootstrap; CSI/PUCCH feedback never reached the scheduler.");

fprintf('FULL_SAME_CHAIN_PASS dl=%d ul=%d pbch=%d prach=%d pdcch=%d pucch=%d srs=%d csirs=%d trs=%d snr=[%s]\n', ...
    height(dl), height(ul), height(raw.PBCH), height(raw.PRACH), ...
    height(raw.PDCCH), height(raw.PUCCH), height(raw.SRS), ...
    height(raw.CSIRS), height(raw.TRS), strjoin(string(configuredSNR), ","));
end

function localAssertTruthRows(T, name)
n = height(T);
assert(~any(localLogical(T, "Crash", false(n, 1))) && ...
    ~any(localLogical(T, "Skipped", false(n, 1))) && ...
    ~any(localLogical(T, "ProxyUsed", false(n, 1))) && ...
    ~any(localLogical(T, "FallbackFlag", false(n, 1))) && ...
    ~any(localLogical(T, "PlaceholderFlag", false(n, 1))), ...
    "%s includes crashed, skipped, proxy, fallback, or placeholder rows.", name);
for field = ["ExecutionBackend","ApproximationMode","SourceClassification"]
    if ~ismember(field, string(T.Properties.VariableNames))
        continue;
    end
    value = lower(strtrim(string(T.(char(field)))));
    assert(~any(contains(value, ["proxy","fallback","synthetic","lut","logistic"])), ...
        "%s includes approximation provenance in %s.", name, field);
end
end

function value = localLogical(T, field, defaultValue)
if ~ismember(field, string(T.Properties.VariableNames))
    value = defaultValue;
    return;
end
raw = T.(char(field));
if islogical(raw)
    value = raw;
elseif isnumeric(raw)
    value = isfinite(raw) & raw ~= 0;
else
    value = ismember(lower(strtrim(string(raw))), ...
        ["true","1","yes","pass","ok","success","completed"]);
end
value = logical(value(:));
end

function value = localFirstFiniteColumn(T, candidates)
value = [];
for name = candidates
    if ~ismember(name, string(T.Properties.VariableNames))
        continue;
    end
    raw = T.(char(name));
    if isnumeric(raw)
        value = double(raw(:));
    else
        value = str2double(string(raw(:)));
    end
    value = value(isfinite(value));
    if ~isempty(value)
        return;
    end
end
end
