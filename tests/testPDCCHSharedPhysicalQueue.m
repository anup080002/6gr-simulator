function ok=testPDCCHSharedPhysicalQueue()
% One actual coded PDCCH through the scheduler's physical owner. This is a
% component fixture, not a connected-data or main-campaign qualification.
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios','lls_pdcch_shared_queue_fixture.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
% Known-candidate timing is explicit in this fixture. The separately tested
% blind receiver must obtain a causal SS/PBCH clock before being enqueued.
assert(~cfg.phy.pdcch.blindSearch && ~s.get('control.blind_search_enabled'));
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),1);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
dl=sixgr.phy.grid.applyRuntimeCarrierTimeline(dl,1);
dl=sixgr.util.structSet(dl,'lls6g.userContext.RuntimeSlotStartTime_s',0);
bits=int8(mod((0:dl.phy.pdcch.configuredPayloadBits-1).',2));
before=owner.Events.NextSampleIndex;
profile clear; profile on;
cleanup=onCleanup(@()profile('off')); %#ok<NASGU>
p=sixgr.link.prepareSharedPDCCHTransmission(dl,'DCIBits',bits,'RNTI',1);
owner.queuePDCCH(1,p,struct('Purpose',"known_candidate_component_fixture"));
profile off; stats=profile('info'); names=string({stats.FunctionTable.FunctionName});
for forbidden=["applyRuntimeChannelState","applyRFImpairmentChain","PDCCH_Rx"]
    assert(~any(contains(names,forbidden)),'Queue preparation executed %s.',forbidden);
end
assert(owner.Events.NextSampleIndex==before && owner.hasPending('PDCCH',1));
assert(size(p.TransmitSamples,2)==size(p.PhysicalPortMapping,1) && ...
    size(p.Tx.Waveform,2)==1 && size(p.TransmitSamples,2)>1);
expected=p.Tx.Waveform*p.PowerContext.AmplitudeScale*p.PhysicalPortMapping.';
assert(norm(expected-p.TransmitSamples,'fro')<1e-12*norm(expected,'fro'));
localReject(@()owner.queuePDCCH(1,p,struct()),'sixgr:truth:SharedPDCCHResourceCollision');
assert(numel(owner.Pending)==1 && owner.Events.NextSampleIndex==before);
[state,completed]=owner.advanceSlot(state,cfg,@localReceive);
assert(numel(completed)==1 && completed.Kind=="PDCCH" && isempty(owner.Pending));
assert(state.TestPDCCHReceive.Ok && isequal(state.TestPDCCHReceive.DCIBits,bits));
rx=state.TestPDCCHReceive;
evidence=struct('ReceiverHestSINR_dB',rx.ReceiverHestSINR_dB, ...
    'ReceiverHestSINRValueStatus',rx.ReceiverHestSINRValueStatus, ...
    'ChannelEstimateAvailable',~isempty(rx.ChannelEstimate) && ...
        any(isfinite(abs(rx.ChannelEstimate(:)))),'ReceiverHestSINRApplicable',false);
evidence=sixgr.truth.bindReceiverSINRApplicability(evidence);
assert(evidence.ReceiverHestSINRApplicable && ...
    evidence.ReceiverHestSINR_dB==rx.ReceiverHestSINR_dB);
assert(state.TestFutureScheduleWasMutable);
assert(state.TestPDCCHInfo.ObservationEndSampleExclusive<owner.Events.NextSampleIndex && ...
    ~state.TestPDCCHInfo.ReceivePaddingApplied && state.TestPDCCHReplay.RuntimeChannelStateUsed);
assert(state.TestPDCCHReplay.ReceiverGainCompensation.Applied);
localReject(@()owner.queuePDCCH(1,p,struct()),'sixgr:truth:LatePDCCHPreparation');
fprintf('PDCCH_SHARED_PHYSICAL_QUEUE_PASS: decision_sample=%d slot_end=%d CRC=%d SINR=%g\n', ...
    state.TestPDCCHInfo.ObservationEndSampleExclusive,owner.Events.NextSampleIndex, ...
    state.TestPDCCHReceive.Ok,state.TestPDCCHReceive.ReceiverHestSINR_dB);
ok=true;
end

function state=localReceive(state,items)
assert(numel(items)==1 && items.Kind=="PDCCH");
item=items(1);
[~,~,tx,replay,receiver]=sixgr.truth.sharedObservationEvidence(item.Planes,item.Context.Prepared);
assert(tx.StartSample==item.Context.Prepared.RuntimeStartSample && ...
    tx.EndSampleExclusive==tx.StartSample+item.Context.Prepared.MinimumReceiveSamples);
assert(receiver.EndSampleExclusive==state.SharedWaveformStream.Events.NextSampleIndex, ...
    'A received DCI decision must occur before any later physical samples.');
[rx,info]=sixgr.link.completePDCCHReception(item.Context.Prepared,receiver);
candidate=sixgr.phy.pdcch.resolveCandidateContext(item.Context.Prepared.Tx.Carrier, ...
    item.Context.Prepared.Tx.PDCCH,rx.CandidateAggregationLevel,rx.CandidateIndexWithinAggregation);
received=table(candidate.FirstCCE,candidate.NumCCE,candidate.AggregationLevel, ...
    candidate.CandidateIndex,'VariableNames',{'PDCCHSelectedCCEIndex','AvailableCCECount', ...
    'PDCCHSelectedAggregationLevel','PDCCHSelectedCandidateIndex'});
bound=sixgr.truth.bindReceivedPDCCHGrantContext(struct(),received);
assert(bound.PDCCHGrantFirstCCE==candidate.FirstCCE && ...
    bound.PDCCHGrantAggregationLevel==rx.CandidateAggregationLevel);
% A DCI completion falls inside an OFDM symbol in this fixture. Explicit
% idle contribution tests schedule mutability only; it is not another NR
% channel or an invented decoded data trial. The former whole-symbol
% commitment incorrectly rejected even this future declaration.
now=state.SharedWaveformStream.Events.NextSampleIndex;
p=item.Context.Prepared;
ofdm=nrOFDMInfo(p.Tx.Carrier);
assert(~any(now==cumsum(double(ofdm.SymbolLengths))), ...
    'This regression requires a genuinely intra-symbol receive completion.');
state.SharedWaveformStream.Events.enqueue('gnb_1','unit_fixture_causal_idle', ...
    sixgr.phy.waveform.WaveformChunk(zeros(1,size(p.TransmitSamples,2),'like',p.TransmitSamples),now));
state.TestFutureScheduleWasMutable=true;
state.TestPDCCHReceive=rx; state.TestPDCCHInfo=info; state.TestPDCCHReplay=replay;
end

function localReject(call,id)
try, call(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingError','Expected %s.',id);
end
