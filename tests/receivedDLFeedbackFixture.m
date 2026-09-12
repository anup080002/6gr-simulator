function [out,timing,receivedAssignment]=receivedDLFeedbackFixture(cfg,slot,process,noiseVariance)
% Actual coded PDSCH and clean decoded DCI through an isolated connector.
% The caller's PUCCH can use a shared CDL owner; this source fixture does
% NOT claim its isolated DL samples passed through that owner or access.
cfg.channel.model='AWGN'; cfg.channel.fading.enabled=false; cfg.channel.fading.type='AWGN';
cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,slot);
carrier=sixgr.phy.grid.makeCarrier(cfg); info=nrOFDMInfo(carrier);
cfg=sixgr.truth.bindSharedDataOccasion(cfg,slot,floor((slot-1)/carrier.SlotsPerFrame)+1,info.SampleRate);
frame=floor((slot-1)/carrier.SlotsPerFrame)+1;
grant=sixgr.link.resolveWaveformGrant(cfg,'DL',frame,'Slot',slot, ...
    'SFN',carrier.NFrame,'ControlAbsoluteSlot',slot-1,'HARQProcess',process);
assert(grant.Frame==frame && grant.Slot==slot);
assert(grant.Valid && grant.ExactPHYFeasible);
control=sixgr.link.preparePDCCHTransmission(cfg,'Grant',grant,'RNTI',grant.RNTI,'K',numel(grant.DCI.Bits));
connected=isfield(sixgr.util.structGet(cfg,'phy.pdcch.operatorControl',struct()),'connected_dci');
receivedAssignment=struct();
if connected
    % Installed monitoring owns RNTI, formats and candidate payload sizes.
    % Expected bits and the scheduled TX configuration are scoring only.
    [rx,rxInfo]=sixgr.phy.dl.PDCCH_Rx(control.TransmitSamples,cfg, ...
        'SampleRate_Hz',control.SampleRateHz);
    receivedAssignment=sixgr.phy.pdcch.materializeConnectedDCI(rx,rxInfo,cfg);
    assert(receivedAssignment.ControlAbsoluteSlot==slot-1 && ...
        receivedAssignment.DataAbsoluteSlot==slot-1 && ...
        receivedAssignment.HARQProcess==process);
else
    [rx,~]=sixgr.phy.dl.PDCCH_Rx(control.TransmitSamples,cfg,'Carrier',control.Tx.Carrier, ...
        'PDCCH',control.Tx.PDCCH,'RNTI',grant.RNTI,'K',numel(grant.DCI.Bits), ...
        'SampleRate_Hz',control.SampleRateHz);
end
assert(rx.Ok && rx.CausalGrantDecodeOk && isequal(rx.DCIBits(:),grant.DCI.Bits(:)));
decoded=sixgr.phy.pdcch.decodeDCIPayload(rx.DCIBits,grant.DCI.Format,grant.DCI.ContextData);
grant.ControlDecodeOk=logical(rx.CausalGrantDecodeOk); grant.PDCCHGrantBindingOk=grant.ControlDecodeOk;
grant.PDCCHGrantDCIId=decoded.PayloadHash; grant.PDCCHGrantDCIFormat=decoded.Format;
grant.PDCCHGrantDCIFieldsHash=sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(orderfields(decoded.Fields)),'UTF-8')));
grant.PDCCHGrantFieldsHash=grant.PDCCHGrantDCIFieldsHash;
context=struct('GrantSnapshot',grant,'PHYGrant',grant.PHYGrant,'PrepareOnly',true);
job=sixgr.truth.buildGrantPHYJob(cfg,'DL',cfg.channel.snr_dB,frame,[],context);
job.StartSlotIndex=slot;
result=sixgr.truth.executeGrantPHYJob(job); p=result.Result.PreparedTransmission;
array=sixgr.rf.AntennaArrayFactory.build(cfg,'bs','signal','pdsch','numPorts',size(p.Tx.Waveform,2));
x=p.Tx.Waveform*cast(array.PortToElementMatrix.','like',p.Tx.Waveform);
numRx=grant.PHYGrant.AntennaArchitecture.NumRxAntennas;
delay=7; count=max(p.ReceiveEndSampleExclusive-p.ReceiveStartSample,delay+size(x,1));
signal=complex(zeros(count,numRx,'like',x));
signal(delay+(1:size(x,1)),:)=x*cast(eye(size(x,2),numRx)*10^(-77/20),'like',x);
[y,noiseState]=sixgr.link.addRuntimeComplexNoise(signal,noiseVariance,81,p.StartSample,struct());
power=mean(abs(double(signal(:))).^2);
replay=struct('InjectedNoiseVariance',noiseVariance,'SampleNoiseVariance',noiseVariance, ...
    'Source','unit_connector_attenuation_and_actual_fixed_variance_noise', ...
    'NoiseVarianceSource','fixed_unit_test_sample_noise_variance', ...
    'DesiredSignalPowerBeforeNoise',power,'CompositeSignalPowerBeforeNoise',power, ...
    'AppliedNoiseSNR_dB',10*log10(power/noiseVariance), ...
    'AppliedNoiseSNRSource','actual_attenuated_sample_power_over_fixed_noise_variance', ...
    'SNRReferencePlane','receiver_sample_waveform_pre_composite_front_end');
observation=localBuffer(p.ReceiveStartSample,y,p.SampleRateHz);
job.PrepareOnly=false;
job.ReceivedContext=struct('Prepared',p,'Observation',observation, ...
    'PhysicalMeasurementObservation',observation,'TransmitterObservation',localBuffer(p.StartSample,x,p.SampleRateHz), ...
    'Replay',replay,'ChannelState',struct('Initialized',false,'UseFading',false,'Obj',[], ...
    'ReceiverNoiseState',noiseState));
if connected
    job.ReceivedContext.ReceivedAssignment=receivedAssignment;
    job.ReceivedContext.UEIndex=grant.UEIndex;
end
result=sixgr.truth.executeGrantPHYJob(job); out=result.Result;
assert(result.ReadyForReceiverCommit && height(out.TrialTable)==1);
out.HARQ.ReceivedTimingEvidence=sixgr.truth.receivedDataSymbolTiming( ...
    p,observation,out.ReceiveTiming,observation.EndSampleExclusive);
timing=sixgr.truth.harqFeedbackReceiveTimingFields(out.HARQ,out.HARQ.GrantSnapshot,true);
fprintf('RECEIVED_DL_FEEDBACK_FIXTURE: slot=%d process=%d CRC=%d sample=%d noise=%g\n', ...
    slot,process,out.TrialTable.CRCPass,timing.DataDecodeAvailableAtSample,noiseVariance);
end

function b=localBuffer(first,x,fs)
b=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(x,1),fs,size(x,2));
b.append(sixgr.phy.waveform.WaveformChunk(x,first),fs);
end
