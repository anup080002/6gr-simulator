function ok=testSharedWaveformPhysicalRuntime()
% Real TDD-profile CDL/OFDM samples; physical-owner tests, not a main run.
% Whole/split owners are independent test oracles, never runtime rollback.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_causal_access_to_data_wiring_tdd.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
runtime=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),1);
runtime.CurrentSlot=1; runtime.CurrentServingIdx(:)=1;
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,runtime,1,'DL');
[ul,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,runtime,1,'UL');
trsSlots=double(sixgr.util.structGet(dl,'phy.trs.slotNumbers',[]));
assert(~isempty(trsSlots),'The authored shared-runtime fixture requires TRS slots.');
p=sixgr.link.prepareTRSTransmission(dl,12,'RuntimeSlot',trsSlots(1)+1);
tx=p.Tx; tx.Waveform=p.TransmitSamples;
truth=sixgr.link.initWaveformTruthChannelState(p.ReceiverConfig,tx,p.TxInfo);
state=truth.RuntimeChannelState;
fs=state.SampleRate_Hz; nt=state.NumTxAnt; nr=state.NumRxAnt;
[x,~]=sixgr.channel.projectRuntimeTransmitSamples(state,p.TransmitSamples);
assert(size(x,2)==nt && any(x(:)~=0));
% Use a real generated TRS waveform fragment followed by actual idle TX
% input. This fixture is not advertised as a decoded complete TRS window.
x=x(1:min(2053,size(x,1)),:);
if ~any(x(:)~=0)
    full=p.TransmitSamples;
    first=find(any(full~=0,2),1);
    [x,~]=sixgr.channel.projectRuntimeTransmitSamples(state,full(first:first+2052,:));
end
assert(any(x(:)~=0));
epoch=3;
% Authored profile coefficients with explicit test-only CFO/ADC activation.
% The physical owner retains these stages; it never reapplies RX to an
% independent noise-only waveform to manufacture diagnostic measurements.
dl.rf.rx.agc.enable=true; dl.rf.rx.agc.targetRms=.2;
dl.rf.rx.agc.minGain_dB=-80; dl.rf.rx.agc.maxGain_dB=80;
dl.rf.rx.cfo_Hz=321; dl.rf.adc.enable=true;
dl.rf.adcBits=12; dl.rf.adc.fullScale=1;
whole=localOwner(dl,ul,state,fs,nt,nr,epoch);
split=localOwner(dl,ul,sixgr.channel.ChannelFactory.forkRuntimeChannelState(state),fs,nt,nr,epoch);
wholeEvent=localEvent(whole,fs,nt,nr);
splitEvent=localEvent(split,fs,nt,nr);
% Observer registration must not change any executed TX/RX samples or RNG.
dlScoring=split.registerLinkScoringPlane(splitEvent,'serving','ue_rx');
ulScoring=split.registerLinkScoringPlane(splitEvent,'serving','gnb_rx');
assert(split.registerLinkScoringPlane(splitEvent,'serving','ue_rx')==dlScoring);
% The capture request deliberately cuts inside processor intervals.
split.requestLinkChannelReference(splitEvent,'serving','ue_rx',3,41);
split.requestLinkChannelReference(splitEvent,'serving','ue_rx',3,41);
before=rng;
guard=double(state.ChannelPadSamples)+9;
% The authored DDD-S-U fixture has its first full UL slot at 4 ms. Consume
% the actual idle interval before that boundary, not an RX padding tail.
stop=round(4e-3*fs);
assert(stop-size(x,1)>=guard);
% Capture the same direction-crossing windows used by the gain checks.
% No extra channel execution or coefficient fill is permitted.
split.requestLinkChannelReference(splitEvent,'serving','ue_rx',0,stop+512);
split.requestLinkChannelReference(splitEvent,'serving','gnb_rx',0,stop+512);
for event={wholeEvent,splitEvent}
    e=event{1};
    % This proves node composition happens BEFORE RF/PA. These are known
    % generated contributions, not missing transmissions filled in by RX.
    e.enqueue('gnb','trs_part_a',sixgr.phy.waveform.WaveformChunk(.25*x,0));
    e.enqueue('gnb','trs_part_b',sixgr.phy.waveform.WaveformChunk(.75*x,0));
    e.commitTransmissionsThrough('gnb',stop);
    e.commitTransmissionsThrough('ue',stop); % declared idle transmitter
    for plane=["gnb:tx","ue_rx:pre_rf","ue_rx:post_rf","gnb_rx:pre_rf"]
        e.observe(plane,plane,0,stop);
    end
end
splitEvent.observe(dlScoring,dlScoring,0,stop);
splitEvent.observe(ulScoring,ulScoring,0,stop);
% A real DL observation can finish after the tail-safe TDD reversal.
% Keep its TX interval separate and retain the actually executed inactive
% DL scoring samples, rather than creating a second channel execution.
splitEvent.observe('gnb:tx','tdd_gain_crossing',0,stop);
for plane=["ue_rx:pre_rf","ue_rx:post_rf",dlScoring]
    splitEvent.observe(plane,'tdd_gain_crossing',0,stop+512);
end
splitEvent.observe('ue:tx','tdd_ul_gain_crossing',stop,stop+512);
for plane=["gnb_rx:pre_rf","gnb_rx:post_rf",ulScoring]
    splitEvent.observe(plane,'tdd_ul_gain_crossing',0,stop+512);
end
result=wholeEvent.advanceUntilEvent(stop);
actual=struct([]); next=0;
for last=unique([1 17 71 777 stop])
    event=splitEvent.advanceUntilEvent(last);
    assert(event.Execution.StartSample==next && event.Execution.EndSampleExclusive==last);
    assert(numel(event.Execution.Links)==1 && numel(event.Execution.RX)==2);
    a=max(next,3); b=min(last,41); references=event.Execution.ChannelReferences;
    references=references(arrayfun(@(c)c.Reference.ObservationStartSample==3 && ...
        c.Reference.ObservationEndSampleExclusive==41,references));
    if a<b
        assert(isscalar(references) && references.LinkID=="serving" && ...
            references.Reference.ObservationStartSample==3 && ...
            references.Reference.ObservationEndSampleExclusive==41 && ...
            references.Reference.StartSample==a && references.Reference.EndSampleExclusive==b && ...
            size(references.Reference.PathGains,1)==b-a, ...
            'Only actual requested channel snapshots may be retained.');
    else
        assert(isempty(references),'Full channel capture must stop at the requested boundary.');
    end
    assert(event.Execution.Links.Replay.RuntimeChannelStartSample==next && ...
        event.Execution.Links.Replay.RuntimeChannelEndSample==last && ...
        ~event.Execution.Links.Replay.RuntimeChannelAlignmentLookaheadExecutedOnFork);
    assert(isnan(event.Execution.RX(1).Replay.SampleNoiseVariance), ...
        'Causal AGC/CFO/ADC does not authorize a fabricated scalar post-RF variance.');
    actual=[actual event.Completed]; %#ok<AGROW>
    next=last;
end
crossing=actual(string({actual.ID})=="tdd_gain_crossing");
actual=actual(string({actual.ID})~="tdd_gain_crossing");
scoring=actual(endsWith(string({actual.ReceiverID}),':desired_pre_noise'));
actual=actual(~endsWith(string({actual.ReceiverID}),':desired_pre_noise'));
assert(numel(actual)==numel(result.Completed) && numel(scoring)==2);
desired=scoring(string({scoring.ReceiverID})==dlScoring).Observation.readComplete();
inactive=scoring(string({scoring.ReceiverID})==ulScoring).Observation.readComplete();
assert(any(desired(:)~=0) && all(inactive(:)==0));
% Subtract the actually emitted noiseless link contribution from the
% pre-RF receiver, which includes the once-generated configured noise.
observed=actual(string({actual.ReceiverID})=="ue_rx:pre_rf").Observation.readComplete();
measuredNoise=mean(abs(observed-desired).^2,'all');
injected=result.Execution.RX(1).Replay.InjectedNoiseVariance;
assert(abs(measuredNoise/injected-1)<.04, ...
    'The scoring tap must be the actual link output before receiver noise.');
for k=1:numel(actual)
    index=find(string({result.Completed.ID})==actual(k).ID);
    a=actual(k).Observation.readComplete(); b=result.Completed(index).Observation.readComplete();
    if actual(k).ReceiverID=="ue_rx:post_rf" || actual(k).ReceiverID=="gnb:tx"
        assert(isequal(a,b),'Retained RF samples depend on chunk partition.');
    else
        assert(norm(a-b,'fro')<1e-12*max(norm(b,'fro'),realmin));
    end
end
assert(isequal(rng,before),'Shared physical execution consumed the global RNG.');
receiverPlanes=actual(ismember(string({actual.ReceiverID}), ...
    ["gnb:tx","ue_rx:pre_rf","ue_rx:post_rf"]));
[~,~,~,receiverReplay]=sixgr.truth.sharedObservationEvidence(receiverPlanes);
assert(receiverReplay.RuntimeGeometryDistance2D_m==dl.channel.distance2D_m && ...
    receiverReplay.RuntimeGeometryDistance3D_m==dl.channel.distance3D_m && ...
    receiverReplay.RuntimeGeometryDistance2D_m<receiverReplay.RuntimeGeometryDistance3D_m, ...
    'Actual shared link geometry must keep horizontal and slant ranges distinct.');
varyingGeometry=receiverPlanes;
geometryPlane=find(endsWith(string({varyingGeometry.ReceiverID}),':post_rf'));
assert(numel(varyingGeometry(geometryPlane).Segments)>1);
varyingGeometry(geometryPlane).Segments{end}.Execution.Links.LossReplay.RuntimeGeometryDistance2D_m= ...
    receiverReplay.RuntimeGeometryDistance2D_m+1;
[~,~,~,variableReplay]=sixgr.truth.sharedObservationEvidence(varyingGeometry);
assert(isnan(variableReplay.RuntimeGeometryDistance2D_m) && ...
    isnan(variableReplay.RuntimeGeometryDistance3D_m), ...
    'A time-varying geometry pair must remain segment evidence, not a selected scalar.');
assert(isequaln(receiverReplay.AppliedPathloss_dB,result.Execution.Links.LossReplay.AppliedPathloss_dB) && ...
    string(receiverReplay.PathlossModelSource)==string(result.Execution.Links.LossReplay.PathlossModelSource), ...
    'Stationary pathloss provenance must survive the actual shared receiver adapter.');
energyTrial=sixgr.truth.bindSharedLargeScaleEvidence(table(1,'VariableNames',{'Slot'}),receiverPlanes);
rfTrial=sixgr.truth.bindSharedRFExecutionEvidence(table(1,'VariableNames',{'Slot'}),receiverPlanes);
validatedRF=sixgr.channel.validateSharedRFExecutionEvidence(rfTrial);
assert(validatedRF.Ok && validatedRF.AnyStageExecuted, ...
    'The independent report validator must accept the actual retained RF manifest: %s',validatedRF.FailureReason);
assert(rfTrial.RFStrictOk && ...
    rfTrial.RxRFInputWaveformSHA256==string(sixgr.rf.waveformSHA256(observed)) && ...
    rfTrial.RxRFOutputWaveformSHA256==string(sixgr.rf.waveformSHA256( ...
        receiverPlanes(endsWith(string({receiverPlanes.ReceiverID}),':post_rf')).Observation.readComplete())) && ...
    rfTrial.RxRFStreamStartSample==0 && rfTrial.RxRFStreamEndSampleExclusive==stop, ...
    'RF provenance must hash the actual complete RX captures, not a segment list or configured reference.');
rfManifest=jsondecode(rfTrial.RFExecutionManifestJSON);
assert(numel(rfManifest.RX.ExecutedSegments)>1 && ...
    rfTrial.RFExecutionManifestSHA256==string(sixgr.util.sha256Hex( ...
        uint8(unicode2native(char(rfTrial.RFExecutionManifestJSON),'UTF-8')))));
missingRF=receiverPlanes;
postIndex=find(endsWith(string({missingRF.ReceiverID}),':post_rf'));
bad=missingRF(postIndex).Segments{1}.Execution;
bad.RX(1).Replay=rmfield(bad.RX(1).Replay,'RFStrictOk');
missingRF(postIndex).Segments{1}.Execution=bad;
localError(@()sixgr.truth.bindSharedRFExecutionEvidence(table(1,'VariableNames',{'Slot'}),missingRF), ...
    'sixgr:truth:MissingRFExecution');
assert(abs(energyTrial.LargeScaleOutputEnergy_mWsample-sum(abs(double(desired(:))).^2)) ...
    <=energyTrial.LargeScalePowerClosureRelativeTolerance*energyTrial.LargeScaleOutputEnergy_mWsample && ...
    abs(energyTrial.LargeScaleOutputEnergy_mWsample-energyTrial.LargeScaleExpectedOutputEnergy_mWsample) ...
    <=energyTrial.LargeScalePowerClosureRelativeTolerance*energyTrial.LargeScaleExpectedOutputEnergy_mWsample, ...
    'Exported DL energy must measure the actual post-gain scoring tap and close against applied net gain.');
assert(energyTrial.LargeScaleMeasurementStartSample==0 && ...
    energyTrial.LargeScaleMeasurementEndSampleExclusive==stop);
assert(all(cellfun(@(s)~isfield(s.Execution.Links.LossReplay,'GainStageMeasurement'), ...
    receiverReplay.ReceiveStreamExecutionSegments)), ...
    'Scoring-only desired-link energy must not become a receiver oracle.');
assert(all(cellfun(@(s)~isfield(s.Execution,'ChannelReferences'), ...
    receiverReplay.ReceiveStreamExecutionSegments)), ...
    'Practical receiver replay must not expose the independent channel reference tensors.');
states=split.channelStates(); assert(states{1}.CurrentSampleIndex==stop);
assert(string(states{1}.StateKey)==string(state.StateKey));
% Two real receiver identities must not share a receiver-noise seed. Their
% noise is generated once per receiver, not once for each incoming link.
assert(result.Execution.RX(1).Replay.NoiseStreamSeed~=result.Execution.RX(2).Replay.NoiseStreamSeed);
localError(@()split.addTransmitter('late',dl,'DL',nt,false),'WAVEFORM:PhysicalLayoutFrozen');
localError(@()split.process(struct(),stop+1,stop+2,[]),'WAVEFORM:PhysicalIntervalMismatch');
assert(~split.Faulted && split.NextSampleIndex==stop);
% A same-clock direction switch occurs only AFTER the outgoing tail has
% actually traversed the channel, with the same reciprocal fading object.
split.retargetTDDLink('serving','ue','gnb_rx',ul);
states=split.channelStates();
assert(states{1}.CurrentSampleIndex==stop && states{1}.Obj.TransmitAndReceiveSwapped);
assert(states{1}.NumTxAnt==nr && states{1}.NumRxAnt==nt);
% Actual uplink samples on the same clock, not a second channel instance.
carrier=sixgr.phy.grid.makeCarrier(ul);
carrier.NSlot=4;
grid=nrResourceGrid(carrier,nr); grid(1:12,1,:)=1;
u=nrOFDMModulate(carrier,grid,'Windowing',0);
u=u(1:512,:);
splitEvent.enqueue('ue','ul_ofdm',sixgr.phy.waveform.WaveformChunk(u,stop));
splitEvent.commitTransmissionsThrough('gnb',stop+size(u,1));
splitEvent.commitTransmissionsThrough('ue',stop+size(u,1));
splitEvent.observe(ulScoring,'ul_score',stop,stop+size(u,1));
split.requestLinkChannelReference(splitEvent,'serving','gnb_rx',stop,stop+size(u,1));
splitEvent.observe(dlScoring,'dl_inactive_score',stop,stop+size(u,1));
for plane=["ue:tx","gnb_rx:pre_rf","gnb_rx:post_rf"]
    splitEvent.observe(plane,plane+":ul_gain_capture",stop,stop+size(u,1));
end
event=splitEvent.advanceUntilEvent(stop+size(u,1));
crossing=[crossing event.Completed(string({event.Completed.ID})=="tdd_gain_crossing")];
event.Completed=event.Completed(string({event.Completed.ID})~="tdd_gain_crossing");
ulCrossing=event.Completed(string({event.Completed.ID})=="tdd_ul_gain_crossing");
event.Completed=event.Completed(string({event.Completed.ID})~="tdd_ul_gain_crossing");
crossEnergy=sixgr.truth.bindSharedLargeScaleEvidence(table(4,'VariableNames',{'Slot'}),crossing);
assert(crossEnergy.LargeScaleInputEnergy_mWsample==energyTrial.LargeScaleInputEnergy_mWsample && ...
    crossEnergy.LargeScaleOutputEnergy_mWsample==energyTrial.LargeScaleOutputEnergy_mWsample && ...
    crossEnergy.LargeScaleExpectedOutputEnergy_mWsample==energyTrial.LargeScaleExpectedOutputEnergy_mWsample && ...
    crossEnergy.LargeScaleSampleElementCount==energyTrial.LargeScaleSampleElementCount, ...
    'A direction-inactive interval must not add reverse-link energy or fabricated gain-stage samples.');
assert(isequal(reshape(jsondecode(crossEnergy.LargeScaleMeasurementInactiveIntervalsJSON),1,[]),[stop stop+512]) && ...
    crossEnergy.LargeScaleMeasurementEndSampleExclusive==stop+512, ...
    'Keep the complete observation coverage and explicitly disclose inactive gain-stage intervals.');
crossPost=find(string({crossing.ReceiverID})=="ue_rx:post_rf");
bad=crossing;
bad(crossPost).Segments{1}.Execution.Links.LossReplay= ...
    rmfield(bad(crossPost).Segments{1}.Execution.Links.LossReplay,'GainStageMeasurement');
localError(@()sixgr.truth.bindSharedLargeScaleEvidence(table(4,'VariableNames',{'Slot'}),bad), ...
    'sixgr:truth:MissingExecutedGainEnergy');
bad=crossing;
entries=bad(crossPost).Segments{end}.Execution.ScoringPlanes;
hit=find(string({entries.ID})==dlScoring); assert(isscalar(hit));
entries(hit).Active=true;
bad(crossPost).Segments{end}.Execution.ScoringPlanes=entries;
localError(@()sixgr.truth.bindSharedLargeScaleEvidence(table(4,'VariableNames',{'Slot'}),bad), ...
    'sixgr:truth:MissingExecutedGainEnergy');
bad=crossing(string({crossing.ReceiverID})~=dlScoring);
localError(@()sixgr.truth.bindSharedLargeScaleEvidence(table(4,'VariableNames',{'Slot'}),bad), ...
    'sixgr:truth:MissingExecutedGainEnergy');
bad=crossing;
bad(string({bad.ReceiverID})==dlScoring).Observation=crossing(crossPost).Observation;
localError(@()sixgr.truth.bindSharedLargeScaleEvidence(table(4,'VariableNames',{'Slot'}),bad), ...
    'sixgr:truth:InactiveGainEvidenceNonzeroContribution');
ulChannel=event.Execution.ChannelReferences;
ulChannel=ulChannel(arrayfun(@(c)c.Reference.ObservationStartSample==stop,ulChannel));
assert(isscalar(ulChannel) && ulChannel.TX=="ue" && ulChannel.RX=="gnb_rx" && ...
    ulChannel.Reference.ObservationStartSample==stop && ...
    ulChannel.Reference.NumTransmitAntennas==nr && ulChannel.Reference.NumReceiveAntennas==nt && ...
    size(ulChannel.Reference.PathGains,1)==size(u,1), ...
    'TDD reversal must capture the actual reverse antenna layout.');
ulReference=event.Completed(string({event.Completed.ID})=="ul_score").Observation.readComplete();
dlInactive=event.Completed(string({event.Completed.ID})=="dl_inactive_score").Observation.readComplete();
assert(size(ulReference,2)==nt && any(ulReference(:)~=0) && all(dlInactive(:)==0));
ulPlanes=event.Completed(ismember(string({event.Completed.ReceiverID}), ...
    ["ue:tx","gnb_rx:pre_rf","gnb_rx:post_rf"]));
ulEnergy=sixgr.truth.bindSharedLargeScaleEvidence(table(5,'VariableNames',{'Slot'}),ulPlanes);
ulCrossEnergy=sixgr.truth.bindSharedLargeScaleEvidence(table(5,'VariableNames',{'Slot'}),ulCrossing);
assert(ulCrossEnergy.LargeScaleInputEnergy_mWsample==ulEnergy.LargeScaleInputEnergy_mWsample && ...
    ulCrossEnergy.LargeScaleOutputEnergy_mWsample==ulEnergy.LargeScaleOutputEnergy_mWsample && ...
    ulCrossEnergy.LargeScaleSampleElementCount==ulEnergy.LargeScaleSampleElementCount, ...
    'A receive prefix before TDD reversal must not import the prior DL gain energy.');
inactiveIntervals=jsondecode(ulCrossEnergy.LargeScaleMeasurementInactiveIntervalsJSON);
assert(inactiveIntervals(1,1)==0 && inactiveIntervals(end,2)==stop && ...
    all(inactiveIntervals(2:end,1)==inactiveIntervals(1:end-1,2)));
localChannelCrossing(crossing,dlScoring,fs,[0 stop],[stop stop+512]);
localChannelCrossing(ulCrossing,ulScoring,fs,[stop stop+512],[0 stop]);
ulRF=sixgr.truth.bindSharedRFExecutionEvidence(table(5,'VariableNames',{'Slot'}),ulPlanes);
validatedULRF=sixgr.channel.validateSharedRFExecutionEvidence(ulRF);
assert(validatedULRF.Ok,'Actual UL RF manifest validation failed: %s',validatedULRF.FailureReason);
assert(ulRF.RFStrictOk && ulRF.RFImpairmentChainId~=rfTrial.RFImpairmentChainId && ...
    ulRF.RxRFStreamStartSample==stop && ulRF.RxRFStreamEndSampleExclusive==stop+size(u,1), ...
    'UL must bind its own RF endpoints and sample clock, not the earlier DL identity.');
assert(abs(ulEnergy.LargeScaleOutputEnergy_mWsample-sum(abs(double(ulReference(:))).^2)) ...
    <=ulEnergy.LargeScalePowerClosureRelativeTolerance*ulEnergy.LargeScaleOutputEnergy_mWsample && ...
    abs(ulEnergy.LargeScaleOutputEnergy_mWsample-ulEnergy.LargeScaleExpectedOutputEnergy_mWsample) ...
    <=ulEnergy.LargeScalePowerClosureRelativeTolerance*ulEnergy.LargeScaleExpectedOutputEnergy_mWsample, ...
    'UL after TDD reversal needs its own actual desired-link energy measurement.');
assert(event.Execution.Links.Replay.RuntimeChannelStartSample==stop);
assert(event.Execution.Links.Replay.RuntimeChannelEndSample==stop+size(u,1));
localError(@()split.retargetTDDLink('serving','gnb','ue_rx',dl),'WAVEFORM:TDDChannelTailNotConsumed');
assert(~split.Faulted);
splitEvent.commitTransmissionsThrough('gnb',stop+size(u,1)+1);
splitEvent.commitTransmissionsThrough('ue',stop+size(u,1)+1);
afterCapture=splitEvent.advanceUntilEvent(stop+size(u,1)+1);
assert(isempty(afterCapture.Execution.ChannelReferences), ...
    'The first actual interval after a completed capture must not retain new coefficients.');
% Duplicate shared-state owners are rejected before consuming any sample.
% The original 'whole' owner consumed state.Obj. Use a newly materialized
% independent test channel for the duplicate-registration negative case.
truth2=sixgr.link.initWaveformTruthChannelState(p.ReceiverConfig,tx,p.TxInfo);
fresh=localOwner(dl,ul,truth2.RuntimeChannelState,fs,nt,nr,epoch);
localError(@()fresh.addLink('duplicate','gnb','ue_rx',truth2.RuntimeChannelState,dl), ...
    'WAVEFORM:DuplicatePhysicalChannelOwner');
ok=true;
disp('SHARED_PHYSICAL_RUNTIME_PASS: actual CDL/RF/noise clock, split invariance, DL/UL tail-safe reversal; no main-run claim.');
end

function owner=localOwner(dl,ul,state,fs,nt,nr,epoch)
owner=sixgr.truth.SharedWaveformPhysicalRuntime(fs,0,epoch);
owner.addTransmitter('gnb',dl,'DL',nt,false);
owner.addTransmitter('ue',ul,'UL',nr,false);
owner.addReceiver('ue_rx',dl,'DL',nr,false);
owner.addReceiver('gnb_rx',ul,'UL',nt,false);
owner.addLink('serving','gnb','ue_rx',state,dl);
end

function event=localEvent(owner,fs,nt,nr) %#ok<INUSD>
event=sixgr.phy.waveform.WaveformEventRuntime(fs,0,@owner.process,owner);
owner.attach(event,'double');
end

function localError(action,id)
try, action(); catch cause
    assert(string(cause.identifier)==id,'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:ExpectedError','Expected %s.',id);
end

function localChannelCrossing(planes,scoringID,fs,activeBounds,inactiveBounds)
% This is a physical-capture fixture, not a decoded TRS/data claim. The
% envelope supplies only the exact observation-clock contract.
scoring=find(string({planes.ReceiverID})==scoringID);
observation=planes(scoring).Observation;
envelope=struct('ExecutionStage',"trs_waveform_prepared_not_received", ...
    'SampleRateHz',fs,'TransmitStartSample',observation.StartSample, ...
    'NumSamples',observation.EndSampleExclusive-observation.StartSample);
root=tempname(fullfile(pwd,'logs')); mkdir(root);
[row,context]=sixgr.truth.exportSharedChannelObservation(root, ...
    table(1,'VariableNames',{'Slot'}),planes,envelope,scoringID);
verified=sixgr.channel.validateSharedChannelObservationArtifact(root,row);
assert(row.ChannelObservationStartSample==observation.StartSample && ...
    row.ChannelObservationEndSampleExclusive==observation.EndSampleExclusive && ...
    row.RuntimeChannelStartSample==activeBounds(1) && ...
    row.RuntimeChannelEndSample==activeBounds(2) && ...
    row.RuntimeChannelCanonicalInputSamples==diff(activeBounds), ...
    'Whole RX observation and actually executed coefficient clocks must remain distinct.');
assert(row.RuntimeChannelCaptureScope=="actual_contiguous_direction_active_interval_within_receive_window" && ...
    isequal(context.PostChannelWaveform,observation.readComplete()));
inactive=verified.Manifest.InactiveIntervals;
if isvector(inactive), inactive=reshape(inactive,1,2); end
assert(inactive(1,1)==inactiveBounds(1) && inactive(end,2)==inactiveBounds(2));
saved=load(verified.MATPath,'Captures');
gains=cellfun(@(c)c.Reference.PathGains,saved.Captures,'UniformOutput',false);
times=cellfun(@(c)c.Reference.SampleTimes_s,saved.Captures,'UniformOutput',false);
assert(isequal(context.RuntimeChannelPathGains,cat(1,gains{:})) && ...
    isequal(context.RuntimeChannelPathGainSampleTimes_s,vertcat(times{:})) && ...
    size(context.RuntimeChannelPathGains,1)==diff(activeBounds), ...
    'Diagnostic coefficients must be exactly the captured active arrays, with no invented zero prefix/tail.');
% Removing one active coefficient must still fail rather than become inactive.
bad=planes;
rxID=extractBefore(string(planes(endsWith(string({planes.ReceiverID}),':post_rf')).ReceiverID),':post_rf');
changed=false;
for k=1:numel(bad(scoring).Segments)
    captures=bad(scoring).Segments{k}.Execution.ChannelReferences;
    hit=find(arrayfun(@(c)c.RX==rxID && ...
        c.Reference.ObservationStartSample==observation.StartSample && ...
        c.Reference.ObservationEndSampleExclusive==observation.EndSampleExclusive,captures),1);
    if isempty(hit), continue; end
    captures(hit).Reference.PathGains=captures(hit).Reference.PathGains(2:end,:,:,:);
    bad(scoring).Segments{k}.Execution.ChannelReferences=captures;
    changed=true;
    break;
end
assert(changed,'The negative fixture must actually remove an active coefficient.');
localError(@()sixgr.truth.exportSharedChannelObservation(root, ...
    table(1,'VariableNames',{'Slot'}),bad,envelope,scoringID), ...
    'sixgr:truth:InvalidSharedChannelReference');
bad=planes;
bad(scoring).Observation=planes(endsWith(string({planes.ReceiverID}),':post_rf')).Observation;
localError(@()sixgr.truth.exportSharedChannelObservation(root, ...
    table(1,'VariableNames',{'Slot'}),bad,envelope,scoringID), ...
    'sixgr:truth:InactiveChannelDiagnosticNonzeroContribution');
fprintf('TDD_CHANNEL_CROSSING_PASS active=[%d,%d) inactive=[%d,%d) folder=%s\n', ...
    activeBounds,inactiveBounds,root);
end
