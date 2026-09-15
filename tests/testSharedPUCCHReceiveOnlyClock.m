function [ok,state]=testSharedPUCCHReceiveOnlyClock(outputRoot,configPath)
% Actual shared DL TX, SRS and absent-PUCCH receiver observation.
% UE PDCCH/PDSCH reception is deliberately unexecuted: this component does
% not claim a measured missed-DCI rate or full connected baseline pass.
if nargin<1, outputRoot=tempname; end
if nargin<2, configPath='simulator/configs/scenarios/lls_pucch_gnb_receive_only_fixture.yaml'; end
assert(~isfolder(outputRoot),'test:EvidenceAlreadyExists','Preserve earlier observations.');
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig(configPath);
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
previousRNG=rng; cleanup=onCleanup(@()rng(previousRNG));
rng(double(cfg.run.seed),'twister');
mkdir(outputRoot); resolvedScenario=s.Data;
save(fullfile(outputRoot,'configuration.mat'),'cfg','resolvedScenario');
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),10);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[ul,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
carrier=sixgr.phy.grid.makeCarrier(ul); fs=owner.SampleRateHz;
% Declared connected-clock component inputs, NOT simulated access.
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
measurement=table(0,loss,"SSB-0","analytic_component_pathloss_selector_fixture",1,-loss,0, ...
    'VariableNames',{'ReferenceSignalId','MeasuredReferenceSignalPathloss_dB', ...
    'PathlossReferenceRS','MeasuredReferenceSignalPathlossSource','ServingCell','SS_RSRP_dBm','ReferenceSignalTxEPRE_dBm'});
state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime(state,'SSB','UE',1, ...
    measurement,'ProducerSlot',1,'AvailableSlot',1,'Valid',true,'Direction','DL', ...
    'SourceSignal','SSB','MeasurementSource','analytic_component_selector_fixture');
[srsCfg,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
srsCfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(srsCfg,5);
srsCfg.lls6g.userContext.RuntimeSlotStartTime_s=sixgr.phy.frame.slotStartSample(carrier,4,fs)/fs;
args={'SlotIndex',5,'SNR_dB',cfg.channel.snr_dB,'TimingAdvanceSamples',0};
prepared=sixgr.link.runSRSChannelEstimation(srsCfg,args{:},'PrepareOnly',true);
owner.queueUplinkControl(1,prepared.PreparedTransmission,struct('Config',srsCfg,'Arguments',{args}));
state.TestEvidenceRoot=outputRoot; state.TestDLReceives=0;
daiLedger=struct(); state.DLQueueBits(1)=0;
for slot=1:10
    state.CurrentSlot=slot; state.CurrentCanonicalSlot=slot;
    state.CurrentFrame=floor((slot-1)/state.SlotsPerFrame)+1;
    if any(slot==[6 7])
        [dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
        dl=sixgr.phy.grid.applyRuntimeCarrierTimeline(dl,slot);
        dl.lls6g.userContext.RuntimeSlotStartTime_s=sixgr.phy.frame.slotStartSample(carrier,slot-1,fs)/fs;
        grant=sixgr.link.resolveWaveformGrant(dl,'DL',1,'Slot',slot,'SFN',0,'ControlAbsoluteSlot',slot-1);
        allocated=state.DLHarq.allocate(grant.RNTI,slot,grant.TBSBits/8,'NewData',true);
        grant=sixgr.link.resolveWaveformGrant(dl,'DL',1,'Slot',slot,'SFN',0, ...
            'ControlAbsoluteSlot',slot-1,'HARQProcess',allocated.HARQ.HarqID);
        grant.ServingCell=grant.BaseStationID;
        [grant,daiLedger]=sixgr.truth.prepareScheduledDLDAI(daiLedger,dl,grant);
        assert(grant.TimingDecision.FeedbackAbsoluteSlot==8 && allocated.HARQ.NDI==grant.HARQ.NDI);
        job=sixgr.truth.buildGrantPHYJob(dl,'DL',cfg.channel.snr_dB,1,[], ...
            struct('GrantSnapshot',grant,'PHYGrant',grant.PHYGrant,'PrepareOnly',true));
        job.StartSlotIndex=slot;
        result=sixgr.truth.executeGrantPHYJob(job);
        owner.queueData(1,result.Result.PreparedTransmission,struct('Purpose',"unreceived_UE_control_component"));
        state.DLQueueBits(1)=state.DLQueueBits(1)+grant.TBSBits;
    end
    [state,~]=owner.advanceSlot(state,cfg,@localEvents);
end
assert(numel(state.SharedDataTXLedger)==2 && state.TestDLReceives==2 && ...
    isempty(state.PendingFeedbackTable) && isempty(state.PUCCHGrantTraceTable) && ...
    isempty(sixgr.util.structGet(state,'SharedUEHARQACKEvents',{})));
assert(height(state.SharedGNBUCIHARQTable)==2 && height(state.ControlTrials.PUCCH)==1 && ...
    numel(state.SharedGNBUCIReceptions)==1 && all(~state.SharedGNBUCIHARQTable.StaleFeedbackIgnored));
rx=state.SharedGNBUCIReceptions{1}.Receiver;
assert(rx.IndependentReceiverAssignment && ~rx.PreparedTransmitterConsumed && ~rx.OraclePayloadBitsUsed);
outcomes=string(state.SharedGNBUCIHARQTable.FeedbackOutcome);
assert(state.DLHarq.Stats.Ack==nnz(outcomes=="ACK") && ...
    state.DLHarq.Stats.Nack==nnz(outcomes=="NACK") && state.DLHarq.Stats.Dtx==nnz(outcomes=="DTX"));
assert(~owner.hasPending('PUCCH',1) && ~owner.hasPending('PUCCHReceiveOnly',1));
writetable(state.SharedGNBUCIHARQTable,fullfile(outputRoot,'gnb_harq_feedback_observations.csv'));
writetable(state.ControlTrials.PUCCH,fullfile(outputRoot,'pucch_receive_only_trials.csv'));
fprintf('SHARED_PUCCH_RECEIVE_ONLY_PASS actual_DL_TX=2 UE_UCI_producers=0 outcomes=%s folder=%s\n', ...
    strjoin(outcomes,','),outputRoot);
ok=true;
end

function state=localEvents(state,items)
for item=items
    if item.Kind=="SRS"
        p=item.Context.Prepared; c=item.Context;
        [~,pre,tx,replay,received]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
        [~,~,references]=sixgr.truth.sharedLinkScoringObservation(item.Planes,p,c.DesiredReferencePlane);
        input=struct('Prepared',p,'Observation',received,'PhysicalMeasurementObservation',pre, ...
            'TransmitterObservation',tx,'Replay',replay,'ScoringChannelReferences',{references}, ...
            'ChannelState',state.SharedWaveformStream.directionalChannelState(1,'UL'));
        output=sixgr.link.runSRSChannelEstimation(c.Config,c.Arguments{:},'ReceivedContext',input);
        % Export the independent score from this actual received SRS. The
        % practical estimator has already run without the scoring reference.
        scoreRow=table(output.NMSE_dB,output.TrueChannelNMSE_dB,string(output.NMSEReferenceSource), ...
            'VariableNames',{'NMSE_dB','TrueChannelNMSE_dB','NMSEReferenceSource'});
        scoreRow=sixgr.truth.bindSharedSRSNMSEEvidence(scoreRow,output);
        assert(scoreRow.NMSEScoringAvailable && ...
            scoreRow.ChannelNMSEComparedComplexValues==output.ChannelNMSEScoring.ComparedComplexValueCount && ...
            scoreRow.ChannelNMSEPilotResourceCount==output.ChannelNMSEScoring.PilotResourceCount && ...
            isequaln(scoreRow.NMSE_dB,output.NMSE_dB) && ...
            scoreRow.ChannelNMSEReferencePlane==string(output.ChannelNMSEReferenceEvidence.ReferencePlane));
        writetable(scoreRow,fullfile(state.TestEvidenceRoot,'received_srs_nmse_evidence.csv'));
        clock=sixgr.truth.retainReceivedSRSTimingReference(p,received,output);
        assert(isa(clock,'sixgr.phy.sync.ReceivedULTimingReference'),'Actual SRS timing must be usable.');
        state.ReceivedULTimingReferences={clock};
        save(fullfile(state.TestEvidenceRoot,'received_srs.mat'),'input','output','p');
    elseif item.Kind=="DataTX"
        state=sixgr.truth.commitSharedDataTransmission(state,item);
        transmitted=state.SharedDataTXLedger{end};
        state=sixgr.truth.CoupledTruthRuntime.armSharedDLHARQOccasionFromGrantRuntime(state,transmitted.Grant,item.UE);
    elseif item.Kind=="PDSCH"
        state.TestDLReceives=state.TestDLReceives+1;
        save(fullfile(state.TestEvidenceRoot,sprintf('unconsumed_ue_pdsch_%d.mat',state.TestDLReceives)),'item');
    elseif item.Kind=="PreparePUCCH"
        assert(isempty(state.PendingFeedbackTable) && isempty(state.PUCCHGrantTraceTable));
        state=sixgr.truth.CoupledTruthRuntime.prepareSharedPUCCHFeedbackRuntime(state,item);
        pending=state.SharedWaveformStream.Pending;
        hit=find(string({pending.Kind})=="PUCCHReceiveOnly");
        assert(isscalar(hit) && ~isfield(pending(hit).Context,'Prepared'));
        h=pending(hit).Context.GNBReception;
        assert(h.Mapping.BitCount==2 && h.Context.HARQACKBits==2);
        c=pending(hit).Context.Config;
        bad=c; bad.phy.csi.reportCSI=true;
        % Keep the original real-overlap rejection on the tested occasion,
        % even when this component is run with another installed calendar.
        bad.phy.csi.reportOffsetSlots=mod(item.Context.Slot-1,bad.phy.csi.reportPeriodicitySlots);
        localReject(@()sixgr.truth.buildScheduledPUCCHHARQReception(state,bad,1,item.Context.Slot,h.Assignment.Data.ObservationID), ...
            'sixgr:truth:UnresolvedCombinedPUCCHReceiveHypothesis');
        noCSIHere=bad;
        noCSIHere.phy.csi.reportOffsetSlots=mod(bad.phy.csi.reportOffsetSlots+1, ...
            bad.phy.csi.reportPeriodicitySlots);
        absentCSI=sixgr.truth.buildScheduledPUCCHHARQReception( ...
            state,noCSIHere,1,item.Context.Slot,h.Assignment.Data.ObservationID);
        assert(isempty(absentCSI.CSIReportCalendar) && ...
            absentCSI.Mapping.Digest==h.Mapping.Digest && ...
            absentCSI.Assignment.Digest==h.Assignment.Digest && absentCSI.Context.Digest==h.Context.Digest);
        poisonedCSIState=state;
        poisonedCSIState.PendingCSITable=table(true,"invented_report", ...
            'VariableNames',{'Processed','ReportIdentity'});
        same=sixgr.truth.buildScheduledPUCCHHARQReception( ...
            poisonedCSIState,noCSIHere,1,item.Context.Slot,h.Assignment.Data.ObservationID);
        assert(isequaln(same,absentCSI),'UE report presence must not change the gNB receive hypothesis.');
        bad=c; bad.phy.pucch.uciOnPUSCHEnabled=NaN;
        localReject(@()sixgr.truth.buildScheduledPUCCHHARQReception(state,bad,1,item.Context.Slot,h.Assignment.Data.ObservationID), ...
            'sixgr:truth:InvalidPUCCHTransportConfiguration');
        if c.phy.pucch.uciOnPUSCHEnabled
            assert(h.TransportScheduleEvidence.OverlappingPUSCHCount==0 && ...
                isempty(state.SharedWaveformStream.readTransmittedULControls(1,item.Context.Slot)));
            poisoned=state;
            poisoned.SharedPendingULGrants=struct('UEIndex',1,'Slot',item.Context.Slot,'ExpectedUCIBits',ones(99,1));
            poisoned.PendingFeedbackTable=table(true,'VariableNames',{'Ack'});
            independent=sixgr.truth.buildScheduledPUCCHHARQReception(poisoned,c,1,item.Context.Slot,h.Assignment.Data.ObservationID);
            assert(independent.Mapping.Digest==h.Mapping.Digest && independent.Assignment.Digest==h.Assignment.Digest && ...
                isequaln(independent.TransportScheduleEvidence,h.TransportScheduleEvidence), ...
                'UE pending grants/ACKs must not replace the physically transmitted gNB control schedule.');
        end
        bad=c; bad.validation.pucch_resources.sr_resource_ids=0;
        localReject(@()sixgr.truth.buildScheduledPUCCHHARQReception(state,bad,1,item.Context.Slot,h.Assignment.Data.ObservationID), ...
            'sixgr:truth:MissingInstalledSRCalendar');
        % Configured receiver obligations, never UE positive/pending SR bits.
        srFixture=sixgr.lls6g.config.readConfigFile(fullfile(fileparts(fileparts(mfilename('fullpath'))), ...
            'simulator','configs','scenarios','lls_tdd_configured_sr_calendar_fixture.yaml'));
        bad.validation.pucch_resources.scheduling_request_resources=srFixture.pucch_resources.scheduling_request_resources;
        localReject(@()sixgr.truth.buildScheduledPUCCHHARQReception(state,bad,1,item.Context.Slot,h.Assignment.Data.ObservationID), ...
            'sixgr:truth:UnresolvedSRPUCCHReceiveHypothesis');
        % The next-slot calendar has no SR in this receive window. Retain
        % exactly the same independently scheduled HARQ count and resource.
        bad.validation.pucch_resources.scheduling_request_resources.offset_slots=4;
        noSR=sixgr.truth.buildScheduledPUCCHHARQReception(state,bad,1,item.Context.Slot,h.Assignment.Data.ObservationID);
        assert(noSR.Context.HARQACKBits==h.Context.HARQACKBits && noSR.Context.SRBits==0 && ...
            noSR.Assignment.Data.ResourceID==h.Assignment.Data.ResourceID);
        bad=c; bad.validation.pucch_resources=rmfield(bad.validation.pucch_resources,'sr_resource_ids');
        localReject(@()sixgr.truth.buildScheduledPUCCHHARQReception(state,bad,1,item.Context.Slot,h.Assignment.Data.ObservationID), ...
            'sixgr:phy:pucch:StaleConfiguration');
        localReject(@()state.SharedWaveformStream.bindPUCCHReceiveOnly(item.Context.ObservationID,c,h), ...
            'sixgr:truth:InvalidPUCCHReceiveOnlyBinding');
    elseif item.Kind=="PUCCHReceiveOnly"
        planes=string({item.Planes.ReceiverID});
        tx=item.Planes(planes=="ue_1:tx").Observation.readComplete();
        assert(all(tx==0,'all'),'No PUCCH or other UE TX contribution may be fabricated in this fixture.');
        before=state.DLHarq.Stats;
        bad=item; bad.Context.Prepared=struct();
        localReject(@()sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHReceiveOnlyRuntime(state,bad), ...
            'sixgr:truth:InvalidPUCCHReceiveOnlyCompletion');
        bad=item; bad.Context.GNBReception.Mapping.Digest="changed_mapping";
        localReject(@()sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHReceiveOnlyRuntime(state,bad), ...
            'sixgr:truth:ChangedPUCCHReceiveHypothesis');
        assert(isequaln(before,state.DLHarq.Stats),'Rejected completions must not mutate HARQ state.');
        state=sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHReceiveOnlyRuntime(state,item);
        after=state.DLHarq.Stats;
        localReject(@()sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHReceiveOnlyRuntime(state,item), ...
            'sixgr:truth:InvalidPUCCHReceiveOnlyCompletion');
        assert(isequaln(after,state.DLHarq.Stats));
        received=state.SharedGNBUCIReceptions{end};
        timingReferences=state.ReceivedULTimingReferences;
        h=item.Context.GNBReception; c=item.Context.Config;
        post=item.Planes(endsWith(planes,":post_rf")).Observation;
        direct=sixgr.link.receivePUCCHObservation(c,h.Assignment,h.Context,post,timingReferences{1});
        assert(isequal(direct.DecodedSequence1,received.Receiver.DecodedSequence1) && ...
            direct.DTX==received.Receiver.DTX && direct.DetectionMetric==received.Receiver.DetectionMetric);
        fprintf('SHARED_PUCCH_RECEIVE_ONLY_GUARDS_PASS rejections=9 configured_SR_overlap_guard=1 unchanged_rejected_HARQ_state=1 actual_IQ_replay_equivalence=1\n');
        save(fullfile(state.TestEvidenceRoot,'received_pucch_absent.mat'),'item','received','timingReferences');
    else
        error('test:UnexpectedPhysicalEvent','Unexpected physical event %s.',item.Kind);
    end
end
end

function localReject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s',id);
end
