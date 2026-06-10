(function () {
  "use strict";

  const CATALOG_URL = "../simulator/configs/schema/parameter_constraints.json";

  function catalogUrls() {
    const productData = window.SIXGR_PRODUCT_DATA || {};
    const urls = [
      productData.parameter_constraints_api_url,
      "/api/parameter-constraints",
      CATALOG_URL
    ].filter((item) => typeof item === "string" && item.trim());
    return [...new Set(urls)];
  }

  const DEFAULT_CONFIG = {
    meta: {
      scenario_id: "LLS_4GHz_100MHz_19S3_100UE_UMa",
      study_mode: "baseline",
      run_profile: "Baseline"
    },
    run_control: {
      execution_mode: "LLS",
      random_seed_master: 73030,
      num_drops: 20,
      warmup_ms: 200,
      measurement_ms: 1000
    },
    frequency: {
      range_name: "FR1",
      center_frequency_hz: 4000000000,
      bandwidth_hz: 100000000
    },
    frame: {
      numerology_mu: 1,
      scs_khz: 30,
      cp_type: "normal",
      tdd_pattern: "DDDSU",
      special_slot_downlink_symbols: 12,
      ul_dl_guard_symbols: 1,
      special_slot_uplink_symbols: 1
    },
    phy: {
      carrier: { NSizeGrid: 273 },
      duplex: { mode: "TDD", tddPattern: "DDDSU" }
    },
    waveform: {
      dl: "CP-OFDM",
      ul: "CP-OFDM",
      fft_size: 4096,
      transform_precoding_enabled: false
    },
    scenario: {
      layout: {
        nSites: 19,
        nSectorsPerSite: 3,
        interSiteDistance_m: 600,
        wrapAround: true
      },
      bs: {
        nTxAnt: 64,
        nRxAnt: 64,
        antenna: { type: "upa" },
        txPower_dBm: 46,
        noiseFigure_dB: 5
      },
      ue: {
        nUE: 100,
        nTxAnt: 2,
        nRxAnt: 4,
        txPower_dBm: 23,
        noiseFigure_dB: 7,
        distribution: { indoorFraction: 0.2 }
      },
      mobility: { speed_kmh: 3, model: "mixed" }
    },
    traffic: {
      service_class: "eMBB",
      traffic_mix_mode: "fixed_mix",
      dl_ul_ratio: "80/20",
      queue_depth_bytes: 5000000,
      latency_budget_ms: 20,
      packet_model: "class_based"
    },
    scheduler: {
      scheduler_type: "pf",
      frequency_domain_scheduling_enable: true,
      beam_aware_scheduler_enable: true,
      fairness_window_ms: 100
    },
    harq: {
      enable: true,
      n_harq_processes: 16,
      max_retransmissions: 4,
      k1: 10,
      rv_sequence: [0, 2, 3, 1],
      soft_combining_enable: true
    },
    link_adaptation: {
      fixed_or_amc: "amc",
      domain: "wideband",
      cqi_table: "table2",
      target_bler_dl: 0.1,
      target_bler_ul: 0.1,
      outer_loop_flag: true,
      inner_loop_flag: true,
      olla_step_up: 0.1,
      olla_step_down: 0.0111,
      bootstrap_cqi_mode: "runtime_srs_or_csi",
      pdsch_link_adaptation_policy: "cqi_olla",
      pusch_link_adaptation_policy: "srs_cqi_olla"
    },
    modulation: {
      max_modulation_dl: "256QAM",
      max_modulation_ul: "64QAM",
      dl_modulation: "qam64",
      ul_modulation: "64QAM",
      mcs_table: "qam256_table2",
      dl_mcs_index: 1,
      ul_mcs_index: 1
    },
    mimo: {
      mode: "MU-MIMO",
      n_layers: 2,
      max_ul_layers: 1,
      beam_management_enable: true,
      beam_codebook_size: 32,
      beam_update_period_ms: 10,
      digital_precoder_family: "zf"
    },
    pdcch: {
      enabled: true,
      coreset_id: 0,
      coreset_duration_symbols: 2,
      blind_decode_limit: 44
    },
    prach: {
      enable: true,
      format: "B4",
      configuration_index: 167,
      sequence_length: 139,
      periodicity_ms: 20,
      preamble_count: 64,
      zero_correlation_zone: 8,
      detection_threshold_mode: "fa_probability_calibrated",
      target_false_alarm_probability: 0.001
    },
    reference_signals: {
      ssb_enabled: true,
      csi_rs_enabled: true,
      srs_enabled: true,
      trs_enabled: true,
      ptrs_enabled: true,
      pdsch_dmrs_ports: 2,
      pusch_dmrs_ports: 1,
      srs_ports: 2,
      srs_periodicity_ms: 10,
      csi_feedback_mode: "wideband_periodic",
      channel_estimation_mode: "realistic_baseline",
      receiver_example: "mmse_irc"
    },
    antenna_and_array: {
      bs_array_type: "upa",
      num_phy_antenna_elements: 64
    },
    channels: {
      model: "TR38901",
      profile: "UMa",
      pathloss_model: "nrPathLoss",
      doppler_hz: 70,
      delay_spread_ns: 300,
      shadowing_enabled: true,
      o2i_enabled: true,
      spatial_consistency: true,
      interference_model: "full_per_link_channel_waveform_sum",
      noise_mode: "receiver_noise_figure_thermal_noise"
    },
    impairments: {
      phase_noise_enabled: true,
      cfo_enabled: true,
      timing_offset_enabled: true,
      iq_imbalance_enabled: true,
      pa_nonlinearity_enabled: true
    },
    output: {
      persistence_mode: "both",
      canonical_artifacts: true,
      raw_iq_capture: false,
      constellation_save: true,
      energy_trace: true,
      compare_runs_support: true
    }
  };

  const FIELD_SECTIONS = {
    scenario: {
      title: "Scenario",
      icon: "SCN",
      fields: [
        { label: "Scenario ID", path: "meta.scenario_id", type: "text", required: true },
        { label: "Study mode", path: "meta.study_mode", type: "select", options: ["smoke", "debug", "baseline", "campaign", "publication"] },
        { label: "Execution mode", path: "run_control.execution_mode", type: "select", options: ["LLS", "SLS", "E2E"], readonly: true, hint: "Only LLS launch is currently fully wired." },
        { label: "Random seed master", path: "run_control.random_seed_master", type: "number" },
        { label: "Num drops", path: "run_control.num_drops", type: "number", min: 1 },
        { label: "Warmup window", path: "run_control.warmup_ms", type: "number", unit: "ms" },
        { label: "Measurement window", path: "run_control.measurement_ms", type: "number", unit: "ms" }
      ]
    },
    geometry: {
      title: "Scenario / Geometry",
      icon: "GEO",
      fields: [
        { label: "Num sites", path: "scenario.layout.nSites", type: "number", min: 1 },
        { label: "Sectors per site", path: "scenario.layout.nSectorsPerSite", type: "select", options: [1, 3, 6] },
        { label: "Inter-site distance", path: "scenario.layout.interSiteDistance_m", type: "number", unit: "m" },
        { label: "Wrap-around", path: "scenario.layout.wrapAround", type: "boolean" },
        { label: "UE count", path: "scenario.ue.nUE", type: "number", min: 1 },
        { label: "Indoor UE fraction", path: "scenario.ue.distribution.indoorFraction", type: "number", min: 0, max: 1 },
        { label: "Mobility speed", path: "scenario.mobility.speed_kmh", type: "number", unit: "km/h" }
      ]
    },
    waveform: {
      title: "Waveform / Carrier",
      icon: "WF",
      fields: [
        { label: "Frequency range", path: "frequency.range_name", type: "select", options: ["FR1", "FR2", "FR3"], required: true },
        { label: "Center frequency", path: "frequency.center_frequency_hz", type: "number", unit: "Hz" },
        { label: "Bandwidth", path: "frequency.bandwidth_hz", type: "select", options: [5000000, 10000000, 15000000, 20000000, 25000000, 30000000, 40000000, 50000000, 60000000, 70000000, 80000000, 90000000, 100000000, 200000000, 400000000], unit: "Hz" },
        { label: "SCS", path: "frame.scs_khz", type: "select", options: [15, 30, 60, 120, 240, 480, 960], unit: "kHz" },
        { label: "Cyclic prefix", path: "frame.cp_type", type: "select", options: ["normal", "extended"] },
        { label: "NRB / NSizeGrid", path: "phy.carrier.NSizeGrid", type: "number", readonly: true },
        { label: "FFT size", path: "waveform.fft_size", type: "number", readonly: true },
        { label: "Duplex mode", path: "phy.duplex.mode", type: "select", options: ["TDD", "FDD"] },
        { label: "TDD pattern", path: "phy.duplex.tddPattern", type: "text" },
        { label: "DL waveform", path: "waveform.dl", type: "select", options: ["CP-OFDM"] },
        { label: "UL waveform", path: "waveform.ul", type: "select", options: ["CP-OFDM", "DFT-s-OFDM"] },
        { label: "Transform precoding", path: "waveform.transform_precoding_enabled", type: "boolean" }
      ]
    },
    traffic: {
      title: "Traffic / QoS",
      icon: "TRF",
      fields: [
        { label: "Service class", path: "traffic.service_class", type: "select", options: ["eMBB", "URLLC", "XR", "mMTC"] },
        { label: "Traffic mix", path: "traffic.traffic_mix_mode", type: "select", options: ["fixed_mix", "full_buffer", "trace_replay"] },
        { label: "DL/UL asymmetry", path: "traffic.dl_ul_ratio", type: "text" },
        { label: "Queue depth", path: "traffic.queue_depth_bytes", type: "number", unit: "bytes" },
        { label: "Latency budget", path: "traffic.latency_budget_ms", type: "number", unit: "ms" },
        { label: "Packet model", path: "traffic.packet_model", type: "select", options: ["class_based", "poisson", "trace_replay"] }
      ]
    },
    mac: {
      title: "MAC / Scheduler",
      icon: "MAC",
      fields: [
        { label: "Scheduler type", path: "scheduler.scheduler_type", type: "select", options: ["pf", "rr", "max_cqi", "qos_pf"] },
        { label: "Frequency-domain scheduling", path: "scheduler.frequency_domain_scheduling_enable", type: "boolean" },
        { label: "Beam-aware scheduling", path: "scheduler.beam_aware_scheduler_enable", type: "boolean" },
        { label: "HARQ enable", path: "harq.enable", type: "boolean" },
        { label: "HARQ processes", path: "harq.n_harq_processes", type: "number", min: 1, max: 16 },
        { label: "HARQ K1", path: "harq.k1", type: "number", min: 1 },
        { label: "Target BLER DL", path: "link_adaptation.target_bler_dl", type: "number", min: 0.001, max: 0.5 },
        { label: "OLLA step up", path: "link_adaptation.olla_step_up", type: "number", unit: "dB" },
        { label: "OLLA step down", path: "link_adaptation.olla_step_down", type: "number", unit: "dB", readonly: true },
        { label: "CQI table", path: "link_adaptation.cqi_table", type: "select", options: ["table1", "table2", "table3"] }
      ]
    },
    l1: {
      title: "L1 / PHY",
      icon: "PHY",
      fields: [
        { label: "DL max modulation", path: "modulation.max_modulation_dl", type: "select", options: ["QPSK", "16QAM", "64QAM", "256QAM"] },
        { label: "UL modulation", path: "modulation.ul_modulation", type: "select", options: ["PI/2-BPSK", "QPSK", "16QAM", "64QAM", "256QAM"] },
        { label: "MCS table", path: "modulation.mcs_table", type: "select", options: ["qam64_table1", "qam256_table2", "qam64_low_se_table3", "transform_precoding_table4"] },
        { label: "DL MCS bootstrap", path: "modulation.dl_mcs_index", type: "number", min: 0, max: 28 },
        { label: "UL MCS bootstrap", path: "modulation.ul_mcs_index", type: "number", min: 0, max: 28 },
        { label: "MIMO mode", path: "mimo.mode", type: "select", options: ["SISO", "SU-MIMO", "MU-MIMO", "Massive-MIMO"] },
        { label: "MIMO layers", path: "mimo.n_layers", type: "number", min: 1, max: 8 },
        { label: "PDCCH enabled", path: "pdcch.enabled", type: "boolean" },
        { label: "CORESET ID", path: "pdcch.coreset_id", type: "number" },
        { label: "PRACH enabled", path: "prach.enable", type: "boolean" },
        { label: "PRACH format", path: "prach.format", type: "select", options: ["Format0", "Format1", "Format2", "Format3", "A1", "A2", "A3", "B1", "B2", "B3", "B4", "C0", "C2", "C0_6G", "C2_6G"] },
        { label: "PRACH sequence length", path: "prach.sequence_length", type: "select", options: [839, 139] },
        { label: "PRACH preambles", path: "prach.preamble_count", type: "number", min: 1, max: 64 }
      ]
    },
    antenna: {
      title: "Antenna / Air Interface",
      icon: "AIR",
      fields: [
        { label: "BS array type", path: "antenna_and_array.bs_array_type", type: "select", options: ["omni", "ula", "upa", "massive_mimo_panel"] },
        { label: "BS antenna elements", path: "antenna_and_array.num_phy_antenna_elements", type: "select", options: [1, 2, 4, 8, 16, 32, 64, 128, 256, 512] },
        { label: "BS TX antennas", path: "scenario.bs.nTxAnt", type: "number", min: 1 },
        { label: "UE RX antennas", path: "scenario.ue.nRxAnt", type: "number", min: 1 },
        { label: "Channel model", path: "channels.model", type: "select", options: ["AWGN", "TDL", "CDL", "TR38901"] },
        { label: "Channel profile", path: "channels.profile", type: "select", options: ["AWGN", "TDL-A", "TDL-B", "TDL-C", "TDL-D", "TDL-E", "CDL-A", "CDL-B", "CDL-C", "CDL-D", "CDL-E", "UMa", "UMi", "RMa", "InH", "InF"] },
        { label: "Pathloss model", path: "channels.pathloss_model", type: "select", options: ["nrPathLoss", "TR38901_UMa", "TR38901_UMi", "TR38901_RMa", "TR38901_InH", "ABG_explicit_study", "TR38901_candidate_extrapolation"] },
        { label: "Shadowing", path: "channels.shadowing_enabled", type: "boolean" },
        { label: "O2I", path: "channels.o2i_enabled", type: "boolean" },
        { label: "Spatial consistency", path: "channels.spatial_consistency", type: "boolean" },
        { label: "Interference model", path: "channels.interference_model", type: "select", options: ["full_per_link_channel_waveform_sum", "muted", "single_cell"] },
        { label: "Noise mode", path: "channels.noise_mode", type: "select", options: ["receiver_noise_figure_thermal_noise"] }
      ]
    },
    outputs: {
      title: "Outputs / Profiles",
      icon: "OUT",
      fields: [
        { label: "Output persistence", path: "output.persistence_mode", type: "select", options: ["both", "database", "results_folder"] },
        { label: "Canonical artifacts", path: "output.canonical_artifacts", type: "boolean" },
        { label: "Raw IQ capture", path: "output.raw_iq_capture", type: "boolean" },
        { label: "Constellation save", path: "output.constellation_save", type: "boolean" },
        { label: "Energy trace", path: "output.energy_trace", type: "boolean" },
        { label: "Compare-runs support", path: "output.compare_runs_support", type: "boolean" }
      ]
    }
  };

  function clone(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function pathParts(path) {
    return String(path || "").split(".").filter(Boolean);
  }

  function getPath(obj, path, fallback) {
    let cur = obj;
    for (const part of pathParts(path)) {
      if (cur == null || typeof cur !== "object" || !(part in cur)) return fallback;
      cur = cur[part];
    }
    return cur;
  }

  function setPath(obj, path, value) {
    const parts = pathParts(path);
    let cur = obj;
    parts.slice(0, -1).forEach((part) => {
      if (cur[part] == null || typeof cur[part] !== "object" || Array.isArray(cur[part])) cur[part] = {};
      cur = cur[part];
    });
    cur[parts[parts.length - 1]] = value;
  }

  function normalizeScalar(value) {
    if (value === "true") return true;
    if (value === "false") return false;
    if (value === "") return "";
    if (typeof value === "string" && /^-?\d+(\.\d+)?([eE][+-]?\d+)?$/.test(value.trim())) {
      return Number(value);
    }
    return value;
  }

  function yamlScalar(value) {
    if (value === null) return "null";
    if (typeof value === "boolean" || typeof value === "number") return String(value);
    if (Array.isArray(value)) return `[${value.map(yamlScalar).join(", ")}]`;
    return JSON.stringify(String(value));
  }

  function toYaml(value, indent) {
    const pad = " ".repeat(indent || 0);
    if (value == null || typeof value !== "object" || Array.isArray(value)) return yamlScalar(value);
    return Object.entries(value).map(([key, item]) => {
      if (item && typeof item === "object" && !Array.isArray(item)) {
        return `${pad}${key}:\n${toYaml(item, (indent || 0) + 2)}`;
      }
      return `${pad}${key}: ${yamlScalar(item)}`;
    }).join("\n");
  }

  class ConstraintEngineImpl {
    constructor() {
      this.catalog = { schema_version: "unloaded", rules: [] };
      this.loaded = false;
    }

    async load() {
      if (this.loaded) return this.catalog;
      const errors = [];
      for (const url of catalogUrls()) {
        try {
          const response = await fetch(url, { cache: "no-store" });
          if (!response.ok) throw new Error(`HTTP ${response.status}`);
          this.catalog = await response.json();
          this.catalog.source_url = url;
          this.loaded = true;
          return this.catalog;
        } catch (err) {
          errors.push(`${url}: ${String(err && err.message ? err.message : err)}`);
        }
      }
      this.catalog = { schema_version: "unavailable", rules: [], load_error: errors.join("; ") };
      this.loaded = true;
      return this.catalog;
    }

    rulesForChild(path) {
      const rules = Array.isArray(this.catalog.rules) ? this.catalog.rules : [];
      return rules.filter((rule) => {
        const child = rule.child;
        return Array.isArray(child) ? child.includes(path) : child === path;
      });
    }

    allowedValues(path, config, baseOptions) {
      let allowed = Array.isArray(baseOptions) ? [...baseOptions] : null;
      const rules = this.rulesForChild(path);
      for (const rule of rules) {
        const next = this.allowedValuesFromRule(rule, config);
        if (!next) continue;
        allowed = allowed ? allowed.filter((item) => next.some((candidate) => String(candidate) === String(item))) : next;
      }
      return allowed || baseOptions || null;
    }

    allowedValuesFromRule(rule, config) {
      const parent = rule.parent;
      if (rule.type === "allowed_values") {
        const value = getPath(config, Array.isArray(parent) ? parent[0] : parent, undefined);
        const match = rule.cases ? rule.cases[String(value)] : null;
        return match ? (match.allowed || match.allowed_hz || match.allowed_scs || null) : null;
      }
      if (rule.type === "allowed_values_matrix") {
        const fr = getPath(config, parent[0], undefined);
        const bw = getPath(config, parent[1], undefined);
        const match = rule.matrix && rule.matrix[String(fr)] ? rule.matrix[String(fr)][String(bw)] : null;
        return match ? (match.allowed || match.allowed_scs || null) : null;
      }
      return null;
    }

    isEnabled(path, config) {
      for (const rule of this.rulesForChild(path)) {
        if (rule.type !== "conditional_enable") continue;
        const value = getPath(config, Array.isArray(rule.parent) ? rule.parent[0] : rule.parent, undefined);
        const match = rule.cases ? rule.cases[String(value)] : null;
        if (match && match.enabled === false) return false;
      }
      return true;
    }

    computedValue(rule, config) {
      if (rule.id === "bw_scs_to_nrb") {
        const bw = getPath(config, "frequency.bandwidth_hz", undefined);
        const scs = getPath(config, "frame.scs_khz", undefined);
        const fr = getPath(config, "frequency.range_name", "FR1");
        const table = rule.lookup_table || {};
        const key = fr === "FR2" ? `${bw}_FR2` : String(bw);
        const row = table[key] || table[String(bw)];
        return row ? row[String(scs)] : undefined;
      }
      if (rule.id === "scs_nrb_to_fft") {
        const nrb = Number(getPath(config, "phy.carrier.NSizeGrid", NaN));
        if (!Number.isFinite(nrb) || nrb <= 0) return undefined;
        const occupied = nrb * 12;
        return 2 ** Math.ceil(Math.log2(Math.max(occupied, 1)));
      }
      return undefined;
    }

    applyComputed(config) {
      const rules = Array.isArray(this.catalog.rules) ? this.catalog.rules : [];
      rules.forEach((rule) => {
        if (rule.type !== "computed_lookup" && rule.type !== "min_power_of_2") return;
        const child = Array.isArray(rule.child) ? rule.child[0] : rule.child;
        const value = this.computedValue(rule, config);
        if (value !== undefined && value !== null && child) setPath(config, child, value);
      });
      rules.forEach((rule) => {
        if (rule.type !== "conditional_enable" && rule.type !== "conditional_required") return;
        const parentPath = Array.isArray(rule.parent) ? rule.parent[0] : rule.parent;
        const parentValue = getPath(config, parentPath, undefined);
        const match = rule.cases ? rule.cases[String(parentValue)] : null;
        if (!match || !Object.prototype.hasOwnProperty.call(match, "force_value")) return;
        const children = Array.isArray(rule.child) ? rule.child : [rule.child];
        children.forEach((child) => {
          if (child) setPath(config, child, match.force_value);
        });
      });
      const target = Number(getPath(config, "link_adaptation.target_bler_dl", NaN));
      const up = Number(getPath(config, "link_adaptation.olla_step_up", NaN));
      if (Number.isFinite(target) && target > 0 && target < 1 && Number.isFinite(up) && up > 0) {
        setPath(config, "link_adaptation.olla_step_down", Number((up * target / Math.max(1 - target, Number.EPSILON)).toFixed(6)));
      }
      const ulWaveform = String(getPath(config, "waveform.ul", "")).toUpperCase();
      setPath(config, "waveform.transform_precoding_enabled", ulWaveform.includes("DFT"));
      const scs = Number(getPath(config, "frame.scs_khz", NaN));
      const nfft = Number(getPath(config, "waveform.fft_size", NaN));
      if (Number.isFinite(scs) && scs > 0 && Number.isFinite(nfft) && nfft > 0) {
        setPath(config, "waveform.sample_rate_hz", Math.round(nfft * scs * 1000));
      }
      const coresetSymbols = Math.max(1, Math.min(3, Math.round(Number(
        getPath(config, "pdcch.coreset_duration_symbols", getPath(config, "control.coreset_duration", 2))
      ) || 2)));
      setPath(config, "pdcch.coreset_duration_symbols", coresetSymbols);
      setPath(config, "pdsch.start_symbol", coresetSymbols);
      setPath(config, "pdsch.num_symbols", Math.max(1, 14 - coresetSymbols));
      setPath(config, "frame_timing.tdd_pattern", getPath(config, "frame.tdd_pattern", getPath(config, "phy.duplex.tddPattern", "DDDSU")));
      setPath(config, "frame_timing.special_slot_downlink_symbols", Number(getPath(config, "frame.special_slot_downlink_symbols", 12)));
      setPath(config, "frame_timing.ul_dl_guard_symbols", Number(getPath(config, "frame.ul_dl_guard_symbols", 1)));
      setPath(config, "frame_timing.special_slot_uplink_symbols", Number(getPath(config, "frame.special_slot_uplink_symbols", 1)));
      return config;
    }

    check(config) {
      this.applyComputed(config);
      const violations = [];
      const rules = Array.isArray(this.catalog.rules) ? this.catalog.rules : [];
      rules.forEach((rule) => {
        const children = Array.isArray(rule.child) ? rule.child : [rule.child];
        children.forEach((child) => {
          if (!child) return;
          const value = getPath(config, child, undefined);
          const allowed = this.allowedValues(child, config, null);
          if (allowed && value !== undefined && value !== null && value !== "" && !allowed.some((item) => String(item) === String(value))) {
            violations.push({ severity: "error", rule_id: rule.id, path: child, message: `${child}=${value} is not allowed by ${rule.id}.` });
          }
          if (rule.type === "min_value") {
            const parentValue = getPath(config, Array.isArray(rule.parent) ? rule.parent[0] : rule.parent, undefined);
            const match = rule.cases ? rule.cases[String(parentValue)] : null;
            if (match && Number(value) < Number(match.min)) {
              violations.push({ severity: "error", rule_id: rule.id, path: child, message: `${child} must be >= ${match.min} for ${rule.parent}=${parentValue}.` });
            }
          }
          if (rule.type === "max_value") {
            const parentValue = getPath(config, Array.isArray(rule.parent) ? rule.parent[0] : rule.parent, undefined);
            const match = rule.cases ? rule.cases[String(parentValue)] : null;
            if (match && Number(value) > Number(match.max)) {
              violations.push({ severity: "error", rule_id: rule.id, path: child, message: `${child} must be <= ${match.max} for ${rule.parent}=${parentValue}.` });
            }
          }
        });
      });
      const maxLayers = Math.min(
        Number(getPath(config, "scenario.bs.nTxAnt", 1)),
        Number(getPath(config, "scenario.ue.nRxAnt", 1)),
        8
      );
      if (Number(getPath(config, "mimo.n_layers", 1)) > maxLayers) {
        violations.push({ severity: "error", rule_id: "antenna_to_mimo_layers", path: "mimo.n_layers", message: `mimo.n_layers must be <= ${maxLayers} for the configured antenna counts.` });
      }
      const srsEnabled = Boolean(getPath(config, "reference_signals.srs_enabled", false));
      const ueTx = Number(getPath(config, "scenario.ue.nTxAnt", 1));
      const srsPorts = Number(getPath(config, "reference_signals.srs_ports", 0));
      if (srsEnabled && srsPorts > ueTx) {
        violations.push({ severity: "error", rule_id: "srs_enabled_to_ports", path: "reference_signals.srs_ports", message: `SRS ports must be <= UE TX antennas (${ueTx}).` });
      }
      return violations;
    }
  }

  class ConfigStoreImpl extends EventTarget {
    constructor() {
      super();
      this.config = clone(DEFAULT_CONFIG);
      this.constraintEngine = new ConstraintEngineImpl();
      this.constraintEngine.applyComputed(this.config);
    }

    async init() {
      await this.constraintEngine.load();
      this.constraintEngine.applyComputed(this.config);
      this.emit();
      return this;
    }

    get(path, fallback) {
      return getPath(this.config, path, fallback);
    }

    set(path, value, options) {
      setPath(this.config, path, normalizeScalar(value));
      this.constraintEngine.applyComputed(this.config);
      if (!options || options.silent !== true) this.emit(path);
    }

    load(payload) {
      if (payload && typeof payload === "object") {
        this.config = clone(payload);
        this.constraintEngine.applyComputed(this.config);
        this.emit();
      }
    }

    serialize() {
      this.constraintEngine.applyComputed(this.config);
      return clone(this.config);
    }

    serializeJSON() {
      return JSON.stringify(this.serialize(), null, 2);
    }

    serializeYAML() {
      return `${toYaml(this.serialize(), 0)}\n`;
    }

    violations() {
      return this.constraintEngine.check(this.config);
    }

    emit(path) {
      this.dispatchEvent(new CustomEvent("change", { detail: { path, config: this.serialize(), violations: this.violations() } }));
    }
  }

  const store = new ConfigStoreImpl();
  window.SixGRConfigCatalog = { FIELD_SECTIONS, DEFAULT_CONFIG, CATALOG_URL, catalogUrls };
  window.ConstraintEngine = store.constraintEngine;
  window.ConfigStore = store;
  window.ConfigPath = { get: getPath, set: setPath };
})();
