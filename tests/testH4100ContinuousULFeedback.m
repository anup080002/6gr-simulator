function ok=testH4100ContinuousULFeedback()
% Actual full-band sounding/control/data on one uninterrupted CDL/RF owner.
% The initial DL clock and TAG are declared component boundaries, not an
% executed access result. This test does not qualify the full coordinator,
% sustained throughput, detector probabilities or the 100-slot scenario.
setup6GRSimToolkit('Verbose',false);
scenario='simulator/configs/scenarios/h4_100_cdlc100_connected_impaired_40db_adaptation.yaml';
source=sixgr.lls6g.config.loadScenarioConfig(scenario);
files=[string(mfilename('fullpath'))+".m"; string(which('testH4100SharedSRSScoring')); ...
    string(which('sixgr.truth.CoupledWaveformStream')); ...
    string(which('sixgr.truth.SharedWaveformPhysicalRuntime')); ...
    string(which('sixgr.truth.CoupledTruthRuntime')); ...
    string(which('sixgr.phy.ul.PUSCH_Rx')); string(which('sixgr.phy.dl.PDCCH_Rx')); ...
    string(which('sixgr.link.ReceivedULHARQState')); source.SourceFiles];
files=[files;string(which('sixgr.link.buildPHYSignalDiagnosticSnapshot')); ...
    string(which('sixgr.link.PHYDiagnosticChannelGrid')); ...
    string(which('sixgr.truth.exportPHYSignalDiagnostic'))];
hashes=arrayfun(@(p)string(sixgr.util.sha256File(p)),files);
[passed,receptions,folder,state]=testH4100SharedSRSScoring(scenario,2,true);
assert(passed && numel(receptions)==2);
owner=state.SharedWaveformStream; origin=owner.Events.NextSampleIndex;
saved=load(fullfile(folder,'configuration.mat'),'cfg'); base=saved.cfg;
firstPendingSlot=state.CurrentSlot;
carrier=sixgr.phy.grid.makeCarrier(base);
assert(origin==sixgr.phy.frame.slotStartSample(carrier,firstPendingSlot-1,owner.SampleRateHz), ...
    'test:H4ContinuousHandoffAlreadyConsumed','Do not rewind an already executed physical slot.');
feedback=state.LatestULFeedback(1);
assert(feedback.Valid && feedback.RI==receptions{end}.Output.RIEstimate && ...
    feedback.PMI==receptions{end}.Output.TPMIEstimate && feedback.SourceSlot==receptions{end}.SourceSlot);
scope="continuous_H4_SRS_adaptation_DCI_PUSCH_component_declared_initial_clock_TAG_not_full_scenario";
% The helper returns BEFORE executing the first boundary at which the last
% SRS is available. Include this unexecuted slot, never an earlier slot.
% Keep the installed K2 and SRS freshness policy unchanged.
decision=struct('Valid',false);
for controlSlot=firstPendingSlot:firstPendingSlot+20
    probe=struct('Direction','UL','ControlAbsoluteSlot',controlSlot-1, ...
        'ControlSymbolAllocation',base.phy.pdcch.symbolAllocation, ...
        'SymbolAllocation',base.phy.pusch.symbolAllocation,'HARQProcess',0);
    decision=sixgr.phy.frame.TimingRelationEngine.resolveProductionGrant(base,probe);
    if ~decision.Valid, continue; end
    dataSlot=double(decision.DataAbsoluteSlot)+1;
    if dataSlot-feedback.SourceSlot<=base.run.controlGating.srsMaxAgeSlots, break; end
    decision.Valid=false;
end
assert(decision.Valid,'test:H4ContinuousNoLegalULOpportunity', ...
    'Do not freshen SRS, shift its source slot or bypass configured TDD timing.');
frame=floor((dataSlot-1)/state.SlotsPerFrame)+1;
[cfg,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(base,state,1,'UL');
cfg=sixgr.truth.bindSharedDataOccasion(cfg,dataSlot,frame,owner.SampleRateHz);
cfg.SharedULTimingContext=receptions{end}.Config.SharedULTimingContext;
p=cfg.phy.pusch;
grant=struct('Direction',"UL",'Frame',frame,'Slot',dataSlot, ...
    'ControlAbsoluteSlot',controlSlot-1,'RNTI',double(p.RNTI),'UEIndex',1, ...
    'ServingCell',1,'BaseStationID',1,'PRBSet',double(p.prbSet), ...
    'SymbolAllocation',double(p.symbolAllocation),'NumLayers',double(p.numLayers), ...
    'Layers',double(p.numLayers),'MCSIndex',double(p.mcsIndex),'MCS',double(p.mcsIndex), ...
    'Modulation',string(p.modulation),'TargetCodeRate',double(p.codeRate), ...
    'HARQ',struct('HarqID',0,'NDI',true,'NDIEpoch',1,'RV',0,'IsRetransmission',false));
grant=sixgr.truth.CoupledTruthRuntime.applyMeasuredFeedbackAMCToGrantRuntime(grant,feedback,[],cfg,'UL');
grant.TPMI=feedback.PMI; grant.SRSValid=true; grant.SRSCausalUsable=true;
grant.SRSCausalMeasurementId="actual_shared_SRS_source_"+feedback.SourceSlot;
grant.LastSuccessfulSRSSlot=feedback.SourceSlot;
grant.SRSAgeSlots=dataSlot-feedback.SourceSlot;
grant.TimingAdvanceTicks=cfg.SharedULTimingContext.ReceivedRARTiming.NTA_Tc+ ...
    cfg.SharedULTimingContext.Offset.NTAOffset_Tc;
scheduler=sixgr.l2.mac.SchedulerPF(cfg,'Direction','UL');
grant=scheduler.attachCanonicalTimingDecision(grant);
grant=scheduler.finalizeExactPHYFeasibility(grant);
assert(grant.Valid && grant.ExactPHYFeasible);
allocated=state.ULHarq.allocate(grant.RNTI,controlSlot,grant.TBSBytes,'NewData',true);
grant.HARQ=allocated.HARQ;
grant.DCI=scheduler.buildDCIBitfield(grant);
grant.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,'UL',grant, ...
    'Slot',dataSlot,'Frame',frame,'HARQContext',grant.HARQ);
grant.PHYGrantContextId=grant.PHYGrant.GrantContextId;
grant=sixgr.truth.prepareScheduledULDAI(struct(),cfg,grant);
[control,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(base,state,1,'DL');
control=sixgr.phy.grid.applyRuntimeCarrierTimeline(control,controlSlot);
control.lls6g.userContext.RuntimeSlotStartTime_s=(controlSlot-1)*state.SlotDuration_s;
controlCarrier=sixgr.phy.grid.makeCarrier(control);
reserved=sixgr.truth.commonPDCCHReservations(state,control,controlSlot-1,1,controlCarrier);
prepared=sixgr.link.prepareSharedPDCCHTransmission(control,'Grant',grant, ...
    'DCIBits',grant.DCI.Bits,'RNTI',grant.RNTI,'ReservedRECoordinates',reserved);
assert(isempty(intersect(reserved,prepared.TxInfo.AllocatedRECoordinates,'rows')));
reference=cfg.SharedULTimingContext.DLReference;
ch=owner.channelState(1,'DL');
reference.ImplementationFilterDelay_samples=ch.ChannelTrimSamples;
reference.SearchGuardSamples=sixgr.phy.sync.resolveTimingSearchGuard(control,owner.SampleRateHz);
context=struct('Grant',grant,'ULConfig',cfg,'ScheduledULHARQConfig',cfg, ...
    'ReceivedDLTimingReference',reference);
owner.queuePDCCH(1,prepared,context);
state.TestContinuousUL=struct('Folder',folder,'Scope',scope,'Grant',grant, ...
    'ControlReceived',false,'DataReceived',false,'SourceSlot',feedback.SourceSlot, ...
    'Feedback',feedback,'OriginSample',origin, ...
    'PayloadSeed',double(source.get('simulation.random_seed')));
save(fullfile(folder,'continuous_configuration.mat'),'cfg','control','grant', ...
    'reference','reserved','scope','files','hashes','origin','-v7.3');
fprintf('H4_CONTINUOUS_UL_START source=%g control=%g data=%g RI=%g MCS=%g physical_origin=%g folder=%s\n', ...
    feedback.SourceSlot,controlSlot,dataSlot,grant.NumLayers,grant.MCSIndex,origin,folder);
for slot=firstPendingSlot:dataSlot+1
    state.CurrentSlot=slot;
    current=sixgr.phy.grid.applyRuntimeCarrierTimeline(base,slot);
    state=owner.advanceSlot(state,current,@receive);
    assert(state.SharedWaveformStream==owner && owner.Events.NextSampleIndex==owner.Physical.NextSampleIndex);
    fprintf('H4_CONTINUOUS_UL_SLOT=%d/%d sample=%g\n',slot,dataSlot+1,owner.Events.NextSampleIndex);
end
assert(state.TestContinuousUL.ControlReceived && state.TestContinuousUL.DataReceived);
assert(isequal(hashes,arrayfun(@(p)string(sixgr.util.sha256File(p)),files)), ...
    'test:H4ContinuousSourceChanged','Do not change source during the physical chain.');
sixgr.util.jsonWrite(fullfile(folder,'continuous_receipt.json'), ...
    struct('Completed',true,'SamePhysicalOwner',true,'ChannelResetAfterSRS',false, ...
    'PhysicalCRCPass',state.TestContinuousUL.CRCPass,'MACSchedulerFeedbackCommitted',false,'ScenarioAccepted',false, ...
    'StatisticallyQualified',false,'Scope',scope,'SourceFiles',files,'SourceSHA256',hashes));
assert(state.TestContinuousUL.CRCPass,'test:H4ContinuousULCRCFailure', ...
    'Retain this physical failure; do not tune seeds or use an independent reset.');
fprintf('H4_CONTINUOUS_UL_PASS folder=%s scenario_accepted=0\n',folder);
ok=true;
end

function state=receive(state,items)
owner=state.SharedWaveformStream; test=state.TestContinuousUL;
for item=items
    if item.Kind=="DataTX"
        % The physical owner already retains the actual TX. This bounded
        % check does not emulate application/packet accounting or claim a
        % completed MAC scheduler/feedback loop.
        continue;
    end
    c=item.Context; p=c.Prepared;
    [post,pre,tx,replay,receiver]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
    if item.Kind=="PDCCH"
        [rx,info]=sixgr.link.completePDCCHReception(p,receiver);
        scope=test.Scope;
        save(fullfile(test.Folder,'continuous_pdcch.mat'),'item','rx','info','scope','-v7.3');
        assert(rx.CausalGrantDecodeOk && isequal(rx.DCIBits(:),c.Grant.DCI.Bits(:)), ...
            'test:H4ContinuousULControlFailure','Preserve continuous-channel control failure.');
        assignment=sixgr.phy.pdcch.materializeConnectedDCI(rx,info,p.ReceiverConfig);
        cfg=c.ULConfig; cfg.phy.pusch.receivedDCIAssignment=assignment;
        cfg.phy.pusch.receivedHARQState=sixgr.link.ReceivedULHARQState(cfg);
        allocation=sixgr.phy.pdcch.connectedDataAllocation(cfg,assignment);
        grant=c.Grant;
        grant.ControlDecodeOk=true; grant.PDCCHGrantBindingOk=true;
        grant.PDCCHCausalGrantDecodeOk=true;
        decoded=sixgr.phy.pdcch.decodeDCIPayload(rx.DCIBits,grant.DCI.Format,grant.DCI.ContextData);
        authored=sixgr.phy.pdcch.decodeDCIPayload(grant.DCI.Bits,grant.DCI.Format,grant.DCI.ContextData);
        hash=@(v)sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(orderfields(v)),'UTF-8')));
        grant.PDCCHGrantDCIId=decoded.PayloadHash; grant.PDCCHGrantDCIFormat=decoded.Format;
        grant.PDCCHGrantDCIFieldsHash=hash(decoded.Fields); grant.PDCCHGrantFieldsHash=hash(authored.Fields);
        grant.PDCCHGrantBindingRequired=true; grant.DCICrcPass=logical(rx.Ok);
        grant.PDCCHPayloadMatch=isequal(rx.DCIBits(:),grant.DCI.Bits(:));
        grant.DecodedDCIFields=decoded.Fields;
        grant.TransportBlockId=char(grant.PHYGrantContextId); grant.TBId=grant.TransportBlockId;
        % Independent deterministic payload stream: neither reset the live
        % channel/noise RNG nor depend on the caller's incidental RNG state.
        payloadStream=RandStream('mt19937ar','Seed',test.PayloadSeed);
        trial=struct('GrantSnapshot',grant,'PHYGrant',grant.PHYGrant,'PrepareOnly',true, ...
            'HARQContext',grant.HARQ, ...
            'TransportBlockBits',int8(randi(payloadStream,[0 1],allocation.NominalTBSBits,1)));
        job=sixgr.truth.buildGrantPHYJob(cfg,'UL',cfg.channel.snr_dB,grant.Frame,[],trial);
        output=sixgr.truth.executeGrantPHYJob(job);
        assert(~output.ReadyForReceiverCommit && isempty(output.Result.TrialTable));
        actual=output.Result.PreparedTransmission;
        assert(actual.Tx.PrecodeInfo.AuthoritativeDCIDecisionUsed && ...
            ~actual.Tx.PrecodeInfo.AuthoritativeSRSDecisionUsed && actual.Tx.PUSCH.NumLayers==test.Feedback.RI);
        owner.queueData(item.UE,actual,struct('Job',job));
        test.ControlReceived=true;
        test.ControlAvailableAtSample=owner.Events.NextSampleIndex;
        test.Payload=actual.Tx.TransportBlock;
        save(fullfile(test.Folder,'continuous_transmission.mat'),'assignment','job','actual','-v7.3');
    elseif item.Kind=="PUSCH"
        job=c.Job; job.PrepareOnly=false;
        replay=sixgr.truth.bindSharedDataNoiseEvidence(item.Planes,p,c.DesiredReferencePlane,replay);
        job.ReceivedContext=struct('Prepared',p,'Observation',receiver, ...
            'PhysicalMeasurementObservation',pre,'TransmitterObservation',tx,'Replay',replay, ...
            'ChannelState',owner.directionalChannelState(item.UE,'UL'));
        job=sixgr.truth.bindSharedPUSCHReceiverContext(state,job);
        % Preserve exact received inputs BEFORE decoder/report execution.
        % This is a receiver-replay artifact, not a checkpoint permitting
        % rewind or reconstruction of the live channel/RF owner.
        scope=test.Scope;
        save(fullfile(test.Folder,'continuous_receiver_input.mat'),'item','job','scope','-v7.3');
        output=sixgr.truth.executeGrantPHYJob(job); result=output.Result;
        assert(output.ReadyForReceiverCommit && height(result.TrialTable)==1);
        assert(test.ControlAvailableAtSample<=post.StartSample && owner.Events.NextSampleIndex>test.OriginSample);
        test.CRCPass=logical(result.TrialTable.CRCPass);
        assert(~test.CRCPass || isequal(result.HARQ.DecodedTransportBlockBits(:),test.Payload(:)), ...
            'test:H4ContinuousWrongPayload','CRC success must recover this actual encoded payload.');
        test.DataReceived=true;
        sixgr.util.csvWriteTable(fullfile(test.Folder,'continuous_pusch_trials.csv'),result.TrialTable,'PreserveSchema',true);
        save(fullfile(test.Folder,'continuous_receiver.mat'),'item','job','result','-v7.3');
        % The complete native result is retained even if the measured CRC
        % fails; no extrapolated BLER or substituted high-SNR outcome.
    else
        error('test:H4ContinuousUnexpectedEvent','Unexpected physical completion: %s',item.Kind);
    end
end
state.TestContinuousUL=test;
end
