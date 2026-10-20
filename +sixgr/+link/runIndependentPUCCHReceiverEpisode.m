function result=runIndependentPUCCHReceiverEpisode(cfg,assignment,context,tx,design,folder)
% One actual installed DMRS-bearing PUCCH receiver episode, H0 or H1.
% Internal execution API; campaign policy/seed schedules belong to YAML.
% Each episode resets its physical channel/RF clock to zero and translates
% to the receiver's radio occasion. It is NOT preceding access/shared-clock
% history, a campaign acceptance decision, or NR conformance qualification.
% Empty tx means a physically absent UE: do not generate a hidden waveform,
% borrow TX pilots, or run DAC dither as though it were a no-transmitter case.
arguments
    cfg (1,1) struct
    assignment (1,1) sixgr.phy.pucch.PUCCHReceptionAssignment
    context (1,1) sixgr.phy.pucch.UCIReportContext
    tx struct
    design (1,1) struct
    folder (1,1) string
end
id='sixgr:link:InvalidPUCCHReceiverEpisode';
required=["EpisodeID","UEIndex","ServingCell","ChannelSeed","NoiseSeed", ...
    "GuardSamples","SignalPresent"];
assert(isequal(sort(string(fieldnames(design))),sort(required(:))),id, ...
    'Provide exactly the declared episode identity, endpoints, seeds, guard and presence.');
assert(islogical(design.SignalPresent) && isscalar(design.SignalPresent) && ...
    isscalar(string(design.EpisodeID)) && ~ismissing(string(design.EpisodeID)) && ...
    strlength(strtrim(string(design.EpisodeID)))>0,id,'Invalid episode identity/presence.');
for name=["UEIndex","ServingCell"]
    validateattributes(design.(name),{'numeric'},{'scalar','real','integer','finite','positive'});
end
for name=["ChannelSeed","NoiseSeed","GuardSamples"]
    validateattributes(design.(name),{'numeric'},{'scalar','real','integer','finite','nonnegative','<=',2^32-1});
end
assert(design.SignalPresent==~isempty(tx) && (isempty(tx)||isscalar(tx)),id, ...
    'H0 requires no transmitter object; H1 requires the actual emitted transmitter.');
assert(assignment.ReportContextDigest==context.Digest,id, ...
    'The independent receive obligation must be frozen before transmission.');
assert(assignment.Format>=1,id, ...
    'Independent reset episodes require DMRS acquisition. Format0 needs a separately qualified retained received clock.');
assert(sixgr.rf.isNormalizedFixedSNRPowerReference(cfg),id, ...
    'This executor uses explicit normalized occupied-RE Es/N0, not an absolute-power/link-budget shortcut.');
assert(~isfolder(folder) && ~isfile(folder),id,'Preserve earlier evidence; use a new episode folder.');
user=sixgr.util.structGet(cfg,'lls6g.userContext',struct());
assert(all(isfield(user,{'RuntimeUEAntenna','RuntimeServingBSAntenna', ...
    'RuntimeUEAntennaMeta','RuntimeServingBSAntennaMeta', ...
    'RuntimeUEIndex','RuntimeServingCell'})),id, ...
    'Install the actual runtime antenna objects before the physical episode.');
assert(user.RuntimeUEIndex==design.UEIndex && user.RuntimeServingCell==design.ServingCell,id, ...
    'Episode endpoints must match the installed runtime antenna owner.');
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,assignment.Data.AbsoluteSlot0+1);
carrier=sixgr.phy.grid.makeCarrier(cfg); ofdm=nrOFDMInfo(carrier);
fs=double(ofdm.SampleRate); epoch=cfg.rf.configurationEpoch;
first=sixgr.phy.frame.slotStartSample(carrier,assignment.Data.AbsoluteSlot0,fs);
stop=sixgr.phy.frame.slotStartSample(carrier,assignment.Data.AbsoluteSlot0+1,fs);
count=stop-first+double(design.GuardSamples);
profile=sixgr.channel.resolveConcreteProfile(cfg);
snr=double(cfg.channel.snr_dB);
validateattributes(snr,{'numeric'},{'real','scalar','finite'});
scope="installed_single_occasion_independent_reset_not_continuous_runtime";
clock=struct('RadioStartSample',first,'PhysicalEpisodeStartSample',0, ...
    'RadioMinusPhysicalSampleOffset',first,'PrecedingSharedClockHistoryExecuted',false);
% Determine physical receiver dimensions from installed antenna ownership,
% never from a generated UE waveform or an arbitrary scenario constant.
nRx=double(user.RuntimeServingBSAntennaMeta.NumElements);
validateattributes(nRx,{'numeric'},{'scalar','integer','finite','positive'});
powerEvidence=struct(); array=struct(); txReplay=struct(); channelReplay=struct();
rfRows=table(); cfgInput=cfg;
if design.SignalPresent
    sixgr.phy.pucch.validateTransmitUCILayout(tx.Report,tx.Serialization);
    assert(tx.OFDMInfo.SampleRate==fs && tx.OFDMInfo.Nfft==ofdm.Nfft && ...
        size(tx.Waveform,1)==stop-first && ...
        tx.Carrier.NCellID==carrier.NCellID && tx.Carrier.NSizeGrid==carrier.NSizeGrid && ...
        tx.Carrier.SubcarrierSpacing==carrier.SubcarrierSpacing && ...
        tx.Carrier.NSlot==carrier.NSlot && tx.Carrier.NFrame==carrier.NFrame,id, ...
        'The transmitter must belong to the same installed radio clock/carrier. Payload hypotheses may differ.');
    [contribution,cfg,powerEvidence]=sixgr.link.preparePUCCHTransmitWaveform( ...
        tx,cfg,'ApplyNodeRF',false);
    array=sixgr.rf.AntennaArrayFactory.build(cfg,'ue', ...
        'signal','pucch','numPorts',size(contribution,2));
    mapped=contribution*cast(array.PortToElementMatrix.','like',contribution);
    nTx=size(mapped,2);
    % Guard is actually emitted and processed; RX never pads its capture.
    samples=[mapped;zeros(design.GuardSamples,nTx,'like',mapped)];
else
    nTx=0; % No transmitter was constructed or executed for H0.
    cfg.lls6g.runtimePowerContext=sixgr.rf.PowerContext(cfg,'UL');
end
mkdir(folder);
save(fullfile(folder,'configuration.mat'),'cfgInput','cfg','design','assignment', ...
    'context','clock','scope','powerEvidence','array');
if design.SignalPresent
    % Scoring/reproduction reference only. This object is never passed to
    % receivePUCCHObservation; H0 must not create a transmitter reference.
    save(fullfile(folder,'transmitter_reference.mat'),'tx','-v7.3');
end
fprintf('PUCCH_RECEIVER_EPISODE_START id=%s present=%d samples=%d physical_RX=%d folder=%s\n', ...
    string(design.EpisodeID),design.SignalPresent,count,nRx,folder);
timer=tic;
rfIdentity=struct('RunId',string(design.EpisodeID),'TrialId',string(design.EpisodeID));
if design.SignalPresent
    txRF=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx','UL',fs,nTx,0,epoch,false,rfIdentity);
    emitted=txRF.apply(sixgr.phy.waveform.WaveformChunk(samples,0),epoch);
    txReplay=emitted.Replay; rfRows=struct2table(emitted.Row);
    fprintf('PUCCH_RECEIVER_EPISODE_TX_RF_SECONDS=%g\n',toc(timer));
    timer=tic;
    channel=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,'UL', ...
        'UEIndex',design.UEIndex,'ServingCell',design.ServingCell, ...
        'Seed',design.ChannelSeed,'AbsoluteSampleIndex',0);
    channel=sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
        channel,cfg,emitted.Waveform,struct('OFDM',tx.OFDMInfo), ...
        'NumTxAnt',nTx,'NumRxAnt',nRx, ...
        'TransmitAntennaRuntime',user.RuntimeUEAntenna, ...
        'ReceiveAntennaRuntime',user.RuntimeServingBSAntenna, ...
        'TransmitAntennaMeta',user.RuntimeUEAntennaMeta, ...
        'ReceiveAntennaMeta',user.RuntimeServingBSAntennaMeta);
    assert(channel.CurrentSampleIndex==0 && channel.TotalIdleAdvancedSamples==0,id, ...
        'Independent physical episodes start at zero, not after a fabricated radio history.');
    [propagated,channelReplay]=sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
        channel,emitted.Waveform,'OutputSampleAlignment','continuous_raw_samples');
    fprintf('PUCCH_RECEIVER_EPISODE_CHANNEL_SECONDS=%g\n',toc(timer));
else
    % H0 is the declared absence of desired RF at the receiver antenna, not
    % a zeroed decoded payload or replacement of actual receiver samples.
    propagated=complex(zeros(count,nRx));
end
assert(isequal(size(propagated),[count nRx]),id,'Physical sample interval/dimensions changed.');
[antenna,noise]=sixgr.phy.waveform.addOccupiedREAWGN(propagated,carrier,snr, ...
    'Seed',design.NoiseSeed,'SignalEnergyPerOccupiedRE',sixgr.link.resolveAWGNReferenceEnergy(cfg));
timer=tic;
rxRF=sixgr.rf.runtime.RFImpairmentStream(cfg,'rx','UL',fs,nRx,0,epoch,false,rfIdentity);
frontend=rxRF.apply(sixgr.phy.waveform.WaveformChunk(antenna,0),epoch);
fprintf('PUCCH_RECEIVER_EPISODE_RX_RF_SECONDS=%g\n',toc(timer));
rawWaveform=frontend.Waveform;
raw=sixgr.phy.waveform.WaveformObservationBuffer(0,count,fs,nRx);
raw.append(frontend.Chunk,fs);
segment=struct('StartSample',0,'EndSampleExclusive',count, ...
    'Execution',struct('RX',struct('ID',"gnb",'Replay',frontend.Replay)));
[received,gain]=sixgr.phy.rx.compensateReceivedAGC(raw,{segment},"gnb");
waveform=received.readComplete();
observation=sixgr.phy.waveform.WaveformObservationBuffer(first,first+count,fs,nRx);
observation.append(sixgr.phy.waveform.WaveformChunk(waveform,first),fs);
if isempty(rfRows), rfRows=struct2table(frontend.Row);
else, rfRows=[rfRows;struct2table(frontend.Row)]; end
rfRows.EpisodeID=repmat(string(design.EpisodeID),height(rfRows),1);
rfRows.SignalPresent=repmat(design.SignalPresent,height(rfRows),1);
rfRows.Scope=repmat(scope,height(rfRows),1);
sixgr.util.csvWriteTable(fullfile(folder,'rf_chain_measurements.csv'),rfRows,'PreserveSchema',true);
execution=struct('EpisodeID',string(design.EpisodeID),'Scope',scope, ...
    'SignalPresent',design.SignalPresent,'TransmitterExecuted',design.SignalPresent, ...
    'DesiredChannelExecuted',design.SignalPresent,'RequestedChannelProfile',profile, ...
    'TxDimensions',nTx,'RxDimensions',nRx,'RadioStartSample',first, ...
    'PhysicalEpisodeStartSample',0,'SampleRateHz',fs,'SampleCount',count, ...
    'ConfiguredSNR_dB',snr,'ChannelSeed',design.ChannelSeed,'NoiseSeed',design.NoiseSeed, ...
    'ReceiverAssignmentDigest',assignment.Digest,'ReceiverContextDigest',context.Digest, ...
    'ScenarioAccepted',false,'StatisticallyQualified',false);
% Preserve actual receiver inputs before calling RX, including on failure.
save(fullfile(folder,'receiver_input.mat'),'cfg','carrier','assignment','context', ...
    'waveform','rawWaveform','gain','noise','channelReplay','rfRows','execution','clock','-v7.3');
rx=sixgr.link.receivePUCCHObservation(cfg,assignment,context,observation,[]);
save(fullfile(folder,'receiver_output.mat'),'rx','execution','-v7.3');
assert(rx.IndependentReceiverAssignment && ~rx.PreparedTransmitterConsumed && ...
    ~rx.InjectedNoiseVarianceConsumed && ~rx.InjectedInterferenceCovarianceConsumed && ...
    ~rx.OraclePayloadBitsUsed && ~rx.ReceiveTiming.OracleTimingUsed,id, ...
    'The episode receiver must consume only installed obligation and actual received samples.');
events=sixgr.link.scoreIndependentPUCCHReceiverEpisode(context,rx,tx,execution);
sixgr.util.csvWriteTable(fullfile(folder,'receiver_event.csv'),events,'PreserveSchema',true);
result=struct('Receiver',rx,'Execution',execution,'Clock',clock, ...
    'TXReplay',txReplay,'RXReplay',frontend.Replay,'ChannelReplay',channelReplay, ...
    'PowerEvidence',powerEvidence,'RFMeasurements',rfRows,'Events',events,'OutputFolder',folder);
end
