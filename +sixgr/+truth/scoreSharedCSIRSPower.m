function [result,isolation]=scoreSharedCSIRSPower(item,reception,desired,source,replay,owner)
%SCORESHAREDCSIRSPOWER Optional POST-receiver original-component power audit.
% The original practical pre-RF CFO decision (capture-origin phase), final
% timing crop and native FFT operator are replayed on the retained desired
% contribution, only after ONE original component-isolation proof. Neither
% timing/CFO/channel estimation nor an RF/channel execution is performed.
% A single resource/port is presently supported by the isolation owner.
% This includes original emitted TX distortion; it is not an ideal pilot,
% nonlinear multiport decomposition, standardized accuracy or hardware test.
% Result fields may be projected verbatim; no reference changes reception,
% CSI state, feedback, scheduler state, or the original measured powers.
[result,evidence]=emptyResult();
isolation=sixgr.truth.sharedCSIRSComponentIsolation(); % Empty schema only.
if nargin==0, return; end
assert(nargin==6,'sixgr:truth:CSIRSPowerReferenceArguments', ...
    'Supply the original completed item, returned receiver, desired plane, source, replay and owner.');
try
    evidence.Stage="original_component_isolation";
    isolation=sixgr.truth.sharedCSIRSComponentIsolation(item,reception,desired,source,replay,owner);
    isolationToken=string(jsonencode(isolation));
    evidence.IsolationEvidenceSHA256=sha(isolationToken);
    evidence.IsolationAvailable=isolation.Available;
    evidence.IsolationStatus=string(isolation.Status);
    if ~isolation.Available
        result.CSIRSEmittedPowerComparisonStatus=string(isolation.Status);
        [result,evidence]=finish(result,evidence);
        return;
    end
    id='sixgr:truth:CSIRSPowerReferenceIdentity';
    p=item.Context.Prepared; carrier=p.Carrier;
    token=string(reception.PhysicalMeasurementDemodulationReceiptJSON);
    receipt=jsondecode(token);
    assert(sha(token)==string(isolation.PhysicalDemodulationReceiptSHA256),id, ...
        'Use the same original noisy measurement operator that passed isolation.');
    evidence.Stage="original_measurement_resource_binding";
    obs=reception.CSIRSObservation;
    measuredResources=obs.MeasurementPhysicalResources;
    assert(iscell(measuredResources)&&numel(measuredResources)==1 && ...
        string(obs.MeasurementPhysicalResourcesJSON)== ...
            string(jsonencode(sixgr.util.jsonSafeValue(measuredResources))),id, ...
        'Original measurement values and their retained resource token must agree.');
    ordinal=double(obs.MeasurementSelectedResourceOrdinal);
    assert(isscalar(ordinal)&&isfinite(ordinal)&&ordinal==1,id, ...
        'Do not substitute another resource for the actually selected measurement.');
    measured=measuredResources{ordinal};
    resource=receipt.Resources;
    if iscell(resource), resource=resource{1}; end
    unit=string(receipt.WaveformAmplitudeUnit);
    normalized=unit=="normalized_complex_baseband";
    powerUnit="W_resource_grid"; suffix="_dBm";
    expectedScale=double(receipt.FFTSupport.Nfft)*sqrt(1000);
    if normalized
        powerUnit="relative_to_unit_occupied_RE_Es";
        suffix="_dB_re_UnitOccupiedRE_Es";
        expectedScale=NaN;
    end
    assert(isstruct(measured)&&isscalar(measured) && ...
        measured.ResourceID==resource.ResourceID && resource.ResourceOrdinal0==ordinal-1 && ...
        measured.RSRPReferencePort==3000 && measured.NumReceiveAntennas==desired.NumReceiveAntennas && ...
        string(measured.PowerUnit)==powerUnit && string(measured.SINR.PowerUnit)==powerUnit && ...
        obs.MeasurementPowerReferenceNormalized==normalized && ...
        obs.MeasurementFFTSize==receipt.FFTSupport.Nfft && ...
        isequaln(double(obs.MeasurementGridScaleToSqrtW),expectedScale) && ...
        obs.MeasurementReceiverGainCorrection_dB==0 && ...
        string(obs.MeasurementReceiverGainCorrectionSource)== ...
            "not_required_exact_pre_front_end_measurement_waveform",id, ...
        'Preserve the original resource, receive columns, units and upstream no-gain-correction plane.');
    signed=double(measured.SINR.DesiredPowerPerReceiveAntenna(:).');
    assert(numel(signed)==desired.NumReceiveAntennas&&all(isfinite(signed))&&isreal(signed),id, ...
        'The original resource must retain one finite signed power per receive column.');
    indices=double(p.Tx.CSIRSIndices(:));
    K=12*double(carrier.NSizeGrid); L=double(carrier.SymbolsPerSlot);
    assert(all(indices>=1&indices<=K*L),id,'This original isolated component must contain port 3000 only.');
    base=unique(indices-1,'sorted'); support=[mod(base,K) floor(base/K)];
    assert(sixgr.phy.waveform.WaveformHash.runtimeArray(support)== ...
        string(resource.Port3000SupportSHA256) && size(support,1)==resource.Port3000RECount,id, ...
        'Compare exactly the original port-3000 RE support, not all logical ports or a new allocation.');
    assert(isequal(double(measured.SymbolIndices0Based(:)),unique(support(:,2))) && ...
        measured.NumRB==resource.NumRB && ...
        measured.FirstPRB0Based==double(carrier.NStartGrid)+resource.RBOffset && ...
        measured.SubcarrierSpacing_kHz==double(carrier.SubcarrierSpacing),id, ...
        'The measured resource coordinates must match its original installed resource.');

    evidence.ObservationID=string(item.ID);
    evidence.TransmitterID=string(source.TransmitterID);
    evidence.ReceiverID=string(source.ReceiverID);
    evidence.LinkID=string(source.LinkID);
    evidence.ComponentID=string(isolation.Transmission.ComponentID);
    evidence.ComponentSHA256=string(isolation.Transmission.ComponentSHA256);
    evidence.PhysicalConfigurationEpoch=double(owner.Physical.ConfigurationEpoch);
    evidence.ObservationStartSample=desired.StartSample;
    evidence.ObservationEndSampleExclusive=desired.EndSampleExclusive;
    evidence.SampleRateHz=desired.SampleRateHz;
    evidence.ResourceSetID=double(receipt.ResourceSetID);
    evidence.ResourceID=double(resource.ResourceID);
    evidence.SelectedResourceOrdinal1=ordinal;
    evidence.ReferencePort=3000;
    evidence.Port3000SupportSHA256=string(resource.Port3000SupportSHA256);
    evidence.PhysicalMeasurementDemodulationReceiptSHA256=sha(token);
    evidence.MeasurementPhysicalResourcesSHA256=sha(string(obs.MeasurementPhysicalResourcesJSON));
    evidence.OriginalNoisyInputSHA256=string(receipt.InputSHA256);
    evidence.OriginalNoisyAlignedSHA256=string(receipt.AlignedSHA256);
    evidence.OriginalNoisyGridSHA256=string(receipt.GridSHA256);
    evidence.DesiredOriginalInputSHA256=string(isolation.Measurement.DesiredObservationSHA256);
    evidence.InputHashSerialization="WaveformHash.runtimeArray_class_dimensions_real_imag_double";
    evidence.AlignedAndGridHashSerialization="WaveformHash.numeric_element_count_real_imag_double";
    evidence.ReceiveElementLayoutSHA256=string(isolation.ReceiveElementBinding.Layout.LayoutSHA256);
    evidence.ReceiveElementExecutionReceiptSHA256= ...
        string({isolation.ReceiveElementBinding.IntervalReceipts.ReceiptSHA256});
    evidence.ReferencePlane=string(isolation.ReferencePlane);
    evidence.Scope=string(isolation.Scope);
    evidence.IncludesOriginalTXRFNonlinearity=logical(isolation.IncludesOriginalTXRFNonlinearity);
    evidence.WaveformAmplitudeUnit=unit;
    evidence.OriginalMeasurementSource=string(measured.Source);
    evidence.OriginalRSRPSource=string(measured.RSRPSource);
    evidence.OriginalSINRSource=string(measured.SINR.Source);
    evidence.OriginalMeasurementCarrier=receipt.Carrier;
    evidence.OriginalPreRFFrequency=receipt.Frequency;
    evidence.OriginalPreRFTiming=receipt.Timing;
    evidence.OriginalPreRFFFTSupport=receipt.FFTSupport;

    evidence.Stage="recorded_native_operator_validation";
    f=receipt.FFTSupport; t=receipt.Timing; frequency=receipt.Frequency;
    assert(string(f.RuntimeMATLABRelease)==string(version('-release')) && ...
        string(f.EngineUsed)=="canonical_nrOFDMDemodulate" && ...
        f.Available && f.OFDMWindowingSamples==0 && ...
        f.SampleRateHz==f.Nfft*double(carrier.SubcarrierSpacing)*1000 && ...
        islogical(frequency.CFOCorrectionApplied)&&isscalar(frequency.CFOCorrectionApplied),id, ...
        'Only the already-qualified original native unresampled operator is supported.');
    assert(any(string(receipt.ContractVersion)==["sixgr.csirs.physical_demodulation/v1", ...
        "sixgr.csirs.physical_demodulation/v2"]),id,'Unknown original demodulation contract.');
    probeAccounting=sixgr.phy.waveform.validateRecordedOFDMFFTAuthority(f,carrier,double(f.Nfft),double(f.SampleRateHz), ...
        double(f.CyclicPrefixFraction),L,0,string(receipt.ContractVersion)=="sixgr.csirs.physical_demodulation/v1");
    evidence.IsolatedFFTCapabilityProbeAccounting=probeAccounting;
    native=nrOFDMInfo(carrier,'Nfft',double(f.Nfft),'SampleRate',double(f.SampleRateHz),'Windowing',0);
    positions=mod(double(carrier.NSlot),double(carrier.SlotsPerSubframe))*L+(1:L);
    assert(native.Nfft==f.Nfft&&native.SampleRate==f.SampleRateHz && ...
        isequal(double(native.CyclicPrefixLengths(positions)),double(f.CyclicPrefixLengths(:).')) && ...
        isequal(double(native.SymbolLengths(positions)),double(f.SymbolLengths(:).')),id, ...
        'Native replay must preserve the exact original CP and useful-symbol sample geometry.');
    original=desired.readComplete();
    offset=double(t.AppliedTimingCorrectionSamples); count=double(t.DemodulatedSampleCount);
    assert(strcmp(class(original),string(receipt.InputClass)) && ...
        offset>=0&&offset==fix(offset)&&count>0&&count==fix(count) && ...
        offset+count<=size(original,1) && count==sum(double(f.SymbolLengths)) && ...
        size(original,2)==receipt.NumReceiveChannels,id, ...
        'Preserve original capture class/columns and the measured final crop, without padding.');
    if frequency.CFOCorrectionApplied
        % Exactly the practical pre-RF expression: phase origin is the FULL
        % original capture, including samples before the final timing crop.
        % Use the retained scalar's original class, not JSON's double class.
        appliedFrequency=reception.PhysicalMeasurementTrackingCorrection.CFOCorrectionApplied_Hz;
        assert(isequaln(double(appliedFrequency),double(frequency.CFOCorrectionApplied_Hz)),id, ...
            'The actual retained pre-RF correction scalar must match its original receipt.');
        evidence.AppliedFrequencyScalarClass=string(class(appliedFrequency));
        rotation=exp(-1i*2*pi*appliedFrequency* ...
            (0:size(original,1)-1).'/native.SampleRate);
        original=original.*cast(rotation,'like',original);
    end
    evidence.DesiredAfterRecordedCFO_SHA256=sixgr.phy.waveform.WaveformHash.numeric(original);
    aligned=original(offset+(1:count),:);
    evidence.DesiredAlignedSHA256=sixgr.phy.waveform.WaveformHash.numeric(aligned);
    evidence.Stage="native_reference_demodulation";
    evidence.AdditionalOFDMDemodulationAttempts=1;
    % Use the same native operator directly. The compatibility facade also
    % performs optional cached noise-calibration probes; those are neither
    % needed nor permitted as an extra reference measurement here.
    grid=nrOFDMDemodulate(carrier,aligned,'Nfft',double(f.Nfft), ...
        'SampleRate',double(f.SampleRateHz),'CyclicPrefixFraction',double(f.CyclicPrefixFraction));
    evidence.AdditionalOFDMDemodulations=1;
    evidence.ReferenceDemodulationEngine="nrOFDMDemodulate_recorded_practical_preRF_operator";
    evidence.DesiredGridSHA256=sixgr.phy.waveform.WaveformHash.numeric(grid);
    assert(size(grid,1)==K&&size(grid,2)==L&&size(grid,3)==desired.NumReceiveAntennas,id, ...
        'The reference grid must share the original resource/receive-column dimensions.');
    evidence.Stage="power_arithmetic_and_original_report_binding";
    arithmetic=sixgr.phy.refsig.compareCSIRSPowerReference(grid,support,f.Nfft,signed,unit);
    originalLog=double(measured.("RSRPPerAntenna"+suffix)(:).');
    expectedLog=arithmetic.MeasuredLogPower_dB;
    if ~normalized, expectedLog=expectedLog+30; end
    assert(isequal(size(originalLog),size(expectedLog))&& ...
        isequal(isnan(originalLog),isnan(expectedLog)),id, ...
        'Original signed nonpositive powers must remain logarithmically unavailable.');
    finite=isfinite(expectedLog);
    assert(all(isfinite(originalLog(finite))) && all(abs(originalLog(finite)-expectedLog(finite))<= ...
        32*eps(max(1,abs(expectedLog(finite))))),id, ...
        'The original per-column logarithmic values must derive from its unchanged signed powers.');
    if arithmetic.MeasuredReportingAvailable
        [reported,selected]=max(originalLog,[],'omitnan');
        assert(obs.("MeasurementRSRP"+suffix)==reported && ...
            obs.MeasurementReceiveAntennaIndex1Based==selected && ...
            selected==arithmetic.MeasuredSelectedColumn0+1,id, ...
            'Keep the original selected-column reporting result, not the reference maximum.');
    else
        assert(isnan(obs.("MeasurementRSRP"+suffix))&& ...
            isnan(obs.MeasurementReceiveAntennaIndex1Based),id, ...
            'No nonpositive measured vector may acquire an invented reported power or column.');
    end
    evidence.Comparison=arithmetic;
    % JSON null is not the identity of -Inf. Retain exact tokens for derived
    % nonfinite logarithms as well as the original finite signed/zero linear
    % powers and the arithmetic validity mask; no floor or surrogate value.
    evidence.ComparisonLogTokens=struct();
    for name=["ReferenceLogPower_dB","MeasuredLogPower_dB", ...
            "ReferencePower_dBm","MeasuredPower_dBm"]
        evidence.ComparisonLogTokens.(name)=compose('%.17g',arithmetic.(name));
    end
    evidence.PowerComparisonPerformed=true;
    result.CSIRSEmittedPowerComparisonUnit=string(arithmetic.LinearPowerUnit);
    result.CSIRSEmittedPowerComparisonReferencePlane=string(isolation.ReferencePlane);
    result.CSIRSEmittedPowerComparisonScope=string(isolation.Scope);
    if arithmetic.ReferenceMaximumPower>0
        result.CSIRSEmittedPowerComparisonAvailable=true;
        result.CSIRSEmittedPowerComparisonStatus="available_original_isolated_emitted_component_model_comparison";
        if ~arithmetic.MeasuredReportingAvailable
            result.CSIRSEmittedPowerComparisonStatus="available_linear_comparison_measured_log_power_unavailable";
        end
        result.CSIRSEmittedPowerComparisonReportedError_dB=arithmetic.ReportedError_dB;
        result.CSIRSEmittedPowerComparisonSelectedColumnError_dB=arithmetic.MeasuredSelectedColumnError_dB;
    else
        result.CSIRSEmittedPowerComparisonStatus="unavailable_no_positive_original_reference_power";
    end
    evidence.Stage="completed_optional_power_comparison";
    % A separate post-receiver audit uses the ORIGINAL noisy capture through
    % this same recorded operator. Failure must not discard valid power
    % evidence or alter the practical receiver's result.
    sinr=scoreSINR(item,reception,source,receipt,measured,grid,support,unit,evidence);
    for name=string(fieldnames(sinr)).', result.(name)=sinr.(name); end
catch cause
    % A malformed/missing optional reference cannot invalidate or modify the
    % original practical measurement/report. Retain the exact failed stage
    % and original proof hashes, but publish no partial comparison scalar.
    result=emptyResult();
    result.CSIRSEmittedPowerComparisonStatus="unavailable_original_reference_comparison_failed";
    result.CSIRSEmittedPowerComparisonErrorIdentifier=string(cause.identifier);
    evidence.ErrorIdentifier=string(cause.identifier);
    evidence.ErrorMessage=string(cause.message);
    if evidence.Stage=="original_component_isolation"
        isolation.Status="unavailable_original_CSI_reference_isolation_proof_failed";
        isolation.ErrorIdentifier=string(cause.identifier);
    end
end
[result,evidence]=finish(result,evidence); %#ok<ASGLU>
end

function [result,evidence]=emptyResult()
result=struct('CSIRSEmittedPowerComparisonAvailable',false, ...
    'CSIRSEmittedPowerComparisonStatus',"unavailable_no_original_component_reference", ...
    'CSIRSEmittedPowerComparisonSource',"post_reception_original_emitted_CSI_component_power_comparison", ...
    'CSIRSEmittedPowerComparisonEvidenceJSON',"",'CSIRSEmittedPowerComparisonEvidenceSHA256',"", ...
    'CSIRSEmittedPowerComparisonErrorIdentifier',"",'CSIRSEmittedPowerComparisonUnit',"", ...
    'CSIRSEmittedPowerComparisonReferencePlane',"",'CSIRSEmittedPowerComparisonScope',"", ...
    'CSIRSEmittedPowerComparisonReportedError_dB',NaN, ...
    'CSIRSEmittedPowerComparisonSelectedColumnError_dB',NaN, ...
    'CSIRSEmittedPowerComparisonStandardizedAccuracyQualified',false);
sinr=emptySINR();
for name=string(fieldnames(sinr)).', result.(name)=sinr.(name); end
evidence=struct('ContractVersion',"sixgr.csirs.original_emitted_power_comparison/v1", ...
    'Stage',"not_attempted",'Source',result.CSIRSEmittedPowerComparisonSource, ...
    'PowerComparisonPerformed',false,'ReferenceUsedByReceiver',false, ...
    'AdditionalTimingAcquisitions',0,'AdditionalFrequencyEstimations',0, ...
    'AdditionalChannelEstimations',0,'AdditionalRFExecutions',0,'AdditionalChannelExecutions',0, ...
    'AdditionalOFDMDemodulationAttempts',0,'AdditionalOFDMDemodulations',0, ...
    'IncludesOriginalTXRFNonlinearity',false,'IncludesReceiverRF',false, ...
    'IdealUndistortedPilotReference',false,'MultiportAttributionQualified',false, ...
    'StandardizedReferencePlaneQualified',false,'StandardizedAccuracyQualified',false, ...
    'StatisticallyQualified',false,'HardwareQualified',false,'ErrorIdentifier',"");
end

function [result,evidence]=finish(result,evidence)
evidence.Available=result.CSIRSEmittedPowerComparisonAvailable;
evidence.Status=result.CSIRSEmittedPowerComparisonStatus;
evidence.ErrorIdentifier=result.CSIRSEmittedPowerComparisonErrorIdentifier;
result.CSIRSEmittedPowerComparisonEvidenceJSON=string(jsonencode(evidence));
result.CSIRSEmittedPowerComparisonEvidenceSHA256=sha(result.CSIRSEmittedPowerComparisonEvidenceJSON);
end

function value=sha(token)
value=string(sixgr.util.sha256Hex(char(token)));
end

function result=emptySINR()
result=struct('CSIRSEmittedSINRComparisonAvailable',false, ...
    'CSIRSEmittedSINRComparisonStatus',"unavailable_no_original_component_reference", ...
    'CSIRSEmittedSINRComparisonSource',"post_reception_original_desired_composite_same_operator", ...
    'CSIRSEmittedSINRComparisonEvidenceJSON',"",'CSIRSEmittedSINRComparisonEvidenceSHA256',"", ...
    'CSIRSEmittedSINRComparisonErrorIdentifier',"", ...
    'CSIRSEmittedSINRComparisonReportedError_dB',NaN, ...
    'CSIRSEmittedSINRComparisonSelectedColumnError_dB',NaN, ...
    'CSIRSEmittedSINRComparisonStandardizedAccuracyQualified',false);
end

function result=scoreSINR(item,reception,source,receipt,measured,desiredGrid,support,unit,powerProof)
result=emptySINR();
e=struct('ContractVersion',"sixgr.csirs.original_emitted_sinr_comparison/v1", ...
    'Stage',"original_composite_operator",'ReferenceUsedByReceiver',false, ...
    'AdditionalTimingAcquisitions',0,'AdditionalFrequencyEstimations',0, ...
    'AdditionalChannelEstimations',0,'AdditionalRFExecutions',0,'AdditionalChannelExecutions',0, ...
    'AdditionalOFDMDemodulationAttempts',0,'AdditionalOFDMDemodulations',0, ...
    'SharedDesiredDemodulationCountedInPowerComparison',true, ...
    'StandardizedAccuracyQualified',false,'StatisticallyQualified',false,'HardwareQualified',false);
try
    id='sixgr:truth:CSIRSSINRReferenceIdentity';
    ids=string({item.Planes.ReceiverID}); hit=find(ids==string(source.ReceiverID)+":pre_rf");
    assert(isscalar(hit),id,'Use exactly the original pre-RF composite observation.');
    original=item.Planes(hit).Observation.readComplete();
    assert(sixgr.phy.waveform.WaveformHash.runtimeArray(original)==string(receipt.InputSHA256),id, ...
        'Original composite must match the measurement input, not a new noise realization.');
    f=receipt.FFTSupport; t=receipt.Timing;
    if receipt.Frequency.CFOCorrectionApplied
        hz=reception.PhysicalMeasurementTrackingCorrection.CFOCorrectionApplied_Hz;
        rotation=exp(-1i*2*pi*hz*(0:size(original,1)-1).'/double(f.SampleRateHz));
        original=original.*cast(rotation,'like',original);
    end
    aligned=original(double(t.AppliedTimingCorrectionSamples)+(1:double(t.DemodulatedSampleCount)),:);
    assert(sixgr.phy.waveform.WaveformHash.numeric(aligned)==string(receipt.AlignedSHA256),id, ...
        'The reproduced noisy crop must match the ORIGINAL receiver operator exactly.');
    e.AdditionalOFDMDemodulationAttempts=1;
    receivedGrid=nrOFDMDemodulate(item.Context.Prepared.Carrier,aligned,'Nfft',double(f.Nfft), ...
        'SampleRate',double(f.SampleRateHz),'CyclicPrefixFraction',double(f.CyclicPrefixFraction));
    e.AdditionalOFDMDemodulations=1;
    assert(sixgr.phy.waveform.WaveformHash.numeric(receivedGrid)==string(receipt.GridSHA256),id, ...
        'The reproduced noisy grid must match the ORIGINAL measured grid exactly.');
    e.Stage="original_same_plane_ratio_comparison";
    arithmetic=sixgr.phy.refsig.compareCSIRSSINRReference( ...
        desiredGrid,receivedGrid,support,f.Nfft,measured.SINR,unit);
    e.OriginalPowerProof=powerProof;
    e.OriginalMeasuredRSRPReceiveColumn1=double(reception.CSIRSObservation.MeasurementReceiveAntennaIndex1Based);
    e.OriginalMeasuredSINRReceiveColumn1=double(measured.SINR.ReceiveBranch1Based);
    e.OriginalMeasuredResourceOrdinal1=double(reception.CSIRSObservation.MeasurementSelectedResourceOrdinal);
    e.OriginalMeasuredResourceID=double(measured.ResourceID);
    e.SignalSupportSHA256=sixgr.phy.waveform.WaveformHash.runtimeArray(support);
    e.DisturbanceSupportSHA256=sixgr.phy.waveform.WaveformHash.runtimeArray(arithmetic.DisturbanceSupport0Based);
    e.ReferencePlane=powerProof.ReferencePlane;
    e.IncludesReceiverRF=false;
    e.Comparison=arithmetic;
    result.CSIRSEmittedSINRComparisonAvailable=true;
    result.CSIRSEmittedSINRComparisonStatus="available_original_sample_linear_operand_comparison";
    result.CSIRSEmittedSINRComparisonReportedError_dB=arithmetic.ReportedError_dB;
    result.CSIRSEmittedSINRComparisonSelectedColumnError_dB=arithmetic.MeasuredSelectedColumnError_dB;
    e.Stage="completed_optional_sinr_comparison";
catch cause
    result.CSIRSEmittedSINRComparisonStatus="unavailable_original_sinr_reference_comparison_failed";
    result.CSIRSEmittedSINRComparisonErrorIdentifier=string(cause.identifier);
    e.ErrorIdentifier=string(cause.identifier); e.ErrorMessage=string(cause.message);
end
e.Available=result.CSIRSEmittedSINRComparisonAvailable;
e.Status=result.CSIRSEmittedSINRComparisonStatus;
result.CSIRSEmittedSINRComparisonEvidenceJSON=string(jsonencode(sixgr.util.jsonSafeValue(e)));
result.CSIRSEmittedSINRComparisonEvidenceSHA256=sha(result.CSIRSEmittedSINRComparisonEvidenceJSON);
end
