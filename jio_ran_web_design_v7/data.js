window.RAN_DATA = {
  app: {
    title: 'Jio Platforms Limited RAN Simulator',
    subtitle: 'Browser-first workstation for waveform-backed RAN studies',
    scenario: 'LLS_4GHz_100MHz_19S3_100UE_UMa',
    runProfile: 'Baseline',
    status: 'Ready',
    db: 'MySQL Connected',
    matlab: 'MATLAB R2023b',
    configHash: 'cfg_950e6d7c',
    lastSaved: '2 min ago'
  },
  nav: [
    {id:'home', label:'Home', href:'index.html'},
    {id:'scenario', label:'Scenario', href:'scenario.html'},
    {id:'geometry', label:'Geometry', href:'geometry.html'},
    {id:'waveform', label:'Waveform', href:'waveform.html'},
    {id:'traffic', label:'Traffic', href:'traffic.html'},
    {id:'mac', label:'MAC / Scheduler', href:'mac_scheduler.html'},
    {id:'l1', label:'L1 / PHY Explorer', href:'l1_phy.html'},
    {id:'antenna', label:'Antenna & Air Interface', href:'antenna_air.html'},
    {id:'studio', label:'Block Studio', href:'block_studio.html'},
    {id:'realtime', label:'Real-Time Data', href:'realtime.html'},
    {id:'analytics', label:'Analytics', href:'analytics.html'},
    {id:'artifacts', label:'Artifacts', href:'artifacts.html'},
    {id:'catalog', label:'Parameter Catalog', href:'parameter_catalog.html'},
    {id:'compare', label:'Compare Runs', href:'compare_runs.html'}
  ],
  modeCards: [
    {name:'LLS', tag:'Default', desc:'Waveform-backed link and coupled multi-cell runtime with PHY truth, control gating, CSI, HARQ, and DB-backed analytics.', route:'lls_builder.html', bullets:['Scenario builder', 'PHY explorer', 'Real-time DB monitor']},
    {name:'SLS', tag:'Planned', desc:'System-level orchestration workspace for campaign-scale studies with honest coverage badges and run pairing.', route:'#', bullets:['Coverage maps', 'Large topology sweeps', 'Canonical KPIs']},
    {name:'E2E', tag:'Planned', desc:'Service and application validation workspace spanning traffic, protocol outcomes, and deployment comparison.', route:'#', bullets:['QoE/latency flows', 'Service chains', 'Operational what-if studies']}
  ],
  profiles: [
    {name:'Smoke', runtime:'~1–2 min', notes:'1 seed · 1 drop · 50 ms measurement'},
    {name:'Debug', runtime:'~5–10 min', notes:'1 seed · 2 drops · raw IQ/grid capture on demand'},
    {name:'Baseline', runtime:'~15–30 min', notes:'deterministic execution · canonical artifacts'},
    {name:'Campaign', runtime:'~hours', notes:'5 seeds · 20 drops · compare-runs enabled'},
    {name:'Publication', runtime:'~hours+', notes:'full report bundle · provenance strict'}
  ],
  sameFlow: [
    {title:'Scenario', href:'scenario.html', status:'Complete', params:48, desc:'Identity, study profile, seeds, validation policy, output policy.', items:['Scenario ID', 'Simulation mode', 'Profiles', 'Run budget']},
    {title:'Geometry', href:'geometry.html', status:'Complete', params:41, desc:'Topology, wrap-around, cell association, hotspots, mobility.', items:['Sites/sectors', 'UE placement', 'Handover', 'Mobility bins']},
    {title:'Waveform', href:'waveform.html', status:'Complete', params:52, desc:'Carrier, numerology, TDD, FFT, coding, modulation, impairments.', items:['SCS / numerology', 'DL/UL waveforms', 'Coding', 'RF impairments']},
    {title:'Traffic', href:'traffic.html', status:'Complete', params:33, desc:'Service classes, offered load, packet models, QoS and latency budgets.', items:['eMBB / XR / UL-heavy', 'Queue model', 'QoS targets']},
    {title:'MAC / Scheduler', href:'mac_scheduler.html', status:'Complete', params:37, desc:'Scheduling, PRBs, MCS/TBS, HARQ, fairness, OLLA, control eligibility.', items:['Scheduler policy', 'HARQ', 'Link adaptation', 'Grant truth']},
    {title:'Control / Access', href:'l1_phy.html#control', status:'Deep Dive', params:22, desc:'PBCH, PRACH, PDCCH, PUCCH, SRS and TRS runtime gating state.', items:['Acquisition', 'Access', 'DCI validity', 'SRS/TRS freshness']},
    {title:'L1 / PHY', href:'l1_phy.html', status:'Deep Dive', params:126, desc:'Interactive explorer for DL/UL control, DL/UL data, RS/MIMO and Massive MIMO signal families.', items:['DL control', 'DL data', 'UL control', 'UL data', 'RS / MIMO', 'Massive MIMO']},
    {title:'Antenna & Air Interface', href:'antenna_air.html', status:'Deep Dive', params:29, desc:'BS/UE arrays, beamforming, ToA/ToD, channel/air-interface coupling and interference.', items:['BS arrays', 'UE arrays', 'Beam truth', 'Propagation truth']},
    {title:'Real-Time Data', href:'realtime.html', status:'Operational', params:0, desc:'Live MySQL-backed monitor for grants, control state, channels, alerts, artifacts and KPIs.', items:['Live grants', 'Live control state', 'Live channel state', 'Live errors']},
    {title:'Analytics', href:'analytics.html', status:'Post-run', params:0, desc:'Reports generated after completion: PHY, MAC, control, channel, energy, compare-runs, output coverage.', items:['KPI summary', 'Root cause', 'Output coverage', 'Compare runs']}
  ],
  l1Families: [
    {
      id:'system', title:'System', summary:'Top-level same-flow view across payload ingress, scheduler/grants, waveform generation, channel, receiver, control gating, and artifact export.',
      blocks:[
        {id:'scenario_ingest', name:'Scenario Ingest', group:'System', purpose:'Resolves browser/YAML config into runtime-owned scenario and policy objects.', algo:'config normalization · ownership resolution · profile expansion', params:['scenario_id','run_profile','simulation_mode','random_seed_master','measurement_time_ms'], runtime:['ResolvedConfigHash','ConfigOwnershipStatus','RoundtripMismatchCount'], outputs:['resolved config snapshot','truth contract seed set'], artifacts:['meta/scenario_config_resolved.json','reports/csv/config_roundtrip_verification.csv']},
        {id:'scheduler_flow', name:'Grant Orchestrator', group:'System', purpose:'Connects MAC scheduler, control gating, HARQ state, CSI inputs, and PHY grant payloads.', algo:'slot coupled truth orchestration', params:['scheduler_type','frequency_domain_scheduling_enable','beam_aware_scheduler_enable','harq_enable'], runtime:['GrantContextId','ControlEligibility','SchedulingEligibility'], outputs:['canonical grant payloads'], artifacts:['packet_flow/csv/live_dl_scheduler_grants.csv','packet_flow/csv/live_ul_scheduler_grants.csv']},
        {id:'export_flow', name:'Canonical Export', group:'System', purpose:'Commits canonical DB-backed artifacts for browser live and post-run analytics.', algo:'artifact ownership + source-role labeling', params:['save_scheduler_decisions','per_ue_logging_enable','raw_grid_capture_enable'], runtime:['ResultOk','RequiredFailureCount','CanonicalArtifactCount'], outputs:['DB-backed artifacts','browser payloads'], artifacts:['reports/csv/output_coverage_registry.csv','outputs/<run_id>/artifact_manifest.json']}
      ]
    },
    {
      id:'dl_control', title:'DL Control', summary:'PDCCH, SSB/PBCH, and CSI-RS grouped by actual signal chain and control/access roles.',
      blocks:[
        {id:'pdcch_payload', name:'PDCCH Payload', group:'DL Control', purpose:'Builds DCI/control payload prior to CRC, polar coding, scrambling, modulation and RE mapping.', algo:'DCI assembly + coreset/search-space mapping', params:['aggregation_levels','dci_formats_supported','coreset_duration_symbols','blind_decode_limit'], runtime:['ControlDecodeOk','GrantControlState','AggregationLevel'], outputs:['PDCCH symbols','DCI truth rows'], artifacts:['control/csv/pdcch_trials.csv','reports/csv/live_control_gating_summary.csv']},
        {id:'ssb_pbch', name:'SSB / PBCH', group:'DL Control', purpose:'Runs sync burst, PBCH payload coding, PBCH DMRS, and acquisition gating.', algo:'PBCH CRC + polar encode + scramble + map', params:['ssb_enable','ssb_periodicity_ms','ssb_beams_per_sector','pbch_payload_mode'], runtime:['CellAcquisitionState','PBCHFailureCount','LastSuccessfulPBCHSlot'], outputs:['SSB beams','PBCH decode state'], artifacts:['control/csv/pbch_trials.csv','reports/csv/live_control_gating_state.csv']},
        {id:'csirs', name:'CSI-RS', group:'DL Control', purpose:'Generates CSI-RS resources for beam/CSI measurement and feedback paths.', algo:'CSI-RS resource mapping + measurement support', params:['csi_rs_enable','csi_rs_type','csi_rs_periodicity_slots','csi_rs_ports'], runtime:['CSI_RS_MeasurementAge','BasedOn','BeamformedFlag'], outputs:['CSI-RS rows','measurement lineage'], artifacts:['control/csv/csi_rs_trials.csv','reports/csv/live_csi_feedback_stats.csv']}
      ]
    },
    {
      id:'dl_data', title:'DL Data', summary:'PDSCH end-to-end chain from TB payload through LDPC, layer mapping, precoding, DMRS/PTRS, RE mapping, OFDM, channel, and decode truth.',
      blocks:[
        {id:'pdsch_tx', name:'PDSCH TX Chain', group:'DL Data', purpose:'TB CRC, CB CRC, LDPC, rate matching, scrambling, modulation, layer mapping, precoding, DMRS/PTRS insertion, RE mapping, OFDM.', algo:'NR-style downlink shared channel chain', params:['max_modulation_dl','decoder_iterations_max','dmrs_type','ptrs_enable','max_dl_layers'], runtime:['TBSize_bits','RateMatchedBits','DMRSRECount','PTRSRECount','AppliedPrecoderPMI'], outputs:['DL IQ samples','DL raw trial row'], artifacts:['air_interface/csv/dl_pdsch_trials.csv','reports/csv/live_tx_rx_stage_trace.csv']},
        {id:'beam_precoding', name:'Beam / Precoding', group:'DL Data', purpose:'Applies selected beam and precoder to serving and interferer paths before waveform generation.', algo:'codebook/non-codebook precoding + beam application', params:['precoding_mode','beam_management_enable','beam_codebook_size','beam_update_period_ms'], runtime:['RequestedBeamIndexSet','AppliedBeamIndexSet','RequestedPrecoderPMI','AppliedPrecoderPMI','BeamformingApplied'], outputs:['beamformed layers','interferer precoder provenance'], artifacts:['packet_flow/csv/live_dl_scheduler_grants.csv','reports/csv/beamforming_runtime_evidence.csv']},
        {id:'dl_rx', name:'PDSCH RX Chain', group:'DL Data', purpose:'Timing estimate, OFDM demod, channel estimation, MMSE equalization, demodulation, LLR, rate recovery, LDPC decode, CRC.', algo:'NR-style downlink receiver', params:['use_ideal_timing_sync','channel_estimator_type','equalizer_type','detector_type'], runtime:['TimingEstimateUsed','MeasuredTrialSINR_dB','NMSE_dB','EVM_rms','DecoderIterations','CRCPass'], outputs:['decoded TBs','goodput/BLER evidence'], artifacts:['air_interface/csv/dl_pdsch_trials.csv','reports/csv/live_error_rate_summary.csv']}
      ]
    },
    {
      id:'ul_control', title:'UL Control', summary:'PUCCH formats 0–4 and PRACH grouped clearly, with requested/resolved format truth and access/control state.',
      blocks:[
        {id:'pucch_f0', name:'PUCCH Format 0', group:'UL Control', purpose:'Low-PAPR sequence generation and format-0 detection for SR/ACK/NACK style control.', algo:'sequence generation + detector', params:['pucch_enable','pucch_formats_supported','harq_ack_transport_mode'], runtime:['RequestedFormat','ResolvedFormat','PUCCHDecodeOk','UCIContentMatch'], outputs:['control payload decision'], artifacts:['control/csv/pucch_trials.csv']},
        {id:'pucch_f1', name:'PUCCH Format 1', group:'UL Control', purpose:'Low-PAPR format-1 processing with DMRS, DTX detection and demodulation.', algo:'DMRS-assisted despread + detection', params:['pucch_formats_supported','dedicated_ul_control_vs_pusch_policy'], runtime:['RequestedFormat','ResolvedFormat','FormatAdapted','DTXFlag'], outputs:['decoded control bits'], artifacts:['control/csv/pucch_trials.csv']},
        {id:'pucch_f234', name:'PUCCH Formats 2/3/4', group:'UL Control', purpose:'Full coded UCI chain with channel estimation, equalization, demapping, descrambling, block handling, rate de-matching and polar/Reed-Muller decode.', algo:'coded UCI receiver chain', params:['uci_payload_size_limits','pucch_formats_supported'], runtime:['CodeBlockCount','CRCApplicable','CRCPass','DecisionMetric'], outputs:['UCI payload to MAC/runtime state'], artifacts:['control/csv/pucch_trials.csv']},
        {id:'prach', name:'PRACH', group:'UL Control', purpose:'Preamble detection path using ZC sequence generation, correlation, IFFT, normalization, noise floor, and peak search.', algo:'PRACH detection + access gating', params:['prach_enable','prach_format','prach_periodicity_ms','preamble_count'], runtime:['AccessState','PRACHFailureCount','CorrelationPeak','TAEstimate'], outputs:['RA success/failure'], artifacts:['control/csv/prach_trials.csv','reports/csv/live_control_gating_state.csv']}
      ]
    },
    {
      id:'ul_data', title:'UL Data', summary:'PUSCH transmit/receive and UCI-on-PUSCH flow with channel estimation, equalization, demapping, HARQ combining, LDPC decode, and CRC.',
      blocks:[
        {id:'pusch_rx', name:'PUSCH RX Chain', group:'UL Data', purpose:'DMRS generation, MMSE-based channel estimation, equalization, RE demapping, layer demap, modulation de-map, descrambling, code-block handling, LDPC decode, CRC.', algo:'NR-style uplink receiver', params:['waveform_ul_default','decoder_iterations_max','dmrs_type','soft_combining_enable'], runtime:['MeasuredTrialSINR_dB','NMSE_dB','EVM_rms','DecoderIterations','CRCPass'], outputs:['UL decoded transport blocks'], artifacts:['air_interface/csv/ul_pusch_trials.csv','reports/csv/live_tx_rx_stage_trace.csv']},
        {id:'uci_on_pusch', name:'UCI on PUSCH', group:'UL Data', purpose:'Decodes UCI carried inside PUSCH when scheduler/policy routes control there.', algo:'UCI demapping + decoder coupling', params:['uci_on_pusch_enable','csi_transport_mode'], runtime:['UCIBits','HARQAckBits','UCIContentMatch'], outputs:['control feedback via UL shared channel'], artifacts:['control/csv/uplink_uci_on_pusch.csv']},
        {id:'ul_tx', name:'UL TX Chain', group:'UL Data', purpose:'UL waveform and precoding path using actual UE antenna/port context and grant-provenance fields.', algo:'UL coding + modulation + mapping + transform/direct mapping', params:['preferred_waveform_ul','max_modulation_ul','max_ul_layers'], runtime:['AppliedBeamIndexSet','AppliedPrecoderPMI','TransformPrecodingApplied'], outputs:['UL IQ samples'], artifacts:['reports/csv/live_tx_rx_stage_trace.csv','packet_flow/csv/live_ul_scheduler_grants.csv']}
      ]
    },
    {
      id:'rs_mimo', title:'RS / MIMO', summary:'SRS, TRS, CSI feedback, rank/PMI/CRI, beam management and rank adaptation.',
      blocks:[
        {id:'srs', name:'SRS', group:'RS / MIMO', purpose:'Sounding reference signal generation/estimation for UL CSI and beam/rank support.', algo:'SRS sequence + MMSE channel estimation', params:['srs_enable','srs_ports','srs_periodicity_ms','srs_for_ul_csi_enable'], runtime:['SRSValidityState','SRSAgeSlots','UL_CSI_Quality'], outputs:['SRS-driven runtime state'], artifacts:['control/csv/srs_trials.csv','reports/csv/live_control_gating_state.csv']},
        {id:'trs', name:'TRS', group:'RS / MIMO', purpose:'Tracking reference signal support and runtime tracking state.', algo:'tracking reference observation / tracking state', params:['tracking_rs_enable','tracking_rs_periodicity_ms','trs_like_mode_enable'], runtime:['TRSValidityState','TRSAgeSlots','EstimatedDopplerHz','TrackingFailureProbability'], outputs:['tracking state / trace'], artifacts:['control/csv/trs_trials.csv','reports/csv/timing_positioning_runtime_evidence.csv']},
        {id:'csi_feedback', name:'CSI Feedback', group:'RS / MIMO', purpose:'CQI / PMI / RI / CRI feedback path and runtime age/staleness handling.', algo:'CSI report construction + scheduling consumption', params:['csi_source_mode','cqi_mode','csi_feedback_delay_ms','rank_adaptation_enable'], runtime:['WidebandCQI','PMI','RI','CRI','CSIValidityState'], outputs:['runtime CSI state and reports'], artifacts:['reports/csv/live_csi_feedback_stats.csv','reports/csv/cqi_pmi_ri_time.csv']}
      ]
    },
    {
      id:'massive', title:'Massive MIMO', summary:'DL and UL beam-weight generation, user buffer selection, ZF beam generation, DL beam forming and UL spatial filtering.',
      blocks:[
        {id:'massive_dl', name:'Massive MIMO DL', group:'Massive MIMO', purpose:'PDSCH beam-weight generation from SRS channel estimate -> user buffer selection -> ZF beam generation -> DL beam weights -> NxM beamforming.', algo:'ZF beam weight generation and DL beam forming', params:['mimo_mode','beam_codebook_size','max_dl_layers','num_phy_antenna_elements'], runtime:['SelectedBeamIndex','BestBeamIndex','BeamHit','SelectedBeamGain_dB'], outputs:['beamformed DL ports / REs'], artifacts:['reports/csv/beamforming_runtime_evidence.csv','reports/csv/beam_stability_analytics_table.csv']},
        {id:'massive_ul', name:'Massive MIMO UL', group:'Massive MIMO', purpose:'UL beam-weight generation from SRS estimate, user buffer selection, ZF beam generation, UL spatial filter and antenna combining.', algo:'UL beam filtering / combining', params:['srs_ports','max_ul_layers','num_txrus'], runtime:['ULBeamWeightsActive','SpatialFilterApplied','InterfererBeamformingAppliedCount'], outputs:['combined UL streams'], artifacts:['reports/csv/beamforming_runtime_evidence.csv','reports/csv/channel_array_consistency.csv']}
      ]
    }
  ],
  builderSections: [
    {title:'Scenario', fields:['Scenario ID','Study mode','Simulation mode','Random seed master','Num drops','Warmup / measurement window']},
    {title:'Scenario / Geometry', fields:['Num sites','Sectors per site','Inter-site distance','Wrap-around','UE count','Hotspots','Handover policy']},
    {title:'Waveform', fields:['Carrier frequency','Bandwidth','Numerology','SCS','TDD pattern','Waveform DL/UL','FFT size','Grid size']},
    {title:'Traffic', fields:['Traffic mix','QoS class','DL/UL asymmetry','Queue depth','Latency budget','Packet model']},
    {title:'MAC / Scheduler', fields:['Scheduler type','Frequency-domain scheduling','Beam-aware scheduling','OLLA','Target BLER','HARQ processes']},
    {title:'L1 / PHY', fields:['Coding','Modulation set','DMRS/PTRS','CSI-RS','SRS','PDCCH','PBCH','PRACH','PUCCH']},
    {title:'Air Interface / Channel', fields:['Channel family','Pathloss','Shadowing','O2I','Spatial consistency','Interference mode','Noise mode','Impairments']},
    {title:'Outputs / Profiles', fields:['Run profile','Canonical artifacts','Raw IQ capture','Constellation save','Energy trace','Compare-runs support']}
  ],
  realtimeKpis: [
    ['Run status','Running'],['Elapsed','00:17:24'],['Run ID','147'],['Active UEs','100'],['Active cells','57'],['DL Throughput','8.42 Gbps'],['UL Throughput','1.96 Gbps'],['DL BLER','8.8%'],['UL BLER','9.6%'],['Interference mode','Full per-link channel truth'],['Scheduler','PF + beam-aware'],['Truth contract','WARN 2']
  ],
  realtimeTables: {
    grants:[
      ['00:17:24.320','DL','Cell 18','UE 044','PRB 42–78','MCS 24','RV0','control_ok','beam 7'],
      ['00:17:24.320','UL','Cell 18','UE 044','PRB 18–29','MCS 16','RV1','control_ok','beam 2'],
      ['00:17:24.340','DL','Cell 03','UE 011','PRB 0–23','MCS 10','RV2','harq_retx','beam 1'],
      ['00:17:24.340','UL','Cell 41','UE 078','PRB 60–71','MCS 12','RV0','control_ok','beam 4']
    ],
    control:[
      ['UE 044','acquired','access_ready','control_ok','valid','fresh','eligible'],
      ['UE 011','acquired','access_ready','control_failed_last','valid','fresh','blocked_this_slot'],
      ['UE 078','acquired','access_ready','control_ok','stale','fallback','conservative']
    ],
    channel:[
      ['UE 044','Cell 18','-79.4 dBm','17.2 dB','30 km/h','19.46 Hz','LOS'],
      ['UE 011','Cell 03','-94.8 dBm','4.5 dB','3 km/h','1.95 Hz','NLOS'],
      ['UE 078','Cell 41','-88.1 dBm','9.1 dB','30 km/h','19.46 Hz','Indoor/O2I']
    ]
  },
  analyticsCards:[
    {title:'KPI Overview', desc:'ResultOk, required failures, throughput, BLER, latency, energy, operating point.'},
    {title:'PHY & Link', desc:'BLER vs SINR, BLER vs MCS, BER/FER summary, EVM, constellation access, stage trace.'},
    {title:'MAC / Scheduler', desc:'PRB heatmap, scheduler decisions, fairness, queue backlog, MCS/TBS evolution.'},
    {title:'Control / Access', desc:'PBCH, PRACH, PDCCH, PUCCH, SRS, TRS, gating effectiveness.'},
    {title:'Channel / Interference', desc:'Pathloss, delay spread, dominant interferers, waterfall plots, LOS/NLOS.'},
    {title:'Beam / MIMO', desc:'Beam index, rank/layer usage, PMI/RI/CRI, beam stability, precoder truth.'},
    {title:'Latency', desc:'CDF, decomposition, HARQ delay, queue delay, scheduler delay.'},
    {title:'Energy', desc:'UE/cell energy, energy per bit, power states, transitions.'},
    {title:'Compare Runs', desc:'Baseline vs candidate, KPI deltas, compatibility checks.'},
    {title:'Output Coverage', desc:'Coverage registry, completeness, API exposure, honest unavailable.'},
    {title:'Root Cause', desc:'Anomaly windows, cross-layer correlations, dominant symptom/cause maps.'}
  ],
  parameterRows: [
    ['scenario_id','Scenario','browser+yml','string','LLS_4GHz_100MHz_19S3_100UE_UMa','configured'],
    ['num_sites','Geometry','browser+yml','int','19','configured'],
    ['sectors_per_site','Geometry','browser+yml','int','3','configured'],
    ['num_ues_total','Geometry','browser+yml','int','100','configured'],
    ['carrier_frequency_hz','Waveform','browser+yml','Hz','4.0e9','configured'],
    ['system_bandwidth_hz','Waveform','browser+yml','Hz','100e6','configured'],
    ['numerology_mu','Waveform','browser+yml','int','1','configured'],
    ['subcarrier_spacing_kHz','Waveform','browser+yml','kHz','30','configured'],
    ['scheduler_type','MAC','browser+yml','enum','pf','configured'],
    ['target_bler_dl','MAC','browser+yml','ratio','0.1','configured'],
    ['MeasuredTrialSINR_dB','PHY','runtime','dB','varies','measured'],
    ['AppliedPrecoderPMI','Beamforming','runtime','int','varies','applied']
  ]
};
