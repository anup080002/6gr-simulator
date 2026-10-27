function out=buildSSBPowerMeasurementReceipt(observation,grid,sync,reception,cfg)
%BUILDSSBPOWERMEASUREMENTRECEIPT Original noisy pre-RF measurement operator.
% This post-measurement receipt never runs an estimator or changes reception.
% It preserves the actual SSS power operands (including the existing zero
% clipping policy), not a new estimate obtained from a reference waveform.
out=struct('SSBPowerMeasurementReceiptAvailable',false, ...
    'SSBPowerMeasurementReceiptStatus',"unavailable_original_preRF_measurement", ...
    'SSBPowerMeasurementReceiptJSON',"",'SSBPowerMeasurementReceiptSHA256',"", ...
    'SSBPhysicalMeasurementReferencePlane',"unavailable_original_measurement_plane");
if nargin==0, return; end
r=struct('ContractVersion',"sixgr.ssb.original_preRF_power_measurement/v2", ...
    'Available',false,'ReferenceUsedByReceiver',false);
try
    id='sixgr:refsig:SSBPowerMeasurementReceipt';
    assert(isa(observation,'sixgr.phy.waveform.WaveformObservationBuffer')&& ...
        isscalar(observation)&&observation.isComplete(),id,'Require original complete pre-RF capture.');
    out.SSBPhysicalMeasurementReferencePlane="received_pre_RX_front_end_columns_RF_reference_unqualified";
    r.PhysicalMeasurementReferencePlane=out.SSBPhysicalMeasurementReferencePlane;
    assert(size(grid,1)==240&&size(grid,2)==4&&size(grid,3)==observation.NumReceiveAntennas&& ...
        all(isfinite(grid(:)))&&sync.SampleRate_Hz==observation.SampleRateHz,id, ...
        'Retain actual received four-symbol SSB grid and receive columns.');
    unit=string(sixgr.util.structGet(cfg,'lls6g.runtimePowerContext.WaveformAmplitudeUnit',""));
    assert(isscalar(unit)&&any(unit==["sqrt_mW","normalized_complex_baseband"]),id, ...
        'No absolute power conversion without the applied waveform unit.');
    normalized=unit=="normalized_complex_baseband";
    assert(normalized==logical(sixgr.util.structGet(reception,'SSPowerReferenceNormalized',false)),id, ...
        'The original measurement and applied unit must agree.');
    nfft=double(sync.Nfft); m=reception.SSBPowerMeasurementSnapshot;
    assert(isstruct(m)&&isscalar(m)&&isfield(m,'DesiredPowerPerReceiveAntenna_W'),id, ...
        'Require original estimator operands, not re-estimation on the reference.');
    raw=double(m.RSRPPowerPerReceiveAntenna_W(:).');
    noise=double(m.NoiseInterferencePowerPerReceiveAntenna_W(:).');
    measured=double(m.DesiredPowerPerReceiveAntenna_W(:).');
    assert(numel(raw)==size(grid,3)&&numel(noise)==numel(raw)&&numel(measured)==numel(raw)&& ...
        all(isfinite([raw noise measured]))&&all([raw noise measured]>=0)&& ...
        isequaln(measured,max(raw-noise,0)),id,'Preserve exact original noise-debiased SSS operands.');
    factor=1;
    if normalized, factor=(nfft*sqrt(1000))^2; end
    r.WaveformAmplitudeUnit=unit;
    r.LinearPowerUnit="W";
    if normalized, r.LinearPowerUnit="relative_to_unit_occupied_RE_Es"; end
    r.OriginalRawPowerPerReceiveColumn=raw*factor;
    r.OriginalDisturbancePerReceiveColumn=noise*factor;
    r.OriginalMeasuredPowerPerReceiveColumn=measured*factor;
    r.OriginalEstimatorClipsNegativePowerAtZero=true;
    r.OriginalEstimator=string(m.NoiseInterferenceEstimator);
    r.OriginalMeasurementSource=string(reception.SSMeasurementSource);
    r.ReceiveColumnIndices0=0:observation.NumReceiveAntennas-1;
    r.NumReceiveColumns=observation.NumReceiveAntennas;
    r.ObservationStartSample=observation.StartSample;
    r.ObservationEndSampleExclusive=observation.EndSampleExclusive;
    r.InputSHA256=observation.sampleHash();
    r.InputHashSerialization="WaveformHash.runtimeArray_class_dimensions_real_imag_double";
    r.SSBGridSHA256=sixgr.phy.waveform.WaveformHash.runtimeArray(grid);
    r.NCellID=double(sync.NCellID);
    r.ObservedSSBOccasionIndex=double(reception.ObservedSSBOccasionIndex);
    r.SSSIndicesOneBased=double(nrSSSIndices);
    r.SSSRECount=numel(r.SSSIndicesOneBased);
    r.ReceiverOperator=struct();
    for name=["SampleRate_Hz","SCS_SSB_kHz","Nfft","DemodulationSlot", ...
            "SSBSymbolColumnsOneBased","SSBDemodulationSampleCount", ...
            "SSBDemodulationStartSampleZeroBased", ...
            "SymbolPhaseCompensationCarrierFrequencyHz","CFOCorrectionApplied", ...
            "CFOCorrectionApplied_Hz","CFOCorrectionSampleOrigin", ...
            "SSBPlacementCorrectionAppliedHz","OriginalDemodulation"]
        r.ReceiverOperator.(name)=sync.(name);
    end
    d=sync.OriginalDemodulation;
    r.FFTSupportAvailable=string(d.EngineUsed)=="canonical_nrOFDMDemodulate" && ...
        string(d.RuntimeMATLABRelease)==string(version('-release')) && d.OFDMWindowingSamples==0 && ...
        observation.SampleRateHz==nfft*double(sync.SCS_SSB_kHz)*1000 && ...
        d.LeftPaddingSamples==0 && sync.SSBDemodulationStartSampleZeroBased>=0;
    r.FFTSupportSource="original_native_unresampled_runtime_proven_CP_fraction_window";
    assert(r.FFTSupportAvailable,id,'Unsupported original resampling, padding or non-native window.');
    nativeCarrier=nrCarrierConfig('NSizeGrid',20,'NStartGrid',0,'NCellID',0, ...
        'SubcarrierSpacing',sync.SCS_SSB_kHz,'CyclicPrefix','normal','NFrame',0,'NSlot',sync.DemodulationSlot);
    [capability,probeAccounting]=sixgr.phy.waveform.nativeOFDMFFTCapability(nativeCarrier,nfft, ...
        observation.SampleRateHz,double(d.CyclicPrefixFraction),numel(d.SymbolLengths), ...
        double(sync.SymbolPhaseCompensationCarrierFrequencyHz));
    assert(isequal(double(capability.SymbolLengths(:)),double(d.SymbolLengths(:))) && ...
        isequal(double(capability.CyclicPrefixLengths(:)),double(d.CyclicPrefixLengths(:))),id, ...
        'Capability geometry must match the original executed SSB operator.');
    r.ReceiverOperator.OriginalDemodulation.NativeFFTCapability=capability;
    r.IsolatedFFTCapabilityProbeAccounting=probeAccounting;
    r.CapabilityProbeAccountingScope="isolated_proof_establishment_not_original_capture_demodulations";
    lengths=double(d.SymbolLengths(:).'); cp=double(d.CyclicPrefixLengths(:).');
    columns=double(sync.SSBSymbolColumnsOneBased(:).');
    assert(isequal(columns,columns(1)+(0:3))&&columns(1)>=1&&columns(end)<=numel(cp)&& ...
        all(lengths==cp+nfft)&&sum(lengths)==sync.SSBDemodulationSampleCount,id, ...
        'Original demodulation lengths and selected four-symbol support disagree.');
    starts=[0 cumsum(lengths(1:end-1))];
    first=double(sync.SSBDemodulationStartSampleZeroBased)+starts(columns)+fix(cp(columns)*d.CyclicPrefixFraction);
    r.SelectedFFTIntervalsCaptureLocal0=[first(:) first(:)+nfft];
    r.SSSFFTIntervalCaptureLocal0=r.SelectedFFTIntervalsCaptureLocal0(3,:);
    assert(all(r.SelectedFFTIntervalsCaptureLocal0(:,2)<=observation.EndSampleExclusive-observation.StartSample), ...
        id,'No fabricated future samples for an incomplete FFT.');
    r.Available=true;
    out.SSBPowerMeasurementReceiptAvailable=true;
    out.SSBPowerMeasurementReceiptStatus="available_original_preRF_operator_and_power_operands";
catch failure
    r.ErrorIdentifier=string(failure.identifier); r.ErrorMessage=string(failure.message);
    out.SSBPowerMeasurementReceiptStatus="unavailable_original_preRF_receipt:"+string(failure.identifier);
end
out.SSBPowerMeasurementReceiptJSON=string(jsonencode(r));
out.SSBPowerMeasurementReceiptSHA256=string(sixgr.util.sha256Hex(char(out.SSBPowerMeasurementReceiptJSON)));
end
