function ok=testH4ChannelCaptureOwnership()
% Actual H4 64x4 CDL/RF ownership and chunk-equivalence component check.
% A full-band OFDM probe is not a decoded data/access/throughput trial.
setup6GRSimToolkit('Verbose',false);
scenario='simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml';
out=fullfile(pwd,'results','lls','h4_channel_ownership', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
assert(~isfolder(out)); mkdir(out);
s=sixgr.lls6g.config.loadScenarioConfig(scenario);
priorRNG=rng;
restoreRNG=onCleanup(@()rng(priorRNG)); %#ok<NASGU>
assert(logical(s.get('simulation.deterministic_mode')));
rng(double(s.get('simulation.random_seed')),'twister');
cfg=sixgr.lls6g.buildInternalConfig(s,out);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
runtime=sixgr.truth.CoupledTruthRuntime.initialize(cfg,out,multi,struct(),1);
runtime.CurrentSlot=1; runtime.CurrentServingIdx(:)=1;
dl=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,runtime,1,'DL');
ul=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,runtime,1,'UL');
carrier=sixgr.phy.grid.makeCarrier(dl); ofdm=nrOFDMInfo(carrier);
fs=double(ofdm.SampleRate);
assert(carrier.NSizeGrid==273 && carrier.SubcarrierSpacing==30 && ...
    ofdm.Nfft==4096 && fs==122.88e6 && cfg.phy.fc_Hz==4e9);
key=sixgr.channel.ChannelFactory.runtimeChannelKey(dl,'DL','UEIndex',1,'ServingCell',1);
channel=sixgr.channel.ChannelFactory.createRuntimeChannelState(dl,'DL','LinkKey',key);
channel=sixgr.channel.ChannelFactory.materializeRuntimeChannelState(channel,dl, ...
    complex(zeros(32,64)),struct('OFDM',ofdm),'NumTxAnt',64,'NumRxAnt',4);
assert(isa(channel.Obj,'nrCDLChannel') && channel.NumTxAnt==64 && ...
    channel.NumRxAnt==4 && isinf(channel.Obj.SampleDensity));

% Native, fully occupied 273-PRB grid. A fixed unit-norm beam is an explicit
% test stimulus; this test does not claim a scheduled beam/PMI or TB decode.
grid=nrResourceGrid(carrier,1);
symbols=exp(1i*(pi/4+pi/2*mod((0:numel(grid)-1)',4)));
grid(:)=symbols;
wave=nrOFDMModulate(carrier,grid,'Nfft',ofdm.Nfft,'SampleRate',fs,'Windowing',0);
count=1024; stop=count+512;
beam=exp(1i*2*pi*(0:63)'/64)/sqrt(64);
samples=wave(1:count,:)*beam.';
assert(size(samples,2)==64 && all(isfinite(samples),'all') && any(samples(:)~=0));

whole=localOwner(dl,ul,channel,fs);
split=localOwner(dl,ul,sixgr.channel.ChannelFactory.forkRuntimeChannelState(channel),fs);
wholeEvents=localEvents(whole,fs); splitEvents=localEvents(split,fs);
for pair={ {whole,wholeEvents}, {split,splitEvents} }
    p=pair{1}; owner=p{1}; events=p{2};
    scoringID=owner.registerLinkScoringPlane(events,'serving','ue_rx');
    owner.requestLinkChannelReference(events,'serving','ue_rx',0,count);
    events.enqueue('gnb','native_fullband_probe',sixgr.phy.waveform.WaveformChunk(samples,0));
    events.commitTransmissionsThrough('gnb',stop);
    events.commitTransmissionsThrough('ue',stop);
    events.observe(scoringID,'owning_scoring_window',0,count);
    % Same link/plane but different window: not a channel-reference owner.
    events.observe(scoringID,'unrelated_long_scoring_window',0,stop);
    events.observe('ue_rx:post_rf','unrelated_receiver_window',0,stop);
    events.observe('gnb:tx','unrelated_transmitter_window',0,stop);
end
randomState=rng;
wholeFirst=wholeEvents.advanceUntilEvent(count);
wholeLast=wholeEvents.advanceUntilEvent(stop);
parts=cell(1,4); completed=struct([]);
ends=[31 257 701 count];
for k=1:numel(ends)
    event=splitEvents.advanceUntilEvent(ends(k));
    parts{k}=event.Execution.ChannelReferences.Reference;
    completed=[completed,event.Completed]; %#ok<AGROW>
end
splitLast=splitEvents.advanceUntilEvent(stop);
assert(isequal(rng,randomState),'Physical owners must not consume the global RNG.');
assert(whole.NextSampleIndex==stop && split.NextSampleIndex==stop);
exact=wholeFirst.Execution.ChannelReferences.Reference;
gains=cellfun(@(r)r.PathGains,parts,'UniformOutput',false);
times=cellfun(@(r)r.SampleTimes_s,parts,'UniformOutput',false);
joined=cat(1,gains{:}); joinedTimes=vertcat(times{:});
gainError=max(abs(joined-exact.PathGains),[],'all');
timeError=max(abs(joinedTimes-exact.SampleTimes_s));
assert(isequal(size(joined),size(exact.PathGains)) && size(joined,1)==count && ...
    size(joined,3)==64 && size(joined,4)==4);
assert(gainError<1e-12 && timeError<1/fs*1e-8, ...
    'Chunk partition changed the actual H4 channel realization or sample clock.');
assert(exact.ObjectTimeOffsetSamples==channel.WarmupSamples && ...
    exact.SampleTimeClockDomain=="nr_channel_object_seconds" && ...
    all(abs(exact.SampleTimes_s*fs-exact.ObjectTimeOffsetSamples-(0:count-1).')<1e-5), ...
    'Native channel timestamps must preserve the executed warm-up-to-physical-clock mapping.');
for k=1:numel(parts)
    part=parts{k};
    assert(part.ObjectTimeOffsetSamples==exact.ObjectTimeOffsetSamples && ...
        all(abs(part.SampleTimes_s*fs-part.ObjectTimeOffsetSamples- ...
        (part.StartSample:part.EndSampleExclusive-1).')<1e-5));
end
assert(isscalar(completed) && completed.ID=="owning_scoring_window");
assert(numel(completed.Segments)==numel(ends));
for segment=completed.Segments
    assert(isfield(segment{1}.Execution,'ChannelReferences') && ...
        size(segment{1}.Execution.ChannelReferences.Reference.PathGains,3)==64, ...
        'The exact scoring owner must retain every executed coefficient.');
end
relativeErrors=zeros(numel(splitLast.Completed),1);
for k=1:numel(splitLast.Completed)
    observed=splitLast.Completed(k);
    expected=wholeLast.Completed(string({wholeLast.Completed.ID})==observed.ID);
    assert(isscalar(expected));
    a=observed.Observation.readComplete(); b=expected.Observation.readComplete();
    relativeErrors(k)=norm(a-b,'fro')/max(norm(b,'fro'),realmin);
    assert(relativeErrors(k)<1e-11,'Chunking changed real TX/RX/scoring samples.');
    localMetadataOnly(observed.Segments);
end
localMetadataOnly(splitEvents.ExecutionTrace);
% The ownership check must reject a real leaked tensor, not the legal typed
% empty collection retained by an inactive/unrequested scoring plane.
leaked=splitLast.Completed(1).Segments;
leaked{1}.Execution.ChannelReferences=wholeFirst.Execution.ChannelReferences;
rejected=false;
try, localMetadataOnly(leaked); catch cause
    assert(strcmp(cause.identifier,'test:H4UnrelatedCoefficientRetention'));
    rejected=true;
end
assert(rejected,'The ownership negative control must detect a retained tensor.');
assert(isempty(splitLast.Execution.ChannelReferences), ...
    'Full coefficient capture must end at its requested boundary.');
metadata=struct('Scope',"H4_native_CDL_RF_capture_ownership_not_scenario_acceptance", ...
    'Scenario',string(scenario),'ScenarioSHA256',string(sixgr.util.sha256File(scenario)), ...
    'SampleRateHz',fs,'NSizeGrid',double(carrier.NSizeGrid),'NumTx',64,'NumRx',4, ...
    'CapturedSamples',count,'ExecutedSamples',stop,'MaximumPathGainDifference',gainError, ...
    'MaximumSampleTimeDifference_s',timeError, ...
    'MaximumRelativeWaveformDifference',max(relativeErrors), ...
    'CoefficientElementsRetainedByOwningWindow',numel(exact.PathGains), ...
    'CoefficientElementsRetainedByUnrelatedWindows',0,'ScenarioAccepted',false);
writetable(struct2table(metadata,'AsArray',true),fullfile(out,'ownership.csv'));
save(fullfile(out,'physical_reference.mat'),'exact','parts','samples','beam','ofdm', ...
    'cfg','metadata','-v7.3');
fprintf('H4_CHANNEL_CAPTURE_OWNERSHIP_PASS folder=%s samples=%d max_gain_error=%.12g max_waveform_error=%.12g\n', ...
    out,stop,gainError,max(relativeErrors));
ok=true;
end

function owner=localOwner(dl,ul,state,fs)
owner=sixgr.truth.SharedWaveformPhysicalRuntime(fs,0,dl.rf.configurationEpoch);
owner.addTransmitter('gnb',dl,'DL',64,false);
owner.addTransmitter('ue',ul,'UL',4,false);
owner.addReceiver('ue_rx',dl,'DL',4,false);
owner.addReceiver('gnb_rx',ul,'UL',64,false);
owner.addLink('serving','gnb','ue_rx',state,dl);
end
function events=localEvents(owner,fs)
events=sixgr.phy.waveform.WaveformEventRuntime(fs,0,@owner.process,owner);
owner.attach(events,'double');
end
function localMetadataOnly(segments)
for k=1:numel(segments)
    execution=segments{k}.Execution;
    assert(~isfield(execution,'ChannelReferences') || isempty(execution.ChannelReferences), ...
        'test:H4UnrelatedCoefficientRetention', ...
        'Unrelated windows and the lifetime trace must not pin coefficient arrays.');
    if ~isfield(execution,'ChannelReferenceMetadata'), continue; end
    for item=reshape(execution.ChannelReferenceMetadata,1,[])
        ref=item.Reference;
        assert(~isfield(ref,'PathGains') && ~isfield(ref,'PathFilters') && ...
            ~isfield(ref,'SampleTimes_s') && ~ref.CoefficientArraysRetained);
    end
end
end
