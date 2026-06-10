window.RAN_DATA = {
  app: {
    title: "Jio Platforms Limited RAN Simulator",
    subtitle: "Browser-first workstation for waveform-backed RAN studies",
    scenario: "LLS_4GHz_100MHz_19S3_100UE_UMa",
    runProfile: "Baseline",
    status: "Awaiting runtime evidence",
    db: "Use dashboard API or run_path to load data",
    matlab: "MATLAB R2023b",
    configHash: "",
    lastSaved: ""
  },
  nav: [
    { id: "home", label: "Home", href: "index.html" },
    { id: "scenario", label: "Scenario", href: "scenario.html" },
    { id: "geometry", label: "Geometry", href: "geometry.html" },
    { id: "waveform", label: "Waveform", href: "waveform.html" },
    { id: "traffic", label: "Traffic", href: "traffic.html" },
    { id: "mac", label: "MAC / Scheduler", href: "mac_scheduler.html" },
    { id: "l1", label: "L1 / PHY Explorer", href: "l1_phy.html" },
    { id: "antenna", label: "Antenna & Air Interface", href: "antenna_air.html" },
    { id: "studio", label: "Block Studio", href: "block_studio.html" },
    { id: "realtime", label: "Real-Time Data", href: "realtime.html" },
    { id: "analytics", label: "Analytics", href: "analytics.html" },
    { id: "artifacts", label: "Artifacts", href: "artifacts.html" },
    { id: "catalog", label: "Parameter Catalog", href: "parameter_catalog.html" },
    { id: "compare", label: "Compare Runs", href: "compare_runs.html" }
  ],
  modeCards: [
    { name: "LLS", tag: "Default", desc: "Waveform-backed link and coupled multi-cell runtime with PHY truth, control gating, CSI, HARQ, and DB-backed analytics.", route: "lls_builder.html", bullets: ["Scenario builder", "PHY explorer", "Runtime CSV/DB monitor"] },
    { name: "SLS", tag: "Planned", desc: "System-level orchestration workspace for campaign-scale studies with honest coverage badges and run pairing.", route: "#", bullets: ["Coverage maps", "Large topology sweeps", "Canonical KPIs"] },
    { name: "E2E", tag: "Planned", desc: "Service and application validation workspace spanning traffic, protocol outcomes, and deployment comparison.", route: "#", bullets: ["QoE/latency flows", "Service chains", "Operational what-if studies"] }
  ],
  profiles: [
    { name: "Smoke", runtime: "configured", notes: "Small runtime profile. Actual duration comes from run artifacts." },
    { name: "Debug", runtime: "configured", notes: "Raw IQ/grid capture on demand. Actual coverage comes from output registry." },
    { name: "Baseline", runtime: "configured", notes: "Deterministic execution with canonical artifacts." },
    { name: "Campaign", runtime: "configured", notes: "Multi-seed or matrix execution when enabled in YAML." },
    { name: "Publication", runtime: "configured", notes: "Full report bundle and strict provenance." }
  ],
  sameFlow: [
    { title: "Scenario", href: "scenario.html", status: "Config", params: 0, desc: "Identity, study profile, seeds, validation policy, and output policy.", items: ["Scenario ID", "Execution mode", "Profiles", "Run budget"] },
    { title: "Geometry", href: "geometry.html", status: "Config", params: 0, desc: "Topology, wrap-around, cell association, hotspots, and mobility.", items: ["Sites/sectors", "UE placement", "Handover", "Mobility bins"] },
    { title: "Waveform", href: "waveform.html", status: "Config", params: 0, desc: "Carrier, numerology, TDD, FFT, coding, modulation, and impairments.", items: ["SCS", "DL/UL waveforms", "Coding", "RF impairments"] },
    { title: "Traffic", href: "traffic.html", status: "Config", params: 0, desc: "Service classes, offered load, packet models, QoS, and latency budgets.", items: ["Service class", "Queue model", "QoS targets"] },
    { title: "MAC / Scheduler", href: "mac_scheduler.html", status: "Config", params: 0, desc: "Scheduling, PRBs, MCS/TBS, HARQ, fairness, OLLA, and control eligibility.", items: ["Scheduler policy", "HARQ", "Link adaptation", "Grant truth"] },
    { title: "L1 / PHY", href: "l1_phy.html", status: "Runtime", params: 0, desc: "Interactive explorer for DL/UL control, data, RS/MIMO, and Massive MIMO signal families.", items: ["DL control", "DL data", "UL control", "UL data", "RS/MIMO"] },
    { title: "Real-Time Data", href: "realtime.html", status: "Evidence", params: 0, desc: "Runtime monitor populated only from loaded CSV or DB-backed artifacts.", items: ["Live grants", "Control state", "Channel state", "Errors"] },
    { title: "Analytics", href: "analytics.html", status: "Evidence", params: 0, desc: "Post-run charts populated only from result CSV/DB evidence.", items: ["KPI summary", "Root cause", "Output coverage", "Compare runs"] }
  ],
  l1Families: [
    {
      id: "system",
      title: "System",
      summary: "Top-level same-flow view across payload ingress, scheduler/grants, waveform generation, channel, receiver, control gating, and artifact export.",
      blocks: [
        { id: "scenario_ingest", name: "Scenario Ingest", group: "System", purpose: "Resolves browser/YAML config into runtime-owned scenario and policy objects.", algo: "config normalization and ownership resolution", params: ["scenario_id", "run_profile", "execution_mode"], runtime: ["ResolvedConfigHash", "ConfigOwnershipStatus"], outputs: ["resolved config snapshot"], artifacts: ["meta/scenario_config_resolved.json"] },
        { id: "scheduler_flow", name: "Grant Orchestrator", group: "System", purpose: "Connects scheduler, control gating, HARQ state, CSI inputs, and PHY grant payloads.", algo: "slot-coupled truth orchestration", params: ["scheduler_type", "harq_enable"], runtime: ["GrantContextId", "ControlEligibility"], outputs: ["canonical grant payloads"], artifacts: ["reports/csv/live_dl_scheduler_grants.csv", "reports/csv/live_ul_scheduler_grants.csv"] },
        { id: "export_flow", name: "Canonical Export", group: "System", purpose: "Commits canonical artifacts for browser live and post-run analytics.", algo: "artifact ownership and source-role labeling", params: ["output.persistence_mode"], runtime: ["ResultOk", "CanonicalArtifactCount"], outputs: ["DB/file artifacts"], artifacts: ["reports/csv/output_coverage_registry.csv"] }
      ]
    },
    {
      id: "dl_control",
      title: "DL Control",
      summary: "PDCCH, SSB/PBCH, and CSI-RS grouped by signal chain and control/access roles.",
      blocks: [
        { id: "pdcch_payload", name: "PDCCH Payload", group: "DL Control", purpose: "Builds DCI/control payload and maps it through control-channel processing.", algo: "DCI assembly, CORESET/search-space mapping", params: ["pdcch.enabled", "aggregation_levels"], runtime: ["ControlDecodeOk", "GrantControlState"], outputs: ["DCI truth rows"], artifacts: ["control/csv/pdcch_trials.csv"] },
        { id: "ssb_pbch", name: "SSB / PBCH", group: "DL Control", purpose: "Runs sync burst, PBCH payload coding, PBCH DMRS, and acquisition gating.", algo: "PBCH CRC, polar coding, scrambling, mapping", params: ["ssb_enabled"], runtime: ["CellAcquisitionState"], outputs: ["PBCH decode state"], artifacts: ["control/csv/pbch_trials.csv"] },
        { id: "csirs", name: "CSI-RS", group: "DL Control", purpose: "Generates CSI-RS resources for beam/CSI measurement and feedback paths.", algo: "CSI-RS resource mapping", params: ["csi_rs_enabled"], runtime: ["CSIValidityState"], outputs: ["CSI-RS rows"], artifacts: ["control/csv/csi_rs_trials.csv"] }
      ]
    },
    {
      id: "dl_data",
      title: "DL Data",
      summary: "PDSCH chain from TB payload through LDPC, mapping, precoding, channel, and decode truth.",
      blocks: [
        { id: "pdsch_tx", name: "PDSCH TX Chain", group: "DL Data", purpose: "TB CRC, code block segmentation, LDPC, rate matching, scrambling, modulation, layer mapping, precoding, DMRS/PTRS insertion, and OFDM.", algo: "NR-style downlink shared channel chain", params: ["mcs_table", "dmrs_ports"], runtime: ["TBSize_bits", "RateMatchedBits"], outputs: ["DL IQ samples"], artifacts: ["air_interface/csv/dl_pdsch_trials.csv"] },
        { id: "beam_precoding", name: "Beam / Precoding", group: "DL Data", purpose: "Applies selected beam and precoder to serving and interferer paths before waveform generation.", algo: "codebook/non-codebook precoding", params: ["beam_management_enable"], runtime: ["AppliedBeamIndexSet", "AppliedPrecoderPMI"], outputs: ["beamformed layers"], artifacts: ["reports/csv/beamforming_runtime_evidence.csv"] },
        { id: "dl_rx", name: "PDSCH RX Chain", group: "DL Data", purpose: "Timing estimate, OFDM demodulation, channel estimation, equalization, demodulation, LDPC decode, and CRC.", algo: "NR-style downlink receiver", params: ["channel_estimation_mode"], runtime: ["MeasuredTrialSINR_dB", "EVM_rms", "CRCPass"], outputs: ["decoded TBs"], artifacts: ["air_interface/csv/dl_pdsch_trials.csv"] }
      ]
    },
    {
      id: "ul_control",
      title: "UL Control",
      summary: "PUCCH formats and PRACH access grouped by actual runtime evidence.",
      blocks: [
        { id: "pucch", name: "PUCCH", group: "UL Control", purpose: "Processes UCI/control payloads on configured PUCCH formats.", algo: "PUCCH sequence/coded UCI receiver", params: ["pucch.enabled"], runtime: ["PUCCHDecodeOk"], outputs: ["decoded UCI"], artifacts: ["control/csv/pucch_trials.csv"] },
        { id: "prach", name: "PRACH", group: "UL Control", purpose: "Preamble detection path using ZC sequence generation, correlation, noise floor, and peak search.", algo: "PRACH detection and access gating", params: ["prach.format"], runtime: ["AccessState", "CorrelationPeak"], outputs: ["RA success/failure"], artifacts: ["control/csv/prach_trials.csv"] }
      ]
    },
    {
      id: "ul_data",
      title: "UL Data",
      summary: "PUSCH transmit/receive and UCI-on-PUSCH flow.",
      blocks: [
        { id: "pusch_rx", name: "PUSCH RX Chain", group: "UL Data", purpose: "DMRS channel estimation, equalization, demapping, HARQ combining, LDPC decode, and CRC.", algo: "NR-style uplink receiver", params: ["waveform.ul", "pusch_dmrs_ports"], runtime: ["MeasuredTrialSINR_dB", "CRCPass"], outputs: ["UL decoded TBs"], artifacts: ["air_interface/csv/ul_pusch_trials.csv"] },
        { id: "ul_tx", name: "UL TX Chain", group: "UL Data", purpose: "UL coding, modulation, mapping, transform/direct mapping, and precoding.", algo: "UL shared-channel transmit chain", params: ["transform_precoding_enabled"], runtime: ["TransformPrecodingApplied"], outputs: ["UL IQ samples"], artifacts: ["reports/csv/live_tx_rx_stage_trace.csv"] }
      ]
    },
    {
      id: "rs_mimo",
      title: "RS / MIMO",
      summary: "SRS, TRS, CSI feedback, rank/PMI/CRI, beam management, and rank adaptation.",
      blocks: [
        { id: "srs", name: "SRS", group: "RS / MIMO", purpose: "Sounding reference signal generation and estimation for UL CSI and beam/rank support.", algo: "SRS sequence and MMSE channel estimation", params: ["srs_enabled", "srs_ports"], runtime: ["SRSValidityState"], outputs: ["SRS runtime state"], artifacts: ["control/csv/srs_trials.csv"] },
        { id: "trs", name: "TRS", group: "RS / MIMO", purpose: "Tracking reference signal support and runtime tracking state.", algo: "tracking reference observation", params: ["trs_enabled"], runtime: ["TRSValidityState"], outputs: ["tracking state"], artifacts: ["control/csv/trs_trials.csv"] },
        { id: "csi_feedback", name: "CSI Feedback", group: "RS / MIMO", purpose: "CQI, PMI, RI, and CRI feedback path and runtime age handling.", algo: "CSI report construction", params: ["csi_feedback_mode"], runtime: ["WidebandCQI", "PMI", "RI"], outputs: ["runtime CSI state"], artifacts: ["reports/csv/live_csi_feedback_stats.csv"] }
      ]
    }
  ],
  builderSections: [
    { title: "Scenario", fields: ["Scenario ID", "Study mode", "Execution mode", "Random seed master", "Num drops", "Warmup / measurement window"] },
    { title: "Scenario / Geometry", fields: ["Num sites", "Sectors per site", "Inter-site distance", "Wrap-around", "UE count", "Mobility"] },
    { title: "Waveform", fields: ["Carrier frequency", "Bandwidth", "Numerology", "SCS", "TDD pattern", "Waveform DL/UL", "FFT size", "Grid size"] },
    { title: "Traffic", fields: ["Traffic mix", "QoS class", "DL/UL asymmetry", "Queue depth", "Latency budget", "Packet model"] },
    { title: "MAC / Scheduler", fields: ["Scheduler type", "Frequency-domain scheduling", "Beam-aware scheduling", "OLLA", "Target BLER", "HARQ processes"] },
    { title: "L1 / PHY", fields: ["Coding", "Modulation set", "DMRS/PTRS", "CSI-RS", "SRS", "PDCCH", "PBCH", "PRACH", "PUCCH"] },
    { title: "Air Interface / Channel", fields: ["Channel family", "Pathloss", "Shadowing", "O2I", "Spatial consistency", "Interference mode", "Noise mode", "Impairments"] },
    { title: "Outputs / Profiles", fields: ["Run profile", "Canonical artifacts", "Raw IQ capture", "Constellation save", "Energy trace", "Compare-runs support"] }
  ],
  realtimeKpis: [],
  realtimeTables: { grants: [], control: [], channel: [] },
  analyticsCards: [
    { title: "KPI Overview", desc: "Result status, throughput, BLER, SINR, fairness, energy, and operating point from runtime CSVs." },
    { title: "PHY & Link", desc: "BLER vs SINR, MCS/CQI, decoder iterations, EVM, and waveform evidence." },
    { title: "MAC / Scheduler", desc: "PRB heatmap, scheduler decisions, fairness, queue backlog, MCS/TBS evolution." },
    { title: "Control / Access", desc: "PBCH, PRACH, PDCCH, PUCCH, SRS, TRS, and gating effectiveness." },
    { title: "Channel / Interference", desc: "Pathloss, delay, interferers, SINR pipelines, LOS/NLOS, and O2I evidence." },
    { title: "Beam / MIMO", desc: "Beam index, rank/layer usage, PMI/RI/CRI, beam stability, and precoder truth." },
    { title: "Latency", desc: "CDF and decomposition when exported by the runtime." },
    { title: "Energy", desc: "UE/cell energy, energy per bit, power states, and transitions." },
    { title: "Compare Runs", desc: "Baseline vs candidate deltas when compatible runs are selected." },
    { title: "Output Coverage", desc: "Coverage registry, completeness, API exposure, and honest unavailable state." }
  ],
  parameterRows: []
};
