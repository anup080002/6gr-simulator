function score=scoreSharedPBCHReception(recovery,reference,source)
% Score AFTER practical reception, using the same executed desired-link IQ.
% No new fading/RF execution, fitted phase/gain, TX bit oracle or noise replay.
% This is effective-link pilot error, NOT an RF-free propagation-matrix NMSE.
score=struct('NMSE_dB',NaN,'NMSEScoringAvailable',false, ...
    'NMSEReferenceSource',"unavailable_no_independent_executed_reference", ...
    'ChannelNMSEQualificationMode',"post_decode_effective_link_pilot_error", ...
    'ChannelNMSEComparedComplexValues',0,'ChannelNMSEErrorEnergy',NaN, ...
    'ChannelNMSEReferenceEnergy',NaN,'ChannelNMSEPilotResourceCount',0, ...
    'ChannelNMSEReferencePlane',"unavailable", ...
    'ChannelNMSEGainOrPhaseFitted',false,'ChannelNMSEReferenceUsedByReceiver',false, ...
    'ChannelNMSEPilotEvidenceJSON',"");
if nargin==0, return; end
snapshot=sixgr.util.structGet(recovery,'PBCHChannelScoringSnapshot',struct());
if isempty(fieldnames(snapshot))
    score.NMSEReferenceSource="unavailable_no_received_pbch_channel_estimate";
    return;
end
if nargin<3 || isempty(reference), return; end
op=snapshot.ReceiverOperator;
assert(op.SampleRate_Hz==reference.SampleRateHz && op.CFOCorrectionSampleOrigin==0, ...
    'sixgr:truth:PBCHScoringClockMismatch', ...
    'Use the recorded receiver sample clock and capture-local frequency correction.');
first=reference.StartSample+op.SSBDemodulationStartSampleZeroBased;
count=op.SSBDemodulationSampleCount;
% The practical receiver may legitimately acquire a window whose earlier
% prefix is outside this capture. Do not fabricate that reference history.
if first<reference.StartSample
    score.NMSEReferenceSource="unavailable_receiver_fft_prefix_precedes_retained_capture";
    return;
end
[wave,clock]=sixgr.truth.sharedReceiverClockScoringWindow(reference,source, ...
    source.ReceiverClockExecution,first,count);
[wave,frequency]=sixgr.truth.applyExecutedReceiverFrequencyForScoring( ...
    wave,op.SampleRate_Hz,first,source.ReceiverClockExecution);
localSamples=op.SSBDemodulationStartSampleZeroBased+(0:count-1).';
% Match the two actual received-sample rotations, including their phase
% origin; re-estimating CFO/timing on the noiseless reference is forbidden.
wave=wave.*cast(exp(2i*pi*op.SSBPlacementCorrectionAppliedHz/op.SampleRate_Hz*localSamples),'like',wave);
wave=wave.*cast(exp(-2i*pi*op.CFOCorrectionApplied_Hz/op.SampleRate_Hz*localSamples),'like',wave);
carrier=nrCarrierConfig('NSizeGrid',20,'SubcarrierSpacing',op.SCS_SSB_kHz, ...
    'NSlot',op.DemodulationSlot,'NCellID',0);
grid=sixgr.phy.waveform.ofdmDemodulate(carrier,wave,'Nfft',op.Nfft, ...
    'SampleRate',op.SampleRate_Hz,'CarrierFrequency',op.SymbolPhaseCompensationCarrierFrequencyHz);
grid=grid(:,op.SSBSymbolColumnsOneBased,:);
assert(isequal(size(grid),size(snapshot.ChannelEstimateGrid)), ...
    'sixgr:truth:PBCHScoringGridMismatch','Score exactly the acquired four-symbol SSB and every RX branch.');
indices=double(nrPBCHDMRSIndices(snapshot.NCellID));
pilots=nrPBCHDMRS(snapshot.NCellID,snapshot.iBar_SSB);
R=size(grid,3);
desired=reshape(grid,960,R);
pilotReference=desired(indices,:)./pilots;
referenceGrid=complex(nan(size(grid)));
for r=1:R
    referenceGrid(indices+(r-1)*960)=pilotReference(:,r);
end
raw=sixgr.phy.dl.scorePBCHChannelEstimate(snapshot,referenceGrid);
for field=string(fieldnames(score)).'
    if isfield(raw,field), score.(field)=raw.(field); end
end
score.NMSEReferenceSource="same_execution_desired_link_IQ_on_recorded_receiver_FFT_clock";
score.ChannelNMSEReferencePlane= ...
    "effective_PBCH_DMRS_includes_TX_RF_channel_RX_timing_CFO_excludes_noise_other_RX_RF";
estimate=reshape(snapshot.ChannelEstimateGrid,960,R);
evidence=struct('PilotIndicesOneBased',indices,'NumReceiveBranches',R, ...
    'EstimateReal',real(estimate(indices,:)),'EstimateImag',imag(estimate(indices,:)), ...
    'ReferenceReal',real(pilotReference),'ReferenceImag',imag(pilotReference), ...
    'ReceiverOperator',op,'ReceiveStartSample',first,'ReceiveEndSampleExclusive',first+count, ...
    'RecordedRXTimingOffset_samples',clock.RecordedReceiverTimingOffset_samples, ...
    'ExecutedReceiverCFO_Hz',frequency.ExecutedReceiverCFO_Hz, ...
    'ReceiverEstimatorInput',false,'AdditionalChannelExecutions',0,'AdditionalRFExecutions',0, ...
    'ReferenceGainOrPhaseFitted',false,'SourceLinkID',source.LinkID);
score.ChannelNMSEPilotEvidenceJSON=string(jsonencode(evidence));
end
