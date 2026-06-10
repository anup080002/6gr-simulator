function validateScenarioConfig(cfg, varargin)
%VALIDATESCENARIOCONFIG Strict schema and compatibility validation.

ip = inputParser;
ip.addRequired("cfg", @(x)builtin("isstruct", x) && isscalar(x));
ip.addParameter("Kind", "scenario", @(x)ischar(x) || isstring(x));
ip.addParameter("AllowPartial", false, @(x)islogical(x) || (isnumeric(x) && isscalar(x)));
ip.addParameter("Context", "", @(x)ischar(x) || isstring(x));
ip.parse(cfg, varargin{:});
opt = ip.Results;

kind = lower(string(opt.Kind));
schemaDef = sixgr.lls6g.config.schema(kind);
catalog = sixgr.lls6g.config.loadParameterCatalog(kind);
ctx = string(opt.Context);

localRejectUnknownTopLevel(cfg, schemaDef.AllowedTopLevel, ctx);
switch kind
    case "scenario"
        localValidateScenarioSections(cfg, schemaDef, catalog, logical(opt.AllowPartial), ctx);
        if ~logical(opt.AllowPartial)
            localValidateScenarioCompatibility(cfg, catalog, ctx);
        end
    case "matrix"
        localValidateMatrix(cfg, schemaDef, catalog, logical(opt.AllowPartial), ctx);
    otherwise
        error("sixgr:lls6g:config:UnknownValidationKind", ...
            "Unsupported validation kind '%s'.", kind);
end
end

function localRejectUnknownTopLevel(cfg, allowed, ctx)
fields = string(fieldnames(cfg));
bad = setdiff(fields, allowed, "stable");
if ~isempty(bad)
    error("sixgr:lls6g:config:UnknownTopLevelKey", ...
        "Unknown top-level keys in %s: %s", localCtx(ctx), strjoin(cellstr(bad), ", "));
end
end

function localValidateScenarioSections(cfg, schemaDef, catalog, allowPartial, ctx)
allowedSections = schemaDef.AllowedBySection;
sectionNames = fieldnames(allowedSections);
for i = 1:numel(sectionNames)
    sec = sectionNames{i};
    if ~isfield(cfg, sec)
        if ~allowPartial && any(schemaDef.RequiredTopLevel == string(sec))
            error("sixgr:lls6g:config:MissingSection", ...
                "Missing required section '%s' in %s.", sec, localCtx(ctx));
        end
        continue;
    end
    if ~(builtin("isstruct", cfg.(sec)) && isscalar(cfg.(sec)))
        error("sixgr:lls6g:config:BadSectionType", ...
            "Section '%s' in %s must be a scalar struct.", sec, localCtx(ctx));
    end
    localRejectUnknownSectionFields(cfg.(sec), allowedSections.(sec), sec, ctx);
    if ~allowPartial
        reqFields = string.empty(0,1);
        if isfield(schemaDef.RequiredBySection, sec)
            reqFields = schemaDef.RequiredBySection.(sec);
        end
        localRequireFields(cfg.(sec), reqFields, sec, ctx);
    end
    localValidateStructRules(cfg.(sec), catalog.sections.(sec).parameters, sec, ctx, catalog, allowPartial);
end

if isfield(cfg, "scenario") && isfield(cfg.scenario, "sweep") && ~isempty(cfg.scenario.sweep)
    if ~(builtin("isstruct", cfg.scenario.sweep) && isscalar(cfg.scenario.sweep))
        error("sixgr:lls6g:config:BadSweepType", ...
            "scenario.sweep in %s must be a scalar struct.", localCtx(ctx));
    end
    localRejectUnknownSectionFields(cfg.scenario.sweep, schemaDef.NestedAllowed.scenario_sweep, "scenario.sweep", ctx);
    localValidateStructRules(cfg.scenario.sweep, catalog.nested_sections.scenario_sweep.parameters, "scenario.sweep", ctx, catalog, allowPartial);
    overrides = sixgr.util.structGet(cfg, "scenario.sweep.overrides", struct([]));
    if ~isempty(overrides)
        if ~isstruct(overrides)
            error("sixgr:lls6g:config:BadSweepOverrides", ...
                "scenario.sweep.overrides in %s must be a struct array.", localCtx(ctx));
        end
        for i = 1:numel(overrides)
            localRejectUnknownSectionFields(overrides(i), schemaDef.NestedAllowed.scenario_sweep_override, ...
                sprintf("scenario.sweep.overrides(%d)", i), ctx);
            localValidateStructRules(overrides(i), catalog.nested_sections.scenario_sweep_override.parameters, ...
                sprintf("scenario.sweep.overrides(%d)", i), ctx, catalog, allowPartial);
            if isfield(overrides(i), "config")
                sixgr.lls6g.config.validateScenarioConfig(overrides(i).config, ...
                    "Kind", "scenario", "AllowPartial", true, "Context", ctx + "::sweep_override");
            end
        end
    end
end
end

function localValidateMatrix(cfg, schemaDef, catalog, allowPartial, ctx)
sectionNames = fieldnames(schemaDef.AllowedBySection);
for i = 1:numel(sectionNames)
    sec = sectionNames{i};
    if strcmp(sec, "scenarios")
        continue;
    end
    if ~isfield(cfg, sec)
        if ~allowPartial
            error("sixgr:lls6g:config:MissingMatrixSection", ...
                "Missing matrix section '%s' in %s.", sec, localCtx(ctx));
        end
        continue;
    end
    if ~(builtin("isstruct", cfg.(sec)) && isscalar(cfg.(sec)))
        error("sixgr:lls6g:config:BadMatrixSectionType", ...
            "Matrix section '%s' in %s must be a scalar struct.", sec, localCtx(ctx));
    end
    localRejectUnknownSectionFields(cfg.(sec), schemaDef.AllowedBySection.(sec), sec, ctx);
    if ~allowPartial
        localRequireFields(cfg.(sec), schemaDef.RequiredBySection.(sec), sec, ctx);
    end
    localValidateStructRules(cfg.(sec), catalog.sections.(sec).parameters, sec, ctx, catalog, allowPartial);
end
if ~isfield(cfg, "scenarios") || isempty(cfg.scenarios)
    if ~allowPartial
        error("sixgr:lls6g:config:MissingMatrixScenarios", ...
            "Matrix config %s must include a non-empty scenarios list.", localCtx(ctx));
    end
    return;
end
if ~(iscell(cfg.scenarios) || isstring(cfg.scenarios))
    error("sixgr:lls6g:config:BadMatrixScenarioList", ...
        "Matrix scenarios in %s must be a string/cellstr list.", localCtx(ctx));
end
end

function localRejectUnknownSectionFields(secStruct, allowed, secName, ctx)
fields = string(fieldnames(secStruct));
bad = setdiff(fields, string(allowed), "stable");
if ~isempty(bad)
    error("sixgr:lls6g:config:UnknownSectionKey", ...
        "Unknown keys in section '%s' of %s: %s", secName, localCtx(ctx), strjoin(cellstr(bad), ", "));
end
end

function localRequireFields(secStruct, required, secName, ctx)
required = string(required);
for i = 1:numel(required)
    key = required(i);
    if ~isfield(secStruct, key)
        error("sixgr:lls6g:config:MissingField", ...
            "Missing required field '%s.%s' in %s.", secName, key, localCtx(ctx));
    end
    end
end

function localValidateScenarioCompatibility(cfg, catalog, ctx)
runnerProfile = lower(string(cfg.scenario.runner_profile));
if ~ismember(runnerProfile, localCatalogAllowedStrings(catalog.sections.scenario.parameters.runner_profile))
    error("sixgr:lls6g:config:BadRunnerProfile", ...
        "scenario.runner_profile in %s is unsupported.", localCtx(ctx));
end
targetCases = string(cfg.scenario.target_cases);
if isempty(targetCases)
    error("sixgr:lls6g:config:EmptyTargetCases", ...
        "scenario.target_cases in %s must be non-empty.", localCtx(ctx));
end
if runnerProfile == "generic_sweep"
    if ~isfield(cfg.scenario, "sweep") || isempty(cfg.scenario.sweep)
        error("sixgr:lls6g:config:MissingSweepConfig", ...
            "scenario.runner_profile='generic_sweep' in %s requires scenario.sweep.", localCtx(ctx));
    end
    sweepBase = lower(string(sixgr.util.structGet(cfg, "scenario.sweep.base_profile", "")));
    if ~ismember(sweepBase, localCatalogAllowedStrings(catalog.nested_sections.scenario_sweep.parameters.base_profile))
        error("sixgr:lls6g:config:BadSweepBaseProfile", ...
            "scenario.sweep.base_profile in %s must be waveform_bundle or ai_benchmark.", ...
            localCtx(ctx));
    end
end

linkDir = lower(string(cfg.simulation.link_direction));
if ~ismember(linkDir, localCatalogAllowedStrings(catalog.sections.simulation.parameters.link_direction))
    error("sixgr:lls6g:config:BadLinkDirection", ...
        "simulation.link_direction in %s must be dl, ul, or both.", localCtx(ctx));
end

scs = double(cfg.frame.scs_khz);
allowedSCS = double(sixgr.util.structGet(cfg, "frequency.numerology_options_khz", scs));
if ~ismember(scs, allowedSCS)
    error("sixgr:lls6g:config:BadBandSCS", ...
        "frame.scs_khz=%g in %s is not allowed by frequency.numerology_options_khz.", scs, localCtx(ctx));
end
localValidateDerivedTimingConsistency(cfg, scs, ctx);
localValidateRunSlotControls(cfg, scs, ctx);
localValidateSpecialSlotPartition(cfg, ctx);

bw = double(cfg.frequency.bandwidth_hz);
allowedBW = double(sixgr.util.structGet(cfg, "frequency.bandwidth_options_hz", bw));
if ~ismember(bw, allowedBW)
    error("sixgr:lls6g:config:BadBandwidth", ...
        "frequency.bandwidth_hz=%g in %s is not allowed by frequency.bandwidth_options_hz.", bw, localCtx(ctx));
end

function localValidateDerivedTimingConsistency(cfg, scsKHz, ctx)
if ~(isfinite(scsKHz) && scsKHz > 0)
    return;
end
mu = log2(scsKHz / 15);
if ~isfinite(mu)
    return;
end
mu = round(mu);
slotDurationMs = 1 / 2^double(mu);
slotsPerFrame = 10 * 2^double(mu);

configuredMu = double(localOptionalStructValue(cfg, "global_radio_scope.numerology_mu", NaN));
if isfinite(configuredMu) && configuredMu ~= mu
    error("sixgr:lls6g:config:NumerologyTimingMismatch", ...
        "global_radio_scope.numerology_mu=%g in %s conflicts with frame.scs_khz=%g (expected mu=%g).", ...
        configuredMu, localCtx(ctx), scsKHz, mu);
end

configuredSlotDuration = double(localOptionalStructValue(cfg, "frame_timing.slot_duration_ms", NaN));
if isfinite(configuredSlotDuration) && abs(configuredSlotDuration - slotDurationMs) > 1e-12
    error("sixgr:lls6g:config:NumerologyTimingMismatch", ...
        "frame_timing.slot_duration_ms=%g in %s conflicts with frame.scs_khz=%g (expected %.12g ms).", ...
        configuredSlotDuration, localCtx(ctx), scsKHz, slotDurationMs);
end

configuredSlotsPerFrame = double(localOptionalStructValue(cfg, "frame_timing.slots_per_frame", NaN));
if isfinite(configuredSlotsPerFrame) && configuredSlotsPerFrame ~= slotsPerFrame
    error("sixgr:lls6g:config:NumerologyTimingMismatch", ...
        "frame_timing.slots_per_frame=%g in %s conflicts with frame.scs_khz=%g (expected %g).", ...
        configuredSlotsPerFrame, localCtx(ctx), scsKHz, slotsPerFrame);
end
end

function localValidateRunSlotControls(cfg, scsKHz, ctx)
slotsPerFrame = NaN;
if isfinite(scsKHz) && scsKHz > 0
    slotsPerFrame = 10 * 2^round(log2(scsKHz / 15));
end
totalFrames = localOptionalFiniteScalarOrNaN(cfg, "run_control.total_frames");
warmupFrames = localOptionalFiniteScalarOrNaN(cfg, "run_control.warmup_frames");
measurementFrames = localOptionalFiniteScalarOrNaN(cfg, "run_control.measurement_frames");
totalSlots = localOptionalFiniteScalarOrNaN(cfg, "run_control.total_slots");
warmupSlots = localOptionalFiniteScalarOrNaN(cfg, "run_control.warmup_slots");
measurementSlots = localOptionalFiniteScalarOrNaN(cfg, "run_control.measurement_slots");
if isfinite(totalFrames) && abs(totalFrames - round(totalFrames)) > eps(max(abs(totalFrames), 1))
    error("sixgr:lls6g:config:BadRunSlotControl", ...
        "run_control.total_frames in %s must be an integer frame count.", localCtx(ctx));
end
if isfinite(warmupFrames) && abs(warmupFrames - round(warmupFrames)) > eps(max(abs(warmupFrames), 1))
    error("sixgr:lls6g:config:BadRunSlotControl", ...
        "run_control.warmup_frames in %s must be an integer frame count.", localCtx(ctx));
end
if isfinite(measurementFrames) && abs(measurementFrames - round(measurementFrames)) > eps(max(abs(measurementFrames), 1))
    error("sixgr:lls6g:config:BadRunSlotControl", ...
        "run_control.measurement_frames in %s must be an integer frame count.", localCtx(ctx));
end
if isfinite(totalSlots) && abs(totalSlots - round(totalSlots)) > eps(max(abs(totalSlots), 1))
    error("sixgr:lls6g:config:BadRunSlotControl", ...
        "run_control.total_slots in %s must be an integer slot count.", localCtx(ctx));
end
if isfinite(warmupSlots) && abs(warmupSlots - round(warmupSlots)) > eps(max(abs(warmupSlots), 1))
    error("sixgr:lls6g:config:BadRunSlotControl", ...
        "run_control.warmup_slots in %s must be an integer slot count.", localCtx(ctx));
end
if isfinite(measurementSlots) && abs(measurementSlots - round(measurementSlots)) > eps(max(abs(measurementSlots), 1))
    error("sixgr:lls6g:config:BadRunSlotControl", ...
        "run_control.measurement_slots in %s must be an integer slot count.", localCtx(ctx));
end
if isfinite(totalFrames) && totalFrames < 1
    error("sixgr:lls6g:config:BadRunSlotControl", ...
        "run_control.total_frames in %s must be at least 1.", localCtx(ctx));
end
if isfinite(totalFrames) && isfinite(warmupFrames) && round(warmupFrames) > round(totalFrames)
    error("sixgr:lls6g:config:BadRunSlotControl", ...
        "run_control.warmup_frames cannot exceed run_control.total_frames in %s.", ...
        localCtx(ctx));
end
if isfinite(totalFrames) && isfinite(warmupFrames) && isfinite(measurementFrames) && ...
        round(warmupFrames) + round(measurementFrames) > round(totalFrames)
    error("sixgr:lls6g:config:BadRunSlotControl", ...
        "run_control.warmup_frames + run_control.measurement_frames cannot exceed run_control.total_frames in %s.", ...
        localCtx(ctx));
end
if isfinite(totalSlots) && isfinite(warmupSlots) && round(warmupSlots) > round(totalSlots)
    error("sixgr:lls6g:config:BadRunSlotControl", ...
        "run_control.warmup_slots cannot exceed run_control.total_slots in %s.", ...
        localCtx(ctx));
end
if isfinite(totalSlots) && isfinite(warmupSlots) && isfinite(measurementSlots) && ...
        round(warmupSlots) + round(measurementSlots) > round(totalSlots)
    error("sixgr:lls6g:config:BadRunSlotControl", ...
        "run_control.warmup_slots + run_control.measurement_slots cannot exceed run_control.total_slots in %s.", ...
        localCtx(ctx));
end
if isfinite(totalFrames) && isfinite(totalSlots) && isfinite(slotsPerFrame) && ...
        round(totalSlots) ~= round(totalFrames) * round(slotsPerFrame)
    error("sixgr:lls6g:config:BadRunSlotControl", ...
        "run_control.total_frames=%g in %s conflicts with total_slots=%g for frame.scs_khz=%g (expected total_slots=%g).", ...
        totalFrames, localCtx(ctx), totalSlots, scsKHz, round(totalFrames) * round(slotsPerFrame));
end
if isfinite(warmupFrames) && isfinite(warmupSlots) && isfinite(slotsPerFrame) && ...
        round(warmupSlots) ~= round(warmupFrames) * round(slotsPerFrame)
    error("sixgr:lls6g:config:BadRunSlotControl", ...
        "run_control.warmup_frames=%g in %s conflicts with warmup_slots=%g for frame.scs_khz=%g (expected warmup_slots=%g).", ...
        warmupFrames, localCtx(ctx), warmupSlots, scsKHz, round(warmupFrames) * round(slotsPerFrame));
end
if isfinite(measurementFrames) && isfinite(measurementSlots) && isfinite(slotsPerFrame) && ...
        round(measurementSlots) ~= round(measurementFrames) * round(slotsPerFrame)
    error("sixgr:lls6g:config:BadRunSlotControl", ...
        "run_control.measurement_frames=%g in %s conflicts with measurement_slots=%g for frame.scs_khz=%g (expected measurement_slots=%g).", ...
        measurementFrames, localCtx(ctx), measurementSlots, scsKHz, round(measurementFrames) * round(slotsPerFrame));
end
if ~(isfinite(totalSlots) && isfinite(scsKHz))
    return;
end
slotDurationMs = 1 / 2^round(log2(scsKHz / 15));
configuredTotalMs = localOptionalFiniteScalarOrNaN(cfg, "run_control.total_time_ms");
if isfinite(configuredTotalMs) && abs(configuredTotalMs - totalSlots * slotDurationMs) > 1e-9
    error("sixgr:lls6g:config:BadRunSlotControl", ...
        "run_control.total_time_ms=%g in %s conflicts with total_slots=%g and frame.scs_khz=%g (expected %.12g ms).", ...
        configuredTotalMs, localCtx(ctx), totalSlots, scsKHz, totalSlots * slotDurationMs);
end
end

function localValidateSpecialSlotPartition(cfg, ctx)
duplex = upper(string(localOptionalStructValue(cfg, "global_radio_scope.duplex_mode", ...
    localOptionalStructValue(cfg, "frequency.duplex_mode", "TDD"))));
if duplex ~= "TDD"
    return;
end

tddPattern = string(localOptionalStructValue(cfg, "frame_timing.tdd_pattern", ...
    localOptionalStructValue(cfg, "frame.tdd_pattern", "DDDSU")));
if ~contains(upper(tddPattern), "S")
    return;
end

try
    sixgr.util.resolveTDDSlotPartition(cfg, 1);
catch ME
    error("sixgr:lls6g:config:BadSpecialSlotPartition", ...
        "Special-slot symbol partition in %s is invalid: %s", localCtx(ctx), string(ME.message));
end
end

minDuration_s = double(cfg.simulation.min_duration_s);
if ~(isfinite(minDuration_s) && minDuration_s > 0)
    error("sixgr:lls6g:config:BadMinDuration", ...
        "simulation.min_duration_s in %s must be a positive scalar.", localCtx(ctx));
end

snrSweepOffsets = double(cfg.simulation.snr_sweep_offsets_db);
if isempty(snrSweepOffsets) || ~isvector(snrSweepOffsets) || any(~isfinite(snrSweepOffsets))
    error("sixgr:lls6g:config:BadSNRSweepOffsets", ...
        "simulation.snr_sweep_offsets_db in %s must be a finite numeric vector.", localCtx(ctx));
end

ulWf = upper(string(cfg.waveform.ul_waveform));
if ulWf == "DFT-S-OFDM" && ~logical(cfg.waveform.transform_precoding_enabled)
    error("sixgr:lls6g:config:BadDFTSOFDM", ...
        "UL DFT-s-OFDM in %s requires waveform.transform_precoding_enabled=true.", localCtx(ctx));
end

if upper(string(cfg.coding.data_code_type)) == "POLAR"
    error("sixgr:lls6g:config:BadDataCoding", ...
        "coding.data_code_type in %s cannot be Polar for data channels.", localCtx(ctx));
end
if upper(string(cfg.coding.control_code_type)) ~= "POLAR"
    error("sixgr:lls6g:config:BadControlCoding", ...
        "coding.control_code_type in %s must be Polar for control-channel scenarios.", localCtx(ctx));
end

aiEnabled = logical(cfg.ai_ml.enabled);
aiMode = lower(string(cfg.ai_ml.mode));
aiUseCase = lower(string(cfg.ai_ml.use_case));
modelPath = string(cfg.ai_ml.model_path);
if aiEnabled && strlength(modelPath) == 0
    error("sixgr:lls6g:config:MissingAIModelPath", ...
        "ai_ml.model_path is required in %s when ai_ml.enabled=true.", localCtx(ctx));
end
if aiEnabled && ~(aiMode == "offline_training" || aiMode == "online_inference" || aiMode == "disabled")
    error("sixgr:lls6g:config:BadAIMode", ...
        "ai_ml.mode in %s must be offline_training, online_inference, or disabled.", localCtx(ctx));
end
if aiEnabled && aiMode == "disabled"
    error("sixgr:lls6g:config:EnabledAIDisabledMode", ...
        "ai_ml.enabled=true in %s cannot use ai_ml.mode='disabled'.", localCtx(ctx));
end
if aiEnabled && strlength(string(cfg.ai_ml.model_id)) == 0
    error("sixgr:lls6g:config:MissingAIModelID", ...
        "ai_ml.model_id is required in %s when ai_ml.enabled=true.", localCtx(ctx));
end
if aiEnabled && strlength(string(cfg.ai_ml.model_version)) == 0
    error("sixgr:lls6g:config:MissingAIModelVersion", ...
        "ai_ml.model_version is required in %s when ai_ml.enabled=true.", localCtx(ctx));
end
if aiEnabled && strlength(string(cfg.ai_ml.descriptor_type)) == 0
    error("sixgr:lls6g:config:MissingAIDescriptorType", ...
        "ai_ml.descriptor_type is required in %s when ai_ml.enabled=true.", localCtx(ctx));
end
if ~ismember(aiUseCase, localCatalogAllowedStrings(catalog.sections.ai_ml.parameters.use_case))
    error("sixgr:lls6g:config:BadAIUseCase", ...
        "ai_ml.use_case in %s is unsupported.", localCtx(ctx));
end

benchmarkObs = double(cfg.ai_ml.benchmark_observations);
if ~(isfinite(benchmarkObs) && benchmarkObs >= 1 && abs(benchmarkObs - round(benchmarkObs)) < eps)
    error("sixgr:lls6g:config:BadAIBenchmarkObservations", ...
        "ai_ml.benchmark_observations in %s must be a positive integer.", localCtx(ctx));
end

nLayers = double(cfg.mimo.n_layers);
dlLayers = double(localOptionalStructValue(cfg, "mimo.max_dl_layers", nLayers));
ulLayers = double(localOptionalStructValue(cfg, "mimo.max_ul_layers", nLayers));
nTx = double(cfg.mimo.n_tx_ant);
nRx = double(cfg.mimo.n_rx_ant);
beamCount = double(cfg.mimo.beam_count);
panelCount = double(cfg.mimo.panel_count);
usersEnabled = logical(localOptionalStructValue(cfg, "users.enabled", false));
nUsers = double(localOptionalStructValue(cfg, "users.n_users", 1));
seedStride = double(localOptionalStructValue(cfg, "users.seed_stride", 1));
rntiStart = double(localOptionalStructValue(cfg, "users.rnti_start", 1));
userExec = lower(string(localOptionalStructValue(cfg, "users.execution_model", "independent_link_sweep")));
beamStrategy = lower(string(localOptionalStructValue(cfg, "users.beam_selection_strategy", "")));
maxMimo = double(sixgr.util.structGet(cfg, "frequency.max_mimo_size", max([nTx nRx])));
if nLayers > min([nTx nRx maxMimo])
    error("sixgr:lls6g:config:BadRank", ...
        "mimo.n_layers=%g in %s exceeds available antennas/ports.", nLayers, localCtx(ctx));
end
if ~(isfinite(beamCount) && beamCount >= 1 && abs(beamCount - round(beamCount)) < eps)
    error("sixgr:lls6g:config:BadBeamCount", ...
        "mimo.beam_count in %s must be a positive integer.", localCtx(ctx));
end
if ~(isfinite(panelCount) && panelCount >= 1 && abs(panelCount - round(panelCount)) < eps)
    error("sixgr:lls6g:config:BadPanelCount", ...
        "mimo.panel_count in %s must be a positive integer.", localCtx(ctx));
end
if logical(cfg.mimo.multi_panel_ready) && panelCount < 2
    error("sixgr:lls6g:config:BadMultiPanelCount", ...
        "mimo.multi_panel_ready in %s requires mimo.panel_count >= 2.", localCtx(ctx));
end
if ~(isfinite(nUsers) && nUsers >= 1 && abs(nUsers - round(nUsers)) < eps)
    error("sixgr:lls6g:config:BadUserCount", ...
        "users.n_users in %s must be a positive integer.", localCtx(ctx));
end
if ~(isfinite(seedStride) && seedStride >= 1 && abs(seedStride - round(seedStride)) < eps)
    error("sixgr:lls6g:config:BadUserSeedStride", ...
        "users.seed_stride in %s must be a positive integer.", localCtx(ctx));
end
if ~(isfinite(rntiStart) && rntiStart >= 1 && abs(rntiStart - round(rntiStart)) < eps)
    error("sixgr:lls6g:config:BadUserRNTIStart", ...
        "users.rnti_start in %s must be a positive integer.", localCtx(ctx));
end
if nUsers > 1 && ~usersEnabled
    error("sixgr:lls6g:config:UsersDisabledMismatch", ...
        "users.enabled in %s must be true when users.n_users > 1.", localCtx(ctx));
end
if usersEnabled && ~ismember(runnerProfile, ["waveform_bundle","system_level_lls"])
    error("sixgr:lls6g:config:UsersRequireWaveformBundle", ...
        "users.enabled in %s is only supported with scenario.runner_profile='waveform_bundle' or 'system_level_lls'.", localCtx(ctx));
end
if usersEnabled && ~ismember(userExec, localCatalogAllowedStrings(catalog.sections.users.parameters.execution_model))
    error("sixgr:lls6g:config:BadUserExecutionModel", ...
        "users.execution_model in %s is unsupported.", localCtx(ctx));
end
if usersEnabled && userExec == "slot_coupled_truth" && linkDir ~= "both"
    error("sixgr:lls6g:config:CoupledTruthRequiresBidirectional", ...
        "users.execution_model='slot_coupled_truth' in %s requires simulation.link_direction='both'.", localCtx(ctx));
end
if usersEnabled && userExec == "independent_link_sweep" && localRequiresSlotCoupledTruth(cfg)
    error("sixgr:lls6g:config:IndependentSweepForbiddenForTruth", ...
        "users.execution_model='independent_link_sweep' in %s is forbidden for strict/no-proxy/truth-tagged multi-user runs; use users.execution_model='slot_coupled_truth' so scheduler, HARQ, mobility, DL, and UL publish from one canonical SlotTrace.", localCtx(ctx));
end
if usersEnabled && ~ismember(beamStrategy, localCatalogAllowedStrings(catalog.sections.users.parameters.beam_selection_strategy))
    error("sixgr:lls6g:config:BadBeamSelectionStrategy", ...
        "users.beam_selection_strategy in %s is unsupported.", localCtx(ctx));
end
if usersEnabled && nTx <= 1
    error("sixgr:lls6g:config:UsersRequireMultiAntennaTx", ...
        "users.enabled in %s requires mimo.n_tx_ant > 1 for beamformed link sweeps.", localCtx(ctx));
end
if usersEnabled && string(cfg.mimo.precoder_type) == "none"
    error("sixgr:lls6g:config:UsersRequirePrecoding", ...
        "users.enabled in %s requires mimo.precoder_type to be a beamforming-capable mode.", localCtx(ctx));
end
if usersEnabled && linkDir == "dl" && ~logical(cfg.reference_signals.csi_rs_enabled) && ~logical(cfg.reference_signals.srs_enabled)
    error("sixgr:lls6g:config:UsersRequireBeamReferenceSignals", ...
        "Beamformed multi-user DL sweeps in %s require CSI-RS or SRS enabled.", localCtx(ctx));
end
if localRequiresFullCarrierReferenceReplay(cfg, linkDir)
    useGrantLocalGrid = logical(localOptionalStructValue(cfg, "system.waveform.useGrantLocalGrid", false));
    replayGridMode = lower(strtrim(string(localOptionalStructValue(cfg, "system.waveform.replayGridMode", "full_carrier"))));
    if useGrantLocalGrid || replayGridMode == "grant_allocation"
        error("sixgr:lls6g:config:GrantLocalGridCSIRSIncompatible", ...
            "system.waveform.useGrantLocalGrid/replayGridMode='grant_allocation' in %s is incompatible with strict DL CSI-RS truth replay. Use full_carrier replay so CSI-RS, PDSCH, and measured CQI/PMI share the same carrier grid.", ...
            localCtx(ctx));
    end
end

pdschDmrsPorts = double(cfg.reference_signals.pdsch_dmrs_ports);
puschDmrsPorts = double(cfg.reference_signals.pusch_dmrs_ports);
if dlLayers > max(pdschDmrsPorts, 1) && ismember(linkDir, ["dl","both"])
    error("sixgr:lls6g:config:BadPDSCHDMRSPorts", ...
        "DL layers=%g in %s exceeds reference_signals.pdsch_dmrs_ports=%g.", ...
        dlLayers, localCtx(ctx), pdschDmrsPorts);
end
if ulLayers > max(puschDmrsPorts, 1) && ismember(linkDir, ["ul","both"])
    error("sixgr:lls6g:config:BadPUSCHDMRSPorts", ...
        "UL layers=%g in %s exceeds reference_signals.pusch_dmrs_ports=%g.", ...
        ulLayers, localCtx(ctx), puschDmrsPorts);
end

pdcchPayloadBits = double(cfg.control.pdcch_payload_bits);
if ~(isfinite(pdcchPayloadBits) && pdcchPayloadBits >= 1 && abs(pdcchPayloadBits - round(pdcchPayloadBits)) < eps)
    error("sixgr:lls6g:config:BadPDCCHPayloadBits", ...
        "control.pdcch_payload_bits in %s must be a positive integer.", localCtx(ctx));
end

blindDecodeListLength = double(cfg.control.blind_decode_list_length);
maxAgg = max(double(cfg.control.aggregation_levels));
if ~(isfinite(blindDecodeListLength) && blindDecodeListLength >= maxAgg && ...
        abs(blindDecodeListLength - round(blindDecodeListLength)) < eps)
    error("sixgr:lls6g:config:BadBlindDecodeListLength", ...
        "control.blind_decode_list_length in %s must be an integer >= max aggregation level.", localCtx(ctx));
end

minDetectionTrials = double(cfg.random_access.min_detection_trials);
if ~(isfinite(minDetectionTrials) && minDetectionTrials >= 1 && ...
        abs(minDetectionTrials - round(minDetectionTrials)) < eps)
    error("sixgr:lls6g:config:BadPrachMinTrials", ...
        "random_access.min_detection_trials in %s must be a positive integer.", localCtx(ctx));
end
localValidateRandomAccessCompatibility(cfg, ctx);

shadowFadingStd_dB = double(cfg.channels.shadow_fading_std_db);
if ~(isfinite(shadowFadingStd_dB) && shadowFadingStd_dB >= 0)
    error("sixgr:lls6g:config:BadShadowFadingStd", ...
        "channels.shadow_fading_std_db in %s must be a non-negative scalar.", localCtx(ctx));
end

pathlossModel = lower(string(cfg.channels.pathloss_model));
if ~ismember(pathlossModel, localCatalogAllowedStrings(catalog.sections.channels.parameters.pathloss_model))
    error("sixgr:lls6g:config:BadPathlossModel", ...
        "channels.pathloss_model in %s must be nrPathLoss, freeSpace, or none.", localCtx(ctx));
end
if isfield(cfg.channels, "compliance_mode")
    complianceMode = lower(string(cfg.channels.compliance_mode));
    if ~ismember(complianceMode, ["strict_38901", "approximate_38901_plus", "legacy_fallback"])
        error("sixgr:lls6g:config:BadChannelComplianceMode", ...
            "channels.compliance_mode in %s must be strict_38901, approximate_38901_plus, or legacy_fallback.", ...
            localCtx(ctx));
    end
end

dmrsConfigType = double(cfg.reference_signals.pdsch_dmrs_config_type);
dmrsTypeAPos = double(cfg.reference_signals.pdsch_dmrs_type_a_position);
dmrsCDMGroups = double(cfg.reference_signals.pdsch_dmrs_num_cdm_groups_without_data);
if ~ismember(dmrsConfigType, localCatalogAllowedNumeric(catalog.sections.reference_signals.parameters.pdsch_dmrs_config_type))
    error("sixgr:lls6g:config:BadDMRSConfigType", ...
        "reference_signals.pdsch_dmrs_config_type in %s must be 1 or 2.", localCtx(ctx));
end
if ~ismember(dmrsTypeAPos, localCatalogAllowedNumeric(catalog.sections.reference_signals.parameters.pdsch_dmrs_type_a_position))
    error("sixgr:lls6g:config:BadDMRSTypeAPosition", ...
        "reference_signals.pdsch_dmrs_type_a_position in %s must be 2 or 3.", localCtx(ctx));
end
if ~ismember(dmrsCDMGroups, localCatalogAllowedNumeric(catalog.sections.reference_signals.parameters.pdsch_dmrs_num_cdm_groups_without_data))
    error("sixgr:lls6g:config:BadDMRSCDMGroups", ...
        "reference_signals.pdsch_dmrs_num_cdm_groups_without_data in %s must be 1, 2, or 3.", ...
        localCtx(ctx));
end

aiEnergyScale = double(cfg.energy_efficiency.ai_compute_energy_per_flop_score);
if ~(isfinite(aiEnergyScale) && aiEnergyScale >= 0)
    error("sixgr:lls6g:config:BadAIEnergyScale", ...
        "energy_efficiency.ai_compute_energy_per_flop_score in %s must be a non-negative scalar.", ...
        localCtx(ctx));
end

profile = upper(string(cfg.channels.profile));
modelType = upper(string(cfg.channels.model_type));
if startsWith(profile, "TDL") && modelType ~= "TDL"
    error("sixgr:lls6g:config:BadChannelProfile", ...
        "channels.profile=%s in %s requires channels.model_type=TDL.", profile, localCtx(ctx));
end
if startsWith(profile, "CDL") && modelType ~= "CDL"
    error("sixgr:lls6g:config:BadChannelProfile", ...
        "channels.profile=%s in %s requires channels.model_type=CDL.", profile, localCtx(ctx));
end
if modelType == "TDL" && ~startsWith(profile, "TDL-")
    error("sixgr:lls6g:config:BadTDLProfile", ...
        "channels.model_type=TDL in %s requires a concrete TDL-* profile.", localCtx(ctx));
end
if modelType == "CDL" && ~startsWith(profile, "CDL-")
    error("sixgr:lls6g:config:BadCDLProfile", ...
        "channels.model_type=CDL in %s requires a concrete CDL-* profile.", localCtx(ctx));
end

studyStatus = localScenarioStudyStatus(cfg);
ulLayerCount = max(double(localOptionalStructValue(cfg, "pusch.layer_count", 1)), ...
    double(localOptionalStructValue(cfg, "mimo.max_ul_layers", cfg.mimo.n_layers)));
if ulWf == "DFT-S-OFDM" && ulLayerCount > 1
    if ~logical(localOptionalStructValue(cfg, "waveform.multi_layer_dfts_ofdm_candidate_enabled", false))
        error("sixgr:lls6g:config:MultiLayerDFTSOFDMCandidateRequired", ...
            "UL DFT-s-OFDM with layer_count > 1 in %s requires waveform.multi_layer_dfts_ofdm_candidate_enabled=true.", ...
            localCtx(ctx));
    end
    if ~localIsCandidateStudy(studyStatus)
        error("sixgr:lls6g:config:MultiLayerDFTSOFDMStudyTagRequired", ...
            "UL DFT-s-OFDM with layer_count > 1 in %s must be tagged as a candidate study.", ...
            localCtx(ctx));
    end
end

pdcchMod = localConfiguredPDCCHModulation(cfg);
if pdcchMod ~= "QPSK" && ~logical(localOptionalStructValue(cfg, "pdcch.non_qpsk_candidate_enabled", false))
    error("sixgr:lls6g:config:NonQPSKPDCCHCandidateRequired", ...
        "pdcch.modulation=%s in %s requires pdcch.non_qpsk_candidate_enabled=true.", ...
        pdcchMod, localCtx(ctx));
end

maxModOrder = localMaxConfiguredModulationOrder(cfg);
if maxModOrder >= 10
    if ~logical(localOptionalStructValue(cfg, "modulation_and_mapping.high_order_modulation_stress_enabled", false))
        error("sixgr:lls6g:config:HighOrderModulationStressRequired", ...
            "Modulation order >= 1024QAM in %s requires modulation_and_mapping.high_order_modulation_stress_enabled=true.", ...
            localCtx(ctx));
    end
    if localIsUnsetPolicy(localOptionalStructValue(cfg, "output_control.impairment_visibility", "none"))
        error("sixgr:lls6g:config:HighOrderModulationImpairmentVisibilityRequired", ...
            "Modulation order >= 1024QAM in %s requires output_control.impairment_visibility to be configured.", ...
            localCtx(ctx));
    end
end

if maxModOrder >= 12
    if ~logical(localOptionalStructValue(cfg, "modulation_and_mapping.qam4096_candidate_enabled", false))
        error("sixgr:lls6g:config:QAM4096CandidateRequired", ...
            "4096QAM in %s requires modulation_and_mapping.qam4096_candidate_enabled=true.", ...
            localCtx(ctx));
    end
    if ~localHasVisibleHardwareImpairment(cfg)
        error("sixgr:lls6g:config:QAM4096HardwareImpairmentRequired", ...
            "4096QAM in %s requires an explicit hardware impairment model.", ...
            localCtx(ctx));
    end
    if ~localHasHighSNRStressSweep(cfg, 35)
        error("sixgr:lls6g:config:QAM4096HighSNRSweepRequired", ...
            "4096QAM in %s requires a high-SNR stress sweep reaching at least 35 dB.", ...
            localCtx(ctx));
    end
end

if localRequiresStrictMCSConsistency(cfg)
    localValidateDirectionModulationMCSConsistency(cfg, "DL", ctx);
    localValidateDirectionModulationMCSConsistency(cfg, "UL", ctx);
end

jsccEnabled = logical(localOptionalStructValue(cfg, "csi_acquisition_and_reporting.jscc_mode", false)) || ...
    lower(string(localOptionalStructValue(cfg, "ai_ml.csi_feedback_mode", "none"))) == "jscc";
jscmEnabled = logical(localOptionalStructValue(cfg, "csi_acquisition_and_reporting.jscm_mode", false)) || ...
    lower(string(localOptionalStructValue(cfg, "ai_ml.csi_feedback_mode", "none"))) == "jscm";
if jsccEnabled || jscmEnabled
    crcAttached = logical(localOptionalStructValue(cfg, "csi_acquisition_and_reporting.crc_attached_mode", false));
    crcFree = logical(localOptionalStructValue(cfg, "csi_acquisition_and_reporting.crc_free_mode", false));
    if crcAttached == crcFree
        error("sixgr:lls6g:config:JSCCJSCMCRCConfigRequired", ...
            "JSCC/JSCM in %s requires an explicit CRC mode with exactly one of crc_attached_mode or crc_free_mode enabled.", ...
            localCtx(ctx));
    end
    if localIsUnsetPolicy(localOptionalStructValue(cfg, "csi_acquisition_and_reporting.multiplexing_with_uci_policy", ""))
        error("sixgr:lls6g:config:JSCCJSCMMultiplexingConfigRequired", ...
            "JSCC/JSCM in %s requires csi_acquisition_and_reporting.multiplexing_with_uci_policy.", ...
            localCtx(ctx));
    end
    if localIsUnsetPolicy(localOptionalStructValue(cfg, "csi_acquisition_and_reporting.rf_papr_assumption", "unspecified"))
        error("sixgr:lls6g:config:JSCCJSCMRFPAPRConfigRequired", ...
            "JSCC/JSCM in %s requires csi_acquisition_and_reporting.rf_papr_assumption.", ...
            localCtx(ctx));
    end
    if localIsUnsetPolicy(localOptionalStructValue(cfg, "ai_ml.baseline_pairing", ""))
        error("sixgr:lls6g:config:JSCCJSCMBaselineRequired", ...
            "JSCC/JSCM in %s requires ai_ml.baseline_pairing to name a non-AI baseline comparator.", ...
            localCtx(ctx));
    end
end

if logical(localOptionalStructValue(cfg, "bandwidth_operation.dci_based_switching_enabled", false))
    if localIsUnsetPolicy(localOptionalStructValue(cfg, "bandwidth_operation.switching_reliability_policy", "none"))
        error("sixgr:lls6g:config:DCISwitchingReliabilityPolicyRequired", ...
            "bandwidth_operation.dci_based_switching_enabled=true in %s requires switching_reliability_policy.", ...
            localCtx(ctx));
    end
    if localIsUnsetPolicy(localOptionalStructValue(cfg, "bandwidth_operation.misalignment_handling_policy", "none"))
        error("sixgr:lls6g:config:DCISwitchingMisalignmentPolicyRequired", ...
            "bandwidth_operation.dci_based_switching_enabled=true in %s requires misalignment_handling_policy.", ...
            localCtx(ctx));
    end
end

jointDLULCSI = logical(localOptionalStructValue(cfg, "csi_acquisition_and_reporting.joint_dl_ul_csi_enabled", false)) || ...
    lower(string(localOptionalStructValue(cfg, "reference_signals.csi_acquisition_mode", ""))) == "joint_dl_ul";
if jointDLULCSI
    if localIsUnsetPolicy(localOptionalStructValue(cfg, "csi_acquisition_and_reporting.joint_port_mapping_policy", "disabled"))
        error("sixgr:lls6g:config:JointCSIPortMappingRequired", ...
            "Joint DL/UL CSI in %s requires csi_acquisition_and_reporting.joint_port_mapping_policy.", ...
            localCtx(ctx));
    end
    if localIsUnsetPolicy(localOptionalStructValue(cfg, "csi_acquisition_and_reporting.joint_timeline_policy", "disabled"))
        error("sixgr:lls6g:config:JointCSITimelineRequired", ...
            "Joint DL/UL CSI in %s requires csi_acquisition_and_reporting.joint_timeline_policy.", ...
            localCtx(ctx));
    end
end

if logical(localOptionalStructValue(cfg, "deployment_topology.full_duplex_flag", false))
    if localIsUnsetPolicy(localOptionalStructValue(cfg, "deployment_topology.self_interference_path_model", "none"))
        error("sixgr:lls6g:config:FullDuplexSIPathRequired", ...
            "full_duplex_flag=true in %s requires deployment_topology.self_interference_path_model.", ...
            localCtx(ctx));
    end
    if localIsUnsetPolicy(localOptionalStructValue(cfg, "interference.self_interference_model", "none"))
        error("sixgr:lls6g:config:FullDuplexSIChannelRequired", ...
            "full_duplex_flag=true in %s requires interference.self_interference_model.", ...
            localCtx(ctx));
    end
    if localIsUnsetPolicy(localOptionalStructValue(cfg, "mimo_and_beam_management.self_interference_estimation", "disabled"))
        error("sixgr:lls6g:config:FullDuplexEstimatorRequired", ...
            "full_duplex_flag=true in %s requires mimo_and_beam_management.self_interference_estimation.", ...
            localCtx(ctx));
    end
    if localIsUnsetPolicy(localOptionalStructValue(cfg, "receiver_algorithms.interference_cancellation", "disabled"))
        error("sixgr:lls6g:config:FullDuplexCancellationRequired", ...
            "full_duplex_flag=true in %s requires receiver_algorithms.interference_cancellation.", ...
            localCtx(ctx));
    end
end

numTRPs = max(double(localOptionalStructValue(cfg, "deployment_topology.num_trps", 1)), ...
    double(localOptionalStructValue(cfg, "mimo.trp_count", 1)));
trackingRSEnabled = logical(localOptionalStructValue(cfg, "reference_signals.tracking_rs.enabled", ...
    localOptionalStructValue(cfg, "reference_signals.tracking_rs_enabled", false)));
if trackingRSEnabled && numTRPs > 1
    trpAssumption = localOptionalStructValue(cfg, "reference_signals.tracking_rs.trp_transmission_assumption", "single_trp_only");
    if localIsUnsetPolicy(trpAssumption) || lower(string(trpAssumption)) == "single_trp_only"
        error("sixgr:lls6g:config:TrackingRSMultiTRPAssumptionRequired", ...
            "tracking_rs with num_trps > 1 in %s requires reference_signals.tracking_rs.trp_transmission_assumption.", ...
            localCtx(ctx));
    end
end

if ~logical(localOptionalStructValue(cfg, "run_control.save_intermediate", false))
    formats = lower(string(localOptionalStructValue(cfg, "output_control.artifact_formats", strings(0,1))));
    if ~logical(localOptionalStructValue(cfg, "output_control.save_resolved_config", false)) || ...
            ~any(formats == "json") || ~any(formats == "csv") || ...
            ~logical(localOptionalStructValue(cfg, "output_control.save_report", false))
        error("sixgr:lls6g:config:MinimumArtifactsRequired", ...
            "save_intermediate=false in %s still requires resolved config, JSON/CSV artifacts, and a saved report.", ...
            localCtx(ctx));
    end
end

if aiEnabled && localIsUnsetPolicy(localOptionalStructValue(cfg, "ai_ml.baseline_pairing", ""))
    error("sixgr:lls6g:config:AINeedsBaselineComparator", ...
        "ai_ml.enabled=true in %s requires ai_ml.baseline_pairing to name a non-AI baseline comparator.", ...
        localCtx(ctx));
end
end

function txt = localCtx(ctx)
ctx = string(ctx);
if strlength(ctx) == 0
    txt = "config";
else
    txt = char(ctx);
end
end

function value = localOptionalStructValue(s, path, defaultValue)
value = sixgr.util.structGet(s, path, defaultValue);
end

function value = localOptionalFiniteScalarOrNaN(s, path)
raw = localOptionalStructValue(s, path, NaN);
if isempty(raw) || ~(isnumeric(raw) || islogical(raw)) || ~isscalar(raw)
    value = NaN;
    return;
end
value = double(raw);
if ~isfinite(value)
    value = NaN;
end
end

function localValidateStructRules(secStruct, ruleStruct, secName, ctx, catalog, allowPartial)
fieldNames = string(fieldnames(ruleStruct));
for i = 1:numel(fieldNames)
    name = fieldNames(i);
    if ~isfield(secStruct, name)
        continue;
    end
    localValidateRuleValue(secStruct.(name), ruleStruct.(name), secName + "." + name, ctx, catalog, allowPartial);
end
end

function localValidateRuleValue(value, rule, fieldPath, ctx, catalog, allowPartial)
if localIsExplicitUnset(value, rule)
    if isfield(rule, "required") && logical(rule.required)
        error("sixgr:lls6g:config:MissingValue", ...
            "%s in %s cannot be explicitly unset.", fieldPath, localCtx(ctx));
    end
    return;
end

if isfield(rule, "type")
    localValidateRuleType(value, string(rule.type), fieldPath, ctx);
end

if isfield(rule, "nonempty") && logical(rule.nonempty)
    if (ischar(value) || isstring(value)) && strlength(strtrim(string(value))) == 0
        error("sixgr:lls6g:config:EmptyValue", ...
            "%s in %s must be non-empty.", fieldPath, localCtx(ctx));
    end
end

if isfield(rule, "allowed_values")
    localValidateAllowedStrings(value, string(rule.allowed_values), fieldPath, ctx);
end
if isfield(rule, "allowed_numeric_values")
    localValidateAllowedNumeric(value, double(rule.allowed_numeric_values), fieldPath, ctx);
end

if isnumeric(value) || islogical(value)
    v = double(value(:));
    if isfield(rule, "min") && any(v < double(rule.min))
        error("sixgr:lls6g:config:ValueTooSmall", ...
            "%s in %s must be >= %g.", fieldPath, localCtx(ctx), double(rule.min));
    end
    if isfield(rule, "max") && any(v > double(rule.max))
        error("sixgr:lls6g:config:ValueTooLarge", ...
            "%s in %s must be <= %g.", fieldPath, localCtx(ctx), double(rule.max));
    end
    if isfield(rule, "min_exclusive") && any(v <= double(rule.min_exclusive))
        error("sixgr:lls6g:config:ValueTooSmall", ...
            "%s in %s must be > %g.", fieldPath, localCtx(ctx), double(rule.min_exclusive));
    end
    if isfield(rule, "integer") && logical(rule.integer)
        if any(abs(v - round(v)) > eps(max(abs(v), 1)))
            error("sixgr:lls6g:config:NonIntegerValue", ...
                "%s in %s must contain only integer values.", fieldPath, localCtx(ctx));
        end
    end
end

if isfield(rule, "min_items")
    nItems = localNumItems(value);
    if nItems < double(rule.min_items)
        error("sixgr:lls6g:config:TooFewItems", ...
            "%s in %s must contain at least %d item(s).", fieldPath, localCtx(ctx), double(rule.min_items));
    end
end

if isfield(rule, "nested_rule")
    nestedKey = char(string(rule.nested_rule));
    if ~builtin("isstruct", value) || ~isscalar(value)
        error("sixgr:lls6g:config:BadNestedStruct", ...
            "%s in %s must be a scalar struct for nested rule '%s'.", fieldPath, localCtx(ctx), nestedKey);
    end
    if ~isfield(catalog, "nested_sections") || ~isfield(catalog.nested_sections, nestedKey)
        error("sixgr:lls6g:config:MissingNestedRule", ...
            "Catalog nested rule '%s' referenced by %s is not defined.", nestedKey, fieldPath);
    end
    nestedRule = catalog.nested_sections.(nestedKey);
    localRejectUnknownSectionFields(value, string(fieldnames(nestedRule.parameters)), fieldPath, ctx);
    reqFields = localRequiredNestedFields(nestedRule.parameters);
    if ~allowPartial
        localRequireFields(value, reqFields, fieldPath, ctx);
    end
    localValidateStructRules(value, nestedRule.parameters, fieldPath, ctx, catalog, allowPartial);
end

if isfield(rule, "type") && strcmpi(string(rule.type), "struct_array") && isfield(rule, "item_nested_rule")
    nestedKey = char(string(rule.item_nested_rule));
    if ~isfield(catalog, "nested_sections") || ~isfield(catalog.nested_sections, nestedKey)
        error("sixgr:lls6g:config:MissingNestedRule", ...
            "Catalog nested rule '%s' referenced by %s is not defined.", nestedKey, fieldPath);
    end
    nestedRule = catalog.nested_sections.(nestedKey);
    reqFields = localRequiredNestedFields(nestedRule.parameters);
    for idx = 1:numel(value)
        elemPath = sprintf("%s(%d)", fieldPath, idx);
        localRejectUnknownSectionFields(value(idx), string(fieldnames(nestedRule.parameters)), elemPath, ctx);
        if ~allowPartial
            localRequireFields(value(idx), reqFields, elemPath, ctx);
        end
        localValidateStructRules(value(idx), nestedRule.parameters, elemPath, ctx, catalog, allowPartial);
    end
end
end

function tf = localIsExplicitUnset(value, rule)
if ~isempty(value)
    tf = false;
    return;
end

typeName = lower(string(sixgr.util.structGet(rule, "type", "")));
if any(typeName == ["string_list","number_list","struct_array"])
    tf = false;
    return;
end

tf = ~(ischar(value) || isstring(value) || iscell(value) || builtin("isstruct", value) || istable(value));
end

function localValidateRuleType(value, typeName, fieldPath, ctx)
switch lower(typeName)
    case "string"
        ok = ischar(value) || (isstring(value) && isscalar(value));
    case "string_or_number"
        ok = ischar(value) || (isstring(value) && isscalar(value)) || ...
            (isnumeric(value) && isscalar(value) && isfinite(double(value)));
    case "string_list"
        ok = ischar(value) || isstring(value) || iscellstr(value) || ...
            (isempty(value) && (isnumeric(value) || iscell(value)));
    case "number"
        ok = isnumeric(value) && isscalar(value) && isfinite(double(value));
    case "number_list"
        ok = (isnumeric(value) && isvector(value) && all(isfinite(double(value(:))))) || ...
            (isempty(value) && (isnumeric(value) || iscell(value)));
    case "integer"
        ok = isnumeric(value) && isscalar(value) && isfinite(double(value)) && abs(double(value) - round(double(value))) <= eps(max(abs(double(value)), 1));
    case "boolean"
        ok = islogical(value) && isscalar(value);
    case "struct"
        ok = builtin("isstruct", value) && isscalar(value);
    case "struct_array"
        ok = isstruct(value) || isempty(value);
    otherwise
        ok = true;
end
if ~ok
    error("sixgr:lls6g:config:BadValueType", ...
        "%s in %s must match catalog type '%s'.", fieldPath, localCtx(ctx), typeName);
end
end

function localValidateAllowedStrings(value, allowedValues, fieldPath, ctx)
allowedValues = lower(string(allowedValues(:)));
if isempty(allowedValues)
    return;
end
if ischar(value) || (isstring(value) && isscalar(value))
    values = lower(string(value));
elseif isstring(value)
    values = lower(value(:));
elseif iscellstr(value)
    values = lower(string(value(:)));
else
    return;
end
bad = values(~ismember(values, allowedValues));
if ~isempty(bad)
    error("sixgr:lls6g:config:BadEnumValue", ...
        "%s in %s contains unsupported value(s): %s", fieldPath, localCtx(ctx), strjoin(cellstr(unique(bad)), ", "));
end
end

function localValidateAllowedNumeric(value, allowedValues, fieldPath, ctx)
allowedValues = double(allowedValues(:));
if isempty(allowedValues) || ~isnumeric(value)
    return;
end
values = double(value(:));
badMask = false(size(values));
for i = 1:numel(values)
    badMask(i) = ~any(abs(values(i) - allowedValues) <= eps(max(abs(values(i)), 1)));
end
if any(badMask)
    bad = values(badMask);
    error("sixgr:lls6g:config:BadEnumValue", ...
        "%s in %s contains unsupported numeric value(s): %s", fieldPath, localCtx(ctx), mat2str(unique(bad(:).')));
end
end

function n = localNumItems(value)
if ischar(value) || (isstring(value) && isscalar(value))
    n = double(strlength(string(value)) > 0);
elseif isstring(value) || isnumeric(value) || islogical(value)
    n = numel(value);
elseif iscell(value) || isstruct(value)
    n = numel(value);
else
    n = 0;
end
end

function req = localRequiredNestedFields(ruleStruct)
names = string(fieldnames(ruleStruct));
req = strings(0,1);
for i = 1:numel(names)
    rule = ruleStruct.(names(i));
    if isfield(rule, "required") && logical(rule.required)
        req(end+1,1) = names(i); %#ok<AGROW>
    end
end
end

function values = localCatalogAllowedStrings(rule)
values = lower(string(rule.allowed_values(:)));
end

function values = localCatalogAllowedNumeric(rule)
values = double(rule.allowed_numeric_values(:));
end

function status = localScenarioStudyStatus(cfg)
status = lower(string(localOptionalStructValue(cfg, "meta.research_class", "")));
if strlength(strtrim(status)) == 0
    status = lower(string(localOptionalStructValue(cfg, "meta.study_status", "")));
end
if strlength(strtrim(status)) == 0
    status = lower(string(localOptionalStructValue(cfg, "meta.maturity_tag", "")));
end
end

function tf = localIsCandidateStudy(status)
status = lower(string(status));
tf = any(status == ["study_item_candidate", "optional_research_experiment"]);
end

function mod = localConfiguredPDCCHModulation(cfg)
pdcchMod = upper(string(localOptionalStructValue(cfg, "pdcch.modulation", "")));
legacyMod = upper(string(localOptionalStructValue(cfg, "modulation_and_mapping.pdcch_modulation", "")));
if strlength(strtrim(pdcchMod)) > 0 && pdcchMod ~= "QPSK"
    mod = pdcchMod;
elseif strlength(strtrim(legacyMod)) > 0 && legacyMod ~= "QPSK"
    mod = legacyMod;
elseif strlength(strtrim(pdcchMod)) > 0
    mod = pdcchMod;
elseif strlength(strtrim(legacyMod)) > 0
    mod = legacyMod;
else
    mod = "QPSK";
end
end

function maxOrder = localMaxConfiguredModulationOrder(cfg)
orders = [ ...
    localQAMOrderFromValue(localOptionalStructValue(cfg, "modulation.dl_modulation_order", []))
    localQAMOrderFromValue(localOptionalStructValue(cfg, "modulation.ul_modulation_order", []))
    localQAMOrderFromValue(localOptionalStructValue(cfg, "modulation_and_mapping.qam_order", []))
    localQAMOrderFromValue(localOptionalStructValue(cfg, "modulation_and_mapping.pdsch_modulation", []))
    localQAMOrderFromValue(localOptionalStructValue(cfg, "modulation_and_mapping.pusch_modulation", []))
    localQAMOrderFromValue(localOptionalStructValue(cfg, "pdsch.modulation", []))
    localQAMOrderFromValue(localOptionalStructValue(cfg, "pusch.modulation", []))
    localQAMOrderFromValue(localOptionalStructValue(cfg, "pdcch.modulation", []))
    ];
orders = orders(isfinite(orders) & orders > 0);
if isempty(orders)
    maxOrder = 0;
else
    maxOrder = max(orders);
end
end

function order = localQAMOrderFromValue(value)
order = NaN;
if isempty(value)
    return;
end
if isnumeric(value) && isscalar(value) && isfinite(double(value))
    order = double(value);
    return;
end
txt = upper(string(value));
if any(txt == ["BPSK", "PI/2-BPSK", "PI_OVER_2_BPSK"])
    order = 1;
elseif txt == "QPSK"
    order = 2;
elseif txt == "16QAM"
    order = 4;
elseif txt == "64QAM"
    order = 6;
elseif txt == "256QAM"
    order = 8;
elseif txt == "1024QAM"
    order = 10;
elseif txt == "4096QAM"
    order = 12;
end
end

function tf = localHasHighSNRStressSweep(cfg, minHighSNRAccept_dB)
tf = false;
values = localOptionalStructValue(cfg, "sweeps_and_matrix.snr_sweep.values_db", []);
enabled = logical(localOptionalStructValue(cfg, "sweeps_and_matrix.snr_sweep.enabled", false));
if enabled && isnumeric(values) && isvector(values) && numel(values) >= 2 && all(isfinite(values))
    tf = max(double(values(:))) >= double(minHighSNRAccept_dB);
    if tf
        return;
    end
end
baseSNR = double(localOptionalStructValue(cfg, "simulation.snr_db", NaN));
offsets = localOptionalStructValue(cfg, "simulation.snr_sweep_offsets_db", []);
if isfinite(baseSNR) && isnumeric(offsets) && isvector(offsets) && numel(offsets) >= 2 && all(isfinite(offsets))
    tf = max(baseSNR + double(offsets(:))) >= double(minHighSNRAccept_dB);
end
end

function tf = localHasVisibleHardwareImpairment(cfg)
frontEndPolicies = lower(string({ ...
    localOptionalStructValue(cfg, "power_and_rf_frontend.pa_nonlinearity_model", "none")
    localOptionalStructValue(cfg, "power_and_rf_frontend.lo_phase_noise_model", "none")
    localOptionalStructValue(cfg, "power_and_rf_frontend.iq_imbalance", "none")
    localOptionalStructValue(cfg, "power_and_rf_frontend.saturation_model", "none")
    }));
tf = any(~ismember(frontEndPolicies, ["", "none", "disabled", "ideal", "constant_zero"]));
if tf
    return;
end
legacyFlags = [ ...
    logical(localOptionalStructValue(cfg, "impairments.pa_nonlinearity_enabled", false))
    logical(localOptionalStructValue(cfg, "impairments.phase_noise_enabled", false))
    logical(localOptionalStructValue(cfg, "impairments.iq_imbalance_enabled", false))
    ];
tf = any(legacyFlags);
end

function tf = localRequiresStrictMCSConsistency(cfg)
tags = lower(string(localOptionalStructValue(cfg, "meta.tags", strings(0, 1))));
scenarioGroup = lower(string(localOptionalStructValue(cfg, "meta.scenario_group", "")));
tf = any(ismember(tags, ["no-proxy", "truth", "strict_truth"])) || any(contains(scenarioGroup, "truth"));
end

function tf = localRequiresSlotCoupledTruth(cfg)
tags = lower(string(localOptionalStructValue(cfg, "meta.tags", strings(0, 1))));
scenarioGroup = lower(string(localOptionalStructValue(cfg, "meta.scenario_group", "")));
honestyMode = lower(string(localOptionalStructValue(cfg, "scenario.honesty_mode", "")));
tf = honestyMode == "strict" || ...
    any(ismember(tags, ["no-proxy", "truth", "strict_truth", "coupled_truth"])) || ...
    any(contains(scenarioGroup, "truth"));
end

function tf = localRequiresFullCarrierReferenceReplay(cfg, linkDir)
linkDir = lower(string(linkDir));
if ~ismember(linkDir, ["dl", "both"])
    tf = false;
    return;
end
csirsEnabled = logical(localOptionalStructValue(cfg, "reference_signals.csi_rs_enabled", false)) || ...
    logical(localOptionalStructValue(cfg, "reference_signals.nzp_csi_rs.enabled", false));
tf = csirsEnabled && localRequiresSlotCoupledTruth(cfg);
end

function localValidateDirectionModulationMCSConsistency(cfg, direction, ctx)
direction = upper(string(direction));
tableName = string(localOptionalStructValue(cfg, "modulation.mcs_table", ""));
if strlength(strtrim(tableName)) == 0
    return;
end
if direction == "DL"
    modValue = localOptionalStructValue(cfg, "modulation.dl_modulation_order", []);
    mcsIndex = localOptionalStructValue(cfg, "modulation.dl_mcs_index", []);
else
    modValue = localOptionalStructValue(cfg, "modulation.ul_modulation_order", []);
    mcsIndex = localOptionalStructValue(cfg, "modulation.ul_mcs_index", []);
end
configuredOrder = localQAMOrderFromValue(modValue);
if ~(isfinite(configuredOrder) && configuredOrder > 0 && isnumeric(mcsIndex) && isscalar(mcsIndex) && isfinite(double(mcsIndex)))
    return;
end
profile = sixgr.link.resolveMCSProfile(tableName, double(mcsIndex));
if ~logical(profile.Valid)
    return;
end
resolvedOrder = localQAMOrderFromValue(string(profile.Modulation));
if ~(isfinite(resolvedOrder) && resolvedOrder > 0)
    return;
end
if round(double(configuredOrder)) ~= round(double(resolvedOrder))
    error("sixgr:lls6g:config:ModulationMCSConsistencyRequired", ...
        "%s modulation order %g in %s conflicts with modulation.mcs_table=%s, %s_mcs_index=%g, which resolves to %s per TS 38.214.", ...
        direction, double(configuredOrder), localCtx(ctx), tableName, lower(direction), double(mcsIndex), string(profile.Modulation));
    end
end

function tf = localIsUnsetPolicy(value)
txt = lower(strtrim(string(value)));
tf = strlength(txt) == 0 || any(txt == ["none", "disabled", "unspecified", "false", "off"]);
end

function localValidateRandomAccessCompatibility(cfg, ctx)
prachFormat = upper(strtrim(string(localOptionalStructValue(cfg, "random_access.prach_format", ""))));
preambleLengthMode = lower(strtrim(string(localOptionalStructValue(cfg, "random_access.preamble_length_mode", ""))));
configurationIndex = double(localOptionalStructValue(cfg, "random_access.configuration_index", NaN));
subcarrierSpacing = double(localOptionalStructValue(cfg, "random_access.subcarrier_spacing_khz", NaN));
if strlength(prachFormat) == 0 || ~isfinite(configurationIndex) || ~isfinite(subcarrierSpacing)
    return;
end
shortFormats = ["A1", "A2", "A3", "B1", "B4", "C0", "C2"];
expectedLengthMode = "long";
if any(prachFormat == shortFormats)
    expectedLengthMode = "short";
end
if strlength(preambleLengthMode) > 0 && preambleLengthMode ~= expectedLengthMode
    error("sixgr:lls6g:config:BadPrachLengthMode", ...
        "random_access.prach_format=%s in %s requires preamble_length_mode=%s, but the scenario resolves to %s.", ...
        prachFormat, localCtx(ctx), expectedLengthMode, preambleLengthMode);
end
if ~(exist("nrPRACHConfig", "class") == 8 || exist("nrPRACHConfig", "file") == 2)
    return;
end
try
    prach = nrPRACHConfig;
    duplexMode = upper(strtrim(string(localOptionalStructValue(cfg, "frequency.duplex_mode", ...
        localOptionalStructValue(cfg, "random_access.duplex_mode", "TDD")))));
    if duplexMode == "FDD"
        prach.DuplexMode = "FDD";
    else
        prach.DuplexMode = "TDD";
    end
    configuredFrequencyRange = upper(strtrim(string(localOptionalStructValue(cfg, "random_access.frequency_range", ""))));
    centerFrequencyHz = double(localOptionalStructValue(cfg, "random_access.carrier_frequency_hz", ...
        localOptionalStructValue(cfg, "frequency.center_frequency_hz", 4e9)));
    if configuredFrequencyRange == "FR1" || configuredFrequencyRange == "FR2"
        prach.FrequencyRange = char(configuredFrequencyRange);
    elseif isfinite(centerFrequencyHz) && centerFrequencyHz >= 24.25e9
        prach.FrequencyRange = "FR2";
    else
        prach.FrequencyRange = "FR1";
    end
    prach.SubcarrierSpacing = double(subcarrierSpacing);
    prach.ConfigurationIndex = double(configurationIndex);
catch ME
    error("sixgr:lls6g:config:BadPrachConfigCompatibility", ...
        "random_access configuration in %s is not toolbox-compatible for configuration_index=%g and subcarrier_spacing_khz=%g: %s", ...
        localCtx(ctx), double(configurationIndex), double(subcarrierSpacing), string(ME.message));
end
carrierScs = double(localOptionalStructValue(cfg, "random_access.carrier_scs_khz", ...
    localOptionalStructValue(cfg, "frame.scs_khz", subcarrierSpacing)));
nRb = double(localOptionalStructValue(cfg, "random_access.n_size_grid", ...
    localOptionalStructValue(cfg, "phy.carrier.NSizeGrid", localOptionalStructValue(cfg, "frequency.n_size_grid", 273))));
numPrachOccasions = round(double(localOptionalStructValue(cfg, "random_access.num_prach_occasions", 4)));
scanSlots = round(double(localOptionalStructValue(cfg, "run_control.total_slots", localOptionalStructValue(cfg, "simulation.n_slots", 40))));
scanSlots = max(scanSlots, max(80, numPrachOccasions * 20));
scanSlots = max(1, scanSlots);
[activeSlot, effectiveFormat] = localFindMaterializedPrachOccasion(prach, carrierScs, nRb, scanSlots);
if ~isfinite(activeSlot)
    error("sixgr:lls6g:config:NoMaterializedPrachOccasion", ...
        "random_access configuration in %s does not materialize a PRACH waveform occasion within the first %g slots for configuration_index=%g and subcarrier_spacing_khz=%g.", ...
        localCtx(ctx), double(scanSlots), double(configurationIndex), double(subcarrierSpacing));
end
if strlength(effectiveFormat) > 0 && effectiveFormat ~= prachFormat
    error("sixgr:lls6g:config:BadPrachFormatMapping", ...
        "random_access configuration in %s requests prach_format=%s, but configuration_index=%g with subcarrier_spacing_khz=%g resolves to %s in nrPRACHConfig.", ...
        localCtx(ctx), prachFormat, double(configurationIndex), double(subcarrierSpacing), effectiveFormat);
end
localValidatePrachHasULSafeOccasion(cfg, ctx, configurationIndex, subcarrierSpacing);
end

function localValidatePrachHasULSafeOccasion(cfg, ctx, configurationIndex, subcarrierSpacing)
prachEnabled = logical(localOptionalStructValue(cfg, "random_access.enabled", true));
prachRequired = logical(localOptionalStructValue(cfg, "control_gating.prach_required", ...
    localOptionalStructValue(cfg, "run.controlGating.prachRequired", false)));
if ~(prachEnabled && prachRequired)
    return;
end
try
    fs = sixgr.phy.FrameStructureEngine(cfg);
catch ME
    error("sixgr:lls6g:config:PrachULSafeOccasionValidationFailed", ...
        "Cannot validate PRACH/TDD slot ownership in %s for configuration_index=%g and subcarrier_spacing_khz=%g: %s", ...
        localCtx(ctx), double(configurationIndex), double(subcarrierSpacing), string(ME.message));
end
validSlots = double(fs.PRACHValidSlots1Based);
validSlots = validSlots(isfinite(validSlots) & validSlots >= 1);
if isempty(validSlots)
    status = string(fs.PRACHValidationStatus);
    error("sixgr:lls6g:config:NoULSafePrachOccasion", ...
        "control_gating.prach_required=true in %s, but PRACH configuration_index=%g/subcarrier_spacing_khz=%g has no UL-safe PRACH occasion in TDD pattern %s with special slot %gDL/%gG/%gUL symbols. Validation status: %s.", ...
        localCtx(ctx), double(configurationIndex), double(subcarrierSpacing), string(fs.TDDPattern), ...
        double(fs.SpecialSlotDLSymbols), double(fs.SpecialSlotGuardSymbols), ...
        double(fs.SpecialSlotULSymbols), status);
end
end

function [activeSlot, effectiveFormat] = localFindMaterializedPrachOccasion(prach, carrierScs, nRb, scanSlots)
activeSlot = NaN;
effectiveFormat = upper(strtrim(string(prach.Format)));
try
    carrier = nrCarrierConfig;
    carrier.SubcarrierSpacing = double(carrierScs);
    carrier.NSizeGrid = double(nRb);
catch
    return;
end
for slotCandidate = 0:max(0, round(double(scanSlots)) - 1)
    try
        carrier.NSlot = double(slotCandidate);
        prach.NPRACHSlot = double(slotCandidate);
        prachSym = nrPRACH(carrier, prach);
        if isempty(prachSym)
            continue;
        end
        prachInd = nrPRACHIndices(carrier, prach);
        if isempty(prachInd)
            continue;
        end
        activeSlot = double(slotCandidate);
        effectiveFormat = upper(strtrim(string(prach.Format)));
        return;
    catch
    end
end
end
