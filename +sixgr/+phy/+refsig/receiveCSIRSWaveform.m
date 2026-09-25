function rx=receiveCSIRSWaveform(carrier,cfg,waveform,physicalWaveform,searchWindow,execution)
% Independently configured CSI-RS reception; no PDSCH assignment or decoder.
% Both inputs are actual, equally bounded receiver captures. Timing comes
% from the installed CSI-RS reference, not the TX waveform/channel delay.
arguments
    carrier (1,1) nrCarrierConfig
    cfg (1,1) struct
    waveform {mustBeNumeric,mustBeFinite,mustBeNonempty}
    physicalWaveform {mustBeNumeric,mustBeFinite,mustBeNonempty}
    searchWindow (1,2) double {mustBeInteger,mustBeNonnegative,mustBeFinite}
    execution (1,1) struct
end
assert(ismatrix(waveform) && isequal(size(waveform),size(physicalWaveform)), ...
    'sixgr:refsig:CSIReceivePlaneDimensions', ...
    'CSI-RS pre/post-front-end captures must have identical sample and antenna extents.');
[indices,symbols]=sixgr.phy.refsig.csirs(carrier,cfg);
assert(~isempty(indices) && ~isempty(symbols), ...
    'sixgr:refsig:CSIReceiveOutsideConfiguredOccasion', ...
    'A CSI-RS receive obligation must use an enabled installed calendar occasion.');
enabled=sixgr.util.structGet(cfg,'phy.rx.cfoCorrectionEnabled',[]);
assert(isscalar(enabled) && (islogical(enabled)||isnumeric(enabled)) && ...
    any(double(enabled)==[0 1]),'sixgr:refsig:CSIReceiverFrequencyPolicyRequired', ...
    'Install explicit phy.rx.cfoCorrectionEnabled before CSI-RS reception.');
[aligned,timing]=sixgr.phy.sync.alignULReferenceObservation( ...
    carrier,waveform,indices,symbols,searchWindow);
ofdm=nrOFDMInfo(carrier);
tracking=struct('CFOEstimateAvailable',false,'EstimatedCFO_Hz',NaN, ...
    'CFOCorrectionApplied',false,'CFOCorrectionApplied_Hz',NaN, ...
    'Source',"receiver_cfo_correction_disabled_by_config", ...
    'Status',"disabled_by_config",'EstimateEvidence',struct());
if enabled
    method=lower(string(sixgr.util.structGet(cfg,'phy.impairments.cfoEstimationMethod',"")));
    assert(isscalar(method) && strlength(method)>0, ...
        'sixgr:refsig:CSIReceiverFrequencyPolicyRequired', ...
        'Enabled CSI-RS frequency correction needs phy.impairments.cfoEstimationMethod.');
    if any(method==["cyclic_prefix","cp"])
        % nrOFDMInfo can describe a subframe. The CP estimator needs the
        % exact captured slot, including its numerology-specific long CP.
        localSlot=mod(double(carrier.NSlot),double(carrier.SlotsPerSubframe));
        positions=localSlot*carrier.SymbolsPerSlot+(1:carrier.SymbolsPerSlot);
        slotInfo=ofdm;
        slotInfo.CyclicPrefixLengths=ofdm.CyclicPrefixLengths(positions);
        [frequency,evidence]=sixgr.phy.rx.estimateCFOFromCyclicPrefix( ...
            aligned,slotInfo,ofdm.SampleRate);
        tracking.Source="cyclic_prefix_cfo_estimator";
    elseif any(method==["dmrs_two_symbol","dmrs","reference_symbol_phase_slope"])
        % The configured reference-phase method uses CSI-RS here, never
        % unknown PDSCH DM-RS. A one-symbol resource cannot supply a slope.
        grid=nrOFDMDemodulate(carrier,aligned);
        [frequency,evidence]=sixgr.phy.rx.estimateCFOFromReferenceSymbols( ...
            grid,indices,symbols,carrier,ofdm.SampleRate);
        tracking.Source="configured_csirs_reference_symbol_phase_slope";
    else
        error('sixgr:refsig:UnsupportedCSIReceiverFrequencyMethod', ...
            'CSI-RS cannot execute phy.impairments.cfoEstimationMethod=%s.',method);
    end
    tracking.EstimateEvidence=evidence;
    tracking.Status=string(evidence.Status);
    tracking.CFOEstimateAvailable=logical(evidence.EstimateAvailable) && isfinite(frequency);
    if tracking.CFOEstimateAvailable
        tracking.EstimatedCFO_Hz=frequency;
        rotation=exp(-1i*2*pi*frequency*(0:size(waveform,1)-1).'/ofdm.SampleRate);
        waveform=waveform.*cast(rotation,'like',waveform);
        physicalWaveform=physicalWaveform.*cast(rotation,'like',physicalWaveform);
        [aligned,timing]=sixgr.phy.sync.alignULReferenceObservation( ...
            carrier,waveform,indices,symbols,searchWindow);
        tracking.CFOCorrectionApplied=true;
        tracking.CFOCorrectionApplied_Hz=frequency;
    end
end
selected=timing.AppliedTimingCorrectionSamples+(1:timing.DemodulatedSampleCount);
physicalAligned=physicalWaveform(selected,:);
[grid,gridInfo]=sixgr.phy.waveform.ofdmDemodulate(carrier,aligned);
[physicalGrid,physicalInfo]=sixgr.phy.waveform.ofdmDemodulate(carrier,physicalAligned);
received=struct('OFDMGrid',grid,'OFDMInfo',gridInfo);
options=struct('PhysicalMeasurementGrid',physicalGrid, ...
    'PhysicalMeasurementOFDMInfo',physicalInfo, ...
    'PhysicalMeasurementGridStatus',"available_exact_pre_front_end_grid", ...
    'PhysicalMeasurementReferencePlane',"receiver_antenna_connector_pre_composite_front_end", ...
    'PhysicalMeasurementSource',"actual_independent_csirs_pre_front_end_capture", ...
    'ReceivedExecutionEvidence',execution);
rx=sixgr.phy.refsig.receiveCSIRSFromGrid(carrier,cfg,received,options);
% Preserve executed noise calibration for audit AFTER receiver estimation.
% These operands must never replace the receiver's measured disturbance.
rx.NoiseExecutionEvidence=struct();
for name=["AppliedAWGNSNR_dB","ReferenceAWGNGridNoiseVariance", ...
        "ReferenceAWGNSampleNoiseVariance","SignalEnergyPerOccupiedRE", ...
        "SampleToGridNoiseVarianceGain","NoiseOperatingMode", ...
        "AppliedAWGNSNRSource","AppliedAWGNSNRValueRole", ...
        "AWGNReferenceEnergySource","SharedNoiseCalibrationSource"]
    if isfield(execution,name)
        rx.NoiseExecutionEvidence.(name)=execution.(name);
    end
end
rx.ReceiveTiming=timing;
rx.ReceiverTrackingCorrection=tracking;
rx.ReceiverReferenceSource="installed_CSI_RS_configuration_and_received_waveform";
rx.PDSCHDecodeAttempted=false;
rx.RxGrid=grid;
end
