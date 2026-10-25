function ok=testPDCCHSharedPhysicalQueue(rxDelay,rxCFO)
% One actual coded PDCCH through the scheduler's physical owner. This is a
% component fixture, not a connected-data or main-campaign qualification.
setup6GRSimToolkit('Verbose',false);
if nargin<1, rxDelay=0; end
if nargin<2, rxCFO=0; end
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'validation','lls_pdcch_known_candidate_queue.yaml'));
% Explicit test-only codec projection: the inherited scenario now installs
% connected DCI semantics. This arbitrary-bit queue test is not that mode.
% Remove that policy before building, not from the production builder or
% after retaining a misleading resolved scenario in cfg.lls6g.
data=s.toStruct();
for field={'connected_dci','connected_monitoring'}
    if isfield(data.control,field{1})
        data.control=rmfield(data.control,field{1});
    end
end
data.meta.description='Test-only isolated known-candidate codec projection; no connected DCI qualification';
s=sixgr.lls6g.config.ScenarioConfig(data);
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg.rf.rx.timingOffsetSamples=rxDelay;
cfg.rf.rx.cfo_Hz=rxCFO;
% Known-candidate timing is explicit in this fixture. The separately tested
% blind receiver must obtain a causal SS/PBCH clock before being enqueued.
assert(~cfg.phy.pdcch.blindSearch && ~s.get('control.blind_search_enabled'));
assert(~isfield(cfg.phy.pdcch.operatorControl,'connected_dci'), ...
    'An arbitrary known codec payload must not masquerade as connected blind DCI.');
assert(~cfg.phy.pdsch.enable && ~cfg.phy.pusch.enable, ...
    'This isolated control-queue test must not declare scheduled data execution.');
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
assert(state.TestPDCCHScore.PDCCHScoringRecordedRXDelay_samples==rxDelay && ...
    state.TestPDCCHScore.PDCCHScoringExecutedRXCFO_Hz==rxCFO);
assert(state.TestPDCCHScore.PDCCHScoringMeasuredCorrectionApplied== ...
    state.TestPDCCHReceive.CFOCorrectionApplied && ...
    isequaln(state.TestPDCCHScore.PDCCHScoringMeasuredCorrection_Hz, ...
    state.TestPDCCHReceive.CFOCorrectionApplied_Hz));
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
fprintf('PDCCH_INDEPENDENT_SCORING_PASS delay=%g CFO=%g NMSE=%g pilots=%d complex_values=%d\n', ...
    rxDelay,rxCFO,state.TestPDCCHScore.NMSE_dB, ...
    state.TestPDCCHScore.ChannelNMSEPilotResourceCount,state.TestPDCCHScore.ChannelNMSEComparedComplexValues);
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
[reference,source]=sixgr.truth.sharedLinkScoringObservation( ...
    item.Planes,item.Context.Prepared,item.Context.DesiredReferencePlane);
[score,paired]=sixgr.truth.scoreSharedPDCCHChannel( ...
    item.Context.Prepared,rx,info,reference,source,replay);
assert(score.NMSEScoringAvailable && score.ChannelNMSEComparedComplexValues>0 && ...
    score.ChannelNMSEComparedComplexValues==score.ChannelNMSEPilotResourceCount*size(rx.RxGrid,3));
assert(~score.ChannelNMSEGainOrPhaseFitted && ~score.ChannelNMSEReferenceUsedByReceiver);
assert(abs(score.NMSE_dB-10*log10(sum(paired.ChannelErrorEnergy)/sum(paired.ChannelReferenceEnergy)))<1e-12);
captured=sixgr.link.bindPDCCHChannelReference(sixgr.link.buildPDCCHChannelEstimateTable(rx),paired);
assert(sum(captured.NMSECompared)==height(paired) && all(captured.IsDMRS(captured.NMSECompared)));
assert(abs(sum(captured.ChannelErrorEnergy(captured.NMSECompared))-score.ChannelNMSEErrorEnergy)<1e-12);
% A deliberately corrupted estimate must affect independent scoring;
% neither gain-fitting nor reuse of Hest as its own reference is allowed.
bad=rx; bad.ChannelEstimate=10*rx.ChannelEstimate;
damaged=sixgr.truth.scoreSharedPDCCHChannel(item.Context.Prepared,bad,info,reference,source,replay);
assert(damaged.NMSE_dB>score.NMSE_dB+10);
[repeat,~]=sixgr.link.completePDCCHReception(item.Context.Prepared,receiver);
assert(isequal(repeat.DCIBits,rx.DCIBits) && isequal(repeat.ChannelEstimate,rx.ChannelEstimate));
state.TestPDCCHScore=score;
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
