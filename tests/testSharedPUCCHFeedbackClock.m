function ok=testSharedPUCCHFeedbackClock(includeLateFeedback,mode,scenarioPath,evidenceRoot,feedbackScenarioPath)
% Actual PUCCH IQ/CDL/RF/thermal-noise reception and delayed HARQ reducer.
% Source DL TB/ACK now come from an isolated coded PDSCH connector fixture;
% that DL is not claimed to pass through this shared CDL owner. TAG and
% pathloss remain declared component inputs, NOT measured access. SRS and PUCCH execute here;
% the pilot-free PUCCH clock must come from that actual earlier SRS receiver.
if nargin<1, includeLateFeedback=false; end
if nargin<2, mode="TDD"; end
assert(any(string(mode)==["TDD","FDD"]),'test:BadDuplexFixture','Use an explicit duplex fixture.');
lateCount=double(includeLateFeedback);
validateattributes(lateCount,{'numeric'},{'scalar','integer','>=',0,'<=',2});
setup6GRSimToolkit('Verbose',false);
fixture='lls_pdcch_shared_queue_fixture.yaml';
if string(mode)=="FDD", fixture='lls_trs_shared_scoring_fdd_fixture.yaml'; end
if nargin>=3 && strlength(string(scenarioPath))>0
    s=sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
else
    s=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios',fixture));
end
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
feedbackCfg=cfg; feedbackScenario=s.Data;
if nargin>=5 && strlength(string(feedbackScenarioPath))>0
    feedbackSource=sixgr.lls6g.config.loadScenarioConfig(feedbackScenarioPath);
    feedbackCfg=sixgr.lls6g.buildInternalConfig(feedbackSource,tempname);
    feedbackScenario=feedbackSource.Data;
end
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),10);
if nargin>=4 && strlength(string(evidenceRoot))>0
    assert(~isfolder(evidenceRoot),'test:EvidenceExists','Choose a new evidence directory.');
    mkdir(evidenceRoot);
    state.TestPhysicalEvidenceRoot=char(evidenceRoot);
    resolvedScenario=s.Data;
    save(fullfile(evidenceRoot,'configuration.mat'),'cfg','resolvedScenario','feedbackCfg','feedbackScenario');
end
state.CurrentSlot=1; state.CurrentFrame=1; state.CurrentCanonicalSlot=1;
state.CurrentServingIdx(:)=1;
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
% Explicit analytical selector, consistent with this fixture's configured
% large-scale link (not the unrelated 77 dB two-tap unit fixture). It is NOT
% a simulated SSB observation or main-run measurement. Actual SRS/PUCCH RX
% still executes the configured fading, front ends and thermal noise.
[~,fixtureLink]=sixgr.link.applyWaveformImpairments( ...
    complex(zeros(1,1)),ul,fs,'ApplyRFChain',false);
fixturePathloss=double(fixtureLink.AppliedLargeScaleLoss_dB);
measurement=table(0,fixturePathloss,"SSB-0","analytic_component_pathloss_selector_fixture", ...
    1,-fixturePathloss,0,'VariableNames',{'ReferenceSignalId','MeasuredReferenceSignalPathloss_dB', ...
    'PathlossReferenceRS','MeasuredReferenceSignalPathlossSource','ServingCell', ...
    'SS_RSRP_dBm','ReferenceSignalTxEPRE_dBm'});
state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state,'SSB','UE',1,measurement,'ProducerSlot',1,'AvailableSlot',1,'Valid',true, ...
    'Direction','DL','SourceSignal','SSB','MeasurementSource','analytic_component_selector_fixture');
[received,receiveFields]=receivedDLFeedbackFixture(feedbackCfg,3,0,1e-13);
assert(received.TrialTable.CRCPass==1);
grant=received.HARQ.GrantSnapshot;
% A decoded DL DCI fixes the future K1/PRI occasion before the PDSCH ACK
% value exists.  Reserve that physical observation now, then bind the
% measured ACK below after its receiver result becomes available.
grant.Slot=3;
grant.RNTI=1;
grant.ServingCell=1;
grant.K1=6;
grant.HARQFeedbackAbsoluteSlot=8;
grant.TimingDecision=struct('Valid',true,'K1',6,'FeedbackAbsoluteSlot',8);
grant.PUCCHResourceIndicator=0;
grant.PUCCHResourceIndicatorSource='decoded_dci_fixture';
grant.PDCCHGrantFirstCCE=0;
grant.PDCCHGrantNumCCE=4;
state=sixgr.truth.CoupledTruthRuntime. ...
    armSharedDLHARQOccasionFromGrantRuntime(state,grant,1);
assert(numel(state.SharedArmedPUCCHOccasions)==1, ...
    'Decoded DCI must reserve the complete future PUCCH observation before PDSCH decoding.');
allocation=state.DLHarq.allocate(1,3,grant.TBSBytes,'NewData',true);
assert(allocation.HARQ.HarqID==grant.HARQ.HarqID && allocation.HARQ.NDI==grant.HARQ.NDI);
state.DLHarq.onTx(1,allocation.HARQ.HarqID,uint8(received.HARQ.TransportBlockBits),grant,3);
row=struct('Direction',"DL",'UEIndex',1,'RNTI',1,'HarqID',allocation.HARQ.HarqID, ...
    'SourceSlot',3,'DueSlot',9,'Ack',logical(received.TrialTable.CRCPass),'CurrentDecodeOK',true,'CombinedDecodeOK',true, ...
    'ServingCell',1,'BaseStationID',1,'TBSBits',grant.TBSBits,'UCIBitCount',1, ...
    'RequestedFormat',0,'ResolvedFormat',0,'PUCCHResourceId',"0", ...
    'PUCCHPRBStart',0,'PUCCHPRBCount',1,'PUCCHSymbolStart',12,'PUCCHNumSymbols',2, ...
    'UCIType',"harq_ack",'ControlResourceSource',"declared_component_feedback_fixture", ...
    'ControlResourceValidity',true,'FormatAdaptationReason',"none_strict_assignment", ...
    'PUCCHGrantId',"shared_component_ack_1",'DeliveryMechanism',"pucch", ...
    'PUSCHGrantContextId',"",'MultiplexedBitIndex',NaN,'Processed',false);
row.ComponentCarrier=cfg.phy.frame.DefaultIdentity.ScheduledCCID;
row.ActiveULBWP=cfg.phy.frame.DefaultIdentity.ULBWPID;
for name=string(fieldnames(receiveFields)).', row.(name)=receiveFields.(name); end
[srsCfg,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
srsCfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(srsCfg,5);
srsCfg.lls6g.userContext.RuntimeSlotStartTime_s=4e-3;
args={'SlotIndex',5,'SNR_dB',12,'TimingAdvanceSamples',0};
prepared=sixgr.link.runSRSChannelEstimation(srsCfg,args{:},'PrepareOnly',true);
owner.queueUplinkControl(1,prepared.PreparedTransmission,struct('Config',srsCfg,'Arguments',{args}));
for slot=1:10
    state.CurrentSlot=slot; state.CurrentCanonicalSlot=slot;
    state.CurrentFrame=floor((slot-1)/state.SlotsPerFrame)+1;
    if slot==5
        assert(row.DataDecodeAvailableAtSample<=owner.Events.NextSampleIndex);
        state.PendingFeedbackTable=struct2table(row);
        state=sixgr.truth.CoupledTruthRuntime.schedulePUCCHGrantRuntime(state,state.PendingFeedbackTable);
        state=sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(state);
        state=sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(state);
        assert(numel(state.SharedArmedPUCCHOccasions)==1,'Arming the same feedback twice must be idempotent.');
    end
    if includeLateFeedback && slot==9
        % Another actual isolated DL result is delivered after the TX/RX
        % capture origins, but before symbols 12-13 are encoded/emitted.
        % Its payload must join the same actual Format-0 waveform.
        hit=find(string({owner.Pending.Kind})=="PUCCH");
        assert(isscalar(hit) && owner.Pending(hit).Context.AwaitingPreparation);
        assert(owner.Events.NextSampleIndex>owner.Pending(hit).Context.PhysicalTiming.TransmitStartSample);
        for lateIndex=1:lateCount
        sourceSlot=5+lateIndex;
        variance=1e-13; if mod(lateIndex,2)==1, variance=1e-4; end
        [received2,receiveFields2]=receivedDLFeedbackFixture(feedbackCfg,sourceSlot,lateIndex,variance);
        grant2=received2.HARQ.GrantSnapshot;
        allocation2=state.DLHarq.allocate(1,sourceSlot,grant2.TBSBytes,'NewData',true);
        assert(allocation2.HARQ.HarqID==grant2.HARQ.HarqID && allocation2.HARQ.NDI==grant2.HARQ.NDI);
        state.DLHarq.onTx(1,allocation2.HARQ.HarqID,uint8(received2.HARQ.TransportBlockBits),grant2,sourceSlot);
        late=row; late.SourceSlot=sourceSlot; late.HarqID=allocation2.HARQ.HarqID;
        late.TBSBits=grant2.TBSBits;
        late.Ack=logical(received2.TrialTable.CRCPass);
        assert(late.Ack==(mod(lateIndex,2)==0),'The actual noisy/clean PDSCH must supply the expected NACK/ACK.');
        late.CurrentDecodeOK=late.Ack; late.CombinedDecodeOK=late.Ack;
        for name=string(fieldnames(receiveFields2)).', late.(name)=receiveFields2.(name); end
        assert(late.DataDecodeAvailableAtSample<=owner.Events.NextSampleIndex);
        late.PUCCHGrantId="shared_component_ack_"+sourceSlot;
        state.PendingFeedbackTable=[state.PendingFeedbackTable;struct2table(late)];
        state=sixgr.truth.CoupledTruthRuntime.schedulePUCCHGrantRuntime(state,struct2table(late));
        state=sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(state);
        assert(numel(state.SharedArmedPUCCHOccasions)==1);
        end
        traceKeys=sixgr.truth.CoupledTruthRuntime.sharedPUCCHOccasionKey( ...
            state.PUCCHGrantTraceTable);
        assert(all(traceKeys==state.SharedArmedPUCCHOccasions(1)), ...
            'test:SharedPUCCHLateFeedbackIdentity', ...
            'Late feedback keys %s must equal armed key %s.', ...
            char(strjoin(traceKeys,',')),char(state.SharedArmedPUCCHOccasions(1)));
        assert(all(~state.PUCCHGrantTraceTable.MultiplexedOnPUSCH), ...
            'test:UnexpectedSharedPUCCHMultiplexing', ...
            'Unexpected multiplex flags=%s context=%s.', ...
            mat2str(logical(state.PUCCHGrantTraceTable.MultiplexedOnPUSCH).'), ...
            char(strjoin(string(state.PUCCHGrantTraceTable.PUSCHGrantContextId),',')));
    end
    [state,~]=owner.advanceSlot(state,cfg,@localEvents);
end
assert(state.TestPUCCHPrepared && state.TestPUCCHReceived);
assert(all(state.PendingFeedbackTable.Processed) && all(state.PUCCHGrantTraceTable.GrantExecutedFlag), ...
    'test:SharedPUCCHFeedbackNotCommitted', ...
    'Pending processed=%s; grant executed=%s.', ...
    mat2str(logical(state.PendingFeedbackTable.Processed).'), ...
    mat2str(logical(state.PUCCHGrantTraceTable.GrantExecutedFlag).'));
assert(height(state.ControlTrials.PUCCH)==1 && state.ControlTrials.PUCCH.Slot==9);
assert(all(state.PUCCHGrantTraceTable.DTXFlag==state.ControlTrials.PUCCH.DTXFlag), ...
    'Physical receiver DTX must propagate to every logical grant sharing its occasion.');
assert(all(strlength(string(state.PUCCHGrantTraceTable.DTXReason))==0), ...
    'Successful receiver decisions must not retain a stale DTX reason.');
assert(state.DLHarq.Stats.Dtx==0 && all( ...
    string(state.PUCCHGrantTraceTable.FeedbackOutcome)== ...
    replace(string(double(state.PUCCHGrantTraceTable.ObservedAck)),["0","1"],["NACK","ACK"])));
assert(all(string(state.PUCCHGrantTraceTable.FeedbackOutcomeReason)=="decoded_uci_bit"));
verifyPUCCHPowerExport(state.ControlTrials.PUCCH,cfg);
thresholdField="detection_threshold_format0_two_symbols";
if state.ControlTrials.PUCCH.PUCCHFormat~=0
    thresholdField="detection_threshold_format"+string(state.ControlTrials.PUCCH.PUCCHFormat);
end
assert(state.ControlTrials.PUCCH.DetectionThreshold==cfg.phy.pucch.receiverDetectionThresholds.(thresholdField));
assert(string(state.ControlTrials.PUCCH.DetectionThresholdSource)=="yaml.pucch."+thresholdField);
assert(all(state.PUCCHGrantTraceTable.DetectionThreshold==state.ControlTrials.PUCCH.DetectionThreshold) && ...
    all(string(state.PUCCHGrantTraceTable.DetectionThresholdSource)=="yaml.pucch."+thresholdField));
assert(~state.ControlTrials.PUCCH.CRCApplicable && isnan(state.ControlTrials.PUCCH.CRCPass));
assert(state.ControlTrials.PUCCH.PUCCHDecodeOk, ...
    'The actual Format-0 payload must decode, not just produce a failed-attempt row.');
assert(isfinite(state.ControlTrials.PUCCH.AppliedTimingCorrectionSamples) && ...
    ~state.ControlTrials.PUCCH.UseIdealTimingSync, ...
    'Actual reference-based capture alignment must survive the runtime timing projection.');
if state.ControlTrials.PUCCH.PUCCHFormat==0
    assert(isnan(state.ControlTrials.PUCCH.EstimatedTimingOffsetSamples) && ...
        ~state.ControlTrials.PUCCH.TimingEstimateUsed && ...
        string(state.ControlTrials.PUCCH.TimingEstimateSource)== ...
        "prior_received_UL_pilot_constant_phase_prediction", ...
        'Pilot-free PUCCH must not relabel retained timing prediction as a fresh estimate.');
else
    assert(isfinite(state.ControlTrials.PUCCH.EstimatedTimingOffsetSamples) && ...
        state.ControlTrials.PUCCH.TimingEstimateUsed, ...
        'test:SharedPUCCHTimingApplicationFlag', ...
        'Measured PUCCH DM-RS timing must retain its application flag.');
end
if ~includeLateFeedback
    assert(state.ControlTrials.PUCCH.ObservedAck);
else
    assert(height(state.PUCCHGrantTraceTable)==1+lateCount && ...
        all(state.PUCCHGrantTraceTable.GrantExecutedFlag));
    assert(state.DLHarq.Stats.Ack==1+floor(lateCount/2) && state.DLHarq.Stats.Nack==ceil(lateCount/2), ...
        'The received codebook must apply each ACK/NACK to its own HARQ process.');
end
if state.ControlTrials.PUCCH.PUCCHFormat==0
    assert(isnan(state.ControlTrials.PUCCH.NoiseVariance) && ...
        string(state.ControlTrials.PUCCH.NoiseVarStatus)=="unavailable");
else
    assert(lateCount==2 && state.ControlTrials.PUCCH.PUCCHFormat==2 && ...
        isfinite(state.ControlTrials.PUCCH.NoiseVariance));
end
assert(~owner.hasPending('PUCCH',1));
assert(state.TestSRSArtifactVerified,'Actual received SRS must publish independently verifiable channel arrays.');
ok=true; disp('SHARED_PUCCH_FEEDBACK_CLOCK_PASS');
end

function state=localEvents(state,events)
for item=events
    if item.Kind=="SRS"
        p=item.Context.Prepared; c=item.Context;
        [~,pre,tx,replay,receiver]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
        [~,channelEvidence,channelReferences]=sixgr.truth.sharedLinkScoringObservation(item.Planes,p,c.DesiredReferencePlane);
        assert(channelEvidence.ChannelReferenceCoverageComplete && ...
            numel(channelReferences)==nnz(channelEvidence.LinkActive) && ...
            all(cellfun(@(s)~isfield(s.Execution,'ChannelReferences'), ...
            replay.ReceiveStreamExecutionSegments)), ...
            'Actual uplink SRS needs complete active-link scoring evidence, isolated from its receiver.');
        input=struct('Prepared',p,'Observation',receiver,'PhysicalMeasurementObservation',pre, ...
            'TransmitterObservation',tx,'Replay',replay,'ScoringChannelReferences',{channelReferences}, ...
            'ChannelState',state.SharedWaveformStream.directionalChannelState(1,'UL'));
        output=sixgr.link.runSRSChannelEstimation(c.Config,c.Arguments{:},'ReceivedContext',input);
        if isfield(state,'TestPhysicalEvidenceRoot')
            save(fullfile(state.TestPhysicalEvidenceRoot,'received_srs.mat'),'output','input','p');
        end
        if ~output.Ok
            diagnosticFile=string(tempname)+"_shared_srs_failure.mat";
            save(diagnosticFile,'output','input','p');
            fprintf('SHARED_SRS_FAILURE=%s NMSE=%g threshold=%g timing=%g noise=%g\n', ...
                diagnosticFile,output.NMSE_dB,output.ChannelNMSEThreshold_dB, ...
                output.ReceiveTiming.AppliedTimingCorrectionSamples,output.NoiseVariance);
            details=[string(output.Notes(:));string(output.FailureReason(:))];
            details=details(~ismissing(details));
            error('test:SharedSRSFailed','Actual SRS failed: %s.', ...
                char(strjoin(details,";")));
        end
        measuredClock=sixgr.truth.retainReceivedSRSTimingReference(p,receiver,output);
        assert(isa(measuredClock,'sixgr.phy.sync.ReceivedULTimingReference'));
        % The capture and practical receiver evidence are identical. Only
        % independent qualification/scoring changes; it must not control
        % which received clock a later pilot-free PUCCH is allowed to use.
        scoringFailure=output;
        scoringFailure.Ok=false; scoringFailure.StrictOk=false;
        scoringFailure.TrueChannelOracleAvailable=false;
        scoringFailure.NMSE_dB=99; scoringFailure.TrueChannelNMSE_dB=99;
        sameClock=sixgr.truth.retainReceivedSRSTimingReference(p,receiver,scoringFailure);
        assert(isequaln(measuredClock,sameClock), ...
            'Independent channel-NMSE scoring changed received UL timing authority.');
        unusable=output; unusable.SRSRuntimeEvidenceUsable=false;
        assert(isempty(sixgr.truth.retainReceivedSRSTimingReference(p,receiver,unusable)));
        invalidCapture=output;
        invalidCapture.ReceiveTiming.AppliedTimingCorrectionSamples= ...
            receiver.EndSampleExclusive-receiver.StartSample;
        try
            sixgr.truth.retainReceivedSRSTimingReference(p,receiver,invalidCapture);
            error('test:MissingCaptureRejection','Invalid timing must not be retained.');
        catch clockFailure
            assert(strcmp(clockFailure.identifier,'sixgr:phy:sync:ULTimingOutsideCapture'));
        end
        state.ReceivedULTimingReferences={measuredClock};
        % Persist the actual uplink captures, then independently reload both
        % the primary CSV binding and coefficient MAT/segment CSV. This is
        % not a reconstructed H, configured profile substitute, or extra
        % channel execution used to manufacture an estimator reference.
        root=tempname; mkdir(root);
        row=table(5,"SRS","UL",'VariableNames',{'Slot','Channel','Direction'});
        row=sixgr.truth.exportSharedChannelObservation(root,row,item.Planes,p,c.DesiredReferencePlane);
        primary=fullfile(root,'received_srs_channel.csv');
        sixgr.util.csvWriteTable(primary,row,'PreserveSchema',true);
        persisted=readtable(primary,'TextType','string','VariableNamingRule','preserve');
        verified=sixgr.channel.validateSharedChannelObservationArtifact(root,persisted);
        assert(height(verified.Segments)==numel(channelReferences) && ...
            all(verified.Segments.NumTransmitAntennas==p.NumPhysicalTransmitAntennas) && ...
            all(verified.Segments.NumReceiveAntennas==p.NumReceiveAntennas) && ...
            verified.Manifest.ObservationStartSample==receiver.StartSample && ...
            verified.Manifest.ObservationEndSampleExclusive==receiver.EndSampleExclusive && ...
            ~verified.Manifest.ReceiverEstimatorInput && verified.Manifest.AdditionalChannelExecutions==0);
        saved=load(verified.MATPath,'Captures');
        for captureIndex=1:numel(channelReferences)
            assert(isequaln(saved.Captures{captureIndex}.Reference.PathGains, ...
                channelReferences{captureIndex}.Reference.PathGains) && ...
                isequaln(saved.Captures{captureIndex}.Reference.PathFilters, ...
                channelReferences{captureIndex}.Reference.PathFilters) && ...
                isequaln(saved.Captures{captureIndex}.Reference.SampleTimes_s, ...
                channelReferences{captureIndex}.Reference.SampleTimes_s));
        end
        state.TestSRSArtifactVerified=true;
    elseif item.Kind=="PreparePUCCH"
        future=state;
        lateTiming=jsondecode(future.PUCCHGrantTraceTable.DataReceiveTimingEvidenceJSON(1));
        lateTiming.ResultAvailableAtSample=state.SharedWaveformStream.Events.NextSampleIndex+1;
        future.PUCCHGrantTraceTable.DataDecodeAvailableAtSample(1)=lateTiming.ResultAvailableAtSample;
        future.PUCCHGrantTraceTable.DataReceiveTimingEvidenceJSON(1)=string(jsonencode(lateTiming));
        localReject(@()sixgr.truth.CoupledTruthRuntime.prepareSharedPUCCHFeedbackRuntime(future,item), ...
            'sixgr:truth:FutureHARQFeedbackAtUCIEncoding');
        state=sixgr.truth.CoupledTruthRuntime.prepareSharedPUCCHFeedbackRuntime(state,item);
        armed=find(string({state.SharedWaveformStream.Pending.Kind})=="PUCCH");
        assert(isscalar(armed) && ...
            height(state.SharedWaveformStream.Pending(armed).Context.FeedbackRows)== ...
            height(state.PUCCHGrantTraceTable), ...
            'test:SharedPUCCHPreparedCodebookRows', ...
            'Prepared rows=%d but trace rows=%d.', ...
            height(state.SharedWaveformStream.Pending(armed).Context.FeedbackRows), ...
            height(state.PUCCHGrantTraceTable));
        assert(all(~state.PendingFeedbackTable.Processed) && all(~state.PUCCHGrantTraceTable.GrantExecutedFlag));
        assert(state.SharedWaveformStream.hasPending('PUCCH',1));
        lateState=state;
        unexpected=state.PUCCHGrantTraceTable(1,:);
        unexpected.PUCCHGrantId="cannot_join_already_encoded_control";
        lateState.PUCCHGrantTraceTable=[lateState.PUCCHGrantTraceTable;unexpected];
        localReject(@()sixgr.truth.CoupledTruthRuntime.armSharedPUCCHFeedbackRuntime(lateState), ...
            'sixgr:truth:LateSharedPUCCHFeedback');
        state.TestPUCCHPrepared=true;
    elseif item.Kind=="PUCCH"
        if isfield(state,'TestPhysicalEvidenceRoot')
            timingReferences=state.ReceivedULTimingReferences;
            save(fullfile(state.TestPhysicalEvidenceRoot,'received_pucch.mat'),'item','timingReferences');
        end
        assert(height(item.Context.FeedbackRows)==height(state.PUCCHGrantTraceTable), ...
            'test:SharedPUCCHReceivedCodebookRows', ...
            'Received rows=%d but trace rows=%d.', ...
            height(item.Context.FeedbackRows),height(state.PUCCHGrantTraceTable));
        assert(all(~state.PendingFeedbackTable.Processed),'No feedback may be applied before actual RX completion.');
        if height(state.PendingFeedbackTable)<=2
            missing=rmfield(state,'ReceivedULTimingReferences');
            localReject(@()sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHFeedbackRuntime(missing,item), ...
                'sixgr:phy:pucch:PUCCHTimingReferenceRequired');
        end
        state=sixgr.truth.CoupledTruthRuntime.completeSharedPUCCHFeedbackRuntime(state,item);
        assert(all(state.ControlTrials.PUCCH.ReceiverInjectedNoiseVarianceConsumed==0) && ...
            all(string(state.ControlTrials.PUCCH.ReceiverInputSampleNoiseVarianceValueRole)== ...
            "physical_execution_metadata_not_receiver_estimate"), ...
            'Shared PUCCH exports must distinguish injection metadata from practical receiver estimates.');
        if isfield(state,'TestPhysicalEvidenceRoot')
            writetable(state.ControlTrials.PUCCH,fullfile(state.TestPhysicalEvidenceRoot,'received_pucch_trials.csv'));
            writetable(state.PUCCHGrantTraceTable,fullfile(state.TestPhysicalEvidenceRoot,'received_pucch_grants.csv'));
        end
        assert(state.SharedLastPUCCHAvailableAtSample==state.SharedWaveformStream.Events.NextSampleIndex);
        state.TestPUCCHReceived=true;
    else
        error('test:UnexpectedSharedEvent','Unexpected event %s.',item.Kind);
    end
end
end

function localReject(f,id)
try, f(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s.',id,cause.identifier); return;
end
error('test:MissingError','Expected %s.',id);
end
