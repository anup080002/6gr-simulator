classdef SharedSRSRuntime
% Original configured shared SRS preparation, receiver completion and delivery.
% Extracted without changing power, collision, receiver or causal-age policy.
% logSink is the caller logger; it cannot supply receiver or scheduler values.
methods (Static)
function [state,queuedUL,queued]=prepare(state,cfg,ue,snr,queuedUL,logSink)
queued=false; owner=state.SharedWaveformStream;
if owner.hasPending("SRS",ue) || ...
        ~isfield(state,'ConnectedULTimingByUE') || numel(state.ConnectedULTimingByUE)<ue || ...
        isempty(state.ConnectedULTimingByUE{ue})
    return;
end
if isfield(state,'SharedSRSResults') && any(cellfun(@(x)x.UE==ue,state.SharedSRSResults)), return; end
authority=state.ConnectedULTimingByUE{ue};
% This initial TAG has only received common BWPs. A later BWP/NTN timing
% reconfiguration needs its own received authority, not a scenario override.
common=state.UECommonCellConfigurationByUE{ue};
carrier=sixgr.phy.grid.makeCarrier(cfg);
assert(carrier.SubcarrierSpacing==common.InitialULBWP.SubcarrierSpacing_kHz, ...
    'sixgr:truth:ConnectedULTimingBWPChanged','Install received dedicated-BWP timing before changing UL numerology.');
for slot=state.CurrentSlot:state.CanonicalSlotsPerSweepPoint
    [~,allowed]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,slot);
    if ~allowed, continue; end
    plan=sixgr.truth.CoupledTruthRuntime.futureULPlanningView(state,slot);
    if ~sixgr.truth.coupledSRSAttemptDue(plan,cfg,slot,ue), continue; end
    occupied=owner.Pending(string({owner.Pending.Kind})=="SRS");
    count=sum(arrayfun(@(x)x.Context.Slot==slot,occupied));
    if count>=cfg.phy.srs.maxUEsPerSlot, continue; end
    [cfgSRS,~]=sixgr.truth.GrantPreparation.applyCoupledRuntimeUserContext(cfg,plan,ue,"UL");
    [powerAdmitted,powerDecision]=sixgr.truth.resolveSharedSRSPowerAdmission(plan,cfgSRS,ue,slot);
    state.ControlTrials.SRSResourceDecisions=sixgr.truth.PDCCHControlRuntime.appendCompatTable( ...
        sixgr.util.structGet(state.ControlTrials,'SRSResourceDecisions',table()),powerDecision);
    if ~powerAdmitted
        logSink("INFO", ...
            "SRS preparation deferred: ue=%d decision_slot=%d source_slot=%d reference=%s reason=%s; no waveform or power state prepared.", ...
            ue,state.CurrentSlot,slot,powerDecision.PowerReferenceRS,powerDecision.PowerReferenceStatus);
        % Later target slots cannot gain new receiver knowledge in this
        % planning call. Retry after the live owner publishes a fresh RS.
        return;
    end
    cfgSRS.SharedULTimingContext=authority;
    [state,cfgSRS]=sixgr.truth.bindSharedSRSReceivedPowerOwner(state,cfgSRS,ue);
    nominal=sixgr.phy.frame.slotStartSample(carrier,slot-1,owner.SampleRateHz);
    timing=sixgr.phy.ra.sharedULStageTiming(cfgSRS,nominal/owner.SampleRateHz,owner.SampleRateHz,1, ...
        authority.ReceivedRARTiming.NTA_Tc);
    if min(timing.TransmitStartSample,timing.ReceiveStartSample)<owner.Events.NextSampleIndex || ...
            timing.TransmitStartSample<authority.TimingAdvanceEffectiveAtSample
        continue; % The complete TX origin cannot precede available knowledge.
    end
    [collision,decisions]=sixgr.truth.SharedSRSRuntime.resolveResourceCollision(cfgSRS,queuedUL,table(),slot,ue);
    if collision
        [state,queuedUL,decisions,collision]=sixgr.truth.resolveSRSPUSCHRuntimePriority( ...
            state,queuedUL,decisions,cfgSRS,slot,ue);
    end
    state.ControlTrials.SRSResourceDecisions=sixgr.truth.PDCCHControlRuntime.appendCompatTable( ...
        sixgr.util.structGet(state.ControlTrials,'SRSResourceDecisions',table()),decisions);
    if collision, continue; end
    % This parameter is metadata only on the shared physical path. The
    % receiver's thermal-noise owner, not a large-scale SINR prediction,
    % determines the actual noise samples.
    args={'SNR_dB',snr,'TrialIndex',slot+1,'SlotIndex',slot, ...
        'TimingAdvanceSamples',authority.ReceivedRARTiming.Samples};
    output=sixgr.link.runSRSChannelEstimation(cfgSRS,args{:},'PrepareOnly',true);
    assert(isfield(output,'PreparedTransmission'), ...
        'sixgr:truth:SharedSRSPreparationFailed','SRS preparation failed: %s',output.Notes);
    if isfield(cfgSRS.phy.pusch,'priorityIndex')
        pendingPUSCH=owner.Pending( ...
            string({owner.Pending.Kind})=="PUSCH" & ...
            [owner.Pending.UE]==ue);
        for pendingIndex=1:numel(pendingPUSCH)
            sixgr.phy.frame.validatePreparedPriorityZeroPUSCHSRS( ...
                output.PreparedTransmission, ...
                pendingPUSCH(pendingIndex).Context.Prepared);
        end
    end
    context=struct('Config',cfgSRS,'Slot',slot,'Frame',1+floor((slot-1)*state.SlotDuration_s/.01), ...
        'RNTI',sixgr.truth.CoupledRadioIdentity.dataRNTI(cfgSRS,ue,"UL"),'ServingCell',state.CurrentServingIdx(ue), ...
        'SNR',snr,'Arguments',{args},'DecisionSlot',state.CurrentSlot);
    owner.queueUplinkControl(ue,output.PreparedTransmission,context);
    queued=true;
    logSink("INFO","Queued full SRS waveform: ue=%d decision_slot=%d source_slot=%d tx_start=%d rx_start=%d.", ...
        ue,state.CurrentSlot,slot,output.PreparedTransmission.StartSample,output.PreparedTransmission.ReceiveStartSample);
    return;
end
end

function state=complete(state,item,logSink)
c=item.Context; p=c.Prepared;
[post,pre,tx,replay,receiver]=sixgr.truth.sharedObservationEvidence(item.Planes,p);
ch=state.SharedWaveformStream.directionalChannelState(item.UE,"UL");
if isfield(ch,'Obj') && isobject(ch.Obj) && isprop(ch.Obj,'DelayProfile') && replay.ChannelFadingApplied
    replay.ChannelModelApplied=char(ch.Obj.DelayProfile);
end
input=struct('Prepared',p,'Observation',receiver,'PhysicalMeasurementObservation',pre, ...
    'TransmitterObservation',tx,'Replay',replay,'ChannelState',ch);
[desiredReference,referenceEvidence]=sixgr.truth.sharedLinkScoringObservation( ...
    item.Planes,p,c.DesiredReferencePlane);
input.DesiredReferenceObservation=desiredReference;
input.DesiredReferenceEvidence=referenceEvidence;
% This is the actual composite link waveform, not a per-port channel
% matrix. Do not feed it into the legacy branch-averaged pilot-ratio NMSE
% helper and misrepresent that number as full channel-estimator accuracy.
[state,output]=sixgr.truth.receiveSharedSRSMeasurement(state,item,input);
receivedClock=sixgr.truth.retainReceivedSRSTimingReference(p,receiver,output);
if ~isempty(receivedClock)
    state=sixgr.truth.storeReceivedULTimingReference(state,item.UE,receivedClock);
end
[raw,~,observed]=sixgr.truth.SharedSRSRuntime.collectTrials(c.Config,c.SNR,1,ch,c.Slot,output);
trial=sixgr.truth.PDCCHControlRuntime.annotateCoupledControlTrial(raw,c.Slot,c.Frame,item.UE,c.RNTI,"UL",c.ServingCell);
trial=sixgr.truth.bindSharedRFExecutionEvidence(trial,item.Planes,true);
trial.RuntimeTransportMode(:)="shared_physical_stream_SRS_received_completion";
trial.ObservationStartSample=post.StartSample;
trial.ObservationEndSampleExclusive=post.EndSampleExclusive;
trial.ObservationSampleRateHz=post.SampleRateHz;
trial.MeasurementClockEpoch=state.SharedWaveformStream.Physical.ConfigurationEpoch;
trial.ObservationCompletionTime_s=post.EndSampleExclusive/post.SampleRateHz;
trial.ObservationCoverageSource="complete_contiguous_received_sample_buffer";
trial.TransmitStartSample=p.StartSample;
trial.TransmitEndSampleExclusive=p.EndSampleExclusive;
trial.TransmitPreparationDecisionSlot=c.DecisionSlot;
trial=sixgr.truth.bindReceivedSRSTimingEvidence( ...
    trial,output.ReceiveTiming,p.PhysicalTiming);
% Independent same-execution arrival scoring is attached after acquisition;
% it is never an input to the practical SRS timing/rank/TPMI receiver.
trial=sixgr.truth.bindSRSArrivalTimingReference(trial,item.Planes,p.PhysicalTiming);
trial.ReceiverGainCompensationApplied=replay.ReceiverGainCompensation.Applied;
trial.DesiredLinkScoringAvailable=true;
trial.DesiredLinkScoringSource=referenceEvidence.Source;
trial.DesiredLinkScoringScope=referenceEvidence.Scope;
trial.DesiredLinkScoringLinkID=referenceEvidence.LinkID;
trial.DesiredLinkScoringAdditionalChannelExecutions=referenceEvidence.AdditionalChannelExecutions;
trial.DesiredLinkScoringChannelMatrixReference=referenceEvidence.ChannelMatrixReference;
trial.AppliedChannelReferenceSegmentCount=0;
trial.AppliedChannelReferenceSource="same_executed_desired_link_waveform_post_decode_SRS_pilot_reference";
trial.AppliedChannelReferenceUsedByReceiver=false;
trial=sixgr.truth.bindSharedSRSNMSEEvidence(trial,output);
% Keep lossless pairs outside repeated raw-table JSON/checkpoint state.
% These samples are scoring-only and never consumed by SRS rank/TPMI/CQI.
trial=sixgr.report.retainControlEVMPairs( ...
    c.Config.run.rootRunFolder,trial,output.PilotEVMPairs);
trial.ReceivedRARTimingAdvanceCommand=c.Config.SharedULTimingContext.ReceivedRARTiming.Command;
trial.TimingAdvanceEffectiveAtSample=c.Config.SharedULTimingContext.TimingAdvanceEffectiveAtSample;
trial.TimeAlignmentTimerCommon=c.Config.SharedULTimingContext.TimeAlignmentTimerCommon;
trial.RuntimeStateUpdated=false;
trial.ObservationDeliverySlot=NaN;
trial.ObservationDeliveryTime_s=NaN;
trial.ObservationDeliverySource="not_yet_delivered_to_scheduler";
% Publish the already executed uplink coefficients only after the practical
% SRS receiver has completed. Scoring captures are not receiver estimates.
if logical(sixgr.util.structGet(c.Config,'outputs.phySignalDiagnosticEnabled',false)) && ...
        (logical(ch.UseFading) || sixgr.channel.IdentityAWGNRuntime.isState(ch))
    trial=sixgr.truth.exportSharedScoringWaveformObservation( ...
        c.Config.run.rootRunFolder,trial,item.Planes,p,c.DesiredReferencePlane);
end
state.ControlTrials.SRS=sixgr.truth.PDCCHControlRuntime.appendCompatTable(state.ControlTrials.SRS,trial);
state.ObservedREAllocationTable=sixgr.truth.PDCCHControlRuntime.appendObservedREAllocation( ...
    sixgr.util.structGet(state,'ObservedREAllocationTable',table()),observed);
state.LastSRSSlotByUE(item.UE)=c.Slot;
if ~isfield(state,'SharedSRSResults'), state.SharedSRSResults=cell(0,1); end
state.SharedSRSResults{end+1,1}=struct('UE',item.UE,'Row',height(state.ControlTrials.SRS), ...
    'Trial',trial,'ServingCell',c.ServingCell);
sixgr.truth.exportSharedULControlObservation(c.Config.run.rootRunFolder,c.Config,p,item.Planes,output);
logSink("INFO","Received shared SRS: ue=%d slot=%d samples=[%d,%d) status=%s timing=%g NMSE=%g reason=%s.", ...
    item.UE,c.Slot,post.StartSample,post.EndSampleExclusive,trial.Status, ...
    trial.SRSReceiveTimingOffset_samples,trial.NMSE_dB,trial.FailureReason);
end

function state=deliver(state)
if ~isfield(state,'SharedSRSResults') || isempty(state.SharedSRSResults), return; end
now=(state.CurrentSlot-1)*state.SlotDuration_s;
keep=true(numel(state.SharedSRSResults),1);
for k=1:numel(keep)
    item=state.SharedSRSResults{k}; trial=item.Trial;
    if trial.ObservationCompletionTime_s>now, continue; end
    assert(state.CurrentServingIdx(item.UE)==item.ServingCell, ...
        'sixgr:truth:SharedSRSOwnerChanged','Censor old-cell SRS explicitly before consuming it in a new cell.');
    trial.ObservationDeliverySlot=state.CurrentSlot;
    trial.ObservationDeliveryTime_s=now;
    trial.ObservationDeliverySource="canonical_slot_start_after_complete_received_window";
    trial=sixgr.truth.bindDeliveredReferenceClock(state,trial);
    state=sixgr.truth.CoupledTruthRuntime.applySRSTrial(state,item.UE,trial);
    trial.RuntimeStateUpdated=true;
    % Update the measured row once. Final-slot evidence is published even
    % when no subsequent scheduler decision consumes it.
    for name=string(trial.Properties.VariableNames)
        if ~ismember(name,string(state.ControlTrials.SRS.Properties.VariableNames))
            state.ControlTrials.SRS.(name)=sixgr.truth.PDCCHControlRuntime.defaultColumnLike(trial,name,height(state.ControlTrials.SRS));
        end
        state.ControlTrials.SRS(item.Row,name)=trial(:,name);
    end
    keep(k)=false;
end
state.SharedSRSResults=state.SharedSRSResults(keep);
end

function [T, chState, observedRET] = collectTrials(cfg, snr_dB, nTrials, chState, trialOffset, receivedOutput)
if nargin < 6, receivedOutput=[]; end
assert(isempty(receivedOutput) || nTrials==1, ...
    'sixgr:truth:SharedSRSReducerMultiplicity','One actual SRS reception produces one canonical trial row.');
if nargin < 4
    chState = [];
end
if nargin < 5
    trialOffset = 0;
end
nTrials = max(1, round(double(nTrials)));
observedRET = table();
template=sixgr.truth.makeLinkTrialRow(cfg, "UL", snr_dB, 1);
template.SRSConfigurationContextID="";
template.SRSNumPorts=NaN;
template.SRSConfigurationContextVersion=""; template.SRSConfigurationEpoch=NaN;
template.SRSResourceID=NaN; template.SRSResourceIDsJSON="";
rows = repmat(template, nTrials, 1);
for k = 1:nTrials
    r = sixgr.truth.makeLinkTrialRow(cfg, "UL", snr_dB, k);
    r.SRSConfigurationContextID="";
    r.SRSNumPorts=NaN;
    r.SRSConfigurationContextVersion=""; r.SRSConfigurationEpoch=NaN;
    r.SRSResourceID=NaN; r.SRSResourceIDsJSON="";
    r.Status = "FAIL";
    try
        srsArgs = {"SNR_dB", snr_dB, ...
            "TrialIndex", double(trialOffset) + k, "ChannelState", chState};
        if isfinite(double(trialOffset)) && double(trialOffset) > 0
            srsArgs = [srsArgs, {"SlotIndex", double(trialOffset)}]; %#ok<AGROW>
        end
        if isempty(receivedOutput)
            outSRS = sixgr.link.runSRSChannelEstimation(cfg, srsArgs{:});
        else
            outSRS = receivedOutput;
        end
        r.SRSConfigurationContextID=string(sixgr.util.structGet(outSRS,'SRSConfigurationContextID',""));
        r.SRSNumPorts=double(sixgr.util.structGet(outSRS,'SRSNumPorts',NaN));
        for field=["SRSConfigurationContextVersion","SRSConfigurationEpoch","SRSResourceID","SRSResourceIDsJSON"]
            r.(field)=sixgr.util.structGet(outSRS,field,r.(field));
        end
        r.RuntimeEvidenceSource = "sixgr.link.runSRSChannelEstimation";
        pilotEVM=sixgr.phy.srs.measureReceivedPilotEVM();
        for field=string(fieldnames(pilotEVM)).'
            r.(field)=sixgr.util.structGet(outSRS,field,pilotEVM.(field));
        end
        observedRET = sixgr.truth.PDCCHControlRuntime.appendCompatTable(observedRET, ...
            sixgr.util.structGet(outSRS, "ObservedREAllocationTable", table()));
        chState = sixgr.util.structGet(outSRS, "ChannelState", chState);
        ok = logical(sixgr.util.structGet(outSRS, "Ok", false)) && ~logical(sixgr.util.structGet(outSRS, "Skipped", false));
        r.NMSE_dB = double(sixgr.util.structGet(outSRS, "NMSE_dB", NaN));
        r.RawChannelNMSE_dB = double(sixgr.util.structGet( ...
            outSRS, "RawChannelNMSE_dB", NaN));
        r.ChannelNMSEPhaseAligned = logical(sixgr.util.structGet( ...
            outSRS, "ChannelNMSEPhaseAligned", false));
        r.ChannelNMSECommonPhaseRotation_rad = double(sixgr.util.structGet( ...
            outSRS, "ChannelNMSECommonPhaseRotation_rad", NaN));
        r.ChannelNMSEQualificationMode = string(sixgr.util.structGet( ...
            outSRS, "ChannelNMSEQualificationMode", "raw_complex_plane_aligned"));
        r.NMSEReferenceSource = string(sixgr.util.structGet(outSRS, "NMSEReferenceSource", ""));
        r.TrueChannelOracleAvailable = logical(sixgr.util.structGet(outSRS, "TrueChannelOracleAvailable", false));
        r.TrueChannelNMSE_dB = double(sixgr.util.structGet(outSRS, "TrueChannelNMSE_dB", r.NMSE_dB));
        r.ChannelNMSEThreshold_dB = double(sixgr.util.structGet(outSRS, "ChannelNMSEThreshold_dB", NaN));
        r.PilotResidualNMSE_dB = double(sixgr.util.structGet(outSRS, "PilotResidualNMSE_dB", NaN));
        % Detection evidence is the actual received pilot correlation,
        % never the negative of an independent true-channel NMSE score.
        r.DetectionMetric = double(sixgr.util.structGet(outSRS, ...
            "ReceiveTiming.CorrelationPeakEnergy", NaN));
        r.DetectionMetricStatus = "unavailable_received_correlation_peak";
        if isfinite(r.DetectionMetric)
            r.DetectionMetricStatus = "received_reference_correlation_peak_energy";
        end
        r.InjectedDoppler_Hz = double(sixgr.util.structGet(outSRS, "InjectedDoppler_Hz", NaN));
        r.EstimatedDopplerHz = double(sixgr.util.structGet(outSRS, "EstimatedDopplerHz", NaN));
        r.DopplerError_Hz = double(sixgr.util.structGet(outSRS, "DopplerError_Hz", NaN));
        phase=sixgr.link.srsPilotPhaseEvidence(outSRS);
        for field=string(fieldnames(phase)).', r.(field)=phase.(field); end
        r.QCLAccuracy = double(sixgr.util.structGet(outSRS, "QCLAccuracy", NaN));
        r.QCLMeasurementStatus = string(sixgr.util.structGet(outSRS,"QCLMeasurementStatus","unavailable"));
        r.InterpolationLoss_dB = double(sixgr.util.structGet(outSRS, "InterpolationLoss_dB", NaN));
        r.MismatchSensitivity_dB = double(sixgr.util.structGet(outSRS, "MismatchSensitivity_dB", NaN));
        r.ComputeLatency_ms = double(sixgr.util.structGet(outSRS, "ComputeLatency_ms", NaN));
        r.ProcedureDelay_ms = double(sixgr.util.structGet(outSRS, "ProcedureDelay_ms", NaN));
        r.AirInterfaceObservation_ms = double(sixgr.util.structGet(outSRS, "AirInterfaceObservation_ms", NaN));
        r.AcquisitionTime_ms = double(sixgr.util.structGet(outSRS, "AcquisitionTime_ms", NaN));
        r.TrackingFailureProbability = double(sixgr.util.structGet(outSRS, "TrackingFailure", NaN));
        r.NoiseVariance = double(sixgr.util.structGet(outSRS, "NoiseVariance", NaN));
        r.NoiseVarianceDomain = string(sixgr.util.structGet(outSRS,"NoiseVarianceDomain",""));
        r.InjectedSampleNoiseVariance = double(sixgr.util.structGet(outSRS,"InjectedSampleNoiseVariance",NaN));
        r.InjectedSampleNoiseVarianceDomain = string(sixgr.util.structGet(outSRS,"InjectedSampleNoiseVarianceDomain",""));
        r.InjectedSampleNoiseVarianceSource = string(sixgr.util.structGet(outSRS,"InjectedSampleNoiseVarianceSource",""));
        r.NoiseVarStatus = string(sixgr.util.structGet(outSRS, "NoiseVarStatus", ""));
        r.NoiseVarSource = string(sixgr.util.structGet(outSRS, "NoiseVarSource", ""));
        r.NoiseVarReason = string(sixgr.util.structGet(outSRS, "NoiseVarReason", ""));
        r.NoiseVarStrictFailure = logical(sixgr.util.structGet(outSRS, "NoiseVarStrictFailure", false));
        r.NoiseOperatingMode = string(sixgr.util.structGet(outSRS, "NoiseOperatingMode", ""));
        % The flattened result contains publication fields, not the original
        % noise receipt. Validate the retained execution operands directly;
        % never reconstruct a receipt from its serialized summary.
        noiseExecution=sixgr.util.structGet(outSRS,'NoiseExecutionEvidence', ...
            struct('NoiseOperatingMode',r.NoiseOperatingMode));
        assert(isequal(string(sixgr.util.structGet(noiseExecution,'NoiseOperatingMode',"")), ...
            r.NoiseOperatingMode),'sixgr:truth:SRSNoiseExecutionModeMismatch', ...
            'SRS result and original noise execution must retain the same operating mode.');
        absoluteNoise=sixgr.link.absoluteReferenceNoisePublication(noiseExecution);
        for noiseField=string(fieldnames(absoluteNoise)).'
            r.(noiseField)=absoluteNoise.(noiseField);
        end
        r.NoisePowerSource = string(sixgr.util.structGet(outSRS, "NoisePowerSource", ""));
        r.ThermalNoisePower_dBm = double(sixgr.util.structGet(outSRS, "ThermalNoisePower_dBm", NaN));
        r.ServingRxPower_dBm = double(sixgr.util.structGet(outSRS, "ServingRxPower_dBm", NaN));
        r.ServingRxPowerSource = string(sixgr.util.structGet(outSRS, "ServingRxPowerSource", ""));
        r.PowerContextDirection = string(sixgr.util.structGet(outSRS, "PowerContextDirection", ""));
        r.PowerContextTotalTxPower_dBm = double(sixgr.util.structGet(outSRS, "PowerContextTotalTxPower_dBm", NaN));
        powerFields=sixgr.link.srsPowerControlEvidence();
        for field=string(fieldnames(powerFields)).'
            r.(field)=sixgr.util.structGet(outSRS,field,powerFields.(field));
        end
        r.TxRFExecutionStatus = string(sixgr.util.structGet(outSRS, "TxRFExecutionStatus", ""));
        r.TxRFStageOrder = string(sixgr.util.structGet(outSRS, "TxRFStageOrder", ""));
        r.TxRFAppliedStageCount = double(sixgr.util.structGet(outSRS, "TxRFAppliedStageCount", NaN));
        r.CompositeReceiverFrontEndApplied = logical(sixgr.util.structGet(outSRS, "CompositeReceiverFrontEndApplied", false));
        r.CompositeReceiverFrontEndStatus = string(sixgr.util.structGet(outSRS, "CompositeReceiverFrontEndStatus", ""));
        r.ConfiguredSNR_dB = double(sixgr.util.structGet(outSRS, "ConfiguredSNR_dB", snr_dB));
        r.AppliedAWGNSNR_dB = double(sixgr.util.structGet(outSRS, "AppliedAWGNSNR_dB", NaN));
        r.DesiredSignalPowerBeforeNoise = double(sixgr.util.structGet(outSRS, "DesiredSignalPowerBeforeNoise", NaN));
        r.CompositeSignalPowerBeforeNoise = double(sixgr.util.structGet(outSRS, "CompositeSignalPowerBeforeNoise", NaN));
        r.AppliedNoiseSNR_dB = double(sixgr.util.structGet(outSRS, "AppliedNoiseSNR_dB", NaN));
        r.NoiseVarianceSource = string(sixgr.util.structGet(outSRS, "NoiseVarianceSource", ""));
        r.SignalEnergyPerOccupiedRE = double(sixgr.util.structGet( ...
            outSRS,"SignalEnergyPerOccupiedRE",NaN));
        r.ReferenceAWGNGridNoiseVariance = double(sixgr.util.structGet( ...
            outSRS,"ReferenceAWGNGridNoiseVariance",NaN));
        r.ReferenceAWGNSampleNoiseVariance = double(sixgr.util.structGet( ...
            outSRS,"ReferenceAWGNSampleNoiseVariance",NaN));
        r.SampleToGridNoiseVarianceGain = double(sixgr.util.structGet( ...
            outSRS,"SampleToGridNoiseVarianceGain",NaN));
        r.SNRReferencePlane = string(sixgr.util.structGet( ...
            outSRS,"SNRReferencePlane",""));
        r.WaveformPowerUsedForAWGN = logical(sixgr.util.structGet( ...
            outSRS,"WaveformPowerUsedForAWGN",false));
        r.ChannelModelApplied = string(sixgr.util.structGet(outSRS, "ChannelModelApplied", ""));
        r.ChannelFadingApplied = logical(sixgr.util.structGet(outSRS, "ChannelFadingApplied", false));
        r.AppliedLargeScaleGain_dB = double(sixgr.util.structGet(outSRS, "AppliedLargeScaleGain_dB", NaN));
        r.AppliedLargeScaleLoss_dB = double(sixgr.util.structGet(outSRS, "AppliedLargeScaleLoss_dB", NaN));
        r.AppliedBasePathloss_dB = double(sixgr.util.structGet(outSRS, "AppliedBasePathloss_dB", NaN));
        r.AppliedPathloss_dB = double(sixgr.util.structGet(outSRS, "AppliedPathloss_dB", NaN));
        r.AppliedShadowFading_dB = double(sixgr.util.structGet(outSRS, "AppliedShadowFading_dB", NaN));
        r.AppliedO2I_dB = double(sixgr.util.structGet(outSRS, "AppliedO2I_dB", NaN));
        r.AppliedLargeScaleGainSource = string(sixgr.util.structGet(outSRS, "AppliedLargeScaleGainSource", ""));
        r.InjectedCFO_Hz = double(sixgr.util.structGet(outSRS, "InjectedCFO_Hz", NaN));
        r.InjectedTimingOffset_samples = double(sixgr.util.structGet(outSRS, "InjectedTimingOffset_samples", NaN));
        r.DetectionAttempted = logical(sixgr.util.structGet(outSRS, "DetectionAttempted", false));
        r.DetectionSuccess = logical(sixgr.util.structGet(outSRS, "DetectionSuccess", false));
        r.DetectionUsable = logical(sixgr.util.structGet(outSRS, "DetectionUsable", false));
        r.ResourceExtractionAttempted = logical(sixgr.util.structGet(outSRS, "ResourceExtractionAttempted", false));
        r.ResourceExtractionAvailable = logical(sixgr.util.structGet(outSRS, "ResourceExtractionAvailable", false));
        r.ChannelEstimateAttempted = logical(sixgr.util.structGet(outSRS, "ChannelEstimateAttempted", false));
        r.ChannelEstimateAvailable = logical(sixgr.util.structGet(outSRS, "ChannelEstimateAvailable", ...
            sixgr.util.structGet(outSRS, "SRSChannelEstimateAvailable", false)));
        r.SRSChannelEstimateAvailable = logical(sixgr.util.structGet(outSRS, "SRSChannelEstimateAvailable", r.ChannelEstimateAvailable));
        r.ChannelEstimateSource=string(sixgr.util.structGet(outSRS,"ChannelEstimateSource",""));
        for name=string(fieldnames(sixgr.link.receivedWaveformEvidence())).'
            if isfield(outSRS,name), r.(name)=outSRS.(name); end
        end
        r.StrictReceiverEvidenceOk = logical(sixgr.util.structGet(outSRS, "StrictReceiverEvidenceOk", false));
        r.SRSRuntimeEvidenceUsable = logical(sixgr.util.structGet(outSRS, "SRSRuntimeEvidenceUsable", false));
        r.StrictOk = logical(sixgr.util.structGet(outSRS, "StrictOk", false));
        r.ReceiverUsable = logical(r.StrictReceiverEvidenceOk);
        r.DecodeUsable = logical(r.StrictOk);
        r.MeasurementAttempted = logical(sixgr.util.structGet(outSRS, "MeasurementAttempted", false));
        r.MeasurementUsable = logical(sixgr.util.structGet(outSRS, "MeasurementUsable", false));
        r.FailureReason = string(sixgr.util.structGet(outSRS, "FailureReason", ""));
        r = sixgr.truth.bindReferenceSignalSINREvidence(r,outSRS,"SRS");
        r.PUSCHSchedulingSINRAnchor_dB = double(sixgr.util.structGet( ...
            outSRS, "PUSCHSchedulingSINRAnchor_dB", NaN));
        r.PUSCHSchedulingSINRAnchorSource = string(sixgr.util.structGet( ...
            outSRS, "PUSCHSchedulingSINRAnchorSource", ""));
        r.PUSCHSchedulingSINRAnchorPowerReferencePlane = string(sixgr.util.structGet( ...
            outSRS, "PUSCHSchedulingSINRAnchorPowerReferencePlane", ""));
        r.PUSCHSchedulingSINRAnchorValueStatus = string(sixgr.util.structGet( ...
            outSRS, "PUSCHSchedulingSINRAnchorValueStatus", "NOT_AVAILABLE"));
        r.WidebandCQI = double(sixgr.util.structGet(outSRS, "CQI", NaN));
        r.CQISource = string(sixgr.util.structGet(outSRS,"CQISource",""));
        r.CQIValueStatus = string(sixgr.util.structGet(outSRS,"CQIValueStatus",""));
        r.CQISelectionSINR_dB = double(sixgr.util.structGet(outSRS,"CQISelectionSINR_dB",NaN));
        r.CQIAppliedSINRMargin_dB = double(sixgr.util.structGet(outSRS,"CQIAppliedSINRMargin_dB",NaN));
        r.CQIDerivedMCS = double(sixgr.util.structGet(outSRS, "MCSIndex", NaN));
        r.CQIDerivedModulation = string(sixgr.util.structGet(outSRS, "Modulation", ""));
        r.CQIDerivedTargetCodeRate = double(sixgr.util.structGet(outSRS, "TargetCodeRate", NaN));
        r.RankEstimate = double(sixgr.util.structGet(outSRS, "RankEstimate", NaN));
        % Retain the actual estimator's spatial decision and codebook
        % provenance, separately from any later scheduler-accepted rank.
        for name=["EstimatedRI","EstimatedTPMI","TPMICandidateCount","TPMIMutualInformation"]
            r.(name)=double(sixgr.util.structGet(outSRS,name,NaN));
        end
        for name=["RISource","TPMISource"]
            r.(name)=string(sixgr.util.structGet(outSRS,name,""));
        end
        r.PredictedPUSCHPostEqSINRPerLayer_dB = sixgr.truth.PDCCHControlRuntime.formatNumericVector( ...
            sixgr.util.structGet(outSRS, "PredictedPUSCHPostEqSINRPerLayer_dB", []));
        r.PredictedPUSCHMinimumLayerSINR_dB = double(sixgr.util.structGet( ...
            outSRS, "PredictedPUSCHMinimumLayerSINR_dB", NaN));
        r.PredictedPUSCHWidebandMeanSINR_dB = double(sixgr.util.structGet( ...
            outSRS, "PredictedPUSCHWidebandMeanSINR_dB", NaN));
        r.PredictedPUSCHPostEqSINRSource = string(sixgr.util.structGet( ...
            outSRS, "PredictedPUSCHPostEqSINRSource", ""));
        r.PredictedPUSCHPostEqSINRValueRole = string(sixgr.util.structGet( ...
            outSRS, "PredictedPUSCHPostEqSINRValueRole", ""));
        r.PredictedPUSCHPostEqSINRValueStatus = string(sixgr.util.structGet( ...
            outSRS, "PredictedPUSCHPostEqSINRValueStatus", "NOT_AVAILABLE"));
        r.PredictedPUSCHPostEqSINRCalibrationOffset_dB = double(sixgr.util.structGet( ...
            outSRS, "PredictedPUSCHPostEqSINRCalibrationOffset_dB", NaN));
        r.PredictedPUSCHPostEqSINRAnchor_dB = double(sixgr.util.structGet( ...
            outSRS, "PredictedPUSCHPostEqSINRAnchor_dB", NaN));
        r.PredictedPUSCHPostEqSINRAnchorSource = string(sixgr.util.structGet( ...
            outSRS, "PredictedPUSCHPostEqSINRAnchorSource", ""));
        r.PredictedPUSCHPostEqSINRPowerReferencePlane = string(sixgr.util.structGet( ...
            outSRS, "PredictedPUSCHPostEqSINRPowerReferencePlane", ""));
        r.PredictedPUSCHReferenceSignalPower = double(sixgr.util.structGet( ...
            outSRS,"PredictedPUSCHReferenceSignalPower",NaN));
        r.PredictedPUSCHDisturbancePower = double(sixgr.util.structGet( ...
            outSRS,"PredictedPUSCHDisturbancePower",NaN));
        r.PUSCHToSRSReferenceEnergyRatio = double(sixgr.util.structGet( ...
            outSRS,"PUSCHToSRSReferenceEnergyRatio",NaN));
        r.PUSCHToSRSReferenceEnergySource = string(sixgr.util.structGet( ...
            outSRS,"PUSCHToSRSReferenceEnergySource",""));
        r.SRS_RSRP_dBm = double(sixgr.util.structGet(outSRS, ...
            "SRS_RSRP_dBm",NaN));
        r.SRS_RSRP_dB_re_UnitOccupiedRE_Es = double(sixgr.util.structGet( ...
            outSRS,"SRS_RSRP_dB_re_UnitOccupiedRE_Es",NaN));
        % Retain the original post-RF engineering power operands. This is
        % not the separately measured antenna-plane diversity RSRP below.
        r.SRSRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es = sixgr.truth.PDCCHControlRuntime.formatNumericVector( ...
            sixgr.util.structGet(outSRS,"SRSRSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es",[]));
        r.SRSRSRPSource = string(sixgr.util.structGet(outSRS,"SRSRSRPSource",""));
        r.SRSRSRPStatus = string(sixgr.util.structGet(outSRS,"SRSRSRPStatus","not_available"));
        r.SRSRSRPPerReceiveAntenna_dBm = sixgr.truth.PDCCHControlRuntime.formatNumericVector( ...
            sixgr.util.structGet(outSRS,"SRSRSRPPerReceiveAntenna_dBm",[]));
        r.SRSAbsolutePowerStatus = string(sixgr.util.structGet( ...
            outSRS,"SRSAbsolutePowerStatus","not_available"));
        antennaPower=sixgr.phy.srs.measureSRSAntennaPower();
        for name=setdiff(string(fieldnames(antennaPower)),"SRSRSRPPerReceiveAntenna_dBm").'
            r.(name)=sixgr.util.structGet(outSRS,name,antennaPower.(name));
        end
        referenceDefaults=sixgr.link.srsReferenceEvidence();
        for name=string(fieldnames(referenceDefaults)).'
            r.(name)=sixgr.util.structGet(outSRS,name,referenceDefaults.(name));
        end
        powerReference=sixgr.truth.scoreSharedSRSAntennaPower();
        for name=string(fieldnames(powerReference)).'
            r.(name)=sixgr.util.structGet(outSRS,name,powerReference.(name));
        end
        r.SRSInterPortLeakageMatrixJSON = string(sixgr.util.structGet( ...
            outSRS,"SRSInterPortLeakageMatrixJSON",""));
        r.SRSInterPortLeakageWorst_dB = double(sixgr.util.structGet( ...
            outSRS,"SRSInterPortLeakageWorst_dB",NaN));
        r.SRSInterPortLeakageStatus = string(sixgr.util.structGet( ...
            outSRS,"SRSInterPortLeakageStatus","not_available"));
        r.SRSInterPortLeakageSource = string(sixgr.util.structGet( ...
            outSRS,"SRSInterPortLeakageSource",""));
        r.SRSOccupiedPRBCount = double(sixgr.util.structGet(outSRS, "SRSOccupiedPRBCount", NaN));
        r.SRSCarrierPRBCount = double(sixgr.util.structGet(outSRS, "SRSCarrierPRBCount", NaN));
        r.SRSBandwidthFraction = double(sixgr.util.structGet(outSRS, "SRSBandwidthFraction", NaN));
        r.SRSFrequencyPRBStart = double(sixgr.util.structGet(outSRS, "SRSFrequencyPRBStart", NaN));
        r.SRSFrequencyPRBEnd = double(sixgr.util.structGet(outSRS, "SRSFrequencyPRBEnd", NaN));
        r.SRSBandwidthCoverageStatus = string(sixgr.util.structGet(outSRS, "SRSBandwidthCoverageStatus", ""));
        r.SRSCoverageGapRB = double(sixgr.util.structGet(outSRS,'SRSCoverageGapRB',NaN));
        r.SRSCoverageToleranceRB = double(sixgr.util.structGet(outSRS,'SRSCoverageToleranceRB',NaN));
        r.SRSLiteralFullCarrierCoverage = logical(sixgr.util.structGet(outSRS,'SRSLiteralFullCarrierCoverage',false));
        r.SpatialSignatureToken = string(sixgr.util.structGet(outSRS, "SpatialSignatureToken", ""));
        r.SpatialSignatureSHA256 = string(sixgr.util.structGet(outSRS, "SpatialSignatureSHA256", ""));
        r.SpatialSignatureRows = double(sixgr.util.structGet(outSRS, "SpatialSignatureRows", NaN));
        r.SpatialSignatureColumns = double(sixgr.util.structGet(outSRS, "SpatialSignatureColumns", NaN));
        r.SpatialSignatureSource = string(sixgr.util.structGet(outSRS, "SpatialSignatureSource", ""));
        r.SpatialSignatureRawRank = double(sixgr.util.structGet(outSRS, "SpatialSignatureRawRank", NaN));
        r.SpatialSignatureRetainedRank = double(sixgr.util.structGet(outSRS, "SpatialSignatureRetainedRank", NaN));
        r.SpatialSignatureDetectionThreshold = double(sixgr.util.structGet(outSRS, "SpatialSignatureDetectionThreshold", NaN));
        r.SpatialSignatureNoiseVariance = double(sixgr.util.structGet(outSRS, "SpatialSignatureNoiseVariance", NaN));
        r.SpatialSignatureNoiseMargin_dB = double(sixgr.util.structGet(outSRS, "SpatialSignatureNoiseMargin_dB", NaN));
        r.SpatialSignatureSnapshotCount = double(sixgr.util.structGet(outSRS, "SpatialSignatureSnapshotCount", NaN));
        r.SpatialSignatureReductionMode = string(sixgr.util.structGet(outSRS, "SpatialSignatureReductionMode", ""));
        r.RankIndicator = double(sixgr.util.structGet(outSRS, "RIEstimate", outSRS.RankEstimate));
        r.PMI = double(sixgr.util.structGet(outSRS, "TPMIEstimate", NaN));
        r.ConditionNumber_dB = double(sixgr.util.structGet(outSRS, "SRSConditionNumber_dB", r.ConditionNumber_dB));
        r.RuntimeIntegrationMode = "coupled_slot_runtime";
        r.RuntimeTransportMode = "srs_tx_power_rf_runtime_channel_noise_rx_rf_srs_rx";
        r.RuntimeStageWaveformsRequired = true;
        r.RuntimeStageWaveformsUsed = true;
        r.RuntimeSelfLoopWaveformsUsed = false;
        r.RuntimeChannelStateUsed = logical(sixgr.util.structGet(outSRS, "RuntimeChannelStateUsed", false));
        r.RuntimeChannelLinkKeys = string(sixgr.util.structGet(outSRS, "RuntimeChannelLinkKeys", ""));
        r.RuntimeNoiseApplied = logical(sixgr.util.structGet(outSRS, "RuntimeNoiseApplied", false));
        r.RuntimeNoiseVarianceMean = double(sixgr.util.structGet(outSRS, "RuntimeNoiseVarianceMean", NaN));
        r.RuntimeNoiseVarianceDomain = string(sixgr.util.structGet(outSRS, "RuntimeNoiseVarianceDomain", ""));
        r.RuntimeNoiseVarianceSource = string(sixgr.util.structGet(outSRS, "RuntimeNoiseVarianceSource", ""));
        r.RuntimeStageCount = double(sixgr.util.structGet(outSRS, "RuntimeStageCount", 5));
        r.CRCPass = NaN;
        if ok
            r.Status = "PASS";
        elseif logical(sixgr.util.structGet(outSRS, "Skipped", false))
            r.Status = "NA";
        else
            r.Status = "FAIL";
            if strlength(strtrim(string(r.FailureReason))) == 0
                r.FailureReason = "srs_runtime_evidence_incomplete";
            end
        end
        r.Notes = string(sixgr.util.structGet(outSRS, "Notes", ""));
    catch ME
        r.Crash = true;
        r.CRCPass = NaN;
        r.Status = "CRASH";
        r.FailureReason = string(ME.identifier) + ": " + string(ME.message);
        r.Notes = string(ME.message);
    end
    rows(k) = r;
end
T = struct2table(rows);
end

function [collision, T] = resolveResourceCollision( ...
        cfg, pendingULGrants, currentPUCCHGrants, slotIdx, ueIdx)
collision = false;
T = table();
if isstruct(pendingULGrants) && ~isempty(pendingULGrants)
    grantSlots = arrayfun(@sixgr.truth.runtimeULGrantSlot,pendingULGrants(:));
    % SRS and PUSCH are received on the same UL carrier at the gNB.
    % Ownership is global across UEs; UE identity and logical ports do not
    % make overlapping time/frequency REs orthogonal.
    indices = find(abs(grantSlots - double(slotIdx)) < 1e-9);
    for ii = reshape(indices, 1, [])
        decision = sixgr.phy.frame.resolveSRSPUSCHCollision( ...
            cfg, pendingULGrants(ii), slotIdx, ueIdx);
        decision.CollisionPair = "SRS_PUSCH";
        decision.GrantOrdinal = double(ii);
        [decision, decisionT] = sixgr.truth.SharedSRSRuntime.serializeExactCollisionDecision(decision);
        T = sixgr.truth.PDCCHControlRuntime.appendCompatTable(T, decisionT);
        collision = collision || logical(decision.Collision);
    end
end

if istable(currentPUCCHGrants) && ~isempty(currentPUCCHGrants)
    dueMask = abs(double(currentPUCCHGrants.ScheduledAbsoluteSlot) - ...
        double(slotIdx)) < 1e-9;
    pucchRows = currentPUCCHGrants(dueMask, :);
    for ii = 1:height(pucchRows)
        decision = sixgr.phy.frame.resolveSRSPUCCHCollision( ...
            cfg, pucchRows(ii, :), slotIdx, ueIdx);
        assert(decision.Action~="drop_overlapping_srs_symbols_preserve_pucch", ...
            'sixgr:truth:PartialSRSSymbolSuppressionRequired', ...
            ['This executor currently defers a whole SRS resource. It must not ' ...
             'drop nonoverlapping symbols of a partially overlapping SRS resource.']);
        decision.GrantOrdinal = double(ii);
        [decision, decisionT] = sixgr.truth.SharedSRSRuntime.serializeExactCollisionDecision(decision);
        T = sixgr.truth.PDCCHControlRuntime.appendCompatTable(T, decisionT);
        collision = collision || logical(decision.Collision);
    end
end
end

function [decision, T] = serializeExactCollisionDecision(decision)
overlapToken = string(mat2str(double(decision.OverlapCoordinates0Based)));
decision = rmfield(decision, "OverlapCoordinates0Based");
decision.OverlapCoordinates0Based = overlapToken;
T = struct2table(decision, "AsArray", true);
end
end
end
