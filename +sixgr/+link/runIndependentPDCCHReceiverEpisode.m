function result=runIndependentPDCCHReceiverEpisode(cfg,prepared,design,folder)
% Installed connected PDCCH receiver on one actual H0/H1 physical episode.
% Internal API: policy, seeds and authored TX inputs belong to configuration.
% Physical/RF state starts at zero, translated to the configured radio slot.
% There is NO replayed access clock, oracle timing, known K/candidate, known
% noise variance, or TX-bit-aided receiver selection. This is not continuous
% scenario acceptance or statistical/conformance qualification.
arguments
    cfg (1,1) struct
    prepared struct
    design (1,1) struct
    folder (1,1) string
end
id='sixgr:link:InvalidPDCCHReceiverEpisode';
names=["EpisodeID","UEIndex","ServingCell","ChannelSeed","NoiseSeed", ...
    "GuardSamples","SignalPresent","AbsoluteSlot0","TimingBoundary"];
assert(isequal(sort(string(fieldnames(design))),sort(names(:))),id,'Undeclared or missing episode policy.');
assert(islogical(design.SignalPresent)&&isscalar(design.SignalPresent)&& ...
    design.SignalPresent==~isempty(prepared)&&(isempty(prepared)||isscalar(prepared)),id, ...
    'H0 requires no transmitter; H1 requires actual production preparation.');
assert(isscalar(string(design.EpisodeID))&&~ismissing(string(design.EpisodeID))&& ...
    strlength(strtrim(string(design.EpisodeID)))>0 && ...
    isequal(string(design.TimingBoundary),"configured_nominal_radio_occasion_no_measured_alignment"),id, ...
    'Declare independent nominal timing; do not fabricate received synchronization.');
for name=["UEIndex","ServingCell","ChannelSeed","NoiseSeed","GuardSamples","AbsoluteSlot0"]
    x=design.(name);
    assert(isnumeric(x)&&isscalar(x)&&isreal(x)&&isfinite(x)&&x==fix(x)&&x>=0&&x<=2^32-1,id, ...
        'Invalid episode field %s.',name);
end
assert(design.UEIndex>=1 && design.ServingCell>=1 && ...
    ~isfolder(folder)&&~isfile(folder),id,'Invalid endpoints or existing evidence path.');
assert(sixgr.rf.isNormalizedFixedSNRPowerReference(cfg),id, ...
    'This executor requires normalized occupied-RE Es/N0, not absolute link-budget operation.');
u=sixgr.util.structGet(cfg,'lls6g.userContext',struct());
assert(all(isfield(u,{'RuntimeUEAntenna','RuntimeServingBSAntenna', ...
    'RuntimeUEAntennaMeta','RuntimeServingBSAntennaMeta','RuntimeUEIndex','RuntimeServingCell'})) && ...
    u.RuntimeUEIndex==design.UEIndex && u.RuntimeServingCell==design.ServingCell,id, ...
    'Use the installed runtime antenna owners, not arbitrary dimensions.');
assert(isequal(sixgr.util.structGet(cfg,'phy.pdcch.blindSearch',false),true),id, ...
    'Do not narrow the installed blind search to the transmitted candidate.');
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,design.AbsoluteSlot0+1);
cfg.lls6g.userContext.RuntimeSignalFamily="PDCCH";
cfg.phy.runtimeSignalFamily="PDCCH";
carrier=sixgr.phy.grid.makeCarrier(cfg); ofdm=nrOFDMInfo(carrier);
fs=double(ofdm.SampleRate);
first=sixgr.phy.frame.slotStartSample(carrier,design.AbsoluteSlot0,fs);
stop=sixgr.phy.frame.slotStartSample(carrier,design.AbsoluteSlot0+1,fs);
count=stop-first+design.GuardSamples;
% Freeze the receiver's full configuration before consulting a TX object.
formats=string(cfg.phy.pdcch.operatorControl.dci_formats(:));
digests=strings(size(formats)); payloadSizes=zeros(size(formats));
for h=1:numel(formats)
    context=sixgr.phy.pdcch.DCIContextFactory.fromRuntimeConfig(cfg,formats(h));
    digests(h)=context.Digest;
    alignment=sixgr.phy.pdcch.DCISizeAlignmentEngine.resolve(context);
    payloadSizes(h)=alignment.Selected.AlignedBits;
end
[monitor,resolution]=sixgr.phy.pdcch.ConnectedPDCCHConfiguration.build( ...
    cfg,carrier,context.Data.RNTIValue,true);
[resources,~,~]=nrPDCCHSpace(carrier,monitor);
nCandidates=0;
for k=1:numel(resources)
    if ~isempty(resources{k}), nCandidates=nCandidates+size(resources{k},2); end
end
assert(nCandidates>0,id,'No monitored candidates in this configured radio occasion.');
availability=sixgr.phy.frame.SlotFormatResolver.isAvailable(cfg.phy.frameStructure.SlotState, ...
    design.AbsoluteSlot0,monitor.SearchSpace.StartSymbolWithinSlot,monitor.CORESET.Duration,'DL');
assert(availability.Available,id,'CORESET is not DL in the installed symbol calendar.');
nRx=double(u.RuntimeUEAntennaMeta.NumElements); nTx=0;
cfg.lls6g.runtimePowerContext=sixgr.rf.PowerContext(cfg,'DL');
power=struct(); txReplay=struct(); channelReplay=struct(); expectedBits=int8([]);
if design.SignalPresent
    assert(all(isfield(prepared,{'Tx','TxInfo','TransmitSamples','PowerContext', ...
        'SampleRateHz','RuntimeStartSample','PhysicalPortMapping','PhysicalPortMappingSHA256'})),id, ...
        'H1 requires prepareSharedPDCCHTransmission output, not a synthetic grid.');
    txCarrier=prepared.Tx.Carrier;
    assert(prepared.SampleRateHz==fs && prepared.RuntimeStartSample==first && ...
        txCarrier.NSizeGrid==carrier.NSizeGrid && txCarrier.NStartGrid==carrier.NStartGrid && ...
        txCarrier.SubcarrierSpacing==carrier.SubcarrierSpacing && txCarrier.NCellID==carrier.NCellID && ...
        txCarrier.NSlot==carrier.NSlot && txCarrier.NFrame==carrier.NFrame && ...
        size(prepared.TransmitSamples,1)==stop-first && ...
        size(prepared.TransmitSamples,2)==u.RuntimeServingBSAntennaMeta.NumElements,id, ...
        'Prepared TX does not belong to the installed carrier/antenna/radio occasion.');
    expectedBits=prepared.Tx.DCIBits;
    nTx=size(prepared.TransmitSamples,2); power=prepared.PowerContext;
    cfg.lls6g.runtimePowerContext=power;
    samples=[prepared.TransmitSamples;zeros(design.GuardSamples,nTx,'like',prepared.TransmitSamples)];
end
scope="installed_single_occasion_independent_reset_not_continuous_runtime";
execution=struct('EpisodeID',string(design.EpisodeID),'Scope',scope, ...
    'SignalPresent',design.SignalPresent,'TransmitterExecuted',design.SignalPresent, ...
    'DesiredChannelExecuted',design.SignalPresent,'AbsoluteSlot0',design.AbsoluteSlot0, ...
    'RadioStartSample',first,'PhysicalEpisodeStartSample',0,'SampleRateHz',fs,'SampleCount',count, ...
    'TxDimensions',nTx,'RxDimensions',nRx,'RequestedChannelProfile',sixgr.channel.resolveConcreteProfile(cfg), ...
    'ConfiguredSNR_dB',cfg.channel.snr_dB,'ChannelSeed',design.ChannelSeed,'NoiseSeed',design.NoiseSeed, ...
    'TimingBoundary',string(design.TimingBoundary),'PrecedingSharedClockHistoryExecuted',false, ...
    'ExpectedCandidateCount',nCandidates,'MonitoredFormats',formats,'MonitoredPayloadSizes',payloadSizes, ...
    'ReceiverContextDigests',digests,'ReceiverOracleUsed',false,'ReceiverCompleted',false, ...
    'ScenarioAccepted',false,'StatisticallyQualified',false);
mkdir(folder);
save(fullfile(folder,'configuration.mat'),'cfg','design','execution','resolution','power');
if design.SignalPresent
    save(fullfile(folder,'transmitter_reference.mat'),'prepared','-v7.3');
end
fprintf('PDCCH_INSTALLED_EPISODE_START id=%s present=%d candidates=%d formats=%d RX=%d\n', ...
    execution.EpisodeID,design.SignalPresent,nCandidates,numel(formats),nRx);
identity=struct('RunId',execution.EpisodeID,'TrialId',execution.EpisodeID);
epoch=cfg.rf.configurationEpoch; rfRows=table(); timer=tic;
if design.SignalPresent
    txRF=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx','DL',fs,nTx,0,epoch,false,identity);
    emitted=txRF.apply(sixgr.phy.waveform.WaveformChunk(samples,0),epoch);
    txReplay=emitted.Replay; rfRows=struct2table(emitted.Row);
    channel=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,'DL', ...
        'UEIndex',design.UEIndex,'ServingCell',design.ServingCell, ...
        'Seed',design.ChannelSeed,'AbsoluteSampleIndex',0);
    channel=sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
        channel,cfg,emitted.Waveform,struct('OFDM',ofdm), ...
        'NumTxAnt',nTx,'NumRxAnt',nRx, ...
        'TransmitAntennaRuntime',u.RuntimeServingBSAntenna,'ReceiveAntennaRuntime',u.RuntimeUEAntenna, ...
        'TransmitAntennaMeta',u.RuntimeServingBSAntennaMeta,'ReceiveAntennaMeta',u.RuntimeUEAntennaMeta);
    assert(channel.CurrentSampleIndex==0 && channel.TotalIdleAdvancedSamples==0,id, ...
        'The physical independent episode must not claim prior shared-clock history.');
    [propagated,channelReplay]=sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
        channel,emitted.Waveform,'OutputSampleAlignment','continuous_raw_samples');
else
    % No transmitter/channel/DAC noise is constructed under desired-signal H0.
    propagated=complex(zeros(count,nRx));
end
assert(isequal(size(propagated),[count nRx]),id,'Physical sample coverage changed.');
[antenna,noise]=sixgr.phy.waveform.addOccupiedREAWGN(propagated,carrier,cfg.channel.snr_dB, ...
    'Seed',design.NoiseSeed,'SignalEnergyPerOccupiedRE',sixgr.link.resolveAWGNReferenceEnergy(cfg));
rxRF=sixgr.rf.runtime.RFImpairmentStream(cfg,'rx','DL',fs,nRx,0,epoch,false,identity);
frontend=rxRF.apply(sixgr.phy.waveform.WaveformChunk(antenna,0),epoch);
rawWaveform=frontend.Waveform;
raw=sixgr.phy.waveform.WaveformObservationBuffer(0,count,fs,nRx);
raw.append(frontend.Chunk,fs);
segment=struct('StartSample',0,'EndSampleExclusive',count, ...
    'Execution',struct('RX',struct('ID',"ue",'Replay',frontend.Replay)));
[received,gain]=sixgr.phy.rx.compensateReceivedAGC(raw,{segment},"ue");
waveform=received.readComplete();
if isempty(rfRows), rfRows=struct2table(frontend.Row);
else, rfRows=[rfRows;struct2table(frontend.Row)]; end
rfRows.EpisodeID=repmat(execution.EpisodeID,height(rfRows),1);
rfRows.SignalPresent=repmat(design.SignalPresent,height(rfRows),1);
sixgr.util.csvWriteTable(fullfile(folder,'rf_chain_measurements.csv'),rfRows,'PreserveSchema',true);
save(fullfile(folder,'receiver_input.mat'),'cfg','waveform','rawWaveform','gain', ...
    'noise','channelReplay','execution','-v7.3');
fprintf('PDCCH_INSTALLED_PHYSICAL_SECONDS=%g\n',toc(timer));
% Only the actual receive waveform, installed config and sampling rate enter
% RX. TX object, payload, format, K, candidate, noise and timing truth do not.
[rx,info]=sixgr.phy.dl.PDCCH_Rx(waveform,cfg,'SampleRate_Hz',fs);
execution.ReceiverCompleted=true;
save(fullfile(folder,'receiver_output.mat'),'rx','info','execution','-v7.3');
events=sixgr.link.scoreIndependentPDCCHReceiverEpisode(rx,info,expectedBits,execution);
sixgr.util.csvWriteTable(fullfile(folder,'candidate_hypotheses.csv'),info.CandidateResults,'PreserveSchema',true);
sixgr.util.csvWriteTable(fullfile(folder,'receiver_event.csv'),events,'PreserveSchema',true);
result=struct('Receiver',rx,'ReceiverInfo',info,'Execution',execution,'Events',events, ...
    'TXReplay',txReplay,'RXReplay',frontend.Replay,'ChannelReplay',channelReplay, ...
    'RFMeasurements',rfRows,'OutputFolder',folder);
fprintf('PDCCH_INSTALLED_EPISODE_COMPLETE id=%s accepted=%d statistical_qualification=0\n', ...
    execution.EpisodeID,rx.Ok);
end
