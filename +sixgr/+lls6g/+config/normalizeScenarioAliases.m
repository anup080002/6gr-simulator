function cfg = normalizeScenarioAliases(cfg, varargin)
%NORMALIZESCENARIOALIASES Synchronize extended top-level 6G sections with legacy runtime sections.

ip = inputParser;
ip.addRequired("cfg", @(x)builtin("isstruct", x) && isscalar(x));
ip.addParameter("SourceFiles", strings(0,1), @(x)isstring(x) || iscellstr(x) || ischar(x));
ip.addParameter("ConfigPath", "", @(x)ischar(x) || isstring(x));
ip.parse(cfg, varargin{:});
opt = ip.Results;

newBase = localNewDefaults();
oldBase = localLegacyDefaults();

cfg = localEnsureConfigInheritance(cfg, string(opt.SourceFiles(:)), string(opt.ConfigPath));

cfg = localSyncValue(cfg, newBase, oldBase, "meta.scenario_id", "meta.scenario_id", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "meta.scenario_name", "meta.description", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "meta.scenario_family", "meta.scenario_group", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "meta.author", "meta.owner", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "meta.study_status", "meta.maturity_tag", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "run_control.seed", "simulation.random_seed", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "run_control.deterministic_mode", "simulation.deterministic_mode", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "global_radio_scope.carrier_frequency_hz", "frequency.center_frequency_hz", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "global_radio_scope.frequency_range_label", "frequency.range_name", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "global_radio_scope.channel_bandwidth_hz", "frequency.bandwidth_hz", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "global_radio_scope.simulation_bandwidth_hz", "frequency.bandwidth_hz", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "global_radio_scope.duplex_mode", "frequency.duplex_mode", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "global_radio_scope.scs_hz", "frame.scs_khz", "hz_to_khz");
cfg = localSyncValue(cfg, newBase, oldBase, "global_radio_scope.cp_type", "frame.cp_type", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "global_radio_scope.sample_rate_hz", "waveform.sample_rate_hz", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "global_radio_scope.fft_size", "waveform.fft_size", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "frame_timing.tdd_pattern", "frame.tdd_pattern", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "frame_timing.special_slot_downlink_symbols", "frame.special_slot_downlink_symbols", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "frame_timing.ul_dl_guard_symbols", "frame.ul_dl_guard_symbols", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "frame_timing.special_slot_uplink_symbols", "frame.special_slot_uplink_symbols", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "deployment_topology.num_ues", "users.n_users", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "mobility.ue_speed_kmh", "channels.mobility_kmph", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "mobility.spatial_consistency_flag", "channels.spatial_consistency_enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "antenna_and_array.bs_num_antenna_elements", "mimo.n_tx_ant", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "antenna_and_array.ue_num_antenna_elements", "mimo.n_rx_ant", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "antenna_and_array.digital_precoder_family", "mimo.precoder_type", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "power_and_rf_frontend.bs_tx_power_dbm", "energy_efficiency.tx_power_dbm", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "waveform.dl_waveform", "waveform.dl_waveform", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "waveform.ul_waveform", "waveform.ul_waveform", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "waveform.transform_precoding", "waveform.transform_precoding_enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "waveform.windowing", "waveform.windowing_enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "channel_model.model_family", "channels.model_type", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "channel_model.scenario_label", "channels.profile", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "channel_model.delay_spread_ns", "channels.delay_spread_ns", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "channel_model.doppler_hz", "channels.doppler_hz", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "channel_model.doppler_source_mode", "channels.doppler_source_mode", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "mimo_and_beam_management.beam_sweeping", "mimo.beam_sweep_enabled", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "mimo_and_beam_management.rank_set", "mimo.n_layers", "first_numeric");
  cfg = localSyncValue(cfg, newBase, oldBase, "mimo_and_beam_management.codebook_family", "mimo.codebook_type", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "mimo_and_beam_management.mtrp_coordination", "mimo.mtrp_ready", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "csi_acquisition_and_reporting.cqi_policy", "reference_signals.cqi_reporting_enabled", "policy_to_bool");
  cfg = localSyncValue(cfg, newBase, oldBase, "csi_acquisition_and_reporting.pmi_policy", "reference_signals.pmi_reporting_enabled", "policy_to_bool");
  cfg = localSyncValue(cfg, newBase, oldBase, "csi_acquisition_and_reporting.ri_policy", "reference_signals.ri_reporting_enabled", "policy_to_bool");
  cfg = localSyncValue(cfg, newBase, oldBase, "csi_acquisition_and_reporting.cri_policy", "reference_signals.cri_reporting_enabled", "policy_to_bool");
  cfg = localSyncValue(cfg, newBase, oldBase, "csi_acquisition_and_reporting.channel_state_information_mode", "reference_signals.csi_feedback_mode", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "csi_acquisition_and_reporting.pmi_codebook_mode", "reference_signals.pmi_codebook_mode", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "csi_acquisition_and_reporting.dl_csi_enabled", "reference_signals.csi_reporting_enabled", "identity");
  cfg = localSyncValue(cfg, newBase, oldBase, "channel_coding.data_channel_family", "coding.data_code_type", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "channel_coding.control_channel_family", "coding.control_code_type", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "channel_coding.ldpc_base_graph", "coding.base_graph", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "harq.enabled", "harq.enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "harq.process_count", "harq.process_count", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "harq.rv_sequence", "harq.rv_sequence", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "harq.combining_mode", "harq.combining_mode", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "ai_ml.enabled", "ai_ml.enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "ai_ml.use_case", "ai_ml.use_case", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "ai_ml.model_name", "ai_ml.model_id", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "ai_ml.fallback_mode", "ai_ml.fallback_enabled", "string_to_bool");
cfg = localSyncValue(cfg, newBase, oldBase, "energy_and_complexity.throughput_per_watt", "kpis.energy_per_bit", "bool_to_metric");
cfg = localSyncValue(cfg, newBase, oldBase, "kpi_spec.mandatory_kpis", "kpis", "kpi_list_to_struct");
cfg = localSyncValue(cfg, newBase, oldBase, "output_control.save_intermediate", "logging.save_intermediate", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "output_control.save_plots", "output.save_figures", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "output_control.save_plots", "output.save_png", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "output_control.save_resolved_config", "output.save_yaml_snapshot", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "output_control.save_resolved_config", "output.save_json_snapshot", "identity");

cfg = localSyncNestedFlag(cfg, newBase, oldBase, "signals_and_channels_common.ssb.enable_flag", "reference_signals.ssb_enabled");
cfg = localSyncNestedFlag(cfg, newBase, oldBase, "signals_and_channels_common.pbch.enable_flag", "reference_signals.pbch_enabled");
cfg = localSyncNestedFlag(cfg, newBase, oldBase, "reference_signals.pdcch_dmrs.enabled", "reference_signals.pdcch_dmrs_enabled");
cfg = localSyncNestedFlag(cfg, newBase, oldBase, "reference_signals.nzp_csi_rs.enabled", "reference_signals.csi_rs_enabled");
cfg = localSyncNestedFlag(cfg, newBase, oldBase, "reference_signals.srs.enabled", "reference_signals.srs_enabled");
cfg = localSyncNestedFlag(cfg, newBase, oldBase, "reference_signals.trs.enabled", "reference_signals.trs_enabled");
cfg = localSyncNestedFlag(cfg, newBase, oldBase, "reference_signals.tracking_rs.enabled", "reference_signals.tracking_rs_enabled");
cfg = localSyncNestedFlag(cfg, newBase, oldBase, "reference_signals.ptrs.enabled", "reference_signals.ptrs_enabled");
cfg = localSyncValue(cfg, newBase, oldBase, "reference_signals.pdsch_dmrs.num_ports", "reference_signals.pdsch_dmrs_ports", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "reference_signals.pusch_dmrs.num_ports", "reference_signals.pusch_dmrs_ports", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "reference_signals.srs.num_ports", "reference_signals.srs_ports", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "reference_signals.srs.sequence_type", "reference_signals.srs_sequence_family", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "reference_signals.srs.periodicity", "reference_signals.srs_periodicity_ms", "numeric_string");
cfg = localSyncValue(cfg, newBase, oldBase, "pdcch.enabled", "control.pdcch_enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "pdcch.aggregation_levels", "control.aggregation_levels", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "pucch.enabled", "control.pucch_enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "prach.enabled", "random_access.enabled", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "prach.sequence_family", "random_access.prach_sequence_family", "identity");
cfg = localSyncValue(cfg, newBase, oldBase, "prach.format_set", "random_access.prach_format", "first_string");
cfg = localApplyDerivedRadioAliases(cfg, newBase);
end

function cfg = localEnsureConfigInheritance(cfg, sourceFiles, configPath)
parents = strings(0,1);
if numel(sourceFiles) > 1
    parents = sourceFiles(1:end-1);
end
prov = struct();
prov.source_files = cellstr(sourceFiles);
prov.config_path = char(configPath);
prov.resolved_at_loader = true;
prov.source_kind = char(localInferSourceKind(configPath, sourceFiles));
cfg = sixgr.util.structSet(cfg, "config_inheritance.parents", cellstr(parents));
cfg = sixgr.util.structSet(cfg, "config_inheritance.merge_policy", "deep_merge_last_writer_wins");
cfg = sixgr.util.structSet(cfg, "config_inheritance.locked_fields", cell(0,1));
cfg = sixgr.util.structSet(cfg, "config_inheritance.overridden_fields", cell(0,1));
cfg = sixgr.util.structSet(cfg, "config_inheritance.provenance", prov);
end

function kind = localInferSourceKind(configPath, sourceFiles)
kind = "scenario_config_file";
if localIsBrowserOverlayPath(configPath)
    kind = "browser_runtime_overlay";
    return;
end
for i = 1:numel(sourceFiles)
    if localIsBrowserOverlayPath(sourceFiles(i))
        kind = "browser_runtime_overlay";
        return;
    end
end
end

function tf = localIsBrowserOverlayPath(candidate)
candidate = string(candidate);
tf = false;
if strlength(candidate) == 0
    return;
end
[~, name, ext] = fileparts(char(candidate));
tf = startsWith(string(name), "__web_runtime_", "IgnoreCase", true) && any(strcmpi(string(ext), [".yaml",".yml",".json"]));
end

function cfg = localSyncNestedFlag(cfg, newBase, oldBase, newPath, oldPath)
cfg = localSyncValue(cfg, newBase, oldBase, newPath, oldPath, "identity");
end

function cfg = localApplyDerivedRadioAliases(cfg, newBase)
scsKHz = double(sixgr.util.structGet(cfg, "frame.scs_khz", NaN));
if ~(isfinite(scsKHz) && scsKHz > 0)
    return;
end

mu = log2(scsKHz / 15);
if isfinite(mu)
    mu = round(mu);
end
if ~(isfinite(mu) && mu >= 0)
    return;
end

slotDurationMs = 1 / 2^double(mu);
slotsPerFrame = 10 * 2^double(mu);

cfg = localReplaceIfDefaultOrMissing(cfg, newBase, "global_radio_scope.scs_hz", scsKHz * 1e3);
cfg = localReplaceIfDefaultOrMissing(cfg, newBase, "global_radio_scope.numerology_mu", mu);
cfg = localReplaceIfDefaultOrMissing(cfg, newBase, "frame_timing.slot_duration_ms", slotDurationMs);
cfg = localReplaceIfDefaultOrMissing(cfg, newBase, "frame_timing.slots_per_frame", slotsPerFrame);
cfg = localReplaceIfDefaultOrMissing(cfg, newBase, "frame_timing.symbols_per_slot", 14);

carrierGrid = double(sixgr.util.structGet(cfg, "frequency.n_size_grid", NaN));
activeMode = lower(strtrim(string(sixgr.util.structGet(cfg, "bandwidth_operation.active_bandwidth_mode", "fullband"))));
supportsPartial = logical(sixgr.util.structGet(cfg, "bandwidth_operation.supports_partial_band_activation", false));
if isfinite(carrierGrid) && carrierGrid > 0 && (~supportsPartial || activeMode == "fullband")
    cfg = localReplaceIfDefaultOrMissing(cfg, newBase, "resource_grid.num_rbs", round(carrierGrid));
end
end

function cfg = localReplaceIfDefaultOrMissing(cfg, baseCfg, pathStr, value)
current = sixgr.util.structGet(cfg, pathStr, []);
baseValue = sixgr.util.structGet(baseCfg, pathStr, []);
if isempty(current) || isequaln(current, baseValue)
    cfg = sixgr.util.structSet(cfg, pathStr, value);
end
end

function cfg = localSyncValue(cfg, newBase, oldBase, newPath, oldPath, mode)
newVal = sixgr.util.structGet(cfg, newPath, []);
oldVal = sixgr.util.structGet(cfg, oldPath, []);
newBaseVal = sixgr.util.structGet(newBase, newPath, []);
oldBaseVal = sixgr.util.structGet(oldBase, oldPath, []);

newDiff = ~isequaln(newVal, newBaseVal);
oldDiff = ~isequaln(oldVal, oldBaseVal);

newToOld = localConvert(newVal, mode, "new_to_old");
oldToNew = localConvert(oldVal, mode, "old_to_new");

if newDiff && ~oldDiff
    cfg = sixgr.util.structSet(cfg, oldPath, newToOld);
elseif oldDiff && ~newDiff
    cfg = sixgr.util.structSet(cfg, newPath, oldToNew);
elseif newDiff && oldDiff
    if ~isequaln(oldVal, newToOld) && ~isequaln(newVal, oldToNew)
        error("sixgr:lls6g:config:AliasConflict", ...
            "Conflicting values between '%s' and '%s'. Use one canonical setting path.", newPath, oldPath);
    end
end
end

function out = localConvert(value, mode, direction)
switch mode
    case "identity"
        out = value;
    case "hz_to_khz"
        if direction == "new_to_old"
            out = double(value) / 1e3;
        else
            out = double(value) * 1e3;
        end
    case "first_numeric"
        if isnumeric(value) && ~isempty(value)
            if direction == "new_to_old"
                out = double(value(1));
            else
                out = double(value);
            end
        else
            out = value;
        end
    case "first_string"
        if (isstring(value) || iscellstr(value)) && ~isempty(value)
            if direction == "new_to_old"
                out = char(string(value(1)));
            else
                out = string(value);
            end
        else
            out = value;
        end
    case "string_to_bool"
        if direction == "new_to_old"
            out = ~ismember(lower(string(value)), ["disabled","none","off","false"]);
        else
            if logical(value)
                out = "enabled";
            else
                out = "disabled";
            end
        end
    case "bool_to_metric"
        if direction == "new_to_old"
            out = logical(value);
        else
            out = logical(value);
        end
    case "policy_to_bool"
        if direction == "new_to_old"
            out = ~ismember(lower(string(value)), ["disabled","none","off","false"]);
        else
            if logical(value)
                out = "baseline";
            else
                out = "disabled";
            end
        end
    case "kpi_list_to_struct"
        if direction == "new_to_old"
            out = localKPIListToStruct(value);
        else
            out = value;
        end
    case "numeric_string"
        if direction == "new_to_old"
            numericValue = str2double(string(value));
            if isfinite(numericValue)
                out = numericValue;
            else
                out = value;
            end
        else
            out = char(string(value));
        end
    otherwise
        out = value;
end
end

function s = localKPIListToStruct(value)
s = struct();
if isstring(value) || iscellstr(value)
    items = string(value(:));
    for i = 1:numel(items)
        key = matlab.lang.makeValidName(char(items(i)));
        s.(key) = true;
    end
elseif builtin("isstruct", value)
    s = value;
end
end

function cfg = localNewDefaults()
persistent cached
if isempty(cached)
    cached = struct();
    paths = localNewDefaultsPaths();
    for i = 1:numel(paths)
        raw = sixgr.lls6g.config.readConfigFile(paths(i));
        if isfield(raw, "inherits")
            raw = rmfield(raw, "inherits");
        end
        cached = sixgr.util.mergeStruct(cached, raw);
    end
end
cfg = cached;
end

function cfg = localLegacyDefaults()
persistent cached
if isempty(cached)
    raw = sixgr.lls6g.config.readConfigFile(localLegacyDefaultsPath());
    if isfield(raw, "inherits")
        raw = rmfield(raw, "inherits");
    end
    cached = raw;
end
cfg = cached;
end

function paths = localNewDefaultsPaths()
root = localRepoRoot();
paths = [ ...
    string(fullfile(root, "simulator", "configs", "defaults", "top_level_required_sections_01.yaml"))
    string(fullfile(root, "simulator", "configs", "defaults", "top_level_required_sections_02.yaml"))
    string(fullfile(root, "simulator", "configs", "defaults", "top_level_required_sections_03.yaml"))
    ];
end

function p = localLegacyDefaultsPath()
root = localRepoRoot();
p = fullfile(root, "simulator", "configs", "defaults", "global.yaml");
end

function root = localRepoRoot()
here = fileparts(mfilename("fullpath"));
root = fileparts(fileparts(fileparts(here)));
end
