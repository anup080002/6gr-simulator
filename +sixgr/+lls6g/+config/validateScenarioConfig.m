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
localWarnSchemaVersionMismatch(cfg, logical(opt.AllowPartial), ctx);

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

function localWarnSchemaVersionMismatch(cfg, allowPartial, ctx)
if allowPartial || ~isfield(cfg, "meta")
    return;
end
current = string(sixgr.lls6g.config.currentVersion());
version = string(sixgr.util.structGet(cfg, "meta.schema_version", ...
    sixgr.util.structGet(cfg, "meta.schemaVersion", current)));
if strlength(strtrim(version)) > 0 && version ~= current
    warning("sixgr:lls6g:config:SchemaVersionMismatch", ...
        "Scenario schema_version '%s' in %s differs from current '%s'.", ...
        char(version), localCtx(ctx), char(current));
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
localValidateCausalPHYChainAudit(cfg, ctx);
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
localValidatePrecodingAuthority(cfg, linkDir, ctx);

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
localValidateCanonicalCarrierGrid(cfg, ctx);

function localValidateDerivedTimingConsistency(cfg, scsKHz, ctx)
cp = string(localOptionalStructValue(cfg, "frame.cp_type", ""));
num = sixgr.phy.frame.NumerologyCatalog.resolve( ...
    scsKHz, cp, "generic_waveform_test", "");
mu = double(num.Mu);
slotDurationMs = double(num.SlotDurationMilliseconds);
slotsPerFrame = double(num.SlotsPerFrame);

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
cp = string(localOptionalStructValue(cfg, "frame.cp_type", ""));
num = sixgr.phy.frame.NumerologyCatalog.resolve( ...
    scsKHz, cp, "generic_waveform_test", "");
slotsPerFrame = double(num.SlotsPerFrame);
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
slotDurationMs = double(num.SlotDurationMilliseconds);
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

common = localOptionalStructValue(cfg, "frame.tdd_common", []);
if ~(isstruct(common) && isscalar(common) && ~isempty(fieldnames(common)))
    error("sixgr:phy:frame:MissingTDDCommonConfig", ...
        "frame.tdd_common is required for TDD in %s.", localCtx(ctx));
end
referenceSCS = localOptionalStructValue(common, ...
    "ReferenceSubcarrierSpacingKHz", []);
pattern1 = localOptionalStructValue(common, "Pattern1", struct());
pattern2 = localOptionalStructValue(common, "Pattern2", struct());
dedicated = localOptionalStructValue(cfg, ...
    "frame.tdd_dedicated", struct([]));
sixgr.phy.frame.SlotFormatResolver.resolve( ...
    "ReferenceSubcarrierSpacingKHz", referenceSCS, ...
    "ActiveSubcarrierSpacingKHz", double(cfg.frame.scs_khz), ...
    "CyclicPrefix", cfg.frame.cp_type, ...
    "Pattern1", pattern1, ...
    "Pattern2", pattern2, ...
    "DedicatedOverrides", dedicated);
end

function localValidateCanonicalCarrierGrid(cfg, ctx)
fcHz = double(localOptionalStructValue(cfg, ...
    "frequency.center_frequency_hz", NaN));
bwHz = double(localOptionalStructValue(cfg, ...
    "frequency.bandwidth_hz", NaN));
scsKHz = double(localOptionalStructValue(cfg, "frame.scs_khz", NaN));
nSizeGrid = double(localOptionalStructValue(cfg, ...
    "frequency.n_size_grid", NaN));
cp = string(localOptionalStructValue(cfg, "frame.cp_type", ""));
configuredRange = string(localOptionalStructValue(cfg, ...
    "frequency.range_name", ""));
try
    if upper(strtrim(configuredRange)) == "FR3"
        customAllowed = logical(localOptionalStructValue(cfg, ...
            "frequency.custom_frequency_override_allowed", false));
        if ~customAllowed
            error("sixgr:phy:frame:CustomCarrierRequiresOptIn", ...
                "FR3 research carriers require frequency.custom_frequency_override_allowed=true.");
        end
        sixgr.phy.frame.CarrierGridConfig.custom( ...
            "ResearchMode", true, ...
            "CenterFrequencyHz", fcHz, ...
            "ChannelBandwidthMHz", bwHz / 1e6, ...
            "SubcarrierSpacingKHz", scsKHz, ...
            "NSizeGrid", nSizeGrid, ...
            "NStartGrid", double(localOptionalStructValue(cfg, ...
                "frequency.n_start_grid", 0)));
    else
        rangeArgs = {"CenterFrequencyHz", fcHz};
        if strlength(strtrim(configuredRange)) > 0
            rangeArgs = [rangeArgs, {"FrequencyRange", configuredRange}]; %#ok<AGROW>
        end
        range = sixgr.phy.frame.FrequencyRangeResolver.resolve(rangeArgs{:});
        sixgr.phy.frame.CarrierGridConfig.resolve( ...
            "Role", "gNB", ...
            "FrequencyRange", range.FrequencyRange, ...
            "CenterFrequencyHz", fcHz, ...
            "ChannelBandwidthMHz", bwHz / 1e6, ...
            "SubcarrierSpacingKHz", scsKHz, ...
            "ConfiguredNSizeGrid", nSizeGrid, ...
            "NStartGrid", double(localOptionalStructValue(cfg, ...
                "frequency.n_start_grid", 0)), ...
            "CyclicPrefix", cp);
    end
catch ME
    wrapped = MException("sixgr:lls6g:config:InvalidCarrierGrid", ...
        "Canonical carrier grid in %s is invalid: %s", ...
        localCtx(ctx), ME.message);
    wrapped = addCause(wrapped, ME);
    throw(wrapped);
end
end

minDuration_s = double(cfg.simulation.min_duration_s);
if ~(isfinite(minDuration_s) && minDuration_s > 0)
    error("sixgr:lls6g:config:BadMinDuration", ...
        "simulation.min_duration_s in %s must be a positive scalar.", localCtx(ctx));
end

snrSweepOffsets = double(cfg.simulation.snr_sweep_offsets_db);
snrSweepEnabled = logical(localOptionalStructValue(cfg, "sweeps_and_matrix.snr_sweep.enabled", false));
if (~isempty(snrSweepOffsets) && ~isvector(snrSweepOffsets)) || any(~isfinite(snrSweepOffsets))
    error("sixgr:lls6g:config:BadSNRSweepOffsets", ...
        "simulation.snr_sweep_offsets_db in %s must be a finite numeric vector.", localCtx(ctx));
end
localValidateSNRSweepRequirements(cfg, snrSweepEnabled, ctx);
localValidateOperatingPointMode(cfg, ctx);
localValidateFixedLinkCalibrationRequirements(cfg, ctx);
localValidateFixedLinkMasterAuthority(cfg, ctx);
localValidateRunClassScenarioRequirements(cfg, ctx);

ulWf = upper(string(cfg.waveform.ul_waveform));
transformEnabled = logical(cfg.waveform.transform_precoding_enabled);
if (ulWf == "DFT-S-OFDM") ~= transformEnabled
    error("sixgr:lls6g:config:BadDFTSOFDM", ...
        ['waveform.ul_waveform=%s and transform_precoding_enabled=%d in %s ' ...
         'must describe the same UL waveform.'], ...
        char(ulWf), transformEnabled, localCtx(ctx));
end

function localValidateCausalPHYChainAudit(cfg, ctx)
audit = sixgr.util.structGet(cfg, ...
    "validation.causal_phy_chain_audit", struct());
if ~(isstruct(audit) && isscalar(audit) && ~isempty(fieldnames(audit)))
    return;
end
enabled = logical(sixgr.util.structGet(audit, "enabled", false));
required = logical(sixgr.util.structGet(audit, "required", false));
if required && ~enabled
    error("sixgr:lls6g:config:CausalAuditRequiredButDisabled", ...
        "validation.causal_phy_chain_audit in %s cannot be required and disabled.", ...
        localCtx(ctx));
end
stages = localStructListItems(sixgr.util.structGet(audit, "stages", []), ...
    "validation.causal_phy_chain_audit.stages", ctx);
bindings = localStructListItems(sixgr.util.structGet(audit, ...
    "parameter_bindings", []), ...
    "validation.causal_phy_chain_audit.parameter_bindings", ctx);
stageIds = strings(numel(stages),1);
stageOrders = nan(numel(stages),1);
for index = 1:numel(stages)
    stage = stages{index};
    stageIds(index) = strtrim(string(stage.stage_id));
    stageOrders(index) = double(stage.order);
    alwaysRequired = logical(sixgr.util.structGet(stage, ...
        "always_required", false));
    featureAuthority = strtrim(string(sixgr.util.structGet(stage, ...
        "feature_authority", "")));
    if alwaysRequired == (strlength(featureAuthority) > 0)
        error("sixgr:lls6g:config:CausalAuditAuthorityAmbiguous", ...
            ["Causal stage '%s' in %s must declare exactly one of " ...
            "always_required=true or feature_authority."], ...
            stageIds(index), localCtx(ctx));
    end
    consumers = [localStringListForValidation(sixgr.util.structGet(stage, ...
        "consumer_functions", [])); ...
        localStringListForValidation(sixgr.util.structGet(stage, ...
        "consumer_source_files", []))];
    if isempty(consumers)
        error("sixgr:lls6g:config:CausalAuditConsumerMissing", ...
            "Causal stage '%s' in %s has no exact runtime consumer.", ...
            stageIds(index), localCtx(ctx));
    end
    localValidateCausalArtifactPath(string(stage.measurement_artifact), ...
        stageIds(index), ctx);
    measuredFields = localStringListForValidation(stage.measured_fields);
    if numel(unique(measuredFields)) ~= numel(measuredFields)
        error("sixgr:lls6g:config:CausalAuditDuplicateMeasuredField", ...
            "Causal stage '%s' in %s repeats a measured field.", ...
            stageIds(index), localCtx(ctx));
    end
    successField = strtrim(string(sixgr.util.structGet(stage, ...
        "success_field", "")));
    successMode = strtrim(string(sixgr.util.structGet(stage, ...
        "success_mode", "")));
    if xor(strlength(successField) > 0, strlength(successMode) > 0)
        error("sixgr:lls6g:config:CausalAuditSuccessRuleIncomplete", ...
            "Causal stage '%s' in %s must declare success_field and success_mode together.", ...
            stageIds(index), localCtx(ctx));
    end
end
if any(stageIds == "") || numel(unique(stageIds)) ~= numel(stageIds)
    error("sixgr:lls6g:config:CausalAuditDuplicateStage", ...
        "Causal audit stage IDs in %s must be unique and nonempty.", localCtx(ctx));
end
if any(~isfinite(stageOrders)) || numel(unique(stageOrders)) ~= numel(stageOrders)
    error("sixgr:lls6g:config:CausalAuditDuplicateOrder", ...
        "Causal audit stage orders in %s must be unique and finite.", localCtx(ctx));
end
for index = 1:numel(stages)
    dependencies = localStringListForValidation(sixgr.util.structGet( ...
        stages{index}, "dependency_stages", []));
    for dependency = dependencies(:).'
        dependencyIndex = find(stageIds == dependency, 1, "first");
        if isempty(dependencyIndex)
            error("sixgr:lls6g:config:CausalAuditUnknownDependency", ...
                "Causal stage '%s' in %s names unknown dependency '%s'.", ...
                stageIds(index), localCtx(ctx), dependency);
        end
        if stageOrders(dependencyIndex) >= stageOrders(index)
            error("sixgr:lls6g:config:CausalAuditDependencyOrder", ...
                "Causal dependency '%s' must precede stage '%s' in %s.", ...
                dependency, stageIds(index), localCtx(ctx));
        end
    end
end
bindingIds = strings(numel(bindings),1);
for index = 1:numel(bindings)
    binding = bindings{index};
    bindingIds(index) = strtrim(string(binding.parameter_id));
    consumers = [localStringListForValidation(sixgr.util.structGet(binding, ...
        "consumer_functions", [])); ...
        localStringListForValidation(sixgr.util.structGet(binding, ...
        "consumer_source_files", []))];
    if isempty(consumers)
        error("sixgr:lls6g:config:CausalAuditBindingConsumerMissing", ...
            "Causal parameter '%s' in %s has no exact runtime consumer.", ...
            bindingIds(index), localCtx(ctx));
    end
end
if any(bindingIds == "") || numel(unique(bindingIds)) ~= numel(bindingIds)
    error("sixgr:lls6g:config:CausalAuditDuplicateParameter", ...
        "Causal audit parameter IDs in %s must be unique and nonempty.", localCtx(ctx));
end
end

function items = localStructListItems(raw, fieldPath, ctx)
if isstruct(raw)
    items = arrayfun(@(index) raw(index), 1:numel(raw), ...
        "UniformOutput", false);
elseif iscell(raw) && all(cellfun(@(x) isstruct(x) && isscalar(x), raw(:)))
    items = raw(:);
else
    error("sixgr:lls6g:config:BadCausalAuditRegistry", ...
        "%s in %s must contain scalar struct mappings.", fieldPath, localCtx(ctx));
end
end

function values = localStringListForValidation(raw)
if isempty(raw)
    values = strings(0,1);
else
    values = strtrim(string(raw(:)));
    values(values == "") = [];
end
end

function localValidateCausalArtifactPath(pathValue, stageId, ctx)
normalized = replace(strtrim(string(pathValue)), "\", "/");
parts = split(normalized, "/");
if normalized == "" || startsWith(normalized, "/") || ...
        ~isempty(regexp(char(normalized), '^[A-Za-z]:', 'once')) || ...
        any(parts == "..")
    error("sixgr:lls6g:config:CausalAuditUnsafeArtifactPath", ...
        "Causal stage '%s' in %s requires a safe run-relative measurement artifact path.", ...
        stageId, localCtx(ctx));
end
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
if usersEnabled && nUsers > 1 && nTx <= 1
    error("sixgr:lls6g:config:UsersRequireMultiAntennaTx", ...
        "Multi-user execution in %s requires mimo.n_tx_ant > 1 for beamformed link sweeps.", localCtx(ctx));
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

if isfield(cfg.control,'dl_reference_signaling')
    data=struct('DLReferenceSignaling',cfg.control.dl_reference_signaling);
    sixgr.phy.pdcch.DLReferenceSignaling.resolve(data);
    refs=cfg.reference_signals; declared=data.DLReferenceSignaling;
    required={'pdsch_dmrs_config_type','pdsch_dmrs_max_length','pdsch_dmrs_num_cdm_groups_without_data'};
    assert(all(isfield(refs,required)), ...
        'sixgr:lls6g:config:MissingDLDMRSAuthority', ...
        'DL reference signaling requires explicit PDSCH DMRS type, max length and CDM group count.');
    assert(refs.pdsch_dmrs_config_type==declared.dmrs_configuration_type && ...
        refs.pdsch_dmrs_max_length==declared.dmrs_max_length && ...
        refs.pdsch_dmrs_num_cdm_groups_without_data<=2 && dlLayers<=4, ...
        'sixgr:lls6g:config:DLDMRSContextMismatch', ...
        'control.dl_reference_signaling must agree with the PDSCH DMRS and single-codeword configuration.');
end
if isfield(cfg.control,'connected_dci')
    assert(isfield(cfg.control,'connected_monitoring'), ...
        'sixgr:phy:pdcch:MissingConnectedMonitoring','Connected DCI requires control.connected_monitoring.');
    sixgr.phy.pdcch.ConnectedPDCCHConfiguration.validatePolicy(cfg.control.connected_monitoring);
    if isfield(cfg.control,'coreset_qcl_association')
        sixgr.pdsch.CORESETQCLReference.validatePolicy(cfg.control.coreset_qcl_association);
    end
    sixgr.phy.pdcch.ConnectedDCIProfile.validatePolicy(cfg.control.connected_dci);
    assert(all(isfield(cfg.control,{'dl_reference_signaling','ul_reference_signaling','ul_precoding'})), ...
        'sixgr:lls6g:config:MissingConnectedReferencePolicy','Connected DCI requires explicit DL/UL reference and UL precoding contexts.');
    for channel={'pdsch','pusch'}
        assert(isfield(cfg,channel{1}) && ...
            all(isfield(cfg.(channel{1}),{'dmrs_nscid','time_domain_allocations'})), ...
            'sixgr:lls6g:config:MissingConnectedDataPolicy', ...
            'Connected DCI requires explicit %s.dmrs_nscid and %s.time_domain_allocations.',channel{1},channel{1});
    end
end
if isfield(cfg.control,'ul_reference_signaling')
    assert(isfield(cfg.control,'ul_precoding'), ...
        'sixgr:lls6g:config:MissingULReferenceContext','control.ul_reference_signaling requires control.ul_precoding.');
    data=struct('ULPrecoding',cfg.control.ul_precoding, ...
        'ULReferenceSignaling',cfg.control.ul_reference_signaling, ...
        'TransformPrecodingEnabled',cfg.waveform.transform_precoding_enabled);
    sixgr.phy.pdcch.ULReferenceSignaling.resolve(data);
    refs=cfg.reference_signals; declared=data.ULReferenceSignaling;
    required={'pusch_dmrs_config_type','pusch_dmrs_max_length','pusch_dmrs_num_cdm_groups_without_data'};
    assert(all(isfield(refs,required)), ...
        'sixgr:lls6g:config:MissingULDMRSAuthority', ...
        'Reference signaling requires explicit reference_signals.pusch_dmrs_config_type, pusch_dmrs_max_length and pusch_dmrs_num_cdm_groups_without_data.');
    assert(refs.pusch_dmrs_config_type==declared.dmrs_configuration_type && ...
        refs.pusch_dmrs_max_length==declared.dmrs_max_length && ...
        refs.pusch_dmrs_num_cdm_groups_without_data<=2, ...
        'sixgr:lls6g:config:ULDMRSContextMismatch', ...
        'control.ul_reference_signaling must agree with the PUSCH DMRS configuration; type 1 permits at most two CDM groups.');
    assert(declared.srs_resource_count==1 && refs.srs_enabled && ...
        isstruct(refs.srs) && isscalar(refs.srs) && string(refs.srs.resource_set_usage)=="codebook", ...
        'sixgr:lls6g:config:SRSResourceSetRuntimeMismatch', ...
        'The active SRS runtime supports one configured codebook resource; a larger resource-set declaration is not executed.');
end
pdcchPayloadBits = sixgr.util.structGet(cfg, "control.pdcch_payload_bits", []);
if ~isempty(pdcchPayloadBits)
    pdcchPayloadBits = double(pdcchPayloadBits);
    if ~(isfinite(pdcchPayloadBits) && pdcchPayloadBits >= 1 && ...
            abs(pdcchPayloadBits - round(pdcchPayloadBits)) < eps)
        error("sixgr:lls6g:config:BadPDCCHPayloadBits", ...
            "control.pdcch_payload_bits in %s must be a positive integer when supplied.", ...
            localCtx(ctx));
    end
elseif ~isfield(cfg.control, "pdcch_strict") || ...
        ~isstruct(cfg.control.pdcch_strict) || ...
        ~isfield(cfg.control.pdcch_strict, "dci_context")
    error("sixgr:phy:pdcch:missing_dci_context", ...
        "control in %s requires pdcch_strict.dci_context when fixed pdcch_payload_bits is omitted.", ...
        localCtx(ctx));
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
pdschDmrsAddPos = double(localOptionalStructValue(cfg, "reference_signals.pdsch_dmrs_additional_positions", 0));
puschDmrsAddPos = double(localOptionalStructValue(cfg, "reference_signals.pusch_dmrs_additional_positions", 0));
pdschDmrsMaxLength = double(localOptionalStructValue(cfg, "reference_signals.pdsch_dmrs_max_length", 1));
puschDmrsMaxLength = double(localOptionalStructValue(cfg, "reference_signals.pusch_dmrs_max_length", pdschDmrsMaxLength));
puschDmrsConfigType = double(localOptionalStructValue(cfg, "reference_signals.pusch_dmrs_config_type", dmrsConfigType));
puschDmrsTypeAPos = double(localOptionalStructValue(cfg, "reference_signals.pusch_dmrs_type_a_position", dmrsTypeAPos));
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
if ~ismember(pdschDmrsAddPos, localCatalogAllowedNumeric(catalog.sections.reference_signals.parameters.pdsch_dmrs_additional_positions))
    error("sixgr:lls6g:config:BadPDSCHDMRSAdditionalPositions", ...
        "reference_signals.pdsch_dmrs_additional_positions in %s must be 0, 1, 2, or 3.", localCtx(ctx));
end
if ~ismember(puschDmrsAddPos, localCatalogAllowedNumeric(catalog.sections.reference_signals.parameters.pusch_dmrs_additional_positions))
    error("sixgr:lls6g:config:BadPUSCHDMRSAdditionalPositions", ...
        "reference_signals.pusch_dmrs_additional_positions in %s must be 0, 1, 2, or 3.", localCtx(ctx));
end
if ~ismember(pdschDmrsMaxLength, localCatalogAllowedNumeric(catalog.sections.reference_signals.parameters.pdsch_dmrs_max_length))
    error("sixgr:lls6g:config:BadPDSCHDMRSMaxLength", ...
        "reference_signals.pdsch_dmrs_max_length in %s must be 1 or 2.", localCtx(ctx));
end
if ~ismember(puschDmrsMaxLength, localCatalogAllowedNumeric(catalog.sections.reference_signals.parameters.pusch_dmrs_max_length))
    error("sixgr:lls6g:config:BadPUSCHDMRSMaxLength", ...
        "reference_signals.pusch_dmrs_max_length in %s must be 1 or 2.", localCtx(ctx));
end
if ~ismember(puschDmrsConfigType, localCatalogAllowedNumeric(catalog.sections.reference_signals.parameters.pusch_dmrs_config_type))
    error("sixgr:lls6g:config:BadPUSCHDMRSConfigType", ...
        "reference_signals.pusch_dmrs_config_type in %s must be 1 or 2.", localCtx(ctx));
end
if ~ismember(puschDmrsTypeAPos, localCatalogAllowedNumeric(catalog.sections.reference_signals.parameters.pusch_dmrs_type_a_position))
    error("sixgr:lls6g:config:BadPUSCHDMRSTypeAPosition", ...
        "reference_signals.pusch_dmrs_type_a_position in %s must be 2 or 3.", localCtx(ctx));
end
cfoEstMethod = lower(strtrim(string(localOptionalStructValue(cfg, "impairments.cfo_estimation_method", ""))));
if cfoEstMethod == "dmrs_two_symbol" && (pdschDmrsAddPos < 1 || puschDmrsAddPos < 1)
    error("sixgr:lls6g:config:DMRSTwoSymbolCFORequiresAdditionalDMRS", ...
        "impairments.cfo_estimation_method=dmrs_two_symbol in %s requires reference_signals.pdsch_dmrs_additional_positions>=1 and pusch_dmrs_additional_positions>=1.", ...
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

if logical(localOptionalStructValue(cfg, "output.phy_signal_diagnostic_enabled", false))
    prerequisitePaths = [ ...
        "run_control.raw_iq_capture_enable", ...
        "run_control.save_channel_tensors", ...
        "run_control.save_constellations", ...
        "output_control.save_raw_waveforms", ...
        "output_control.save_channel_snapshots", ...
        "output_control.save_constellations", ...
        "output_control.save_plots", ...
        "output.save_figures", ...
        "output.save_png"];
    missingPrerequisites = strings(0, 1);
    for path = prerequisitePaths
        if ~logical(localOptionalStructValue(cfg, path, false))
            missingPrerequisites(end+1, 1) = path; %#ok<AGROW>
        end
    end
    if ~isempty(missingPrerequisites)
        error("sixgr:lls6g:config:PHYSignalDiagnosticPrerequisites", ...
            "phy_signal_diagnostic_enabled=true in %s requires these capture/save " + ...
            "gates to be true: %s.", ...
            localCtx(ctx), strjoin(missingPrerequisites, ", "));
    end
    waveformSamples = double(localOptionalStructValue(cfg, ...
        "output.phy_signal_diagnostic_waveform_samples", 1024));
    fftLength = double(localOptionalStructValue(cfg, ...
        "output.phy_signal_diagnostic_fft_length", 1024));
    if fftLength > waveformSamples
        error("sixgr:lls6g:config:PHYSignalDiagnosticFFTWindow", ...
            "phy_signal_diagnostic_fft_length in %s must not exceed phy_signal_diagnostic_waveform_samples.", ...
            localCtx(ctx));
    end
    if abs(log2(fftLength) - round(log2(fftLength))) > 1e-12
        error("sixgr:lls6g:config:PHYSignalDiagnosticFFTPowerOfTwo", ...
            "phy_signal_diagnostic_fft_length in %s must be a power of two.", localCtx(ctx));
    end
end

if aiEnabled && localIsUnsetPolicy(localOptionalStructValue(cfg, "ai_ml.baseline_pairing", ""))
    error("sixgr:lls6g:config:AINeedsBaselineComparator", ...
        "ai_ml.enabled=true in %s requires ai_ml.baseline_pairing to name a non-AI baseline comparator.", ...
        localCtx(ctx));
end

continuousRawIQ = logical(localOptionalStructValue(cfg, ...
    "run_control.continuous_raw_iq_capture_enable", false));
if continuousRawIQ
    missingContinuousPrerequisites = strings(0,1);
    if ~logical(localOptionalStructValue(cfg, ...
            "run_control.raw_iq_capture_enable", false))
        missingContinuousPrerequisites(end+1,1) = ...
            "run_control.raw_iq_capture_enable"; %#ok<AGROW>
    end
    if ~logical(localOptionalStructValue(cfg, ...
            "output_control.save_raw_waveforms", false))
        missingContinuousPrerequisites(end+1,1) = ...
            "output_control.save_raw_waveforms"; %#ok<AGROW>
    end
    executionModel = lower(strtrim(string(localOptionalStructValue( ...
        cfg,"users.execution_model",""))));
    if executionModel ~= "slot_coupled_truth"
        missingContinuousPrerequisites(end+1,1) = ...
            "users.execution_model=slot_coupled_truth"; %#ok<AGROW>
    end
    if ~isempty(missingContinuousPrerequisites)
        error("sixgr:lls6g:config:ContinuousRawIQPrerequisites", ...
            "continuous_raw_iq_capture_enable=true in %s requires exact " + ...
            "shared-stream ownership and raw-waveform persistence: %s.", ...
            localCtx(ctx),strjoin(missingContinuousPrerequisites,", "));
    end
end
end

function localValidateOperatingPointMode(cfg, ctx)
mode = lower(strtrim(string(localOptionalStructValue(cfg, ...
    "link_adaptation.operating_point_mode", ""))));
if ~any(mode == ["fixed", "adaptive", "bounded_adaptive"])
    error("sixgr:lls6g:config:InvalidOperatingPointMode", ...
        ['link_adaptation.operating_point_mode in %s must be fixed, ' ...
        'adaptive, or bounded_adaptive.'], localCtx(ctx));
end
legacyMode = lower(strtrim(string(localOptionalStructValue(cfg, ...
    "link_adaptation.fixed_or_amc", ""))));
legacyFixed = any(legacyMode == ["fixed","fixed_mcs","configured_fixed", ...
    "disabled","off","none","false"]);
if (mode == "fixed") ~= legacyFixed
    error("sixgr:lls6g:config:OperatingPointModeConflict", ...
        ['link_adaptation.operating_point_mode=''%s'' conflicts with ' ...
        'link_adaptation.fixed_or_amc=''%s'' in %s.'], ...
        mode, legacyMode, localCtx(ctx));
end
if mode == "bounded_adaptive"
    initialMCS = double(localOptionalStructValue(cfg, ...
        "link_adaptation.initial_mcs", NaN));
    maximumMCS = double(localOptionalStructValue(cfg, ...
        "link_adaptation.maximum_mcs", NaN));
    if ~(isscalar(initialMCS) && isfinite(initialMCS) && ...
            initialMCS >= 0 && initialMCS <= 31 && initialMCS == fix(initialMCS) && ...
            isscalar(maximumMCS) && isfinite(maximumMCS) && ...
            maximumMCS >= initialMCS && maximumMCS <= 31 && ...
            maximumMCS == fix(maximumMCS))
        error("sixgr:lls6g:config:InvalidBoundedAdaptiveEnvelope", ...
            ['bounded_adaptive in %s requires integer initial_mcs and ' ...
            'maximum_mcs with 0 <= initial_mcs <= maximum_mcs <= 31.'], ...
            localCtx(ctx));
    end
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
        elem = localStructArrayElement(value, idx, fieldPath, ctx);
        localRejectUnknownSectionFields(elem, string(fieldnames(nestedRule.parameters)), elemPath, ctx);
        if ~allowPartial
            localRequireFields(elem, reqFields, elemPath, ctx);
        end
        localValidateStructRules(elem, nestedRule.parameters, elemPath, ctx, catalog, allowPartial);
    end
end
end

function elem = localStructArrayElement(value, idx, fieldPath, ctx)
% YAML mappings with heterogeneous optional fields are decoded as a cell
% array of scalar structs by the repository YAML reader. Treat that as the
% same schema type as a homogeneous MATLAB struct array, while rejecting
% mixed or non-scalar elements.
if iscell(value)
    elem = value{idx};
else
    elem = value(idx);
end
if ~builtin("isstruct", elem) || ~isscalar(elem)
    error("sixgr:lls6g:config:BadStructArrayElement", ...
        "%s(%d) in %s must be a scalar struct.", fieldPath, idx, localCtx(ctx));
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
    case "string_or_struct"
        ok = ischar(value) || (isstring(value) && isscalar(value)) || ...
            (builtin("isstruct", value) && isscalar(value));
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
        ok = isstruct(value) || isempty(value) || ...
            (iscell(value) && all(cellfun(@(x) builtin("isstruct", x) && isscalar(x), value(:))));
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

function localValidateSNRSweepRequirements(cfg, snrSweepEnabled, ctx)
if ~snrSweepEnabled
    return;
end
statePolicy = lower(strtrim(string(localOptionalStructValue(cfg, ...
    "sweeps_and_matrix.snr_sweep.state_policy", ""))));
if strlength(statePolicy) > 0 && ...
        ~ismember(statePolicy, ["independent_link_state_per_point", "continuous_runtime"])
    error("sixgr:lls6g:config:BadSNRSweepStatePolicy", ...
        "sweeps_and_matrix.snr_sweep.state_policy in %s must be independent_link_state_per_point or continuous_runtime.", ...
        localCtx(ctx));
end
initialAccessStatePolicy = lower(strtrim(string(localOptionalStructValue(cfg, ...
    "sweeps_and_matrix.snr_sweep.initial_access_state_policy", ...
    "continuous_runtime"))));
if ~ismember(initialAccessStatePolicy, ...
        ["independent_per_point", "continuous_runtime"])
    error("sixgr:lls6g:config:BadSNRSweepInitialAccessStatePolicy", ...
        "sweeps_and_matrix.snr_sweep.initial_access_state_policy in %s " + ...
        "must be independent_per_point or continuous_runtime.", ...
        localCtx(ctx));
end
snrPoints = localResolveSNRSweepGrid(cfg);
if numel(snrPoints) < 2
    error("sixgr:lls6g:config:SNRSweepNeedsAtLeastTwoPoints", ...
        "sweeps_and_matrix.snr_sweep.enabled=true in %s requires at least two finite SNR points from sweeps_and_matrix.snr_sweep.values_db or simulation.snr_db + simulation.snr_sweep_offsets_db.", ...
        localCtx(ctx));
end
end

function localValidateFixedLinkCalibrationRequirements(cfg, ctx)
if ~logical(localOptionalStructValue(cfg, "sweeps_and_matrix.fixed_link_calibration.enabled", false))
    return;
end

snrGrid = localFiniteNumericRowVector(localOptionalStructValue(cfg, "sweeps_and_matrix.fixed_link_calibration.snr_db", []));
if isempty(snrGrid)
    snrGrid = localResolveSNRSweepGrid(cfg);
end
if isempty(snrGrid)
    error("sixgr:lls6g:config:FixedLinkCalibrationRequiresSNRGrid", ...
        "sweeps_and_matrix.fixed_link_calibration.enabled=true in %s requires a finite SNR grid.", localCtx(ctx));
end

minTrials = localOptionalFiniteScalarOrNaN(cfg, "sweeps_and_matrix.fixed_link_calibration.min_trials");
maxTrials = localOptionalFiniteScalarOrNaN(cfg, "sweeps_and_matrix.fixed_link_calibration.max_trials");
confidenceLevel = localResolvedConfidenceLevel(cfg);
targetBLER = localResolvedTargetBLER(cfg);

if ~localIsFiniteIntegerAtLeast(minTrials, 1)
    error("sixgr:lls6g:config:FixedLinkCalibrationMinTrialsInvalid", ...
        "sweeps_and_matrix.fixed_link_calibration.min_trials in %s must be an integer >= 1.", localCtx(ctx));
end
if ~localIsFiniteIntegerAtLeast(maxTrials, round(minTrials))
    error("sixgr:lls6g:config:FixedLinkCalibrationTrialRangeInvalid", ...
        "sweeps_and_matrix.fixed_link_calibration.max_trials in %s must be an integer >= min_trials.", localCtx(ctx));
end
if ~(isfinite(confidenceLevel) && confidenceLevel > 0 && confidenceLevel < 1)
    error("sixgr:lls6g:config:FixedLinkCalibrationConfidenceLevelInvalid", ...
        "sweeps_and_matrix.fixed_link_calibration.confidence_level in %s must satisfy 0 < confidence_level < 1.", localCtx(ctx));
end
if ~(isfinite(targetBLER) && targetBLER > 0 && targetBLER < 1)
    error("sixgr:lls6g:config:FixedLinkCalibrationTargetBLERInvalid", ...
        "sweeps_and_matrix.fixed_link_calibration.target_bler in %s must satisfy 0 < target_bler < 1.", localCtx(ctx));
end

if logical(localOptionalStructValue(cfg, "sweeps_and_matrix.fixed_link_calibration.only", false))
    noiseMode = strtrim(string(localOptionalStructValue(cfg, "simulation.noise_operating_mode", "")));
    if noiseMode ~= "standalone_awgn_snr_argument"
        error("sixgr:lls6g:config:FixedLinkCalibrationOnlyRequiresStandaloneAWGN", ...
            "sweeps_and_matrix.fixed_link_calibration.only=true in %s requires simulation.noise_operating_mode='standalone_awgn_snr_argument'.", ...
            localCtx(ctx));
    end
end
end

function localValidateFixedLinkMasterAuthority(cfg, ctx)
campaign = localOptionalStructValue( ...
    cfg, "validation.fixed_link_campaign", struct());
if ~(isstruct(campaign) && isscalar(campaign) && ...
        logical(sixgr.util.structGet(campaign, "enabled", false)))
    return;
end
authority = lower(strtrim(string(sixgr.util.structGet( ...
    campaign, "configuration_authority", ""))));
if authority ~= "master_yaml"
    return;
end

required = [ ...
    "enabled","direction","channel_model","snr_db","mcs", ...
    "rank","layers","n_prb","min_tb_per_point","max_tb_per_point", ...
    "min_errors_for_ci","max_ci_half_width","confidence_level", ...
    "interval_method", ...
    "trials_per_drop","disable_auxiliary_signals","enable_ptrs", ...
    "fixed_reference_mode","noise_operating_mode", ...
    "pdsch_execution_profile", ...
    "link_adaptation_mode","harq_enabled","single_user_mode", ...
    "seeds","target_bler","max_target_crossing_bracket_db"];
for name = required
    if ~isfield(campaign, char(name))
        error("sixgr:lls6g:config:FixedLinkMasterFieldMissing", ...
            char("validation.fixed_link_campaign.configuration_authority=" + ...
            "'master_yaml' in %s requires field '%s'."), ...
            localCtx(ctx), name);
    end
end

intervalMethod = upper(strtrim(string(campaign.interval_method)));
if ~ismember(intervalMethod, ...
        ["CLOPPER_PEARSON_TWO_SIDED", "WILSON_TWO_SIDED"])
    error("sixgr:lls6g:config:FixedLinkIntervalMethodInvalid", ...
        char("validation.fixed_link_campaign.interval_method in %s " + ...
        "must be CLOPPER_PEARSON_TWO_SIDED or WILSON_TWO_SIDED."), ...
        localCtx(ctx));
end

maxCrossingBracket = double(campaign.max_target_crossing_bracket_db);
if ~(isscalar(maxCrossingBracket) && isfinite(maxCrossingBracket) && ...
        maxCrossingBracket > 0)
    error("sixgr:lls6g:config:FixedLinkTargetCrossingBracketInvalid", ...
        char("validation.fixed_link_campaign.max_target_crossing_bracket_db " + ...
        "in %s must be a finite positive scalar."), localCtx(ctx));
end

if ~logical(campaign.fixed_reference_mode)
    error("sixgr:lls6g:config:FixedLinkMasterNeedsFixedReference", ...
        "validation.fixed_link_campaign.fixed_reference_mode in %s must be true.", ...
        localCtx(ctx));
end
if lower(strtrim(string(campaign.noise_operating_mode))) ~= ...
        "standalone_awgn_snr_argument"
    error("sixgr:lls6g:config:FixedLinkMasterNoiseModeMismatch", ...
        char("validation.fixed_link_campaign.noise_operating_mode in %s " + ...
        "must be standalone_awgn_snr_argument."), localCtx(ctx));
end
if lower(strtrim(string(campaign.link_adaptation_mode))) ~= "fixed"
    error("sixgr:lls6g:config:FixedLinkMasterLinkAdaptationMismatch", ...
        "validation.fixed_link_campaign.link_adaptation_mode in %s must be fixed.", ...
        localCtx(ctx));
end
configuredLinkAdaptationMode = lower(strtrim(string( ...
    localOptionalStructValue(cfg, "link_adaptation.fixed_or_amc", ""))));
if configuredLinkAdaptationMode ~= ...
        lower(strtrim(string(campaign.link_adaptation_mode)))
    error("sixgr:lls6g:config:FixedLinkMasterLinkAdaptationAuthorityConflict", ...
        char("link_adaptation.fixed_or_amc and validation.fixed_link_campaign." + ...
        "link_adaptation_mode conflict in %s."), localCtx(ctx));
end
if logical(campaign.harq_enabled)
    error("sixgr:lls6g:config:FixedLinkMasterHARQUnsupported", ...
        char("validation.fixed_link_campaign.harq_enabled in %s must be " + ...
        "false because campaign trials are independent transport blocks."), ...
        localCtx(ctx));
end
if ~logical(campaign.single_user_mode)
    error("sixgr:lls6g:config:FixedLinkMasterNeedsSingleUser", ...
        "validation.fixed_link_campaign.single_user_mode in %s must be true.", ...
        localCtx(ctx));
end

configuredChannelModel = upper(strtrim(string(localOptionalStructValue( ...
    cfg, "channels.model_type", ""))));
if configuredChannelModel ~= upper(strtrim(string(campaign.channel_model)))
    error("sixgr:lls6g:config:FixedLinkMasterChannelAuthorityConflict", ...
        char("channels.model_type and " + ...
        "validation.fixed_link_campaign.channel_model conflict in %s."), ...
        localCtx(ctx));
end
configuredNoiseMode = lower(strtrim(string(localOptionalStructValue( ...
    cfg, "simulation.noise_operating_mode", ""))));
if configuredNoiseMode ~= lower(strtrim(string(campaign.noise_operating_mode)))
    error("sixgr:lls6g:config:FixedLinkMasterNoiseAuthorityConflict", ...
        char("simulation.noise_operating_mode and " + ...
        "validation.fixed_link_campaign.noise_operating_mode conflict in %s."), ...
        localCtx(ctx));
end
configuredProfile = lower(strtrim(string(localOptionalStructValue( ...
    cfg, "pdsch.execution_profile", ""))));
campaignProfile = lower(strtrim(string(campaign.pdsch_execution_profile)));
if configuredProfile ~= campaignProfile
    error("sixgr:lls6g:config:FixedLinkMasterPDSCHProfileAuthorityConflict", ...
        char("pdsch.execution_profile and validation.fixed_link_campaign." + ...
        "pdsch_execution_profile conflict in %s."), localCtx(ctx));
end
direction = lower(strtrim(string(campaign.direction)));
if any(direction == ["dl","both"]) && campaignProfile ~= "phy_calibration"
    error("sixgr:lls6g:config:FixedLinkMasterPDSCHProfileMismatch", ...
        "pdsch.execution_profile in %s must be phy_calibration for DL fixed-link execution.", ...
        localCtx(ctx));
end

configuredHARQ = logical(localOptionalStructValue(cfg, "harq.enabled", false));
if configuredHARQ ~= logical(campaign.harq_enabled)
    error("sixgr:lls6g:config:FixedLinkMasterHARQAuthorityConflict", ...
        char("harq.enabled and validation.fixed_link_campaign.harq_enabled " + ...
        "conflict in %s."), localCtx(ctx));
end
configuredPTRS = logical(localOptionalStructValue( ...
    cfg, "reference_signals.ptrs_enabled", false));
if configuredPTRS ~= logical(campaign.enable_ptrs)
    error("sixgr:lls6g:config:FixedLinkMasterPTRSAuthorityConflict", ...
        char("reference_signals.ptrs_enabled and " + ...
        "validation.fixed_link_campaign.enable_ptrs conflict in %s."), ...
        localCtx(ctx));
end
if any(direction == ["ul","both"])
    configuredPUSCHPorts = double(localOptionalStructValue( ...
        cfg, "pusch.num_antenna_ports", NaN));
    configuredUEElements = double(localOptionalStructValue( ...
        cfg, "antenna_and_array.ue_num_antenna_elements", NaN));
    if ~(isscalar(configuredPUSCHPorts) && ...
            isfinite(configuredPUSCHPorts) && ...
            configuredPUSCHPorts == fix(configuredPUSCHPorts) && ...
            configuredPUSCHPorts >= 1 && ...
            isscalar(configuredUEElements) && ...
            isfinite(configuredUEElements) && ...
            configuredUEElements >= configuredPUSCHPorts)
        error("sixgr:lls6g:config:FixedLinkMasterPUSCHAntennaAuthorityConflict", ...
            char("pusch.num_antenna_ports=%g in %s requires at least " + ...
            "that many UE antenna elements; received elements=%g."), ...
            configuredPUSCHPorts,localCtx(ctx),configuredUEElements);
    end
end
configuredUserCount = double(localOptionalStructValue( ...
    cfg, "users.n_users", NaN));
configuredUsersEnabled = logical(localOptionalStructValue( ...
    cfg, "users.enabled", false));
if ~(isscalar(configuredUserCount) && isfinite(configuredUserCount) && ...
        configuredUserCount == 1 && ~configuredUsersEnabled)
    error("sixgr:lls6g:config:FixedLinkMasterUserAuthorityConflict", ...
        char("single_user_mode=true in %s requires users.n_users=1 and " + ...
        "users.enabled=false."), localCtx(ctx));
end
expectedLayers = double(campaign.layers);
if any(direction == ["dl","both"])
    localValidateFixedLinkLayers( ...
        cfg, "mimo.max_dl_layers", expectedLayers, ctx);
end
if any(direction == ["ul","both"])
    localValidateFixedLinkLayers( ...
        cfg, "mimo.max_ul_layers", expectedLayers, ctx);
end

expectedNPRB = double(campaign.n_prb);
if any(direction == ["dl","both"])
    localValidateFixedLinkDataAllocation( ...
        cfg, "pdsch", expectedNPRB, ctx);
end
if any(direction == ["ul","both"])
    localValidateFixedLinkDataAllocation( ...
        cfg, "pusch", expectedNPRB, ctx);
end
end

function localValidateFixedLinkLayers(cfg, path, expectedLayers, ctx)
configuredLayers = double(localOptionalStructValue(cfg, path, NaN));
if ~(isscalar(expectedLayers) && isfinite(expectedLayers) && ...
        expectedLayers == fix(expectedLayers) && expectedLayers >= 1 && ...
        isscalar(configuredLayers) && isfinite(configuredLayers) && ...
        configuredLayers == expectedLayers)
    error("sixgr:lls6g:config:FixedLinkMasterLayerAuthorityConflict", ...
        char("validation.fixed_link_campaign.layers=%g conflicts with " + ...
        "%s=%g in %s."), ...
        expectedLayers, path, configuredLayers, localCtx(ctx));
end
end

function localValidateFixedLinkDataAllocation(cfg, section, expectedNPRB, ctx)
explicitSet = localOptionalStructValue(cfg, section + ".prb_set", []);
startPRB = localOptionalStructValue(cfg, section + ".prb_start", []);
numPRB = localOptionalStructValue(cfg, section + ".num_prb", []);
hasSet = ~isempty(explicitSet);
hasPair = ~isempty(startPRB) || ~isempty(numPRB);
if hasSet == hasPair
    error("sixgr:lls6g:config:FixedLinkMasterPRBAllocationMissing", ...
        char("%s in %s must configure exactly one of prb_set or the " + ...
        "prb_start/num_prb pair."), section, localCtx(ctx));
end
if hasSet
    actualNPRB = numel(double(explicitSet));
else
    if isempty(startPRB) || isempty(numPRB)
        error("sixgr:lls6g:config:FixedLinkMasterPRBAllocationIncomplete", ...
            "%s.prb_start and %s.num_prb in %s must be configured together.", ...
            section, section, localCtx(ctx));
    end
    actualNPRB = double(numPRB);
end
if ~(isscalar(expectedNPRB) && isfinite(expectedNPRB) && ...
        expectedNPRB == fix(expectedNPRB) && expectedNPRB >= 1 && ...
        isscalar(actualNPRB) && isfinite(actualNPRB) && ...
        actualNPRB == expectedNPRB)
    error("sixgr:lls6g:config:FixedLinkMasterPRBCountConflict", ...
        char("validation.fixed_link_campaign.n_prb=%g conflicts with " + ...
        "%s allocation count=%g in %s."), ...
        expectedNPRB, section, actualNPRB, localCtx(ctx));
end
end

function localValidateRunClassScenarioRequirements(cfg, ctx)
runClass = lower(strtrim(string(localOptionalStructValue(cfg, "validation.run_class", ...
    localOptionalStructValue(cfg, "validation.RunClass", "")))));
switch runClass
    case "fixed_snr_sweep_lls"
        if logical(localOptionalStructValue(cfg, ...
                "canonical_control.launch.geometry_enabled", false)) || ...
                logical(localOptionalStructValue(cfg, ...
                "validation.geometry_evidence_required", false))
            error("sixgr:lls6g:config:RunClassFixedSNRSweepDisallowsGeometry", ...
                char("validation.run_class='fixed_snr_sweep_lls' in %s " + ...
                 "requires geometry execution and geometry evidence to be disabled."), ...
                localCtx(ctx));
        end
        if ~logical(localOptionalStructValue(cfg, "sweeps_and_matrix.fixed_link_calibration.enabled", false))
            error("sixgr:lls6g:config:RunClassFixedSNRSweepNeedsCalibration", ...
                "validation.run_class='fixed_snr_sweep_lls' in %s requires sweeps_and_matrix.fixed_link_calibration.enabled=true.", ...
                localCtx(ctx));
        end
        if ~logical(localOptionalStructValue(cfg, "sweeps_and_matrix.snr_sweep.enabled", false))
            error("sixgr:lls6g:config:RunClassFixedSNRSweepNeedsSweep", ...
                "validation.run_class='fixed_snr_sweep_lls' in %s requires sweeps_and_matrix.snr_sweep.enabled=true.", ...
                localCtx(ctx));
        end
    case "ue_placement_geometry_lls"
        if logical(localOptionalStructValue(cfg, ...
                "canonical_control.launch.sweep_enabled", false)) || ...
                logical(localOptionalStructValue(cfg, ...
                "canonical_control.launch.fixed_link_campaign_enabled", false)) || ...
                logical(localOptionalStructValue(cfg, ...
                "sweeps_and_matrix.fixed_link_calibration.enabled", false))
            error("sixgr:lls6g:config:RunClassGeometryDisallowsFixedSNRSweep", ...
                char("validation.run_class='ue_placement_geometry_lls' in %s " + ...
                 "requires fixed-SNR sweep and fixed-link calibration execution to be disabled."), ...
                localCtx(ctx));
        end
        userExec = lower(strtrim(string(localOptionalStructValue(cfg, "users.execution_model", ""))));
        if userExec ~= "slot_coupled_truth"
            error("sixgr:lls6g:config:RunClassGeometryNeedsSlotCoupledTruth", ...
                "validation.run_class='ue_placement_geometry_lls' in %s requires users.execution_model='slot_coupled_truth'.", ...
                localCtx(ctx));
        end
        speedKmh = localResolvedMobilitySpeedKmh(cfg);
        if ~(isfinite(speedKmh) && speedKmh >= 0)
            error("sixgr:lls6g:config:RunClassGeometryNeedsMobilitySpeed", ...
                "validation.run_class='ue_placement_geometry_lls' in %s requires a finite mobility.ue_speed_kmh.", ...
                localCtx(ctx));
        end
        if logical(localOptionalStructValue(cfg, "sweeps_and_matrix.snr_sweep.enabled", false))
            error("sixgr:lls6g:config:RunClassGeometryDisallowsSNRSweep", ...
                "validation.run_class='ue_placement_geometry_lls' in %s requires sweeps_and_matrix.snr_sweep.enabled=false.", ...
                localCtx(ctx));
        end
end
end

function snrGrid = localResolveSNRSweepGrid(cfg)
snrGrid = localFiniteNumericRowVector(localOptionalStructValue(cfg, "sweeps_and_matrix.snr_sweep.values_db", []));
if ~isempty(snrGrid)
    return;
end
baseSNR = localOptionalFiniteScalarOrNaN(cfg, "simulation.snr_db");
offsets = localFiniteNumericRowVector(localOptionalStructValue(cfg, "simulation.snr_sweep_offsets_db", []));
if isfinite(baseSNR) && ~isempty(offsets)
    snrGrid = baseSNR + offsets;
else
    snrGrid = [];
end
end

function values = localFiniteNumericRowVector(raw)
values = [];
if isempty(raw) || ~(isnumeric(raw) || islogical(raw))
    return;
end
values = double(raw(:)).';
values = values(isfinite(values));
end

function tf = localIsFiniteIntegerAtLeast(value, minValue)
tf = isfinite(value) && value >= minValue && abs(value - round(value)) <= eps(max(abs(value), 1));
end

function value = localResolvedConfidenceLevel(cfg)
value = localOptionalFiniteScalarOrNaN(cfg, "sweeps_and_matrix.fixed_link_calibration.confidence_level");
if isfinite(value)
    return;
end
value = localOptionalFiniteScalarOrNaN(cfg, "validation.fixed_link_campaign.confidence_level");
if ~isfinite(value)
    value = 0.95;
end
end

function value = localResolvedTargetBLER(cfg)
value = localOptionalFiniteScalarOrNaN(cfg, "sweeps_and_matrix.fixed_link_calibration.target_bler");
if isfinite(value)
    return;
end
campaignTargets = localFiniteNumericRowVector(localOptionalStructValue(cfg, "validation.fixed_link_campaign.target_bler", []));
if ~isempty(campaignTargets)
    value = campaignTargets(1);
else
    value = 0.10;
end
end

function speedKmh = localResolvedMobilitySpeedKmh(cfg)
speedKmh = localOptionalFiniteScalarOrNaN(cfg, "mobility.ue_speed_kmh");
if isfinite(speedKmh)
    return;
end
speedKmh = localOptionalFiniteScalarOrNaN(cfg, "scenario.mobility.speed_kmh");
if isfinite(speedKmh)
    return;
end
speedKmh = localOptionalFiniteScalarOrNaN(cfg, "channels.mobility_kmph");
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
baseSNR = localOptionalFiniteScalarOrNaN(cfg, "simulation.snr_db");
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
    error("sixgr:lls6g:config:InitialMCSRateRequired", ...
        "%s configured initial MCS %g in %s has no defined rate in modulation.mcs_table=%s. " + ...
        "Reserved retransmission MCS rows require retained HARQ state and cannot initialize a scenario.", ...
        direction,double(mcsIndex),localCtx(ctx),tableName);
end
resolvedOrder = localQAMOrderFromValue(string(profile.Modulation));
if ~(isfinite(resolvedOrder) && resolvedOrder > 0)
    return;
end
% In strict/no-proxy validation, a fixed configured MCS profile and the
% configured modulation order must describe the same scheduled operating
% point. Capability ceilings belong in separate max-modulation fields; using
% *_modulation_order as a looser upper bound hides an actual MCS/modulation
% mismatch in browser/YAML-owned strict scenarios.
if round(double(configuredOrder)) ~= round(double(resolvedOrder))
    error("sixgr:lls6g:config:ModulationMCSConsistencyRequired", ...
        "%s modulation order %g in %s does not match modulation.mcs_table=%s, %s_mcs_index=%g, which resolves to %s per TS 38.214.", ...
        direction, double(configuredOrder), localCtx(ctx), tableName, lower(direction), double(mcsIndex), string(profile.Modulation));
    end
end

function tf = localIsUnsetPolicy(value)
txt = lower(strtrim(string(value)));
tf = strlength(txt) == 0 || any(txt == ["none", "disabled", "unspecified", "false", "off"]);
end

function localValidatePrecodingAuthority(cfg, linkDir, ctx)
% A scalar PMI/TPMI selects a codebook entry.  It is not meaningful for
% non-codebook transmission, where the scheduled precoding matrix is the
% authority.  Reject the contradiction before a waveform or grant is built.
if ismember(linkDir, ["dl", "both"])
    dlScheme = localCanonicalTransmissionScheme(localOptionalStructValue( ...
        cfg, "pdsch.transmission_scheme", ""));
    dlPMI = localOptionalStructValue(cfg, "pdsch.pmi", []);
    if dlScheme == "noncodebook" && localHasConfiguredScalarIndex(dlPMI)
        error("sixgr:lls6g:config:NonCodebookPMIAuthorityConflict", ...
            "%s", sprintf([ ...
            'pdsch.transmission_scheme=nonCodebook in %s cannot also ' ...
            'configure pdsch.pmi. Remove the scalar PMI and let the ' ...
            'scheduled non-codebook precoding matrix own the waveform.'], ...
            localCtx(ctx)));
    end
end
if ismember(linkDir, ["ul", "both"])
    ulScheme = localCanonicalTransmissionScheme(localOptionalStructValue( ...
        cfg, "pusch.transmission_scheme", ""));
    ulTPMI = localOptionalStructValue(cfg, "pusch.tpmi", []);
    if ulScheme == "noncodebook" && localHasConfiguredScalarIndex(ulTPMI)
        error("sixgr:lls6g:config:NonCodebookTPMIAuthorityConflict", ...
            "%s", sprintf([ ...
            'pusch.transmission_scheme=nonCodebook in %s cannot also ' ...
            'configure pusch.tpmi. Remove the scalar TPMI and let the ' ...
            'scheduled non-codebook precoding matrix own the waveform.'], ...
            localCtx(ctx)));
    end
end
end

function scheme = localCanonicalTransmissionScheme(raw)
scheme = lower(regexprep(strtrim(string(raw)), "[^a-zA-Z0-9]", ""));
end

function tf = localHasConfiguredScalarIndex(value)
tf = isnumeric(value) && isscalar(value) && isfinite(double(value));
end

function localValidateRandomAccessCompatibility(cfg, ctx)
if ~logical(localOptionalStructValue(cfg, "random_access.enabled", true))
    return;
end
procedureType = lower(strtrim(string(localOptionalStructValue( ...
    cfg, "random_access.procedure_type", ""))));
strictFourStep = logical(localOptionalStructValue( ...
    cfg, "random_access.four_step_ra_required", false)) || ...
    procedureType == "contention_based_four_step";
grantPolicy = localOptionalStructValue(cfg, "random_access.rar_grant", struct());
if strictFourStep || ~isempty(fieldnames(grantPolicy))
    requiredGrantFields = ["field_layout","frequency_hopping","time_resource_assignment","tpc_command"];
    for name = requiredGrantFields
        if ~isfield(grantPolicy,name)
            error("sixgr:lls6g:config:MissingRARGrantPolicy", ...
                "random_access.rar_grant.%s in %s must be explicit.",name,localCtx(ctx));
        end
    end
    if string(grantPolicy.field_layout) ~= "licensed_27bit" || ...
            ~isscalar(grantPolicy.frequency_hopping) || ...
            ~isequal(double(grantPolicy.frequency_hopping),0)
        error("sixgr:lls6g:config:UnsupportedRARGrantPolicy", ...
            "random_access.rar_grant in %s supports licensed_27bit without frequency hopping only.",localCtx(ctx));
    end
    tdra = grantPolicy.time_resource_assignment;
    tpc = grantPolicy.tpc_command;
    if ~isnumeric(tdra) || ~isreal(tdra) || ~isscalar(tdra) || ...
            ~isfinite(tdra) || tdra ~= fix(tdra) || tdra < 0 || tdra > 15 || ...
            ~isnumeric(tpc) || ~isreal(tpc) || ~isscalar(tpc) || ...
            ~isfinite(tpc) || tpc ~= fix(tpc) || tpc < 0 || tpc > 7
        error("sixgr:lls6g:config:UnsupportedRARGrantPolicy", ...
            "random_access.rar_grant in %s requires integer default-A TDRA index [0,15] and integer TPC command [0,7].",localCtx(ctx));
    end
end
if strictFourStep
    mandatoryPolicyFields = [ ...
        "random_access.msg1_fdm", ...
        "random_access.frequency_start", ...
        "random_access.ra_response_window_slots", ...
        "random_access.power_ramping_step_db", ...
        "random_access.preamble_received_target_power_dbm", ...
        "random_access.ra_rnti_policy", ...
        "random_access.prach_occasion_policy"];
    missingPolicyFields = mandatoryPolicyFields(arrayfun(@(path) ...
        isempty(localOptionalStructValue(cfg, path, [])), ...
        mandatoryPolicyFields));
    if ~isempty(missingPolicyFields)
        error("sixgr:lls6g:config:MissingStrictRAPolicy", ...
            "Strict four-step random access in %s requires explicit YAML fields: %s.", ...
            localCtx(ctx), strjoin(missingPolicyFields, ", "));
    end
    raRntiPolicy = lower(strtrim(string(localOptionalStructValue( ...
        cfg, "random_access.ra_rnti_policy", ""))));
    if raRntiPolicy ~= "ts_38_321_ra_rnti_formula"
        error("sixgr:lls6g:config:UnsupportedRARNTIPolicy", ...
            "random_access.ra_rnti_policy in %s must be ts_38_321_ra_rnti_formula.", ...
            localCtx(ctx));
    end
    occasionPolicy = lower(strtrim(string(localOptionalStructValue( ...
        cfg, "random_access.prach_occasion_policy", ""))));
    if occasionPolicy ~= "ts_38_211_configuration_index_resolution"
        error("sixgr:lls6g:config:UnsupportedPRACHOccasionPolicy", ...
            "random_access.prach_occasion_policy in %s must be ts_38_211_configuration_index_resolution.", ...
            localCtx(ctx));
    end
end
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
duplexMode = upper(strtrim(string(localOptionalStructValue(cfg, ...
    "frequency.duplex_mode", ...
    localOptionalStructValue(cfg, "random_access.duplex_mode", "")))));
centerFrequencyHz = double(localOptionalStructValue(cfg, ...
    "random_access.carrier_frequency_hz", ...
    localOptionalStructValue(cfg, "frequency.center_frequency_hz", NaN)));
configuredFrequencyRange = upper(strtrim(string( ...
    localOptionalStructValue(cfg, "random_access.frequency_range", ...
    localOptionalStructValue(cfg, "frequency.range_name", "")))));
rangeArgs = {"CenterFrequencyHz", centerFrequencyHz};
if strlength(configuredFrequencyRange) > 0
    rangeArgs = [rangeArgs, ...
        {"FrequencyRange", configuredFrequencyRange}]; %#ok<AGROW>
end
rangeInfo = sixgr.phy.frame.FrequencyRangeResolver.resolve(rangeArgs{:});
carrierScs = double(localOptionalStructValue(cfg, ...
    "random_access.carrier_scs_khz", ...
    localOptionalStructValue(cfg, "frame.scs_khz", NaN)));
nRb = double(localOptionalStructValue(cfg, ...
    "random_access.n_size_grid", ...
    localOptionalStructValue(cfg, "frequency.n_size_grid", NaN)));
try
    resolvedPrach = sixgr.phy.frame.PRACHOccasionResolver.resolve( ...
        "FrequencyRange", rangeInfo.FrequencyRange, ...
        "DuplexMode", duplexMode, ...
        "ConfigurationIndex", configurationIndex, ...
        "CarrierSubcarrierSpacingKHz", carrierScs, ...
        "CarrierCyclicPrefix", localOptionalStructValue( ...
            cfg, "frame.cp_type", "normal"), ...
        "NSizeGrid", nRb, ...
        "NStartGrid", localOptionalStructValue( ...
            cfg, "frequency.n_start_grid", 0), ...
        "NCellID", localOptionalStructValue( ...
            cfg, "random_access.n_cell_id", 0), ...
        "PRACHSubcarrierSpacingKHz", subcarrierSpacing, ...
        "SequenceIndex", localOptionalStructValue( ...
            cfg, "random_access.sequence_index", 0), ...
        "PreambleIndex", localOptionalStructValue( ...
            cfg, "random_access.preamble_index", 0), ...
        "RestrictedSet", localOptionalStructValue( ...
            cfg, "random_access.restricted_set", "UnrestrictedSet"), ...
        "ZeroCorrelationZone", localOptionalStructValue( ...
            cfg, "random_access.zero_correlation_zone", 0), ...
        "Msg1FDM", localOptionalStructValue( ...
            cfg, "random_access.msg1_fdm", 1), ...
        "Msg1FrequencyStart", localOptionalStructValue( ...
            cfg, "random_access.frequency_start", 0));
catch ME
    if localIsMATLABServiceUnavailable(ME)
        warning("sixgr:lls6g:config:PrachToolboxCompatibilityUnavailable", ...
            "Skipping nrPRACHConfig compatibility validation for %s because MATLAB services are unavailable: %s", ...
            localCtx(ctx), string(ME.message));
        return;
    end
    error("sixgr:lls6g:config:BadPrachConfigCompatibility", ...
        "random_access configuration in %s is not toolbox-compatible for configuration_index=%g and subcarrier_spacing_khz=%g: %s", ...
         localCtx(ctx), double(configurationIndex), double(subcarrierSpacing), string(ME.message));
end
effectiveFormat = upper(strtrim(string(resolvedPrach.Format)));
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
        "control_gating.prach_required=true in %s, but PRACH configuration_index=%g/subcarrier_spacing_khz=%g has no UL-safe occasion in canonical TDD state %s. Validation status: %s.", ...
        localCtx(ctx), double(configurationIndex), double(subcarrierSpacing), string(fs.TDDPattern), ...
        status);
end
end

function tf = localIsMATLABServiceUnavailable(ME)
msg = lower(string(ME.message));
id = lower(string(ME.identifier));
tf = contains(msg, "error 5006") || ...
    contains(msg, "services required to run matlab") || ...
    ((contains(id, "license") || contains(id, "service")) && contains(msg, "matlab"));
end
