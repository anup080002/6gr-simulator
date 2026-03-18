function cfg = defaultConfig()
% sixgr.config.defaultConfig
% Canonical default configuration for 6GR Sim Studio unified simulator.
%
% Notes:
% - Keep this file pure MATLAB (no toolbox calls) so it always loads.
% - Organize by layers and domains: run, scenario, channel, phy, mac, rlc,
%   pdcp, rrc, rf, ai, outputs, gui.
% - All numeric units are explicit in the field name.

cfg = struct();

% -------------------------------------------------------------------------
% Meta / provenance
% -------------------------------------------------------------------------
cfg.meta = struct();
cfg.meta.toolkitName = '6GR Sim Studio Unified';
cfg.meta.version = 'v18';
cfg.meta.schemaVersion = 1;
cfg.meta.createdUTC = char(datetime('now','TimeZone','UTC','Format','yyyy-MM-dd''T''HH:mm:ss''Z'''));
cfg.meta.loadedFrom = '';

% -------------------------------------------------------------------------
% Run control
% -------------------------------------------------------------------------
cfg.run = struct();
cfg.run.seed = 1;
cfg.run.mode = 'both';              % link|system|hybrid|both
cfg.run.module = 'sixgr_run_3gpp_full_campaign'; % unified public entrypoint
cfg.run.failFast = true;
cfg.run.useParallel = false;
cfg.run.numWorkers = 0;             % 0 -> auto / use default pool
cfg.run.resultsRoot = 'results';
cfg.run.runTag = '';                % optional string appended to run folder
cfg.run.shortRun = true;            % quick smoke runs vs long runs
cfg.run.numFrames = 20;             % link-level default frames per SNR point
cfg.run.numTTI = 200;               % system-level default TTIs
cfg.run.saveIntermediate = false;
cfg.run.verbose = true;

% -------------------------------------------------------------------------
% Scenario / layout / mobility
% -------------------------------------------------------------------------
cfg.scenario = struct();

% Active scenario name (must match a profile in cfg.scenario.profiles.*)
cfg.scenario.name = 'UrbanMacro';

% Layout generation controls
cfg.scenario.layout = struct();
cfg.scenario.layout.type = 'hex';     % hex|grid|manual
cfg.scenario.layout.nSites = 19;      % typical 3GPP UMa hex grid
cfg.scenario.layout.interSiteDistance_m = 500;
cfg.scenario.layout.nSectorsPerSite = 3;
cfg.scenario.layout.wrapAround = true;

% Base station parameters (gNB)
cfg.scenario.bs = struct();
cfg.scenario.bs.height_m = 25;
cfg.scenario.bs.txPower_dBm = 46;     % per carrier
cfg.scenario.bs.noiseFigure_dB = 7;
cfg.scenario.bs.nTxAnt = 64;
cfg.scenario.bs.nRxAnt = 64;
cfg.scenario.bs.antenna = struct();
cfg.scenario.bs.antenna.type = 'URA'; % URA|ULA|custom
cfg.scenario.bs.antenna.size = [8 8]; % [M N] for URA
cfg.scenario.bs.antenna.elementSpacing_wl = [0.5 0.5];

% UE parameters
cfg.scenario.ue = struct();
cfg.scenario.ue.nUE = 190;               % total UEs in scenario
cfg.scenario.ue.height_m = 1.5;
cfg.scenario.ue.txPower_dBm = 23;
cfg.scenario.ue.noiseFigure_dB = 9;
cfg.scenario.ue.nTxAnt = 4;
cfg.scenario.ue.nRxAnt = 4;
cfg.scenario.ue.distribution = struct();
cfg.scenario.ue.distribution.type = 'uniform'; % uniform|hotspot|manual
cfg.scenario.ue.distribution.indoorFraction = 0.2;
cfg.scenario.ue.distribution.minBSdist_m = 10;
cfg.scenario.ue.distribution.maxBSdist_m = 500;

% Mobility (UE movement)
cfg.scenario.mobility = struct();
cfg.scenario.mobility.enable = true;
cfg.scenario.mobility.model = 'randomWaypoint'; % randomWaypoint|straightLine|trace
cfg.scenario.mobility.speed_kmh = [3 30];       % [min max] for random draws
cfg.scenario.mobility.updatePeriod_s = 0.1;

% Traffic / QoS (system-level)
cfg.traffic = struct();
cfg.traffic.model = 'fullBuffer';  % fullBuffer|xr|genai|mmtc|mixed
cfg.traffic.transport = 'UDP';     % UDP|TCP|MIXED
cfg.traffic.flowDirection = 'BIDIR'; % DL|UL|BIDIR
cfg.traffic.dlRatio = 0.8;         % DL share of offered load
cfg.traffic.ulRatio = 0.2;
cfg.traffic.packetDelayBudget_ms = 50;
cfg.traffic.packetSize_bytes = 1200;
cfg.traffic.packetInterval_ms = 10;
cfg.traffic.targetRate_Mbps = 50;
cfg.traffic.jitterPct = 0.1;
cfg.traffic.fullBufferBitsPerTTI = 1e5;
cfg.traffic.tcp = struct();
cfg.traffic.tcp.initCwnd_packets = 10;
cfg.traffic.tcp.maxCwnd_packets = 256;
cfg.traffic.tcp.lossProb = 0.01;
cfg.traffic.tcp.lossBackoff = 0.5;
cfg.traffic.tcp.minRateFloor = 0.2;
cfg.traffic.qos = struct();
cfg.traffic.qos.enable5QI = true;
cfg.traffic.qos.default5QI = 9;    % eMBB default
cfg.traffic.qos.latencyBudget_ms = 50;
cfg.traffic.qos.flows = [];        % optional array of per-flow configs
cfg.traffic.flows = struct([]);    % optional array of explicit flow definitions

% -------------------------------------------------------------------------
% System-level mobility-control loop (measurement / beam / handover)
% -------------------------------------------------------------------------
cfg.system = struct();
cfg.system.tti_s = [];                 % [] -> derive from numerology
cfg.system.queueMaxBits = 5e7;
cfg.system.ulSinrOffset_dB = -1.0;
cfg.system.mobility = struct();
cfg.system.mobility.updatePeriod_slots = [];         % [] -> derive from scenario.mobility.updatePeriod_s
cfg.system.largeScaleUpdatePeriod_slots = [];        % [] -> reuse mobility update cadence
cfg.system.measurement = struct();
cfg.system.measurement.periodSlots = 2;
cfg.system.measurement.filterAlpha = 0.7;
cfg.system.beam = struct();
cfg.system.beam.enable = true;
cfg.system.beam.numBeams = 8;
cfg.system.beam.updatePeriod_slots = 4;
cfg.system.beam.sectorSpan_deg = 120;
cfg.system.beam.maxGain_dB = 12;
cfg.system.handover = struct();
cfg.system.handover.enable = true;
cfg.system.handover.a3Offset_dB = 3.0;
cfg.system.handover.hysteresis_dB = 1.0;
cfg.system.handover.timeToTrigger_slots = 6;
cfg.system.handover.minServingSlots = 8;
cfg.system.handover.preparationSlots = 1;
cfg.system.handover.interruptionSlots = 2;
cfg.system.handover.blockDuringPreparation = false;

% -------------------------------------------------------------------------
% Channel models
% -------------------------------------------------------------------------
cfg.channel = struct();
cfg.channel.type = 'TR38901';      % TR38901|TDL|CDL|raytracing|AWGN
cfg.channel.fc_Hz = 4.0e9;
cfg.channel.bandwidth_Hz = 100e6;
cfg.channel.subcarrierSpacing_kHz = 30;

% Large-scale
cfg.channel.pathloss = struct();
cfg.channel.pathloss.model = 'nrPathLoss'; % nrPathLoss|CI|ABG|custom
cfg.channel.shadowFadingStd_dB = 6;
cfg.channel.o2iLoss_dB = 0;              % optional additional penetration

% Small-scale fading
cfg.channel.fading = struct();
cfg.channel.fading.enable = true;
cfg.channel.fading.model = 'TDL';    % TDL|CDL
cfg.channel.fading.profile = 'TDL-C';
cfg.channel.fading.delaySpread_s = 100e-9;
cfg.channel.fading.maxDoppler_Hz = 70;

% Ray tracing (optional)
cfg.channel.raytracing = struct();
cfg.channel.raytracing.enable = false;
cfg.channel.raytracing.scene = '';          % e.g. 'city.stl' or siteviewer scene
cfg.channel.raytracing.method = 'sbr';      % sbr|image
cfg.channel.raytracing.maxReflections = 2;

% Interference
cfg.channel.interference = struct();
cfg.channel.interference.enable = true;
cfg.channel.interference.model = 'fullReuse'; % fullReuse|custom

% -------------------------------------------------------------------------
% PHY (NR waveform + channels + procedures)
% -------------------------------------------------------------------------
cfg.phy = struct();

% Common numerology / carrier
cfg.phy.carrier = struct();
cfg.phy.carrier.NCellID = 1;
cfg.phy.carrier.SubcarrierSpacing = 30; % kHz
cfg.phy.carrier.NSizeGrid = 51;         % RBs
cfg.phy.carrier.CyclicPrefix = 'normal';
cfg.phy.carrier.NFrame = 0;

% UL/DL enable flags
cfg.phy.dl = struct();
cfg.phy.ul = struct();
cfg.phy.duplex = struct();

cfg.phy.duplex.mode = 'TDD'; % TDD|FDD
cfg.phy.duplex.tddPattern = 'DDDSU'; % simple symbolic pattern (expand later)

% Waveform options
cfg.phy.waveform = struct();
cfg.phy.waveform.dl = 'CP-OFDM';      % CP-OFDM
cfg.phy.waveform.ul = 'DFT-s-OFDM';   % DFT-s-OFDM|CP-OFDM

% Synchronization / broadcast
cfg.phy.ssb = struct();
cfg.phy.ssb.enable = true;
cfg.phy.ssb.blockPattern = 'Case B';
cfg.phy.ssb.period_ms = 20;
cfg.phy.ssb.nBeams = 8;

cfg.phy.pbch = struct();
cfg.phy.pbch.enable = true;

cfg.phy.mib = struct();
cfg.phy.mib.enable = true;

cfg.phy.sib1 = struct();
cfg.phy.sib1.enable = true;

% PRACH (RACH)
cfg.phy.prach = struct();
cfg.phy.prach.enable = true;
cfg.phy.prach.configurationIndex = 16;
cfg.phy.prach.subcarrierSpacing_kHz = 1.25;
cfg.phy.prach.preambleFormat = 'A1';
cfg.phy.prach.rootSeqIndex = 1;
cfg.phy.prach.zeroCorrelationZone = 8;

% DL control: PDCCH
cfg.phy.pdcch = struct();
cfg.phy.pdcch.enable = true;
cfg.phy.pdcch.searchSpaceType = 'ue'; % ue|common
cfg.phy.pdcch.aggregationLevel = 8;
cfg.phy.pdcch.dciFormat = '1_0';

% DL data: PDSCH
cfg.phy.pdsch = struct();
cfg.phy.pdsch.enable = true;
cfg.phy.pdsch.modulation = '256QAM'; % QPSK|16QAM|64QAM|256QAM|1024QAM|4096QAM
cfg.phy.pdsch.nLayers = 4;
cfg.phy.pdsch.codeRate = 0.75;
cfg.phy.pdsch.enablePTRS = false;
cfg.phy.pdsch.dmrs = struct();
cfg.phy.pdsch.dmrs.typeApos = 2;
cfg.phy.pdsch.dmrs.configType = 1;
cfg.phy.pdsch.dmrs.numCDMGroupsWithoutData = 2;

% CSI-RS / CSI feedback
cfg.phy.csirs = struct();
cfg.phy.csirs.enable = true;
cfg.phy.csirs.nPorts = 8;

cfg.phy.csi = struct();
cfg.phy.csi.enable = true;
cfg.phy.csi.feedbackMode = 'PMI+CQI'; % PMI+CQI|RI+PMI+CQI|none

% UL control: PUCCH
cfg.phy.pucch = struct();
cfg.phy.pucch.enable = true;
cfg.phy.pucch.format = 2;

% UL data: PUSCH
cfg.phy.pusch = struct();
cfg.phy.pusch.enable = true;
cfg.phy.pusch.modulation = '256QAM';
cfg.phy.pusch.nLayers = 2;
cfg.phy.pusch.codeRate = 0.75;
cfg.phy.pusch.transformPrecoding = true; % DFT-s-OFDM
cfg.phy.pusch.dmrs = struct();
cfg.phy.pusch.dmrs.configType = 1;
cfg.phy.pusch.dmrs.numCDMGroupsWithoutData = 2;

% SRS (UL sounding)
cfg.phy.srs = struct();
cfg.phy.srs.enable = true;
cfg.phy.srs.nPorts = 2;
cfg.phy.srs.period_slots = 20;

% HARQ (PHY/MAC interface)
cfg.phy.harq = struct();
cfg.phy.harq.enable = true;
cfg.phy.harq.nProcesses = 16;
cfg.phy.harq.rvSequence = [0 2 3 1];

% LDPC decoder options
cfg.phy.ldpc = struct();
cfg.phy.ldpc.maxIterations = 12;
cfg.phy.ldpc.algorithm = 'Normalized min-sum';
cfg.phy.ldpc.useMexBatchDecode = true;

% Receiver algorithms (link-level)
cfg.phy.rx = struct();
cfg.phy.rx.channelEstimation = 'DMRS';     % DMRS|SRS|perfect
cfg.phy.rx.equalizer = 'MMSE';            % ZF|MMSE|IRC
cfg.phy.rx.mimoDetector = 'MMSE';         % MMSE|ML|SIC
cfg.phy.rx.cfoCompensation = true;
cfg.phy.rx.useFastChannelEstMex = false;

% -------------------------------------------------------------------------
% MAC / Scheduler / L2
% -------------------------------------------------------------------------
cfg.mac = struct();
cfg.mac.scheduler = struct();
cfg.mac.scheduler.type = 'PF';           % PF|RR|MaxCqi
cfg.mac.scheduler.metricAveraging = 'exp';
cfg.mac.scheduler.alpha = 0.9;
cfg.mac.harq = struct();
cfg.mac.harq.enable = true;
cfg.mac.harq.maxRetx = 3;

cfg.rlc = struct();
cfg.rlc.mode = 'AM';                     % AM|UM|TM
cfg.rlc.tPollRetransmit_ms = 45;
cfg.rlc.tReassembly_ms = 35;

cfg.pdcp = struct();
cfg.pdcp.snLen_bits = 18;
cfg.pdcp.enableCiphering = false;
cfg.pdcp.enableIntegrity = false;

cfg.sdap = struct();
cfg.sdap.enable = true;

cfg.rrc = struct();
cfg.rrc.enable = true;
cfg.rrc.attachProcedure = true;

% -------------------------------------------------------------------------
% RF impairments + energy
% -------------------------------------------------------------------------
cfg.rf = struct();
cfg.rf.enable = false; % enable RF impairment chain in link-level sims
cfg.rf.noiseFigure_dB = 7;
cfg.rf.iqImbalance = struct('enable',false,'ampImb_dB',0,'phaseImb_deg',0);
cfg.rf.phaseNoise = struct('enable',false,'level_dBcHz',-80,'offset_Hz',1e5);
cfg.rf.pa = struct('enable',false,'model','memoryless','backoff_dB',3);

cfg.energy = struct();
cfg.energy.enable = true;
cfg.energy.bs = struct('pStatic_W',500,'pDynPerWattPerHz',2e-6);
cfg.energy.ue = struct('pStatic_W',2,'pDynPerWattPerHz',5e-6);

% -------------------------------------------------------------------------
% AI / ML modules (placeholders wired by config)
% -------------------------------------------------------------------------
cfg.ai = struct();
cfg.ai.enable = false;

cfg.ai.csiCompression = struct();
cfg.ai.csiCompression.enable = false;
cfg.ai.csiCompression.latentDim = 64;
cfg.ai.csiCompression.network = 'autoencoder'; % autoencoder|transformer

cfg.ai.beamSelection = struct();
cfg.ai.beamSelection.enable = false;
cfg.ai.beamSelection.network = 'cnn';

cfg.ai.neuralReceiver = struct();
cfg.ai.neuralReceiver.enable = false;
cfg.ai.neuralReceiver.type = 'nnEqualizer';

cfg.ai.positioning = struct();
cfg.ai.positioning.enable = false;

% -------------------------------------------------------------------------
% Outputs / logging
% -------------------------------------------------------------------------
cfg.outputs = struct();
cfg.outputs.saveMAT = true;
cfg.outputs.saveCSV = true;
cfg.outputs.saveFigures = true;  % canonical flag used by runners
cfg.outputs.saveFIG = cfg.outputs.saveFigures; % backward-compatible alias
cfg.outputs.savePNG = true;
cfg.outputs.plotVisible = false;
cfg.outputs.kpi = struct();
cfg.outputs.kpi.enable = true;
cfg.outputs.kpi.list = {'throughput','bler','ber','evm','papr','sinr','cqi'};

% -------------------------------------------------------------------------
% GUI defaults
% -------------------------------------------------------------------------
cfg.gui = struct();
cfg.gui.enable = true;
cfg.gui.useSiteViewer = true;
cfg.gui.showUEMobility = true;

end
