function cfg = buildF1RuntimeConfig(study, caseRow, snrDB, seed)
%BUILDF1RUNTIMECONFIG Resolve a fixed-MCS independent-TB calibration config.
% This is a physical link calibration, with no access/control/HARQ lifecycle.
arguments
    study struct
    caseRow table
    snrDB (1,1) double {mustBeFinite}
    seed (1,1) double {mustBeInteger,mustBePositive}
end
assert(height(caseRow)==1 && string(caseRow.ExperimentID)=="F1", ...
    'sixgr:ran1ai1032:F1Case','Exactly one F1 case is required.');
e=study.lls.execution;
assert(string(e.base_config_path)=="sixgr.config.defaultConfig", ...
    'sixgr:ran1ai1032:F1BaseConfig','Use the explicitly selected YAML-backed core default factory.');
cfg=sixgr.config.defaultConfig();
cfg.run.seed=seed;
cfg.run.numFrames=1;
cfg.run.strictMode=true;
cfg.run.noProxyTruthContract=true;
cfg.run.fixedReferenceMode=true;
cfg.run.noiseOperatingMode='standalone_awgn_snr_argument';
cfg.integration.run_mode='FIXED_SNR_SWEEP';
cfg.integration.configured_snr_is_link_authority=true;
cfg.integration.power_reference_mode='normalized_unit_es';
cfg.run.interferenceExecutionMode='none';
cfg.run.puschExecutionProfile='phy_calibration';
cfg.phy.pusch.executionProfile='phy_calibration';
cfg.phy.carrier.NSizeGrid=double(e.grid_prbs);
cfg.phy.carrier.NStartGrid=0;
cfg.phy.carrier.SubcarrierSpacing=double(study.carrier.scs_khz);
cfg.phy.carrier.SubcarrierSpacing_kHz=double(study.carrier.scs_khz);
cfg.phy.carrier.CyclicPrefix='normal';
cfg.phy.carrier.NCellID=double(e.cell_id);
cfg.phy.channelBandwidth_MHz=double(study.carrier.bandwidth_hz)/1e6;
cfg.channel.bandwidth_Hz=double(study.carrier.bandwidth_hz);
cfg.channel.fc_Hz=double(study.carrier.frequency_hz);
cfg.channel.carrierFrequency_Hz=double(study.carrier.frequency_hz);
cfg.phy.fc_Hz=double(study.carrier.frequency_hz);
cfg.phy.duplexMode='TDD'; cfg.frame.duplexMode='TDD'; cfg.channel.duplexMode='TDD';
cfg.phy.bwp.ul=struct('NStartBWP',0,'NSizeBWP',double(e.grid_prbs));
cfg.phy.bwp.dl=cfg.phy.bwp.ul;
cfg.channel.model=char(caseRow.ChannelProfile);
cfg.channel.awgnOnly=string(caseRow.ChannelProfile)=="AWGN";
cfg.channel.fading.enable=~cfg.channel.awgnOnly;
if cfg.channel.awgnOnly
    cfg.channel.type='AWGN'; cfg.channel.fading.model=''; cfg.channel.fading.profile='';
else
    cfg.channel.type=char(extractBefore(string(caseRow.ChannelProfile),'-'));
    cfg.channel.fading.model=cfg.channel.type;
    cfg.channel.fading.profile=char(caseRow.ChannelProfile);
end
cfg.channel.fading.delaySpread_s=double(caseRow.DelaySpread_ns)*1e-9;
cfg.channel.delaySpread_s=cfg.channel.fading.delaySpread_s;
cfg.channel.delaySpread=cfg.channel.delaySpread_s;
cfg.channel.doppler_Hz=double(study.lls.mobility.derived_doppler_hz);
cfg.channel.fading.maxDoppler_Hz=cfg.channel.doppler_Hz;
if startsWith(string(caseRow.ChannelProfile),"CDL-")
    cfg.channel.cdlProfile=char(caseRow.ChannelProfile);
    cfg.channel.fading.cdlProfile=cfg.channel.cdlProfile;
elseif startsWith(string(caseRow.ChannelProfile),"TDL-")
    cfg.channel.tdlProfile=char(caseRow.ChannelProfile);
    cfg.channel.fading.tdlProfile=cfg.channel.tdlProfile;
end
cfg.channel.pathlossEnabled=false; cfg.channel.shadowFadingEnabled=false;
cfg.channel.snr_dB=snrDB;
cfg.channel.awgnReferenceREEnergy=double(e.awgn_reference_re_energy);
nt=double(caseRow.TxChains); nr=double(caseRow.RxChains); rank=double(caseRow.Rank);
assert(rank<=min(nt,nr),'sixgr:ran1ai1032:F1Rank','Rank exceeds physical chains.');
cfg.phy.nTxAnt=nr; cfg.phy.nRxAnt=nt; % Global fields are DL-oriented.
cfg.antenna.ue.numElements=nt; cfg.antenna.bs.numElements=nr;
cfg.scenario.ue.nTxAnt=nt; cfg.scenario.ue.nRxAnt=nt;
cfg.scenario.bs.nTxAnt=nr; cfg.scenario.bs.nRxAnt=nr;
cfg.channel.ul=struct('nTxAnt',nt,'nRxAnt',nr);
cfg.channel.nTxAnt=nr; cfg.channel.nRxAnt=nt;
cfg.channel.nTxAntUL=nt; cfg.channel.nRxAntUL=nr;
cfg.channel.sharedIdentityAWGNEnabled=false;
if cfg.channel.awgnOnly
    assert(string(e.awgn_spatial_policy)=="unit_column_dft", ...
        'sixgr:ran1ai1032:F1SpatialPolicy','AWGN requires explicit unit_column_dft policy.');
    % Unit-norm orthogonal columns; total received energy equals TX energy.
    % Stored DL matrix is transposed by the directional channel factory.
    H=exp(-1i*2*pi*(0:nr-1).'*(0:nt-1)/nr)/sqrt(nr);
    cfg.channel.awgnSpatialMatrixDL=H.';
    assert(norm(H'*H-eye(nt),'fro')<1e-10, ...
        'sixgr:ran1ai1032:F1SpatialPower','AWGN channel must conserve total power.');
end
tableA=sixgr.studies.ran1ai1032.MCSCatalog.optionA();
entry=tableA(tableA.entry_id==string(caseRow.EntryID),:);
assert(height(entry)==1,'sixgr:ran1ai1032:F1Entry','Unknown immutable F1 entry.');
cfg.phy.pusch.enable=true;
cfg.phy.pusch.mcsTable='experimental_6gr_ai1032_option_a';
cfg.phy.pusch.experimentalMCSTable=sixgr.phy.research.resolveExperimentalMCSTable(cfg.phy.pusch.mcsTable);
cfg.phy.pusch.researchTransportPolicy=sixgr.lls6g.config.readConfigFile(string(e.research_transport_policy_path));
assert(string(cfg.phy.pusch.researchTransportPolicy.meta.research_class)== ...
    string(cfg.phy.pusch.experimentalMCSTable.ResearchClass), ...
    'sixgr:ran1ai1032:F1ResearchPolicy','Transport policy and installed MCS research classes differ.');
cfg.phy.pusch.mcsIndex=double(entry.indication_index);
cfg.phy.pusch.configuredMCSIndex=cfg.phy.pusch.mcsIndex;
cfg.phy.pusch.modulation=char(string(2^double(entry.Qm))+"QAM");
cfg.phy.pusch.codeRate=double(entry.target_code_rate_x1024)/1024;
cfg.phy.pusch.nLayers=rank; cfg.phy.pusch.numLayers=rank;
cfg.phy.pusch.numAntennaPorts=nt; cfg.phy.pusch.numPorts=nt;
cfg.phy.pusch.NumAntennaPorts=nt;
cfg.phy.pusch.prbSet=0:double(e.grid_prbs)-1; cfg.phy.pusch.PRBSet=cfg.phy.pusch.prbSet;
cfg.phy.pusch.symbolAllocation=[double(study.lls.reference_pusch.start_symbol), ...
    double(study.lls.reference_pusch.number_of_symbols)];
cfg.phy.pusch.mappingType='A'; cfg.phy.pusch.transformPrecoding=false;
cfg.phy.pusch.transmissionScheme='codebook'; cfg.phy.pusch.TPMI=double(e.tpmi);
if nt==1, cfg.phy.pusch.transmissionScheme='nonCodebook'; end
cfg.phy.pusch.enablePTRS=false; cfg.phy.pusch.RNTI=double(e.rnti);
cfg.phy.pusch.rv=0; cfg.phy.pusch.xOverhead=0; cfg.phy.pusch.equalizer='MMSE';
cfg.phy.pusch.dmrs.typeAPosition=double(e.dmrs_type_a_position);
cfg.phy.pusch.dmrs.additionalPosition=double(e.dmrs_additional_position);
cfg.phy.pusch.dmrs.additionalPositions=double(e.dmrs_additional_position);
cfg.phy.pusch.dmrs.length=1; cfg.phy.pusch.dmrs.configurationType=1;
cfg.phy.pusch.dmrs.maxLength=1;
cfg.phy.pusch.dmrs.numCDMGroupsWithoutData=double(e.dmrs_cdm_groups_without_data);
cfg.phy.pusch.dmrs.portSet=0:rank-1; cfg.phy.pusch.dmrs.scheduledPortSet=0:rank-1;
cfg.phy.channelEstimation.method='LS'; cfg.phy.ldpc.maxIterations=double(study.lls.ldpc.maximum_iterations);
cfg.mac.scheduler.fastNREApprox=false;
cfg.phy.harq.enable=false; cfg.mac.harq.enable=false;
cfg.phy.linkAdaptation.mode='fixed'; cfg.phy.linkAdaptation.ulPolicy='fixed';
cfg.phy.linkAdaptation.rankPolicy='fixed'; cfg.phy.linkAdaptation.beamPolicy='fixed';
cfg.phy.linkAdaptation.innerLoopFlag=false; cfg.phy.linkAdaptation.outerLoopFlag=false;
cfg.phy.linkAdaptation.fixedReferenceMode=true;
cfg.phy.pusch.powerControl.enabled=false; cfg.powerAndRF.puschPowerControlEnabled=false;
for f=["cfoEnabled","phaseNoiseEnabled","iqImbalanceEnabled","timingOffsetEnabled","paNonlinearityEnabled"]
    cfg.phy.impairments.(f)=false;
end
cfg.phy.impairments.cfoHz=0; cfg.phy.impairments.timingOffsetSamples=0;
cfg.phy.rx.cfoCorrectionEnabled=false; cfg.phy.rx.iqImbalanceCorrectionEnabled=false;
for f=["pbch","mib","sib1","pdcch","pucch","srs","trs","ptrs","csirs","prach","pdsch"]
    cfg.phy.(f).enable=false;
end
cfg.outputs.rawIQCaptureEnabled=false; cfg.outputs.saveRawWaveforms=false;
cfg.lls6g.users.enabled=false; cfg.lls6g.users.n_users=1;
cfg.lls6g.users.beam_selection_strategy='fixed_first_beam';
cfg.meta.f1StudyCaseID=char(caseRow.CaseID);
cfg.meta.f1RFBranch=char(e.rf_branch);
cfg.meta.f1PowerPlane='normalized_total_UE_power_occupied_RE_reference';
branch=sixgr.studies.ran1ai1032.resolveF1RFBranch(study,cfg.phy.pusch.modulation);
cfg.rf.studyBranch=branch;
cfg.meta.f1RFProfileID=char(sixgr.studies.ran1ai1032.rfBranchIdentity(branch));
if isfield(branch,'ptrs')
    p=branch.ptrs;
    cfg.phy.pusch.enablePTRS=logical(p.enabled);
    cfg.phy.pusch.ptrs=struct('enableCPECorrection',logical(p.compensation_enabled), ...
        'timeDensity',double(p.time_density),'frequencyDensity',double(p.frequency_density), ...
        'reOffset',char(p.re_offset),'portSet',double(p.port_set));
end
% All independent F1 endpoint RF policy is set explicitly. CFO uses the
% production retained oscillator; EVM is added once at each physical plane.
cfg.rf.tx.cfo_Hz=double(branch.residual_normalized_cfo)*1000*study.carrier.scs_khz;
cfg.rf.rx.cfo_Hz=0;
cfg.phy.impairments.cfoEnabled=cfg.rf.tx.cfo_Hz~=0;
cfg.phy.impairments.cfoHz=cfg.rf.tx.cfo_Hz;
cfg.phy.impairments.phaseNoiseEnabled=logical(branch.phase_noise_enabled);
cfg.rf.rx.additiveEVMStudy=struct('enabled',double(branch.rx_evm_percent)>0, ...
    'percent',double(branch.rx_evm_percent),'seed',mod(double(seed)+29011,2^32), ...
    'reference','pre_receiver_noise_physical_signal_per_chain', ...
    'normalization','complete_observation_mean');
cfg.rf.tx.phaseNoise.enable=false; cfg.rf.rx.phaseNoise.enable=false;
if logical(branch.phase_noise_enabled)
    % PhaseNoiseModel resolves this canonical versioned profile in the
    % production retained RF chain. No frequency-derived default is used.
    cfg.rf.specification.profile_id='rf_impaired_research';
    cfg.rf.configurationEpoch=1;
    cfg.rf.frontend.phase_noise=branch.phase_noise_profile;
    cfg.rf.frontend.phase_noise.seed=mod(double(seed)+71023,2^32);
    cfg.rf.tx.phaseNoise.enable=true;
end
cfg.meta.f1RFClassification=char(branch.classification);
end
