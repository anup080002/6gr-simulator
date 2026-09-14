function ok = testDataChannelStreamStages(mode,caseIndices)
% Actual coded TDD-configured TX/RX through an attenuator plus sample noise.
% This tests stage ownership/coverage and exact payload retention. The
% analytic pathloss fixture and isolated SRS below do NOT qualify access,
% RF, shared-channel propagation, scheduler integration or link adaptation.
setup6GRSimToolkit('Verbose',false);
if nargin<1, mode="TDD"; end
if nargin<2, caseIndices=1:4; end
validateattributes(caseIndices,{'numeric'},{'vector','integer','>=',1,'<=',4});
assert(any(string(mode)==["TDD","FDD"]));
scenario='lls_causal_access_to_data_wiring_tdd.yaml';
if string(mode)=="FDD", scenario='lls_causal_access_to_data_wiring.yaml'; end
s = sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs', ...
    'scenarios',scenario));
base = sixgr.lls6g.buildInternalConfig(s,tempname);
base.channel.model = 'AWGN';
base.channel.fading.enabled = false;
base.channel.fading.type = 'AWGN';
sixgr.runtime.RuntimeCallLedger.configure(tempname);
cleanup = onCleanup(@()sixgr.runtime.RuntimeCallLedger.reset()); %#ok<NASGU>
directions = ["DL","UL","UL","UL"];
for caseIndex = reshape(caseIndices,1,[])
    direction = directions(caseIndex);
    withUCI = caseIndex>=3;
    cfg = base;
    if direction == "UL"
        cfg.lls6g.userContext.RuntimeServingPathloss_dB = 77;
        cfg.lls6g.userContext.RuntimeServingPathlossSource = 'unit_test_analytic_reference_pathloss';
        cfg.lls6g.userContext.RuntimeServingPathlossReferenceRS = 'unit_test_reference';
        cfg.lls6g.userContext.RuntimeServingPathlossMeasurementId = 'unit_test_analytic_input_not_runtime_measurement';
        if caseIndex>=3
            carrier=sixgr.phy.grid.makeCarrier(cfg); ofdm=nrOFDMInfo(carrier);
            common=struct('Source',"decoded_sib1",'TimingAdvanceOffsetPresent',false,'TimingAdvanceOffset',"");
            cfg.SharedULTimingContext=struct('DLReference',struct( ...
                'Source',"received_SSB_timing_and_decoded_BCH", ...
                'SampleRateHz',ofdm.SampleRate,'DLPhaseOffsetSamples',6,'AvailableAtSample',1000), ...
                'Offset',sixgr.phy.frame.resolveULTimingAdvanceOffset(common,'FR1'), ...
                'ReceivedRARTiming',sixgr.phy.ra.resolveRARTimingAdvance( ...
                3*(caseIndex-3),carrier.SubcarrierSpacing,ofdm.SampleRate), ...
                'TimingAdvanceAvailableAtSample',1000,'TimingAdvanceEffectiveAtSample',2000, ...
                'TimeAlignmentExpirySampleExclusive',round(.02*ofdm.SampleRate));
        end
    end
    % The authored SSB burst occupies the first two slots. This isolated
    % full-band data fixture uses the following DL control/data occasion;
    % it must not bypass the production SSB/DM-RS ownership guard.
    controlSlot0 = 2;
    if direction=="UL"
        % Authored DDD-S-U pattern: SRS in U (slot 4), subsequent control
        % in S (slot 8), K2=1 to U. Feedback precedes the UL grant.
        % Slot 0 + K2 would hit a fixed DL slot and must remain rejected.
        if string(mode)=="TDD"
            localReject(@()sixgr.link.resolveWaveformGrant(cfg,direction,0), ...
                'sixgr:SchedulerBase:TimingDecisionRejected');
        end
        controlSlot0 = 8;
    end
    if direction=="UL"
        [cfg,grant] = localSoundedULGrant(cfg,controlSlot0);
    else
        grant = localDLGrant(cfg,controlSlot0);
    end
    assert(grant.Valid && grant.ExactPHYFeasible && grant.DCI.BitExactPDCCHPayload);
    slot = double(grant.ScheduledAbsoluteSlot)+1;
    frame = floor((slot-1)/(10*double(cfg.phy.carrier.SubcarrierSpacing)/15))+1;
    % Reproduce future UL preparation while the current context still holds
    % the control occasion. Bind the waveform calendar, not future knowledge.
    cfg.lls6g.userContext.RuntimeSlotStartTime_s=controlSlot0*sixgr.time.slotDurationSec(cfg);
    ofdm=nrOFDMInfo(sixgr.phy.grid.makeCarrier(cfg));
    [cfg,occasion]=sixgr.truth.bindSharedDataOccasion(cfg,slot,frame,ofdm.SampleRate);
    assert(cfg.lls6g.userContext.RuntimeSlotStartTime_s==occasion.StartSample/ofdm.SampleRate);
    if direction=="DL"
        reserved=sixgr.phy.frame.ssbPRBSymbolReservation( ...
            cfg,sixgr.phy.grid.makeCarrier(cfg),slot-1);
        assert(isempty(reserved.ReservedCarrierRE0), ...
            'The full-band staged-data fixture must use an actual SSB-free allocation.');
    end
    if direction == "DL"
        runner = @localDLJob;
        txName = "sixgr.phy.dl.PDSCH_Tx"; rxName = "sixgr.phy.dl.PDSCH_Rx";
        grant.ControlDecodeOk = false; grant.PDCCHGrantBindingOk = false;
    else
        runner = @localULJob;
        txName = "sixgr.phy.ul.PUSCH_Tx"; rxName = "sixgr.phy.ul.PUSCH_Rx";
        % Dynamic UL transmission needs an actually decoded control waveform.
        grant = localReceiveControl(cfg,grant);
    end
    args = {'NumFrames',1,'StartSlotIndex',slot,'StartFrameIndex',frame, ...
        'GrantSnapshot',grant,'PHYGrant',grant.PHYGrant};
    if withUCI
        % Known codec-test HARQ bits, not invented feedback from a DL run.
        uci = sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',int8([1;0]));
        args = [args {'ExpectedUCIPayload',uci}]; %#ok<AGROW>
    end
    before = sixgr.runtime.RuntimeCallLedger.snapshot();
    pending = runner(cfg,args{:},'PrepareOnly',true);
    afterTX = sixgr.runtime.RuntimeCallLedger.snapshot();
    assert(~pending.Ok && ~pending.Skipped && isempty(pending.TrialTable) && ...
        pending.ExecutionStage == "transmit_prepared_not_received");
    assert(localCount(afterTX,txName)==localCount(before,txName)+1 && ...
        localCount(afterTX,rxName)==localCount(before,rxName));
    prepared = pending.PreparedTransmission;
    assert(grant.Slot==slot && grant.Frame==frame && ...
        grant.PHYGrant.ChannelStateKey.Slot==slot && ...
        grant.PHYGrant.ChannelStateKey.Frame==frame);
    sixgr.link.bindExecutedHARQClock(grant,prepared.Tx.Carrier,slot);
    badClock=grant; badClock.Frame=frame+1;
    localReject(@()sixgr.link.bindExecutedHARQClock(badClock,prepared.Tx.Carrier,slot), ...
        'sixgr:link:HARQExecutedClockMismatch');
    if direction=="UL"
        calendar=prepared.RequestBinding.Grant;
        if withUCI, calendar.ExpectedUCIPayload=uci; end
        sixgr.truth.validatePreparedPUSCHUCI(calendar,prepared);
        altered=calendar;
        altered.ExpectedUCIPayload=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',int8([0;1;0]));
        localReject(@()sixgr.truth.validatePreparedPUSCHUCI(altered,prepared), ...
            'sixgr:truth:LateSharedPUSCHUCIChange');
        altered=calendar; altered.UCIOnPUSCHFeedbackGrantIds="different-source";
        localReject(@()sixgr.truth.validatePreparedPUSCHUCI(altered,prepared), ...
            'sixgr:truth:LateSharedPUSCHUCIChange');
    end
    assert(~prepared.Tx.PowerContext.PAApplied && ...
        (~prepared.Tx.PowerContext.PAEnabled || prepared.Tx.PowerContext.PAExecutionDeferred) && ...
        ~isfield(prepared.Tx,'TxRFImpairmentReplay'));
    assert(all(isfinite(prepared.Tx.Waveform(:))) && any(abs(prepared.Tx.Waveform(:))>0));
    if direction == "DL"
        receivedGrant = localReceiveControl(cfg,grant);
        args{8} = receivedGrant;
    end
    % The test owner applies a declared 77 dB connector attenuation and
    % independent fixed sample noise. It measures the actual signal power;
    % it does not adapt noise to current signal power or manufacture SNR.
    if direction=="DL", role='bs'; signalName='pdsch'; else, role='ue'; signalName='pusch'; end
    array = sixgr.rf.AntennaArrayFactory.build(cfg,role,'signal',signalName, ...
        'numPorts',size(prepared.Tx.Waveform,2));
    x = prepared.Tx.Waveform * cast(array.PortToElementMatrix.','like',prepared.Tx.Waveform);
    assert(size(x,2)==prepared.NumPhysicalTransmitAntennas);
    assert(abs(norm(x,'fro')-norm(prepared.Tx.Waveform,'fro')) < 1e-10*norm(x,'fro'), ...
        'The configured physical port projection must conserve this waveform power.');
    numRx = grant.PHYGrant.AntennaArchitecture.NumRxAntennas;
    connector = eye(size(x,2),numRx) .* 10^(-77/20);
    delaySamples = 7;
    % Exact integer-delay test channel, including its actual late samples.
    % Idle input after the TX slot lets the channel flush its stored samples.
    arrival=prepared.StartSample+delaySamples-prepared.ReceiveStartSample;
    assert(arrival>=0);
    count=max(prepared.ReceiveEndSampleExclusive-prepared.ReceiveStartSample, ...
        arrival+size(x,1));
    signal=complex(zeros(count,numRx,'like',x));
    signal(arrival+(1:size(x,1)),:)=x*cast(connector,'like',x);
    variance = 1e-13; % mW per complex sample per branch, fixed for both directions.
    [y,noiseState] = sixgr.link.addRuntimeComplexNoise(signal,variance,81,prepared.StartSample,struct());
    signalPower = mean(abs(double(signal(:))).^2);
    replay = struct('InjectedNoiseVariance',variance,'SampleNoiseVariance',variance, ...
        'Source','unit_connector_attenuation_and_actual_fixed_variance_noise', ...
        'NoiseVarianceSource','fixed_unit_test_sample_noise_variance', ...
        'DesiredSignalPowerBeforeNoise',signalPower,'CompositeSignalPowerBeforeNoise',signalPower, ...
        'AppliedNoiseSNR_dB',10*log10(signalPower/variance), ...
        'AppliedNoiseSNRSource','actual_attenuated_sample_power_over_fixed_noise_variance', ...
        'SNRReferencePlane','receiver_sample_waveform_pre_composite_front_end');
    context = struct('Prepared',prepared,'Observation',localBuffer(prepared,y), ...
        'PhysicalMeasurementObservation',localBuffer(prepared,y), ...
        'TransmitterObservation',localBuffer(prepared,x,"transmitter"), ...
        'Replay',replay, ...
        'ChannelState',struct('Initialized',false,'UseFading',false,'Obj',[], ...
        'ReceiverNoiseState',noiseState));
    if caseIndex==4
        % A declared two-bit codec obligation, bound to the actual UL DCI and
        % receive window. This is not a physically derived DL HARQ codebook.
        binding=sixgr.truth.puschUCIObservationBinding(grant,context.Observation);
        receiveData=struct('ObservationID',binding.ObservationID, ...
            'AssignmentDigest',binding.AssignmentDigest,'ConfigurationEpoch',binding.ConfigurationEpoch, ...
            'HARQMappingDigest',"declared_two_bit_codec_obligation_not_actual_dl", ...
            'HARQACKBitCount',2,'ConfiguredGrantUCIBitCount',0, ...
            'CSIReportConfigID',"",'CSIConfigurationEpoch',NaN);
        context.UCIReceiveContext=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(receiveData);
        % Declared metadata checks for the real receiver's pre-demapping
        % strict-noise failure path. No fabricated PHY result is exported.
        unavailable=struct('NoiseVarStrictFailure',true,'DecodeAttempted',false, ...
            'ULSCHDecodeAttempted',false,'ReceiverUsable',false);
        snapshot=unavailable;
        score=sixgr.link.scoreIndependentPUSCHUCI(unavailable,context.UCIReceiveContext,uci);
        assert(~score.HARQACKContentMatch && isequaln(snapshot,unavailable));
        unexplained=rmfield(unavailable,'NoiseVarStrictFailure');
        localReject(@()sixgr.link.scoreIndependentPUSCHUCI(unexplained,context.UCIReceiveContext,uci), ...
            'sixgr:pusch:MissingIndependentUCIEvidence');
        leaked=unavailable; leaked.DecodedHARQACKBits=int8(1);
        localReject(@()sixgr.link.scoreIndependentPUSCHUCI(leaked,context.UCIReceiveContext,uci), ...
            'sixgr:pusch:InvalidIndependentUCIScoringBits');
        bad=context; wrong=receiveData; wrong.ObservationID=wrong.ObservationID+"-different";
        bad.UCIReceiveContext=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(wrong);
        localReject(@()runner(cfg,args{:},'ReceivedContext',bad),'sixgr:pusch:UCIReceiveObservationMismatch');
        bad=context; wrong=receiveData; wrong.AssignmentDigest="different_scheduled_grant";
        bad.UCIReceiveContext=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(wrong);
        localReject(@()runner(cfg,args{:},'ReceivedContext',bad),'sixgr:pusch:UCIReceiveObservationMismatch');
        bad=context; wrong=receiveData; wrong.ConfigurationEpoch=wrong.ConfigurationEpoch+1;
        bad.UCIReceiveContext=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(wrong);
        localReject(@()runner(cfg,args{:},'ReceivedContext',bad),'sixgr:pusch:UCIReceiveObservationMismatch');
    end
    bad = context;
    bad.Observation = sixgr.phy.waveform.WaveformObservationBuffer( ...
        prepared.ReceiveStartSample,prepared.ReceiveStartSample+size(y,1),prepared.SampleRateHz,size(y,2));
    localReject(@()runner(cfg,args{:},'ReceivedContext',bad),'WAVEFORM:IncompleteObservation');
    bad = context;
    bad.Observation = sixgr.phy.waveform.WaveformObservationBuffer( ...
        prepared.ReceiveStartSample+1,prepared.ReceiveStartSample+size(y,1)+1,prepared.SampleRateHz,size(y,2));
    localReject(@()runner(cfg,args{:},'ReceivedContext',bad),'sixgr:link:DataObservationMismatch');
    bad = context;
    bad.PhysicalMeasurementObservation = localBuffer(prepared,[y;y(end,:)]);
    localReject(@()runner(cfg,args{:},'ReceivedContext',bad),'sixgr:link:DataObservationPlaneMismatch');
    bad = context; bad.Replay.ApproximationMode = 'fast_proxy';
    localReject(@()runner(cfg,args{:},'ReceivedContext',bad),'sixgr:link:ProxyDataStreamForbidden');
    bad = context; bad.Replay.FallbackUsedForPathloss = true;
    localReject(@()runner(cfg,args{:},'ReceivedContext',bad),'sixgr:link:ProxyDataStreamForbidden');
    wrongCfg = cfg; wrongCfg.phy.carrier.NCellID = cfg.phy.carrier.NCellID+1;
    localReject(@()runner(wrongCfg,args{:},'ReceivedContext',context), ...
        'sixgr:link:PreparedDataRequestMismatch');
    if withUCI
        badArgs = args;
        badArgs{end} = sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',int8([0;0]));
        localReject(@()runner(cfg,badArgs{:},'ReceivedContext',context), ...
            'sixgr:link:PreparedDataRequestMismatch');
    end
    rng(459,'twister'); rngBefore = rng;
    beforeRX = sixgr.runtime.RuntimeCallLedger.snapshot();
    completed = runner(cfg,args{:},'ReceivedContext',context);
    % Preserve the actual failing stimulus before any result assertion. These
    % are component diagnostics, not replacement primary run measurements.
    diagnosticRoot=tempname(fullfile(pwd,'logs'));
    mkdir(diagnosticRoot);
    save(fullfile(diagnosticRoot,'received_data_stages.mat'), ...
        'mode','caseIndex','cfg','grant','prepared','context','completed', ...
        'signal','x','y','variance','arrival','args','-v7.3');
    fprintf('RECEIVED_DATA_STAGE_EVIDENCE: %s case=%d root=%s\n', ...
        mode,caseIndex,diagnosticRoot);
    if caseIndex==4
        assert(completed.HARQ.UCIReceiveContextDigest==context.UCIReceiveContext.Digest && ...
            string(completed.HARQ.UCIReceiverEvidence.ReceiverContextDigest)==context.UCIReceiveContext.Digest);
        assert(completed.HARQ.UCIReferenceScoringSource== ...
            "post_reception_reference_comparison_not_receiver_authority");
        assert(isequal(completed.HARQ.DecodedHARQACKBits,int8([1;0])) && ...
            completed.HARQ.HARQACKContentMatch);
    end
    afterRX = sixgr.runtime.RuntimeCallLedger.snapshot();
    assert(isequal(rngBefore,rng),'Receive completion must not reset/consume the TX RNG.');
    assert(localCount(afterRX,txName)==localCount(beforeRX,txName) && ...
        localCount(afterRX,rxName)==localCount(beforeRX,rxName)+1);
    if completed.TrialTable.CRCPass~=1
        disp(completed.Notes);
        fields = intersect(["Direction","Slot","CRCPass","TrialStatus","Notes", ...
            "EVM_rms","MeasuredSINR_dB","PostEqSINR_dB","TimingOffset", ...
            "DecodeAvailable","DecodeFailureReason","ULSCHCRCStatus"], ...
            string(completed.TrialTable.Properties.VariableNames),'stable');
        disp(completed.TrialTable(:,fields));
    end
    assert(height(completed.TrialTable)==1 && ...
        completed.TrialTable.CRCPass==1 && ...
        completed.ExecutionStage=="received_shared_stream_completed");
    verifyReceivedConstellationCapture(completed,cfg,1);
    % Scaling only the physical measurement observation must scale reported
    % watts, independently of the digital/AGC-normalized receiver waveform.
    scaled=context; scaled.PhysicalMeasurementObservation=localBuffer(prepared,2*y);
    changed=sixgr.truth.measureReceivedDataCarrierPower(prepared,scaled,completed.ReceiveTiming);
    before=jsondecode(completed.TrialTable.AllocationCarrierPowerMeasurementJSON);
    after=jsondecode(changed.AllocationCarrierPowerMeasurementJSON);
    assert(max(abs(after.RSSIPerAntenna_dBm-before.RSSIPerAntenna_dBm-20*log10(2)))<1e-9);
    assert(~strcmp(after.PhysicalObservationSHA256,before.PhysicalObservationSHA256));
    % Independent absolute calibration: unit constant antenna-plane IQ is
    % exactly 1 mW at DC, inside the configured carrier, for each branch.
    tone=context; tone.PhysicalMeasurementObservation=localBuffer(prepared,complex(ones(size(y))));
    calibrated=sixgr.truth.measureReceivedDataCarrierPower(prepared,tone,completed.ReceiveTiming);
    calibration=jsondecode(calibrated.AllocationCarrierPowerMeasurementJSON);
    assert(max(abs(calibration.RSSIPerAntenna_dBm))<1e-8, ...
        'Unit sqrt(mW) IQ must measure 0 dBm independently of Nfft and antenna count.');
    verifyReceivedDataSymbolTiming(completed,prepared,context.Observation,arrival);
    assert(isequal(completed.HARQ.TransportBlockBits,completed.HARQ.DecodedTransportBlockBits));
    [retainedBits,decodedBits,executedGrant] = sixgr.truth.validateExecutedHARQPayload( ...
        completed.HARQ,completed.TrialTable(end,:),direction);
    assert(isequal(retainedBits,completed.HARQ.TransportBlockBits(:)) && ...
        isequal(decodedBits,completed.HARQ.DecodedTransportBlockBits(:)) && ...
        isequaln(executedGrant,completed.HARQ.GrantSnapshot));
    assert(all(completed.NoiseDomainValidation.Status=="PASS"));
    if direction=="DL"
        if string(mode)=="TDD"
            % Original normalized-RE fixture: about 20 dB sample SNR, not
            % the physical-power FDD fixture's 75 dB. Retain its original
            % noise/power and verify every symbol independently instead of
            % imposing the physically inapplicable high-SNR 2% EVM bound.
            assert(~cfg.phy.rx.cfoCorrectionEnabled && ...
                isnan(completed.TrialTable.EstimatedCFO_Hz) && ...
                string(completed.TrialTable.CFOEstimateAvailability)=="missing");
            verifyStagedDLReference(completed,prepared,y,arrival,variance);
        else
            % High-SNR physical fixture: measured acquisition must not
            % invent CFO because capture precedes the received CP boundary.
            assert(abs(completed.TrialTable.EstimatedCFO_Hz)<5, ...
                'Measured DL CFO must remain near zero in the no-CFO fixture.');
            assert(completed.TrialTable.EVM_rms<0.02, ...
                'High-SNR delayed DL reception must not retain spurious CFO EVM.');
        end
        frozenPrecoder=completed.HARQ.GrantSnapshot.PHYGrant.PrecodingState;
        assert(isequaln(completed.TrialTable.RequestedPrecoderPMI,double(frozenPrecoder.PMI)) && ...
            string(completed.TrialTable.RequestedPrecoderSource)=="frozen_PHYGrant_precoding_state", ...
            "Actual DL transmission requests must come from the frozen grant, not this receiver's new CSI.");
        assert(completed.ReceiveTiming.TimingOffsetSamples==arrival && ...
            completed.ReceiveTiming.AppliedTimingCorrectionSamples==arrival && ...
            ~completed.ReceiveTiming.OracleTimingUsed && ~completed.ReceiveTiming.ReceiverZeroPaddingUsed);
        % The component has no complete channel/RF qualification reference.
        % Preserve that gate instead of promoting a coded loopback to a run pass.
        assert(~completed.Ok && contains(completed.Notes,'dl_pdsch_channel_rf_reference_missing'));
    else
        assert(completed.Ok);
    end
    assert(isequaln(completed.ChannelState,context.ChannelState));
    if direction=="UL"
        assert(string(completed.TrialTable.NoiseVarSource)=="runtime_channel_estimate", ...
            'Received PUSCH must not replace its DM-RS estimate with pre-front-end noise metadata.');
        assert(completed.ReceiveTiming.TimingOffsetSamples==arrival && ...
            completed.ReceiveTiming.AppliedTimingCorrectionSamples==arrival && ...
            ~completed.ReceiveTiming.OracleTimingUsed && ~completed.ReceiveTiming.ReceiverZeroPaddingUsed);
        assert(completed.TrialTable.TXStartSample==prepared.StartSample && ...
            completed.TrialTable.RXStartSample==prepared.ReceiveStartSample && ...
            completed.TrialTable.TXEndSampleExclusive==context.TransmitterObservation.EndSampleExclusive && ...
            completed.TrialTable.RXEndSampleExclusive==context.Observation.EndSampleExclusive && ...
            completed.TrialTable.SharedStreamSampleRateHz==prepared.SampleRateHz);
        if caseIndex>=3
            clockReference=sixgr.phy.sync.ReceivedULTimingReference( ...
                prepared,context.Observation,completed.ReceiveTiming);
            assert(clockReference.SourceSignal=="PUSCH_DMRS" && ...
                clockReference.Identity.RNTI==cfg.phy.pusch.RNTI && ...
                clockReference.ArrivalOffsetFromNominalSamples== ...
                context.Observation.StartSample+arrival-prepared.PhysicalTiming.NominalStartSample);
            badClock=completed.ReceiveTiming; badClock.OracleTimingUsed=true;
            localReject(@()sixgr.phy.sync.ReceivedULTimingReference(prepared,context.Observation,badClock), ...
                'sixgr:phy:sync:MeasuredULTimingRequired');
            assert(prepared.PhysicalTiming.WaveformTimingApplied && ...
                ~prepared.PhysicalTiming.FiniteWaveformCropped && ...
                prepared.StartSample~=prepared.ReceiveStartSample);
            assert(completed.PhysicalTiming.TotalAdvanceTicks== ...
                grant.TimingDecision.DataDecision.TimingAdvanceTicks);
            assert(completed.TrialTable.WaveformTimingApplied && ...
                completed.TrialTable.TimingAdvanceTotal_Tc== ...
                completed.TrialTable.TimingAdvanceNTA_Tc+completed.TrialTable.TimingAdvanceOffset_Tc);
            expired=cfg;
            expired.SharedULTimingContext.TimeAlignmentExpirySampleExclusive=prepared.EndSampleExclusive-1;
            localReject(@()runner(expired,args{:},'PrepareOnly',true), ...
                'sixgr:link:ConnectedULAfterTAExpiry');
            future=cfg;
            future.SharedULTimingContext.TimingAdvanceEffectiveAtSample=prepared.StartSample+1;
            localReject(@()runner(future,args{:},'PrepareOnly',true), ...
                'sixgr:link:ConnectedULBeforeTAApplication');
        end
        assert(isequaln(completed.PUSCHPowerControlState,prepared.PowerControlState));
        assert(logical(completed.TrialTable.PUSCHPowerControlEnabled)== ...
            logical(prepared.PowerControl.Enabled));
        if prepared.PowerControl.Enabled
            assert(isfinite(completed.TrialTable.PUSCHRequestedPower_dBm) && ...
                isfinite(prepared.PowerControl.RequestedPower_dBm) && ...
                abs(completed.TrialTable.PUSCHRequestedPower_dBm - ...
                prepared.PowerControl.RequestedPower_dBm)<1e-12);
        else
            % Disabled power control owns no absolute requested dBm. Preserve
            % unavailability rather than comparing NaN numerically or filling
            % it with a configured budget/normalized waveform measurement.
            assert(string(prepared.PowerControl.Status)=="disabled" && ...
                string(completed.TrialTable.PUSCHPowerControlStatus)=="disabled" && ...
                isnan(prepared.PowerControl.RequestedPower_dBm) && ...
                isnan(completed.TrialTable.PUSCHRequestedPower_dBm));
        end
        if withUCI
            assert(completed.HARQ.HARQACKContentMatch && ...
                isequal(completed.HARQ.DecodedHARQACKBits,int8(uci.HARQACK(:))), ...
                'PUSCH must recover the exact retained HARQ-ACK payload alongside the transport block.');
        end
        wrongTiming = prepared.RequestBinding;
        wrongTiming.Grant.TimingDecision.DataDecision.TimingAdvanceTicks = ...
            wrongTiming.Grant.TimingDecision.DataDecision.TimingAdvanceTicks+int64(1024);
        errorId='sixgr:link:SharedULTimingAdvanceNotIntegrated';
        if caseIndex>=3, errorId='sixgr:link:DataTimingAuthorityMismatch'; end
        localReject(@()sixgr.link.PreparedDataTransmission('UL',cfg,wrongTiming, ...
            prepared.Tx,prepared.TxInfo,prepared.ReceiverConfig,prepared.SampleRateHz,0, ...
            prepared.PowerControl,prepared.PowerControlState), ...
            errorId);
        fprintf('[PASS] %s PUSCH fixture %d: actual timing=%g, TB CRC=1, UCI=%d.\n', ...
            mode,caseIndex,arrival,withUCI);
    end
end
ok = true;
disp('PASS testDataChannelStreamStages: retained coded DL/UL samples, exact coverage and one TX/one RX.');
end

function grant = localReceiveControl(cfg,grant)
controlCfg = sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,double(grant.ControlAbsoluteSlot)+1);
p = sixgr.link.preparePDCCHTransmission(controlCfg,'Grant',grant, ...
    'RNTI',grant.RNTI,'K',numel(grant.DCI.Bits));
[rx,~] = sixgr.phy.dl.PDCCH_Rx(p.TransmitSamples,controlCfg, ...
    'Carrier',p.Tx.Carrier,'PDCCH',p.Tx.PDCCH,'RNTI',grant.RNTI, ...
    'K',numel(grant.DCI.Bits),'ExpectedDCIBits',grant.DCI.Bits, ...
    'SampleRate_Hz',p.SampleRateHz);
decoded = sixgr.phy.pdcch.decodeDCIPayload(rx.DCIBits,grant.DCI.Format,grant.DCI.ContextData);
authored = sixgr.phy.pdcch.decodeDCIPayload(grant.DCI.Bits,grant.DCI.Format,grant.DCI.ContextData);
assert(rx.Ok && rx.CausalGrantDecodeOk && isequal(rx.DCIBits(:),grant.DCI.Bits(:)) && ...
    isequaln(decoded.Fields,authored.Fields));
grant.ControlDecodeOk = logical(rx.CausalGrantDecodeOk);
grant.PDCCHGrantBindingOk = logical(rx.CausalGrantDecodeOk);
grant.PDCCHGrantDCIId = decoded.PayloadHash;
grant.PDCCHGrantDCIFormat = decoded.Format;
grant.PDCCHGrantDCIFieldsHash = sixgr.util.sha256Hex(uint8(unicode2native( ...
    jsonencode(orderfields(decoded.Fields)),'UTF-8')));
grant.PDCCHGrantFieldsHash = sixgr.util.sha256Hex(uint8(unicode2native( ...
    jsonencode(orderfields(authored.Fields)),'UTF-8')));
% These additional gates are required BEFORE preparing dynamic UL samples.
if string(grant.Direction)=="UL"
    grant.PDCCHGrantBindingRequired = true;
    grant.DCICrcPass = logical(rx.Ok);
    grant.PDCCHPayloadMatch = isequal(rx.DCIBits(:),grant.DCI.Bits(:));
    grant.DecodedDCIFields = decoded.Fields;
end
end

function [cfg,grant] = localSoundedULGrant(cfg,controlSlot0)
% Execute actual SRS samples/estimation; never relax the strict SRS gate.
strictSRS=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
period=double(strictSRS.ToolboxSRS.SRSPeriod);
assert(isnumeric(period) && numel(period)==2,'This fixture requires authored periodic SRS.');
srsSlot0=floor((controlSlot0-1-period(2))/period(1))*period(1)+period(2);
assert(srsSlot0>=0 && srsSlot0<controlSlot0);
srsSlot=srsSlot0+1;
srsCfg = sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,srsSlot);
[tx,info] = sixgr.phy.ul.SRS_Tx(srsCfg);
assert(~isempty(tx.SRSIndices) && any(abs(tx.Waveform(:))>0));
nRx = cfg.antenna.bs.numElements;
array = sixgr.rf.AntennaArrayFactory.build(srsCfg,'ue','signal','srs', ...
    'numPorts',size(tx.Waveform,2));
physical = tx.Waveform * cast(array.PortToElementMatrix.','like',tx.Waveform);
clean = physical * cast(eye(size(physical,2),nRx),'like',physical);
[y,~] = sixgr.link.addRuntimeComplexNoise(clean,1e-9,41,0,struct());
[rx,~] = sixgr.phy.ul.SRS_Rx(y,srsCfg,'Carrier',tx.Carrier,'SRS',tx.SRS, ...
    'NoiseVar',1e-9,'NoiseVarDomain','time');
choice = sixgr.phy.ul.estimateSRSRITPMI(rx.Hest,rx.NoiseVar,srsCfg);
assert(choice.Valid && isfinite(choice.TPMI) && choice.RI==cfg.phy.pusch.nLayers);
measurementId = sixgr.phy.waveform.WaveformHash.numeric(rx.RxGrid);
cfg.phy.pusch.TPMI = choice.TPMI;
cfg.phy.pusch.srsDecision = struct('Authoritative',choice.Valid, ...
    'MeasurementID',measurementId,'MeasurementSlot',srsSlot,'RI',choice.RI, ...
    'TPMI',choice.TPMI,'NumPorts',choice.PUSCHCodebookNumPorts);
p = cfg.phy.pusch;
grant = struct('Direction','UL','ControlAbsoluteSlot',controlSlot0, ...
    'RNTI',p.RNTI,'UEIndex',1,'BaseStationID',1,'ServingCell',1, ...
    'PRBSet',p.prbSet,'SymbolAllocation',p.symbolAllocation, ...
    'Modulation',p.modulation,'TargetCodeRate',p.codeRate, ...
    'MCSIndex',p.mcsIndex,'MCS',p.mcsIndex,'RV',0, ...
    'Layers',choice.RI,'NumLayers',choice.RI,'RI',choice.RI, ...
    'NumLogicalPorts',choice.PUSCHCodebookNumPorts,'TPMI',choice.TPMI, ...
    'SRSCausalUsable',choice.Valid,'SRSValid',choice.Valid, ...
    'SRSCausalMeasurementId',measurementId,'LastSuccessfulSRSSlot',srsSlot, ...
    'HARQ',struct('HarqID',0,'NDI',true,'RV',0,'IsRetransmission',false));
if isfield(cfg,'SharedULTimingContext')
    grant.TimingAdvanceTicks=cfg.SharedULTimingContext.ReceivedRARTiming.NTA_Tc+ ...
        cfg.SharedULTimingContext.Offset.NTAOffset_Tc;
end
grant = localFreezeFixtureGrant(cfg,grant);
assert(info.OFDMInfo.SampleRate>0 && double(grant.ControlAbsoluteSlot)>srsSlot0);
end

function grant=localDLGrant(cfg,controlSlot0)
p=cfg.phy.pdsch;
layers=double(sixgr.util.structGet(cfg,'phy.pdsch.numLayers',1));
grant=struct('Direction','DL','ControlAbsoluteSlot',controlSlot0, ...
    'RNTI',p.RNTI,'UEIndex',1,'BaseStationID',1,'ServingCell',1, ...
    'PRBSet',p.prbSet,'SymbolAllocation',p.symbolAllocation, ...
    'Modulation',p.modulation,'TargetCodeRate',p.codeRate, ...
    'MCSIndex',p.mcsIndex,'MCS',p.mcsIndex,'RV',0, ...
    'Layers',layers,'NumLayers',layers, ...
    'PortCount',double(sixgr.util.structGet(cfg,'phy.pdsch.numPorts',layers)), ...
    'HARQ',struct('HarqID',0,'NDI',true,'RV',0,'IsRetransmission',false));
[grant.DMRSPortSet,grant.DMRSPortSetSource]= ...
    sixgr.phy.grant.resolveScheduledDMRSPortSet(cfg,'DL',layers,grant);
grant=localFreezeFixtureGrant(cfg,grant);
end

function grant=localFreezeFixtureGrant(cfg,grant)
% Resolve the control/data relationship before freezing immutable PHY fields.
carrier=sixgr.phy.grid.makeCarrier(cfg);
scheduler=sixgr.l2.mac.SchedulerPF(cfg,'Direction',grant.Direction);
grant=scheduler.attachCanonicalTimingDecision(grant);
dataSlot0=double(grant.TimingDecision.DataAbsoluteSlot);
grant.Slot=dataSlot0+1;
grant.Frame=floor(dataSlot0/double(carrier.SlotsPerFrame))+1;
grant.SFN=mod(grant.Frame-1,1024);
assert(grant.ScheduledAbsoluteSlot==dataSlot0);
grant=scheduler.finalizeExactPHYFeasibility(grant);
grant.DCI=scheduler.buildDCIBitfield(grant);
grant.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,grant.Direction,grant, ...
    'Frame',grant.Frame,'Slot',grant.Slot,'HARQContext',grant.HARQ);
grant.PHYGrantContextId=grant.PHYGrant.GrantContextId;
end

function buffer = localBuffer(prepared,x,plane)
if nargin<3, plane="receiver"; end
first=prepared.ReceiveStartSample;
if string(plane)=="transmitter", first=prepared.StartSample; end
buffer = sixgr.phy.waveform.WaveformObservationBuffer(first, ...
    first+size(x,1),prepared.SampleRateHz,size(x,2));
split = floor(size(x,1)/2);
buffer.append(sixgr.phy.waveform.WaveformChunk(x(1:split,:),first),prepared.SampleRateHz);
buffer.append(sixgr.phy.waveform.WaveformChunk(x(split+1:end,:),first+split),prepared.SampleRateHz);
end

function n = localCount(t,name)
n = sum(string(t.FunctionName)==name);
end

function out=localDLJob(cfg,varargin)
out=localJob(cfg,'DL',varargin{:});
end

function out=localULJob(cfg,varargin)
out=localJob(cfg,'UL',varargin{:});
end

function out=localJob(cfg,direction,varargin)
context=struct(varargin{:});
job=sixgr.truth.buildGrantPHYJob(cfg,direction,cfg.channel.snr_dB, ...
    context.StartFrameIndex,[],context);
assert(job.StartSlotIndex==context.StartSlotIndex && ...
    job.GrantSnapshot.Slot==context.StartSlotIndex && ...
    job.GrantSnapshot.Frame==context.StartFrameIndex, ...
    'The fixture must freeze canonical clocks before job construction.');
result=sixgr.truth.executeGrantPHYJob(job);
out=result.Result;
if strlength(job.GrantContextId)>0
    assert(string(job.GrantSnapshot.GrantContextId)==job.GrantContextId);
    if isfield(out,'HARQ') && isfield(out.HARQ,'GrantSnapshot')
        assert(string(out.HARQ.GrantSnapshot.GrantContextId)==job.GrantContextId);
    end
end
if job.PrepareOnly
    assert(~job.WorkerSafe && ~result.ReadyForReceiverCommit && ...
        isempty(result.LinkAdaptationState) && isequaln(result.ChannelState,job.ChannelState));
elseif ~isempty(fieldnames(job.ReceivedContext))
    assert(~job.WorkerSafe && result.ReadyForReceiverCommit);
end
end

function localReject(call,identifier)
try, call(); catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s, got %s: %s',identifier,cause.identifier,cause.message);
    return;
end
error('TEST:MissingRejection','Expected %s.',identifier);
end
