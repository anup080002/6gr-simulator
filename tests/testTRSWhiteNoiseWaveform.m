function ok=testTRSWhiteNoiseWaveform()
% Physical receiver campaign, not a replay of retained scenario outcomes.
% Repeat the declared two-slot reference waveform on fresh contiguous AWGN
% samples; each episode runs timing search and the production TRS detector.
setup6GRSimToolkit('Verbose',false);
plan=sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/validation/trs_white_noise_waveform_campaign.yaml');
root=fullfile(pwd,'logs','trs_white_noise_waveform',char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
mkdir(root);
s=sixgr.lls6g.config.loadScenarioConfig(plan.scenario);
cfg=sixgr.lls6g.buildInternalConfig(s,root);
cfg.run.seed=plan.seed; % Independent qualification seed, retained below.
requested=double(sixgr.truth.resolveWaveformOperatingPointMetadata(cfg));
p=sixgr.link.prepareTRSTransmission(cfg,requested, ...
    'RuntimeSlot',double(cfg.phy.trs.slotNumbers(1))+1);
assert(p.StrictConfig.DetectionPolicy=="white_noise_projection_v1");
array=sixgr.rf.AntennaArrayFactory.build(p.ReceiverConfig,'bs', ...
    'signal','trs','numPorts',size(p.TransmitSamples,2));
x=p.TransmitSamples*array.PortToElementMatrix.';
assert(size(x,2)==4 && cfg.phy.nRxAnt==2 && ...
    norm(array.PortToElementMatrix'*array.PortToElementMatrix-eye(size(p.TransmitSamples,2)),'fro')<1e-10);
state=sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,'DL','UEIndex',1,'ServingCell',1);
state.TargetUEIndex=1; state.TargetServingCell=1;
state=sixgr.channel.ChannelFactory.materializeRuntimeChannelState(state,cfg, ...
    complex(zeros(1,4)),struct('OFDM',p.Tx.OFDM),'NumTxAnt',4,'NumRxAnt',2);
owner=sixgr.truth.SharedWaveformPhysicalRuntime(p.SampleRateHz,0,1);
owner.addTransmitter('qualification_gnb',cfg,'DL',4,false);
owner.addReceiver('qualification_ue',cfg,'DL',2,false);
owner.addLink('qualification_link','qualification_gnb','qualification_ue',state,cfg);
save(fullfile(root,'frozen_inputs.mat'),'plan','cfg','p','array','-v7.3');
nNoise=plan.noise_episodes; nSignal=plan.signal_episodes;
rows=repmat(struct('Episode',NaN,'SignalPresent',false,'AnyDetection',false, ...
    'AllDetected',false,'AnyResourceExtraction',false,'AllTimingAvailable',false, ...
    'AppliedAWGNSNR_dB',NaN,'NoiseVariance',NaN,'DetectionEvidenceJSON',"", ...
    'TimingEvidenceJSON',""),nNoise+nSignal,1);
capturedFailure=false;
for k=1:numel(rows)
    signal=k>nNoise;
    samples=x;
    if ~signal, samples=complex(zeros(size(x),'like',x)); end % This transmitter is physically idle.
    first=owner.NextSampleIndex; last=first+size(samples,1);
    input=struct('ID',"qualification_gnb",'Chunk',sixgr.phy.waveform.WaveformChunk(samples,first));
    [planes,execution]=owner.process(input,first,last,[]);
    hit=string({planes.ID})=="qualification_ue:post_rf";
    assert(nnz(hit)==1);
    raw=sixgr.phy.waveform.WaveformObservationBuffer(first,last,p.SampleRateHz,2);
    raw.append(planes(hit).Chunk,p.SampleRateHz);
    segment=struct('StartSample',first,'EndSampleExclusive',last,'Execution',execution);
    [received,gainEvidence]=sixgr.phy.rx.compensateReceivedAGC(raw,{segment},'qualification_ue');
    wave=received.readComplete();
    replay=execution.RX.Replay;
    assert(abs(replay.AppliedAWGNSNR_dB-requested)<1e-10);
    rx=struct('Waveform',wave,'NoiseVariance',replay.InjectedNoiseVariance, ...
        'InjectedTimingOffset_samples',0,'FaultMode',"normal", ...
        'WhiteGaussianNoiseModelEstablished',gainEvidence.GainOnlyRFExecuted && ...
        strcmpi(string(replay.NoiseOperatingMode),'standalone_awgn_snr_argument'));
    timing=sixgr.phy.trs.estimateTRSTiming(rx,p.StrictConfig,p.Tx);
    det=sixgr.phy.trs.detectTRSResources(rx,p.StrictConfig,p.Tx,'Timing',timing);
    if k==1
        bad=rx; bad.WhiteGaussianNoiseModelEstablished=false;
        rejected=false;
        try
            sixgr.phy.trs.detectTRSResources(bad,p.StrictConfig,p.Tx,'Timing',timing);
        catch cause
            assert(strcmp(cause.identifier,'sixgr:phy:trs:UnestablishedWhiteNoiseModel'));
            rejected=true;
        end
        assert(rejected);
    end
    rows(k).Episode=k; rows(k).SignalPresent=signal;
    rows(k).AnyDetection=any(det.Table.DetectionSuccess);
    rows(k).AllDetected=all(det.Table.DetectionSuccess);
    rows(k).AnyResourceExtraction=any(det.Table.ObservedRECount>0);
    rows(k).AllTimingAvailable=all(timing.Table.TRSTimingEstimateAvailable);
    rows(k).AppliedAWGNSNR_dB=replay.AppliedAWGNSNR_dB;
    rows(k).NoiseVariance=replay.InjectedNoiseVariance;
    rows(k).DetectionEvidenceJSON=string(jsonencode(table2struct(det.Table)));
    rows(k).TimingEvidenceJSON=string(jsonencode(table2struct(timing.Table)));
    failure=(~signal && rows(k).AnyDetection) || (signal && ~rows(k).AllDetected);
    if k==1 || k==nNoise+1 || (failure && ~capturedFailure)
        save(fullfile(root,sprintf('physical_episode_%d.mat',k)), ...
            'wave','execution','timing','det','signal','gainEvidence','-v7.3');
        if failure, capturedFailure=true; end
    end
    if mod(k,plan.progress_period_episodes)==0 || k==numel(rows)
        sixgr.util.csvWriteTable(fullfile(root,'episodes.csv'),struct2table(rows(1:k)), ...
            'PreserveSchema',true);
        fprintf('TRS_WAVEFORM_PROGRESS episode=%d/%d false=%d missed=%d root=%s\n', ...
            k,numel(rows),nnz([rows(1:min(k,nNoise)).AnyDetection]), ...
            nnz(~[rows(nNoise+1:k).AllDetected]),root);
    end
end
falseCount=nnz([rows(1:nNoise).AnyDetection]);
missCount=nnz(~[rows(nNoise+1:end).AllDetected]);
falseUpper=localUpper(falseCount,nNoise,plan.confidence_level);
missUpper=localUpper(missCount,nSignal,plan.confidence_level);
noiseExtraction=mean([rows(1:nNoise).AnyResourceExtraction]);
result=table(falseCount,nNoise,falseUpper,missCount,nSignal,missUpper,noiseExtraction);
sixgr.util.csvWriteTable(fullfile(root,'qualification.csv'),result,'PreserveSchema',true);
disp(result);
assert(noiseExtraction>=plan.minimum_noise_extraction_fraction, ...
    'Do not claim qualification from a receiver that never extracts noise-only observations.');
assert(falseUpper<=plan.false_alarm_probability_limit && missUpper<=plan.miss_probability_limit, ...
    'Frozen physical detector confidence gates failed; retain policy and failed samples.');
ok=true;
fprintf('TRS_WHITE_NOISE_WAVEFORM_QUALIFIED_DECLARED_4TX2RX_AWGN_SCOPE root=%s\n',root);
end

function p=localUpper(errors,total,confidence)
if errors==total, p=1; else, p=betaincinv(confidence,errors+1,total-errors); end
end
