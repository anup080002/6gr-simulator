function ok=testAbsoluteReferenceNoiseWaveform()
% One actual DL TB, UL TB and SRS occasion through direct production owners.
% The required phy_calibration API profile means isolated PHY ownership here,
% NOT calibration, BLER/SINR accuracy, received control or campaign evidence.
% The actual channel is explicitly unit AWGN; the frozen UMa reference is a
% separate nominal noise definition, never asserted to match received SINR.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
logs=fullfile(pwd,'logs'); if ~isfolder(logs), mkdir(logs); end
folder=tempname(logs); mkdir(folder);
fprintf('ABSOLUTE_REFERENCE_WAVEFORM evidence=%s\n',folder);
cfg=configuration(folder);
save(fullfile(folder,'original_configuration.mat'),'cfg');
failures=strings(0,1);
for signal=["PDSCH","PUSCH","SRS"]
    try
        if signal=="SRS", runSRS(cfg,folder); else, runData(cfg,folder,signal); end
        fprintf('ABSOLUTE_REFERENCE_WAVEFORM %s PASS\n',signal);
    catch cause
        failures(end+1)=signal+": "+string(cause.identifier)+" "+string(cause.message); %#ok<AGROW>
        fprintf(2,'%s\n',getReport(cause,'extended','hyperlinks','off'));
    end
end
save(fullfile(folder,'completion.mat'),'failures');
assert(isempty(failures),'test:AbsoluteReferenceNoiseWaveform','%s; evidence=%s', ...
    strjoin(failures,newline),folder);
ok=true;
fprintf('ABSOLUTE_REFERENCE_WAVEFORM_PASS DL_attempts=1 UL_attempts=1 SRS_occasions=1 extra_RX=0 performance_claim=0 evidence=%s\n',folder);
end

function runData(cfg,folder,signal)
direction="DL"; if signal=="PUSCH", direction="UL"; end
cfg=sixgr.util.structSet(cfg,'lls6g.userContext.RuntimeCurrentDirection',direction);
if direction=="DL"
    result=sixgr.link.runDLPDSCHThroughput(cfg,'NumFrames',1, ...
        'SNR_dB',cfg.channel.snr_dB,'ExecutionProfile','phy_calibration');
else
    result=sixgr.link.runULPUSCHThroughput(cfg,'NumFrames',1, ...
        'SNR_dB',cfg.channel.snr_dB,'ExecutionProfile','phy_calibration');
end
% Retain the original result before any new evidence assertion can fail.
save(fullfile(folder,lower(signal)+'_original_result.mat'),'result','cfg');
T=result.TrialTable;
assert(~result.Skipped&&height(T)==1&&~T.Crash&&T.DecodeAttempted&& ...
    T.ChannelEstimateAttempted&&T.ResourceExtractionAttempted, ...
    'test:AbsoluteNoiseReceiver','Actual %s receiver did not complete.',signal);
assert(string(T.ApproximationMode)=="none"&& ...
    string(T.ExecutionProfile)=="phy_calibration"&&~T.StrictSchedulingOwnership);
assert(T.ReceiverReplayCaptureStatus=="captured_exact_receiver_input");
path=fullfile(folder,T.ReceiverReplayMATFile);
assert(string(sixgr.util.sha256File(path))==T.ReceiverReplayMATSHA256);
saved=load(path,'ReceiverReplay'); original=saved.ReceiverReplay;
assert(original.Source=="executed_receiver_input_not_reconstructed"&& ...
    ~original.CaptureUsedByReceiver&&original.AdditionalChannelExecutions==0&& ...
    ~original.Context.ScoringReferenceReceiverInput&& ...
    original.Context.ScoringReferenceAdditionalChannelExecutions==0&& ...
    original.Context.ScoringOnlyDesiredWaveformSource=="same_executed_isolated_desired_link_samples");
assert(original.WaveformSHA256== ...
    string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(original.Waveform)));
rx=original.ReceiverResult;
assert(rx.DecodeAttempted&&islogical(rx.TBCRCPass)&&isscalar(rx.TBCRCPass)&& ...
    logical(T.CRCPass)==rx.TBCRCPass);
bits=rx.TransportBlock; transmitted=original.Context.ScoringOnlyTransmittedBits;
assert(isnumeric(bits)&&isnumeric(transmitted)&&numel(bits)==numel(transmitted)&& ...
    numel(bits)==T.TBSize_bits&&T.BitsCompared==numel(bits)&& ...
    T.BitErrors==sum(bits(:)~=transmitted(:)), ...
    'test:AbsoluteNoiseDecodeOutcome','Retain the actual decoder payload/CRC, including any failure.');
% Neither CRC success nor measured SINR==nominal Es/N0 is an acceptance gate.
assertPublication(table2struct(T),cfg,direction);
assertNoiseSamples(original.Waveform,original.Context.ScoringOnlyDesiredWaveform, ...
    T.AbsoluteReferenceNoiseInjectedSampleVariance_mW,signal);
writeAndCheck(fullfile(folder,lower(signal)+'_trials.csv'),T);
fprintf('ABSOLUTE_NOISE_RX signal=%s CRC=%d bits=%g errors=%g N0=%.17g draw=%.17g\n', ...
    signal,T.CRCPass,T.TBSize_bits,T.BitErrors,T.ReferenceNoisePSD_mWPerHz, ...
    T.AbsoluteReferenceNoiseInjectedSampleVariance_mW);
end

function runSRS(cfg,folder)
cfg=sixgr.util.structSet(cfg,'lls6g.userContext.RuntimeCurrentDirection',"UL");
[result,capture]=sixgr.link.runSRSChannelEstimation(cfg, ...
    'SNR_dB',cfg.channel.snr_dB,'TrialIndex',1,'SlotIndex',1);
save(fullfile(folder,'srs_original_result.mat'),'result','capture','cfg');
assert(~result.Skipped&&isfield(capture,'Rx')&& ...
    result.DetectionAttempted&&result.ResourceExtractionAttempted&& ...
    result.ChannelEstimateAttempted&&result.ChannelEstimateAvailable&& ...
    ~isempty(capture.Rx.Hest)&&all(isfinite(capture.Rx.Hest),'all'), ...
    'test:AbsoluteNoiseSRSReceiver','SRS requires an actual finite receiver estimate, not a prepared transmission.');
assertPublication(result,cfg,"UL");
pub=sixgr.link.absoluteReferenceNoisePublication(capture.Replay);
fromOutput=sixgr.link.absoluteReferenceNoisePublication(result.NoiseExecutionEvidence);
assert(isequaln(pub,fromOutput));
for field=string(fieldnames(pub)).'
    assert(isequaln(result.(field),pub.(field)),'SRS output changed original %s.',field);
end
assertNoiseSamples(capture.ReceivedWaveform,capture.ScoringReferenceWaveform, ...
    result.AbsoluteReferenceNoiseInjectedSampleVariance_mW,"SRS");
% Serialize only actual returned scalar fields; do not invent a collector row
% or any accepted SRS/scheduler/received-control authority.
row=pub;
for field=["NoiseOperatingMode","ConfiguredSNR_dB","AppliedAWGNSNR_dB", ...
        "DetectionAttempted","DetectionSuccess","ChannelEstimateAttempted", ...
        "ChannelEstimateAvailable","StrictOk","SRSRuntimeEvidenceUsable", ...
        "NoiseVariance","SINR_dB","SINRSource","FailureReason"]
    row.(field)=result.(field);
end
writeAndCheck(fullfile(folder,'srs_returned_evidence.csv'),struct2table(row));
fprintf('ABSOLUTE_NOISE_RX signal=SRS detected=%d H_available=%d strict=%d N0=%.17g draw=%.17g\n', ...
    result.DetectionSuccess,result.ChannelEstimateAvailable,result.StrictOk, ...
    result.ReferenceNoisePSD_mWPerHz,result.AbsoluteReferenceNoiseInjectedSampleVariance_mW);
end

function assertPublication(row,cfg,direction)
assert(row.AbsoluteReferenceNoiseEvidenceAvailable&& ...
    string(row.NoiseOperatingMode)=="absolute_reference_esn0"&& ...
    isnan(row.AppliedAWGNSNR_dB)&&row.ThermalNoiseApplied==0&& ...
    row.ControlledReferenceNoiseApplied==1&&row.ConfiguredSNR_dB==cfg.channel.snr_dB);
token=string(row.AbsoluteReferenceNoiseJSON);
assert(string(row.AbsoluteReferenceNoiseJSONSHA256)==string(sixgr.util.sha256Hex(char(token))));
[variance,expected]=sixgr.link.resolveAbsoluteReferenceNoise(cfg,direction,row.ReferenceNoiseSampleRate_Hz);
assert(token==string(jsonencode(expected)), ...
    'test:AbsoluteNoiseOriginalReceipt','Returned receipt must retain the original frozen direction/reference.');
assert(row.RequestedReferenceEsN0_dB==expected.RequestedReferenceEsN0_dB&& ...
    row.ReferenceNoisePSD_mWPerHz==expected.NoisePSD_mWPerHz&& ...
    row.ReferenceNoiseSampleVariance_mW==variance&& ...
    row.AbsoluteReferenceNoiseInjectedSampleVariance_mW==variance&& ...
    string(row.AbsoluteReferenceNoiseInjectionDomain)=="receiver_sample_waveform_pre_composite_front_end"&& ...
    string(row.ReferenceNoiseContractSHA256)==string(expected.ReferenceContractSHA256)&& ...
    string(row.ReferenceNoiseSource)==string(expected.Source)&& ...
    string(row.ReferenceNoiseReferencePlane)==string(expected.ReferencePoint));
end

function assertNoiseSamples(received,desired,variance,signal)
% The declared RF chain is identity. Both arrays are original returned
% samples; subtract only after reception, never feed this reference to RX.
assert(isequal(size(received),size(desired))&&~isempty(received)&& ...
    isa(received,'double')&&isa(desired,'double')&& ...
    all(isfinite(received),'all')&&all(isfinite(desired),'all'));
noise=received-desired;
observed=mean(abs(noise).^2,'all');
assert(isfinite(variance)&&variance>0&&isfinite(observed)&&observed>0&& ...
    abs(observed/variance-1)<.08,'test:AbsoluteNoiseActualDraw', ...
    '%s original sample difference power %.17g disagrees with N0*Fs %.17g.',signal,observed,variance);
fprintf('ABSOLUTE_NOISE_SAMPLES signal=%s count=%g expected=%.17g observed=%.17g population_tolerance=0.08\n', ...
    signal,numel(noise),variance,observed);
end

function writeAndCheck(path,T)
sixgr.util.csvWriteTable(path,T,'PreserveSchema',true,'RoundTripNumericText',true);
restored=sixgr.util.csvReadTable(path,'TextType','string');
defaults=sixgr.link.absoluteReferenceNoisePublication();
for field=string(fieldnames(defaults)).'
    if isstring(T.(field))
        assert(isequal(string(restored.(field)),T.(field)),'CSV changed %s.',field);
    else
        assert(isequaln(double(restored.(field)),double(T.(field))),'CSV changed %s.',field);
    end
end
end

function cfg=configuration(folder)
cfg=withCanonicalSchedulerTiming(sixgr.config.defaultConfig());
cfg.run.shortRun=true; cfg.run.seed=187913;
cfg.run.noiseOperatingMode='absolute_reference_esn0';
cfg.run.interferenceExecutionMode='none'; cfg.run.rootRunFolder=folder;
cfg.integration=struct('run_mode','GEOMETRY_NETWORK', ...
    'configured_snr_is_link_authority',false,'power_reference_mode','absolute_calibrated_sqrt_mw');
cfg.outputs.saveCSV=false; cfg.outputs.saveMAT=false; cfg.outputs.saveFigures=false;
cfg.outputs.phySignalDiagnosticEnabled=false;
cfg.outputs.receiverReplayCapturePolicy='all'; cfg.outputs.receiverReplayCaptureMaxTrials=1;
cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true; cfg.channel.snr_dB=10;
cfg.channel.bandwidth_Hz=10e6; cfg.channel.fc_Hz=2350e6; cfg.phy.fc_Hz=2350e6;
cfg.channel.pathlossEnabled=true; cfg.channel.pathloss_dB=0;
cfg.channel.nTxAnt=1; cfg.channel.nRxAnt=1; cfg.phy.nTxAnt=1; cfg.phy.nRxAnt=1;
cfg.scenario.ue.nTxAnt=1; cfg.scenario.ue.nRxAnt=1; cfg.antenna.ue.numElements=1;
cfg.scenario.bs.nTxAnt=1; cfg.scenario.bs.nRxAnt=1; cfg.antenna.bs.numElements=1;
cfg.phy.carrier=struct('NSizeGrid',24,'NStartGrid',0,'SubcarrierSpacing',30, ...
    'CyclicPrefix','normal','NCellID',1,'NSlot',0,'NFrame',0);
cfg.phy.numerology.scs_kHz=30; cfg.phy.numerology.cyclicPrefix='normal';
bwp=struct('NSizeBWP',24,'NStartBWP',0,'SubcarrierSpacing_kHz',30,'BWPID',0);
cfg.phy.bwp=struct('dl',bwp,'ul',bwp);
cfg.phy.ssb.enable=false; cfg.phy.csirs.enable=false; cfg.phy.csirs.enabled=false;
cfg.phy.channelEstimation.method='LS'; cfg.phy.rx.cfoCorrectionEnabled=false;
cfg.rf.enable=false; cfg.rf.pa.enable=false; cfg.rf.phaseNoise.enable=false;
cfg.rf.iqImbalance.enable=false; cfg.rf.agc.enable=false;
cfg.rf.adc.enable=false; cfg.rf.dac.enable=false;
cfg.powerAndRF.bsTxPower_dBm=30; cfg.powerAndRF.ueTxPower_dBm=23;
for key=["pdsch","pusch"]
    cfg.phy.(key).enable=true; cfg.phy.(key).executionProfile='phy_calibration';
    cfg.phy.(key).nLayers=1; cfg.phy.(key).numLayers=1;
    cfg.phy.(key).mcsIndex=4; cfg.phy.(key).mcsTable='qam64_table1';
    cfg.phy.(key).modulation='QPSK'; cfg.phy.(key).codeRate=308/1024;
    cfg.phy.(key).prbSet=0:5; cfg.phy.(key).symbolAllocation=[2 12];
    cfg.phy.(key).mappingType='A'; cfg.phy.(key).dmrs.portSet=0;
    cfg.phy.(key).dmrs.nPorts=1;
    cfg.phy.(key).equalizer='MMSE';
end
cfg.phy.pusch.numAntennaPorts=1; cfg.phy.pusch.numPorts=1;
cfg.phy.pusch.transmissionScheme='nonCodebook'; cfg.phy.pusch.transformPrecoding=false;
cfg.phy.pusch.enablePTRS=false;
cfg.phy.srs.enable=true; cfg.phy.srs.nPorts=1;
cfg.phy.srs.period_slots=1; cfg.phy.srs.period_offset=0;
cfg.phy.srs.SymbolStart=12; cfg.phy.srs.NumSRSSymbols=2;
cfg.phy.srs.Repetition=1; cfg.phy.srs.bandwidthRB=24;
cfg.phy.srs.expectedNumRB=24; cfg.phy.srs.resourceSetUsage='noncodebook';
nativeSRS=nrSRSConfig; bandwidths=nativeSRS.BandwidthConfigurationTable;
widths=bandwidths{:,'m_SRS_0'}; ids=bandwidths{:,'C_SRS'};
cfg.phy.srs.CSRS=double(ids(find(widths==24,1,'first'))); cfg.phy.srs.BSRS=0;
assert(isscalar(cfg.phy.srs.CSRS),'The native SRS table must support this declared 24-RB fixture.');
cfg.phy.srs.powerControlAlpha=0; cfg.phy.srs.p0=0; cfg.phy.srs.deltaTF_dB=0;
cfg.rf.frontend.configuration_epoch=1;
cfg.rf.frontend.ul_power_control.require_measured_reference_rs=false;
cfg.rf.frontend.ul_power_control.closed_loop_enabled=false;
cfg.rf.frontend.ul_power_control.srs.adjustment_state='open_loop_only';
cfg.lls6g.userContext.RuntimeServingPathloss_dB=0;
cfg.lls6g.userContext.RuntimeServingPathlossSource='declared_unit_channel_component_not_measurement';
cfg.run.absoluteReferenceNoisePolicy=struct('reference_policy','nominal_full_bwp_unity_array', ...
    'reference_pathloss_scenario','UMa','reference_bs_position_m',[0 0 25], ...
    'reference_ue_position_m',[85 0 1.5],'reference_los',false, ...
    'nominal_dl_tx_power_dbm',30,'nominal_ul_tx_power_dbm',23, ...
    'classification','optional_research_experiment');
carrier=sixgr.phy.grid.makeCarrier(cfg); ofdm=nrOFDMInfo(carrier);
[~,~,cfg.run.absoluteReferenceNoise]=sixgr.link.resolveAbsoluteReferenceNoise( ...
    cfg,"DL",double(ofdm.SampleRate),'Freeze',true);
end
