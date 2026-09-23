function ok=testSharedStandaloneSRReception()
% Actual shared SR TX/RX and noise-only monitoring before any CSI-RS/SRS.
% Connected access clock is a declared component input, not access proof.
% Two episodes do not statistically qualify the acquired-timing detector.
setup6GRSimToolkit('Verbose',false);
canonicalEpisodes=cell(1,2);
for positive=[false true]
    folder=tempname(fullfile(pwd,'logs')); mkdir(folder);
    s=sixgr.lls6g.config.loadScenarioConfig( ...
        'simulator/configs/scenarios/lls_tdd_5mhz_rank2_shared_awgn_20db.yaml');
    cfg=sixgr.lls6g.buildInternalConfig(s,folder);
    cfg.run.rootRunFolder=folder;
    previous=rng; cleanup=onCleanup(@()rng(previous)); %#ok<NASGU>
    rng(double(cfg.run.seed),'twister');
    multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
    state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),5);
    state=sixgr.truth.CoupledTruthRuntime.startSlot(state,cfg,'DL',1,1,1,5,cfg.channel.snr_dB);
    state.CurrentServingIdx(:)=1;
    [state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
    carrier=sixgr.phy.grid.makeCarrier(cfg); fs=owner.SampleRateHz;
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
    states=state.UEConfiguredSRProcedures{1,1}; assert(isscalar(states));
    d=states.Data; d.PendingPositiveSR=positive;
    state.UEConfiguredSRProcedures{1,1}=sixgr.phy.pucch.SchedulingRequestState(d);
    h=sixgr.truth.buildConfiguredPUCCHReception(state,cfg,1,4,"SR_schema");
    assert(h.Context.SRBits==1 && h.Context.HARQACKBits==0 && h.Context.CSIPart1Bits==0);
    poisoned=state; poisoned.PendingCSITable="not_a_payload_oracle";
    poisoned.ControlTrials.CSIRS=struct('CQI',99,'Observed',true,'Consumed',true);
    poisoned.UEConfiguredSRProcedures={struct('invalid',true)};
    same=sixgr.truth.buildConfiguredPUCCHReception(poisoned,cfg,1,4,"SR_schema");
    assert(same.Context.Digest==h.Context.Digest && same.Assignment.Digest==h.Assignment.Digest);
    for slot=1:5
        [state,~,blocked]=sixgr.truth.CoupledTruthRuntime.startSlotWithQueuedUL( ...
            state,cfg,'DL',1,1,slot,5,cfg.channel.snr_dB,repmat(struct(),0,1),true);
        assert(isempty(blocked));
        [state,~]=owner.advanceSlot(state,cfg,@receive);
    end
    rows=state.SharedGNBSRReceptionTable;
    assert(height(rows)==1 && rows.Slot==4 && isempty(state.PendingCSITable) && ...
        isempty(sixgr.util.structGet(state,'SharedGNBCSIReportTable',table())) && ...
        numel(owner.PUCCHTransmissions)==double(positive) && isempty(owner.DataTransmissions));
    assert(rows.UETransmissionExecuted==positive && ~rows.SchedulerStateChanged);
    rx=state.SharedGNBUCIReceptions{1}.Receiver;
    assert(rx.IndependentReceiverAssignment && ~rx.PreparedTransmitterConsumed && ~rx.OraclePayloadBitsUsed && ...
        rx.ReceiveTiming.TimingSource=="received_configured_SR_sequence_bounded_search" && ...
        ~rx.ReceiveTiming.OracleTimingUsed && ~rx.ReceiveTiming.ReceiverZeroPaddingUsed);
    writetable(rows,fullfile(folder,'SR_received.csv'));
    writetable(state.ControlTrials.PUCCH,fullfile(folder,'pucch_trials.csv'));
    save(fullfile(folder,'SR_physical_episode.mat'),'cfg','rows','rx','positive');
    assert(rows.PositiveSRDetected==positive, ...
        'test:StandaloneSRDetectionMismatch','Retained actual SR/noise episode did not meet its expected decision: %s.',folder);
    assert(all(state.PUCCHFailureCount==0),'Negative standalone SR is not a missing HARQ/CSI failure.');
    canonical=sixgr.truth.CoupledTruthRuntime.canonicalizePersistedControlReferenceTable( ...
        "PUCCH",state.ControlTrials.PUCCH);
    writetable(canonical,fullfile(folder,'pucch_trials_canonical.csv'));
    assert(height(canonical)==1 && ~canonical.FailureFlag && ...
        canonical.SuccessFlag==positive && canonical.DecodeSuccess==positive && ...
        canonical.ControlObservationAvailable && canonical.FinalizedFlag);
    assert(canonical.StrictOk==positive && canonical.StrictReceiverEvidenceOk==positive);
    assert(canonical.TimingEstimateUsed && ...
        canonical.AppliedTimingCorrectionSamples==rx.ReceiveTiming.AppliedTimingCorrectionSamples);
    if positive
        assert(canonical.Status=="PASS" && canonical.UCIExpectedBitVector=="1" && ...
            canonical.UCIDecodedBitVector=="1" && canonical.UCIBitErrorVector=="0" && ...
            canonical.ExpectedBitCount==1 && canonical.BitsCompared==1 && canonical.BitErrors==0);
    else
        assert(canonical.UCIExpectedBitVector=="not_applicable_for_active_pucch_runtime" && ...
            canonical.UCIBitErrorVector=="not_applicable_for_active_pucch_runtime" && ...
            strlength(state.ControlTrials.PUCCH.UCIExpectedBitVector)==0 && ...
            strlength(state.ControlTrials.PUCCH.UCIBitErrorVector)==0 && isnan(canonical.ExpectedBitCount) && ...
            canonical.BitsCompared==0 && isnan(canonical.BitErrors));
    end
    canonicalEpisodes{1+double(positive)}=canonical;
    component=sixgr.truth.evaluateInPathComponentEvidence(struct(),struct('PUCCH',canonical),"pucch");
    assert(component.StrictOk==positive && component.NoTransmissionSRObservationCount==double(~positive), ...
        'An SR-only monitoring episode must not itself qualify successful PUCCH reception.');
    if ~positive
        assert(isnan(canonical.UCIContentMatch) && canonical.Status=="NA" && ...
            canonical.NAReason=="standalone_SR_no_positive_request_transmitted_or_detected");
    end
    % Declared export-only counterexamples, not synthetic primary PHY rows.
    failed=state.ControlTrials.PUCCH;
    failed.Status(:)="FAIL"; failed.NAReason(:)="";
    failed.PUCCHDecodeOk(:)=~positive;
    failed.PositiveSRDetected(:)=~positive;
    failed.FalseSRDetection(:)=~positive;
    failed.MissedSRDetection(:)=positive;
    if positive, failed.UCIContentMatch(:)=0; end
    failed=sixgr.truth.CoupledTruthRuntime.canonicalizePersistedControlReferenceTable("PUCCH",failed);
    assert(failed.FailureFlag && ~failed.SuccessFlag && failed.DecodeSuccess==~positive, ...
        'False and missed SR detections must remain failures without rewriting the decoder outcome.');
    fprintf('SHARED_STANDALONE_SR_PASS positive=%d CSI_bits=0 actual_TX=%d acquired_timing=1 detector_qualified=0 folder=%s\n', ...
        positive,numel(owner.PUCCHTransmissions),folder);
end
combined=vertcat(canonicalEpisodes{:});
component=sixgr.truth.evaluateInPathComponentEvidence(struct(),struct('PUCCH',combined),"pucch");
assert(component.StrictOk && ~component.AllRowsComponentPass && ...
    component.AllRowsValidRuntimeAttempts && component.SummaryTable.PassingRows==1 && ...
    component.SummaryTable.ObservedRows==2 && component.NoTransmissionSRObservationCount==1);
% Malformed or false-detection monitoring must never receive the no-TX
% exception. Declared reducer counterexamples, not additional RF episodes.
for field=["PUCCHTransmissionPrepared","ReceiverExpectedHARQBitCount", ...
        "ReceiverExpectedCSIPart1BitCount","PositiveSRDetected", ...
        "FalseSRDetection","MissedSRDetection","ReceiverTimingOracleUsed", ...
        "ReceiverZeroPaddingUsed","OraclePayloadBitsUsed"]
    bad=combined; bad.(field)(1)=1;
    check=sixgr.truth.evaluateInPathComponentEvidence(struct(),struct('PUCCH',bad),"pucch");
    assert(~check.StrictOk,'Invalid monitoring must fail the component gate: %s.',field);
end
bad=combined; bad.DetectionMetricValid(1)=false;
assert(~sixgr.truth.evaluateInPathComponentEvidence(struct(),struct('PUCCH',bad),"pucch").StrictOk);
bad=combined; bad.UCIContentMatch=[];
assert(~sixgr.truth.evaluateInPathComponentEvidence(struct(),struct('PUCCH',bad),"pucch").StrictOk);
fprintf('STANDALONE_SR_CANONICAL_AND_COMPONENT_PASS RF_episodes=2 quiet_SR_not_decode_success=1 false_missed_and_oracle_guards=1\n');
ok=true;
end

function state=receive(state,items)
for item=items
    switch item.Kind
        case "PreparePUCCH"
            state=sixgr.truth.CoupledTruthRuntime.prepareSharedPUCCHFeedbackRuntime(state,item);
        case "PUCCHTX"
            state=sixgr.truth.commitSharedPUCCHTransmission(state,item);
        case {"PUCCH","PUCCHReceiveOnly"}
            state=sixgr.truth.CoupledTruthRuntime.completeConfiguredPUCCHSR(state,item);
            original=state.SharedGNBSRReceptionTable;
            rejected=false;
            try, sixgr.truth.CoupledTruthRuntime.completeConfiguredPUCCHSR(state,item);
            catch err
                if ~strcmp(err.identifier,'sixgr:truth:DuplicateConfiguredSRCompletion'), rethrow(err); end
                rejected=true;
            end
            assert(rejected && isequaln(state.SharedGNBSRReceptionTable,original));
        otherwise
            error('test:UnexpectedSREvent','Unexpected %s.',item.Kind);
    end
end
end
