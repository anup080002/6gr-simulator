function ok=testSharedPUSCHChannelArtifacts(mode,withCoincidentSRS,deferUCIDelivery,withCSI,twoPortUL)
% Actual shared SRS -> received UL DCI -> coded PUSCH with HARQ-ACK UCI.
% Initial TAG remains an explicit component input. In a configured-Es/N0
% fixture, geometry/pathloss are deliberately not applicable. The two UCI bits
% come from isolated coded DL receptions, not this shared CDL owner.
% One grant does not qualify access or adaptation.
setup6GRSimToolkit('Verbose',false);
if nargin<1, mode="TDD"; end
if nargin<2, withCoincidentSRS=false; end
if nargin<3, deferUCIDelivery=false; end
if nargin<4, withCSI=false; end
if nargin<5, twoPortUL=false; end
assert(any(string(mode)==["TDD","FDD"]));
fixture='lls_pdcch_shared_queue_fixture.yaml';
if string(mode)=="FDD", fixture='lls_pusch_shared_queue_fdd_fixture.yaml'; end
if withCSI
    assert(string(mode)=="TDD",'The deferred CSI component scenario is authored for TDD.');
    fixture='lls_pusch_csi_delivery_fixture.yaml';
end
if twoPortUL
    assert(string(mode)=="TDD" && ~withCSI);
    fixture='lls_two_port_ul_shared_queue_fixture.yaml';
end
s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios',fixture));
root=tempname; mkdir(root);
cfg=sixgr.lls6g.buildInternalConfig(s,root);
if twoPortUL
    assert(cfg.phy.srs.nPorts==2 && cfg.phy.pusch.NumAntennaPorts==2 && cfg.phy.pusch.numLayers==1);
end
if withCSI, localSaveScenarioEvidence(s,cfg,root); end
% This component bypasses runSingle, which normally initializes the run
% RNG. Bind the UE drop to the resolved YAML seed, not the preceding test.
priorRNG=rng;
rngCleanup=onCleanup(@()rng(priorRNG)); %#ok<NASGU>
rng(double(cfg.run.seed),'twister');
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,root,multi,struct(),11);
state.CurrentSlot=1; state.CurrentFrame=1; state.CurrentCanonicalSlot=1;
state.CurrentServingIdx(:)=1; state.TestRoot=root;
state.TestDeferUCIDelivery=logical(deferUCIDelivery);
state.TestWithCSI=logical(withCSI);
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[ul,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
carrier=sixgr.phy.grid.makeCarrier(ul); fs=owner.SampleRateHz;
reference=struct('Source',"received_SSB_timing_and_decoded_BCH", ...
    'NCellID',carrier.NCellID,'SampleRateHz',fs,'DLPhaseOffsetSamples',6,'AvailableAtSample',0);
common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset',"");
state.ConnectedULTimingByUE={struct('DLReference',reference, ...
    'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1'), ...
    'ReceivedRARTiming',sixgr.phy.ra.resolveRARTimingAdvance(0,carrier.SubcarrierSpacing,fs), ...
    'TimingAdvanceAvailableAtSample',0,'TimingAdvanceEffectiveAtSample',0, ...
    'TimeAlignmentExpirySampleExclusive',round(.02*fs))};
state.UECommonCellConfigurationByUE={decodedSSBPowerCodecFixture(cfg,0,1,1)};
state.UECommonCellConfigurationByUE{1}.InitialULBWP.SubcarrierSpacing_kHz=carrier.SubcarrierSpacing;
[~,link]=sixgr.link.applyWaveformImpairments(complex(zeros(1,1)),ul,fs,'ApplyRFChain',false);
loss=double(link.AppliedLargeScaleLoss_dB);
measurement=table(0,loss,"SSB-0","analytic_component_pathloss_selector_fixture", ...
    1,-loss,0,'VariableNames',{'ReferenceSignalId','MeasuredReferenceSignalPathloss_dB', ...
    'PathlossReferenceRS','MeasuredReferenceSignalPathlossSource','ServingCell', ...
    'SS_RSRP_dBm','ReferenceSignalTxEPRE_dBm'});
state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state,'SSB','UE',1,measurement,'ProducerSlot',1,'AvailableSlot',1,'Valid',true, ...
    'Direction','DL','SourceSignal','SSB','MeasurementSource','analytic_component_selector_fixture');
[srsCfg,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
srsCfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(srsCfg,5);
srsCfg.lls6g.userContext.RuntimeSlotStartTime_s=4*sixgr.time.slotDurationSec(cfg);
args={'SlotIndex',5,'SNR_dB',cfg.channel.snr_dB,'TimingAdvanceSamples',0};
prepared=sixgr.link.runSRSChannelEstimation(srsCfg,args{:},'PrepareOnly',true);
owner.queueUplinkControl(1,prepared.PreparedTransmission,struct('Config',srsCfg,'Arguments',{args}));
for slot=1:11
    state.CurrentSlot=slot; state.CurrentCanonicalSlot=slot;
    state.CurrentFrame=floor((slot-1)/state.SlotsPerFrame)+1;
    if slot==11 && isfield(state,'TestDeferredUCI')
        h=state.TestDeferredUCI;
        assert(sixgr.truth.receivedPUSCHUCIOccasion(owner,h,h.GrantSnapshot)==10 && ...
            state.CurrentSlot==11 && all(~state.PendingFeedbackTable.Processed));
        % Exercise compatibility with pre-field trace schemas. In the CSI
        % case, HARQ-only processing must not zero-fill the unobserved row.
        state.PUCCHGrantTraceTable(:,{'PUSCHUCITransmissionSlot','PUSCHUCIDeliverySlot'})=[];
        state=sixgr.truth.CoupledTruthRuntime.applyDecodedPUSCHUCIRuntime(state,h);
        assert(all(state.PendingFeedbackTable.Processed) && ...
            state.DLHarq.Stats.Ack==1 && state.DLHarq.Stats.Nack==1);
        ackRows=startsWith(string(state.PUCCHGrantTraceTable.PUCCHGrantId),"shared_pusch_actual_dl_");
        assert(all(state.PUCCHGrantTraceTable.PUSCHUCITransmissionSlot(ackRows)==10) && ...
            all(state.PUCCHGrantTraceTable.PUSCHUCIDeliverySlot(ackRows)==11));
        path=fullfile(root,'late_uci_delivery.csv');
        sixgr.util.csvWriteTable(path,state.PUCCHGrantTraceTable,'PreserveSchema',true);
        saved=sixgr.util.csvReadTable(path,'TextType','string');
        assert(all(saved.PUSCHUCITransmissionSlot(ackRows)==10) && all(saved.PUSCHUCIDeliverySlot(ackRows)==11));
        if state.TestWithCSI, localVerifyCSI(state); end
        disp('SHARED_PUSCH_LATE_UCI_DELIVERY_PASS: actual slot-10 reception delivered in slot 11.');
    end
    if slot==9
        assert(isfield(state,'TestSRS') && state.TestSRS.AvailableAtSample<=owner.Events.NextSampleIndex);
        state=localReceivedDLReservations(state,cfg,10);
        [ul,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
        ul=sixgr.phy.grid.applyRuntimeCarrierTimeline(ul,slot);
        ul.lls6g.userContext.RuntimeSlotStartTime_s=(slot-1)*sixgr.time.slotDurationSec(cfg);
        [grant,ul]=localGrant(state,ul,slot-1);
        if withCoincidentSRS
            % The authored TDD allocation ends before the configured SRS
            % symbol. Exercise both actual contributions and one shared
            % channel observation; never erase an overlapping allocation.
            puschSymbols=grant.SymbolAllocation(1)+(0:grant.SymbolAllocation(2)-1);
            assert(~ismember(13,puschSymbols),'test:FixtureSRSDataOverlap', ...
                'This coexistence fixture requires nonoverlapping authored PUSCH/SRS symbols.');
            sounding=sixgr.phy.grid.applyRuntimeCarrierTimeline(ul,10);
            sounding.lls6g.userContext.RuntimeSlotStartTime_s=9*sixgr.time.slotDurationSec(cfg);
            soundingArgs={'SlotIndex',10,'SNR_dB',cfg.channel.snr_dB,'TimingAdvanceSamples',0};
            soundingTX=sixgr.link.runSRSChannelEstimation(sounding,soundingArgs{:},'PrepareOnly',true);
            owner.queueUplinkControl(1,soundingTX.PreparedTransmission, ...
                struct('Config',sounding,'Arguments',{soundingArgs}));
        end
        allocation=state.ULHarq.allocate(grant.RNTI,slot,grant.TBSBytes,'NewData',true);
        assert(isequaln(allocation.HARQ.HarqID,grant.HARQ.HarqID) && ...
            allocation.HARQ.NDI==grant.HARQ.NDI && allocation.HARQ.RV==grant.HARQ.RV);
        state.ULQueueBits(1)=grant.TBSBits; % Explicit fixture queue, actual allocated TB.
        [dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
        dl=sixgr.phy.grid.applyRuntimeCarrierTimeline(dl,slot);
        dl.lls6g.userContext.RuntimeSlotStartTime_s=(slot-1)*sixgr.time.slotDurationSec(cfg);
        p=sixgr.link.prepareSharedPDCCHTransmission(dl,'Grant',grant,'RNTI',grant.RNTI,'K',numel(grant.DCI.Bits));
        owner.queuePDCCH(1,p,struct('Grant',grant,'ULConfig',ul));
    end
    [state,~]=owner.advanceSlot(state,cfg,@localEvents);
end
assert(state.TestPUSCHReceived && state.ULHarq.Stats.Tx==1 && state.ULQueueBits(1)==0);
assert(numel(owner.DataTransmissions)==1 && ~owner.hasPending('PUSCH',1));
if withCoincidentSRS
    assert(state.TestLastSRSObservationID==state.TestPUSCHObservationID, ...
        'Coincident SRS and PUSCH must share one verified immutable channel artifact.');
end
fprintf('SHARED_PUSCH_CHANNEL_ARTIFACTS_PASS: %s actual SRS/DCI/PUSCH/UCI, seed=%g root=%s\n',mode,cfg.run.seed,root);
ok=true;
end

function [grant,cfg]=localGrant(state,cfg,slot0)
measured=state.TestSRS;
ports=double(cfg.phy.pusch.NumAntennaPorts);
assert(isfinite(measured.RI) && isfinite(measured.TPMI) && ports<=measured.NumSRSPorts);
cfg.phy.pusch.TPMI=measured.TPMI;
cfg.phy.pusch.srsDecision=struct('Authoritative',true,'MeasurementID',measured.ID, ...
    'MeasurementSlot',5,'RI',measured.RI,'TPMI',measured.TPMI,'NumPorts',ports);
p=cfg.phy.pusch;
grant=struct('Direction','UL','Frame',0,'Slot',slot0,'RNTI',p.RNTI,'UEIndex',1, ...
    'BaseStationID',1,'ServingCell',1,'PRBSet',p.prbSet,'SymbolAllocation',p.symbolAllocation, ...
    'Modulation',p.modulation,'TargetCodeRate',p.codeRate,'MCSIndex',p.mcsIndex,'MCS',p.mcsIndex, ...
    'RV',0,'Layers',measured.RI,'NumLayers',measured.RI,'RI',measured.RI, ...
    'NumLogicalPorts',ports,'TPMI',measured.TPMI,'SRSCausalUsable',true,'SRSValid',true, ...
    'SRSCausalMeasurementId',measured.ID,'LastSuccessfulSRSSlot',5, ...
    'HARQ',struct('HarqID',0,'NDI',true,'RV',0,'IsRetransmission',false));
grant.TimingAdvanceTicks=cfg.SharedULTimingContext.ReceivedRARTiming.NTA_Tc+cfg.SharedULTimingContext.Offset.NTAOffset_Tc;
scheduler=sixgr.l2.mac.SchedulerPF(cfg,'Direction','UL');
grant=scheduler.attachCanonicalTimingDecision(grant);
grant=scheduler.finalizeExactPHYFeasibility(grant);
grant.DCI=scheduler.buildDCIBitfield(grant);
grant.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,'UL',grant,'Frame',0,'Slot',slot0,'HARQContext',grant.HARQ);
grant.PHYGrantContextId=grant.PHYGrant.GrantContextId;
end

function state=localEvents(state,items)
owner=state.SharedWaveformStream;
for item=items
    if item.Kind=="DataTX"
        state=sixgr.truth.commitSharedDataTransmission(state,item); continue;
    end
    c=item.Context; p=c.Prepared;
    [~,pre,tx,replay,receiver]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
    assert(all(cellfun(@(s)~isfield(s.Execution,'ChannelReferences'),replay.ReceiveStreamExecutionSegments)));
    if item.Kind=="SRS"
        [~,e,refs]=sixgr.truth.sharedLinkScoringObservation(item.Planes,p,c.DesiredReferencePlane);
        assert(e.ChannelReferenceCoverageComplete);
        input=struct('Prepared',p,'Observation',receiver,'PhysicalMeasurementObservation',pre, ...
            'TransmitterObservation',tx,'Replay',replay,'ScoringChannelReferences',{refs}, ...
            'ChannelState',owner.directionalChannelState(1,'UL'));
        out=sixgr.link.runSRSChannelEstimation(c.Config,c.Arguments{:},'ReceivedContext',input);
        assert(out.Ok,'test:SharedSRSFailed','Actual SRS receiver must pass before a sounded grant.');
        state.TestSRS=struct('RI',out.EstimatedRI,'TPMI',out.EstimatedTPMI, ...
            'ID',sixgr.phy.waveform.WaveformHash.numeric(receiver.readComplete()), ...
            'NumSRSPorts',p.Tx.SRS.NumSRSPorts,'AvailableAtSample',receiver.EndSampleExclusive);
        state.ReceivedULTimingReferences={sixgr.phy.sync.ReceivedULTimingReference(p,receiver,out.ReceiveTiming)};
        row=table(double(c.Arguments{2}),"SRS",'VariableNames',{'Slot','Channel'});
        row=sixgr.truth.exportSharedChannelObservation(state.TestRoot,row,item.Planes,p,c.DesiredReferencePlane);
        sixgr.channel.validateSharedChannelObservationArtifact(state.TestRoot,row);
        state.TestLastSRSObservationID=row.ChannelObservationID;
    elseif item.Kind=="PDCCH"
        [rx,~]=sixgr.link.completePDCCHReception(p,receiver);
        grant=c.Grant;
        assert(rx.Ok && rx.CausalGrantDecodeOk && isequal(rx.DCIBits(:),grant.DCI.Bits(:)));
        decoded=sixgr.phy.pdcch.decodeDCIPayload(rx.DCIBits,grant.DCI.Format,grant.DCI.ContextData);
        authored=sixgr.phy.pdcch.decodeDCIPayload(grant.DCI.Bits,grant.DCI.Format,grant.DCI.ContextData);
        assert(isequaln(decoded.Fields,authored.Fields));
        if string(grant.DCI.Format)=="0_1" && isfield(grant.DCI.ContextData,'ULPrecoding')
            assert(decoded.Fields.precoding_information_and_number_of_layers_tpmi==grant.TPMI && ...
                decoded.Fields.precoding_information_and_number_of_layers_rank_minus1==grant.NumLayers-1);
        end
        grant.ControlDecodeOk=logical(rx.CausalGrantDecodeOk); grant.PDCCHGrantBindingOk=logical(rx.CausalGrantDecodeOk);
        grant.PDCCHGrantDCIId=decoded.PayloadHash; grant.PDCCHGrantDCIFormat=decoded.Format;
        hash=@(v)sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(orderfields(v)),'UTF-8')));
        grant.PDCCHGrantDCIFieldsHash=hash(decoded.Fields); grant.PDCCHGrantFieldsHash=hash(authored.Fields);
        grant.PDCCHGrantBindingRequired=true; grant.DCICrcPass=logical(rx.Ok);
        grant.PDCCHPayloadMatch=isequal(rx.DCIBits(:),grant.DCI.Bits(:)); grant.DecodedDCIFields=decoded.Fields;
        slot=double(grant.ScheduledAbsoluteSlot)+1;
        frame=floor((slot-1)/state.SlotsPerFrame)+1;
        % Cross the same scheduler-zero/runtime-one boundary as the main
        % received-DCI queue. Direct multiplex(...,slot) previously hid the
        % late-feedback reconciler's off-by-one ScheduledAbsoluteSlot read.
        controlSlot=double(grant.TimingDecision.ControlAbsoluteSlot)+1;
        controlFrame=floor((controlSlot-1)/state.SlotsPerFrame)+1;
        grant=sixgr.truth.bindQueuedULGrantOccasion( ...
            grant,controlSlot,slot,controlFrame,frame,grant.K2);
        [cfg,~]=sixgr.truth.bindSharedDataOccasion(c.ULConfig,slot,frame,owner.SampleRateHz);
        future=state;
        lateTiming=jsondecode(future.PendingFeedbackTable.DataReceiveTimingEvidenceJSON(1));
        lateTiming.ResultAvailableAtSample=owner.Events.NextSampleIndex+1;
        future.PendingFeedbackTable.DataDecodeAvailableAtSample(1)=lateTiming.ResultAvailableAtSample;
        future.PendingFeedbackTable.DataReceiveTimingEvidenceJSON(1)=string(jsonencode(lateTiming));
        localReject(@()sixgr.truth.CoupledTruthRuntime.multiplexDueHARQACKOnPUSCHRuntime(future,grant,slot), ...
            'sixgr:truth:FutureHARQFeedbackAtUCIEncoding');
        missing=state; missing.PendingFeedbackTable.DataReceiveTimingEvidenceJSON(1)="";
        localReject(@()sixgr.truth.CoupledTruthRuntime.multiplexDueHARQACKOnPUSCHRuntime(missing,grant,slot), ...
            'sixgr:truth:MissingUCIReceiveTiming');
        [state,grant,blocked]=sixgr.truth.CoupledTruthRuntime. ...
            reconcileQueuedPUSCHAfterDLFeedbackRuntime(state,grant,true);
        assert(isempty(blocked) && numel(grant)==1, ...
            'Canonical queued PUSCH must retain its actual due slot during late UCI reconciliation.');
        uci=grant.ExpectedUCIPayload;
        assert(isequal(int8(uci.HARQACK(:)),int8([1;0])) && ...
            all(string(state.PendingFeedbackTable.DeliveryMechanism)=="pusch_uci") && ...
            all(state.PUCCHGrantTraceTable.MultiplexedOnPUSCH));
        context=struct('GrantSnapshot',grant,'PHYGrant',grant.PHYGrant,'PrepareOnly',true,'ExpectedUCIPayload',uci);
        job=sixgr.truth.buildGrantPHYJob(cfg,'UL',cfg.channel.snr_dB,frame,[],context); job.StartSlotIndex=slot;
        result=sixgr.truth.executeGrantPHYJob(job);
        assert(~result.ReadyForReceiverCommit && isempty(result.Result.TrialTable));
        owner.queueData(1,result.Result.PreparedTransmission,struct('Job',job));
    elseif item.Kind=="PUSCH"
        job=c.Job; job.PrepareOnly=false;
        replay=sixgr.truth.bindSharedDataNoiseEvidence(item.Planes,p,c.DesiredReferencePlane,replay);
        expectedTiming=(p.StartSample-p.ReceiveStartSample) + ...
            replay.RuntimeChannelFilterDelay_samples + ...
            replay.RuntimeChannelMinimumPathDelay_samples + ...
            replay.InjectedTimingOffset_samples;
        assert(replay.TrueReceiverTimingOffset_samples==expectedTiming && ...
            ~replay.TimingTruthReceiverEstimatorInput, ...
            'UL timing truth must include the shared-clock observation displacement and executed channel delay.');
        job.ReceivedContext=struct('Prepared',p,'Observation',receiver,'PhysicalMeasurementObservation',pre, ...
            'TransmitterObservation',tx,'Replay',replay,'ChannelState',owner.directionalChannelState(1,'UL'));
        result=sixgr.truth.executeGrantPHYJob(job); out=result.Result;
        assert(result.ReadyForReceiverCommit && height(out.TrialTable)==1 && out.TrialTable.CRCPass==1);
        assert(out.TrialTable.TrueTimingOffset_samples==expectedTiming && ...
            abs(out.TrialTable.ResidualTimingError_PostCorrection_samples)<=1, ...
            'The practical PUSCH timing estimate must reconcile against receiver-arrival truth within one sample.');
        verifyReceivedConstellationCapture(out,job.Cfg,item.UE);
        assert(string(out.TrialTable.NoiseVarSource)=="runtime_channel_estimate", ...
            'Shared PUSCH must estimate disturbance from received reference REs, not injected-noise metadata.');
        assert(out.HARQ.HARQACKContentMatch && isequal(out.HARQ.DecodedHARQACKBits,int8([1;0])));
        assert(string(out.HARQ.GrantSnapshot.GrantContextId)==string(job.GrantContextId), ...
            'The actual decoded grant must retain the same PHY-job identity used for UCI reservation.');
        % Exercise the main shared completion's receive-event handoff on
        % actual CDL/SRS/PUSCH captures, without a known-delay/oracle input.
        out.HARQ.ReceivedTimingEvidence=sixgr.truth.receivedDataSymbolTiming( ...
            p,receiver,out.ReceiveTiming,owner.Events.NextSampleIndex);
        assert(sixgr.truth.receivedPUSCHUCIOccasion(owner,out.HARQ,out.HARQ.GrantSnapshot)==10);
        missing=rmfield(out.HARQ,'ReceivedTimingEvidence');
        localReject(@()sixgr.truth.receivedPUSCHUCIOccasion(owner,missing,out.HARQ.GrantSnapshot), ...
            'sixgr:truth:MissingSharedHARQReceiveTiming');
        future=out.HARQ; future.ReceivedTimingEvidence.ResultAvailableAtSample=owner.Events.NextSampleIndex+1;
        localReject(@()sixgr.truth.receivedPUSCHUCIOccasion(owner,future,out.HARQ.GrantSnapshot), ...
            'sixgr:truth:FuturePUSCHUCIDelivery');
        if state.TestDeferUCIDelivery
            % An explicit one-slot receiver-to-scheduler delivery delay;
            % do not change the captured waveform or its availability time.
            state.TestDeferredUCI=out.HARQ;
            assert(all(~state.PendingFeedbackTable.Processed));
        else
            state=sixgr.truth.CoupledTruthRuntime.applyDecodedPUSCHUCIRuntime(state,out.HARQ);
            assert(all(state.PendingFeedbackTable.Processed) && ...
                state.DLHarq.Stats.Ack==1 && state.DLHarq.Stats.Nack==1);
        end
        timingFields=sixgr.truth.harqFeedbackReceiveTimingFields( ...
            out.HARQ,out.HARQ.GrantSnapshot,true);
        for name=string(fieldnames(timingFields)).'
            out.TrialTable.(name)=timingFields.(name);
        end
        row=sixgr.truth.bindSharedLargeScaleEvidence(out.TrialTable,item.Planes);
        row=sixgr.truth.bindSharedRFExecutionEvidence(row,item.Planes);
        row=sixgr.truth.exportSharedChannelObservation(state.TestRoot,row,item.Planes,p,c.DesiredReferencePlane);
        path=fullfile(state.TestRoot,'received_pusch.csv');
        if logical(sixgr.util.structGet(job.Cfg,'integration.configured_snr_is_link_authority',false))
            assert(isnan(row.RuntimeGeometryDistance2D_m) && ...
                isnan(row.RuntimeGeometryDistance3D_m) && ...
                string(row.RuntimeGeometrySource)=="not_applicable_fixed_configured_esn0", ...
                'Configured-Es/N0 PUSCH must not report dormant geometry as executed pathloss evidence.');
        else
            assert(isfinite(row.RuntimeGeometryDistance2D_m) && ...
                row.RuntimeGeometryDistance2D_m<row.RuntimeGeometryDistance3D_m, ...
                'A geometry-authority PUSCH row must retain distinct executed horizontal/slant ranges.');
        end
        sixgr.util.csvWriteTable(path,row,'PreserveSchema',true);
        persisted=sixgr.util.csvReadTable(path,'TextType','string');
        assert(persisted.DataDecodeAvailableAtSample==owner.Events.NextSampleIndex && ...
            persisted.DataReceiveSymbolEndSampleExclusive<=receiver.EndSampleExclusive && ...
            persisted.DataReceiveSampleRateHz==owner.SampleRateHz);
        retainedTiming=jsondecode(persisted.DataReceiveTimingEvidenceJSON);
        assert(retainedTiming.DataAbsoluteSlot==out.HARQ.GrantSnapshot.ScheduledAbsoluteSlot && ...
            retainedTiming.RNTI==out.HARQ.GrantSnapshot.RNTI && ...
            retainedTiming.Direction=="UL" && ~retainedTiming.ProcessingBudgetIncluded);
        verified=sixgr.channel.validateSharedChannelObservationArtifact(state.TestRoot,persisted);
        assert(all(verified.Segments.NumTransmitAntennas==p.NumPhysicalTransmitAntennas) && ...
            all(verified.Segments.NumReceiveAntennas==receiver.NumReceiveAntennas));
        state.TestPUSCHReceived=true;
        state.TestPUSCHObservationID=row.ChannelObservationID;
    else
        error('test:UnexpectedSharedEvent','Unexpected event %s.',item.Kind);
    end
end
end

function state=localReceivedDLReservations(state,cfg,dueSlot)
% Actual isolated source decodes; resource reservation is component setup.
for k=1:2
    sourceSlot=3; variance=1e-13;
    if k==2, sourceSlot=6; variance=1e-4; end
    [out,timing]=receivedDLFeedbackFixture(cfg,sourceSlot,k-1,variance);
    g=out.HARQ.GrantSnapshot; ack=logical(out.TrialTable.CRCPass);
    assert(ack==(k==1) && timing.DataDecodeAvailableAtSample<=state.SharedWaveformStream.Events.NextSampleIndex);
    a=state.DLHarq.allocate(g.RNTI,sourceSlot,g.TBSBytes,'NewData',true);
    assert(a.HARQ.HarqID==g.HARQ.HarqID && a.HARQ.NDI==g.HARQ.NDI);
    state.DLHarq.onTx(g.RNTI,a.HARQ.HarqID,uint8(out.HARQ.TransportBlockBits),g,sourceSlot);
    f=struct('Direction',"DL",'UEIndex',1,'RNTI',g.RNTI,'HarqID',a.HARQ.HarqID, ...
        'SourceSlot',sourceSlot,'DueSlot',dueSlot,'Ack',ack,'CurrentDecodeOK',ack,'CombinedDecodeOK',ack, ...
        'ServingCell',1,'BaseStationID',1,'TBSBits',g.TBSBits,'UCIBitCount',1, ...
        'RequestedFormat',0,'ResolvedFormat',0,'PUCCHResourceId',"0", ...
        'PUCCHPRBStart',0,'PUCCHPRBCount',1,'PUCCHSymbolStart',12,'PUCCHNumSymbols',2, ...
        'UCIType',"harq_ack",'ControlResourceSource',"declared_component_resource_actual_dl_payload", ...
        'ControlResourceValidity',true,'FormatAdaptationReason',"none_strict_assignment", ...
        'PUCCHGrantId',"shared_pusch_actual_dl_"+k,'DeliveryMechanism',"pucch", ...
        'PUSCHGrantContextId',"",'MultiplexedBitIndex',NaN,'Processed',false, ...
        'RightCensored',false, ...
        'ComponentCarrier',cfg.phy.frame.DefaultIdentity.ScheduledCCID, ...
        'ActiveULBWP',cfg.phy.frame.DefaultIdentity.ULBWPID);
    for name=string(fieldnames(timing)).', f.(name)=timing.(name); end
    if k==1, state.PendingFeedbackTable=struct2table(f);
    else, state.PendingFeedbackTable=[state.PendingFeedbackTable;struct2table(f)]; end
    state=sixgr.truth.CoupledTruthRuntime.schedulePUCCHGrantRuntime(state,struct2table(f));
end
if state.TestWithCSI
    [out,timing]=receivedDLFeedbackFixture(cfg,7,2,1e-13);
    csi=out.CSIRSTrialTable;
    assert(height(csi)==1 && csi.Observed && csi.CSIMeasurementAvailable && ...
        timing.DataDecodeAvailableAtSample<=state.SharedWaveformStream.Events.NextSampleIndex, ...
        'CSI must come from an available, executed CSI-RS receiver.');
    sixgr.util.csvWriteTable(fullfile(state.TestRoot,'isolated_received_csirs.csv'),csi,'PreserveSchema',true);
    state=sixgr.truth.CoupledTruthRuntime.enqueueCSIReportRuntime(state,1,'DL',out.TrialTable,cfg,csi);
    assert(height(state.PendingCSITable)==1 && state.PendingCSITable.DueSlot==dueSlot && ...
        string(state.PendingCSITable.SourceSignal)=="CSI-RS");
    state.TestExpectedCSI=state.PendingCSITable;
end
end

function localVerifyCSI(state)
report=state.PendingCSITable; expected=state.TestExpectedCSI;
assert(height(report)==1 && report.Processed && report.DeliveredSlot==state.CurrentSlot && ...
    report.DueSlot==expected.DueSlot && report.CSIUCIDecodeOk && ...
    string(report.CSIUCITransport)=="pusch_decoded");
trace=state.PUCCHGrantTraceTable;
hit=string(trace.PUCCHGrantId)=="PUCCH-CSI-"+string(report.ReportIdentity);
assert(nnz(hit)==1 && trace.PUSCHUCITransmissionSlot(hit)==report.DueSlot && ...
    trace.PUSCHUCIDeliverySlot(hit)==report.DeliveredSlot && ...
    trace.MultiplexedOnPUSCH(hit) && ~trace.GrantExecutedFlag(hit), ...
    'Received CSI on PUSCH must not become a standalone PUCCH execution.');
for field=["CQI","RI","PMI","PMI_I11","PMI_I12","PMI_I13","PMI_I2","CRI"]
    assert(isequaln(report.(field),expected.(field)), ...
        'Received CSI %s must survive actual coded PUSCH transport.',field);
end
path=fullfile(state.TestRoot,'late_csi_delivery.csv');
sixgr.util.csvWriteTable(path,report,'PreserveSchema',true);
saved=sixgr.util.csvReadTable(path,'TextType','string');
assert(saved.SourceSlot==expected.SourceSlot && saved.DueSlot==expected.DueSlot && ...
    saved.DeliveredSlot==state.CurrentSlot && saved.CSIUCIDecodeOk);
disp('SHARED_PUSCH_LATE_CSI_DELIVERY_PASS: measured CSI-RS report retained across actual PUSCH and late delivery.');
end

function localSaveScenarioEvidence(s,cfg,root)
meta=fullfile(root,'meta'); mkdir(meta);
inputs=fullfile(meta,'input_configs'); mkdir(inputs);
for k=1:numel(s.SourceFiles)
    [~,name,ext]=fileparts(s.SourceFiles(k));
    copyfile(s.SourceFiles(k),fullfile(inputs,sprintf('%03d_%s%s',k,name,ext)));
end
sixgr.util.jsonWrite(fullfile(meta,'resolved_config.json'),s.toStruct());
sixgr.lls6g.config.writeYAML(fullfile(meta,'resolved_config.yaml'),s.toStruct());
sixgr.util.jsonWrite(fullfile(meta,'schema_validation_report.json'), ...
    struct('Passed',true,'Validator','loadScenarioConfig/validateScenarioConfig','ConfigHash',s.ConfigHash));
[status,revision]=system('git rev-parse HEAD'); assert(status==0);
[status,changes]=system('git status --porcelain'); assert(status==0);
sixgr.util.jsonWrite(fullfile(meta,'environment_summary.json'),struct( ...
    'MATLABVersion',version,'Platform',computer,'Toolboxes',ver,'GitHash',strtrim(revision), ...
    'WorktreeStatus',changes,'Scope','component: isolated DL source and shared UL, not full-run qualification'));
sixgr.util.jsonWrite(fullfile(meta,'seeds.json'),struct('RunSeed',cfg.run.seed));
end

function localReject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s.',id);
end
