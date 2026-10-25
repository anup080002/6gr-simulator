function [metrics,paired]=scoreSharedPDCCHChannel(prepared,rx,info,reference,source,replay)
% Post-decode NMSE against the SAME executed desired-link pilot waveform.
% This is an effective DM-RS port reference, not a pure propagation matrix.
% Neither the desired samples nor the TX pilot identity enters PDCCH_Rx.
metrics=struct('NMSE_dB',NaN,'NMSEScoringAvailable',false, ...
    'ChannelNMSEQualificationMode',"no_matching_transmitted_DMRS_for_received_hypothesis", ...
    'ChannelNMSEComparedComplexValues',0,'ChannelNMSEPilotResourceCount',0, ...
    'ChannelNMSEErrorEnergy',NaN,'ChannelNMSEReferenceEnergy',NaN, ...
    'ChannelNMSEReferencePlane',"same_execution_effective_DMRS_port_on_RX_timing_clock_with_RX_CFO_before_other_RX_RF", ...
    'NMSEReferenceSource',"actual_executed_serving_link_DMRS_waveform_after_decode", ...
    'ChannelNMSEReferenceIncludesRFImpairments',true, ...
    'ChannelNMSEGainOrPhaseFitted',false,'ChannelNMSEReferenceUsedByReceiver',false);
paired=table();
assert(prepared.ExecutionStage=="pdcch_waveform_prepared_not_received" && ...
    reference.SampleRateHz==prepared.SampleRateHz && ...
    source.Source=="actual_executed_link_contribution" && ...
    ~source.ReceiverEstimatorInput && source.AdditionalChannelExecutions==0 && ...
    source.AdditionalRFExecutions==0 && ...
    replay.ReceiverGainCompensation.OutputPlane=="digital_gain_compensated_received_samples_before_fft", ...
    'sixgr:truth:InvalidPDCCHScoringAuthority', ...
    'Independent scoring requires the actual desired link and actual gain-compensated receiver.');
if isempty(rx.ChannelEstimate) || isempty(rx.MonitoredDMRSREIndices), return; end
h=rx.ChannelEstimate; K=size(h,1); L=size(h,2); R=size(h,3);
assert(size(h,4)==1,'sixgr:truth:PDCCHReferencePortCount','PDCCH has one effective DM-RS port.');
idx=double(rx.MonitoredDMRSREIndices(:)); pilots=rx.MonitoredDMRSSymbols(:);
% Reference identity is a post-decode scoring check, never a hypothesis
% selector. An absent candidate has no transmitted channel to qualify.
[matched,atTx]=ismember(idx,double(prepared.Tx.DMRSInd(:)));
if ~all(matched), return; end
txPilots=prepared.Tx.Grid(prepared.Tx.DMRSInd(atTx));
if any(abs(txPilots(:)-pilots)>1e-12), return; end
shift=double(rx.AppliedTimingCorrection_samples);
count=double(info.DemodulatedReceiveSamples);
first=double(info.ObservationStartSample)+shift;
[wave,clock]=sixgr.truth.sharedReceiverClockScoringWindow(reference,source,replay,first,count);
% Mirror only the executed RX oscillator's clock. RX IQ/phase noise/ADC
% errors are deliberately not removed; AGC was already digitally inverted
% by the actual receiver. No fitted common phase or amplitude is allowed.
clockEvidence=source.ReceiverClockExecution;
segments=clockEvidence.ReceiveStreamExecutionSegments;
hz=NaN;
for k=1:numel(segments)
    endpoints=segments{k}.Execution.RX;
    endpoint=endpoints(string({endpoints.ID})==string(source.ReceiverID));
    assert(isscalar(endpoint) && all(isfield(endpoint.Replay,{'CFOApplied','InjectedCFO_Hz'})), ...
        'sixgr:truth:MissingPDCCHRXFrequencyExecution','Retain the actual RX oscillator operator.');
    current=0;
    if endpoint.Replay.CFOApplied, current=double(endpoint.Replay.InjectedCFO_Hz); end
    assert(isscalar(current) && isfinite(current), ...
        'sixgr:truth:InvalidPDCCHRXFrequencyExecution','Executed RX CFO must be finite.');
    if k==1, hz=current; end
    assert(current==hz,'sixgr:truth:ChangingPDCCHRXFrequencyExecution', ...
        'Changing oscillators require retained phase accumulators, not one guessed frequency.');
end
assert(isfinite(hz),'sixgr:truth:MissingPDCCHRXFrequencyExecution','No executed RX oscillator evidence.');
wave=wave.*exp(2i*pi*hz/prepared.SampleRateHz*(first+(0:count-1).'));
% The post-decode reference must use the exact measured RX derotation,
% including its local aligned-capture origin. The executed oscillator above
% remains separate physical scoring metadata, never a receiver estimate.
frequency=sixgr.util.structGet(rx,'ReceiveFrequency',struct());
assert(~isempty(fieldnames(frequency)) && ...
    isequaln(frequency,info.ReceiveFrequency) && frequency.SampleRateHz==prepared.SampleRateHz && ...
    frequency.CorrectionSampleCount==count && frequency.CFOCorrectionSampleOrigin==0 && ...
    frequency.CorrectionSign==-1, ...
    'sixgr:truth:InvalidPDCCHFrequencyOperator','Retain the original executed RX frequency operator.');
if frequency.CFOCorrectionApplied
    wave=wave.*exp(-2i*pi*frequency.CFOCorrectionApplied_Hz/prepared.SampleRateHz*(0:count-1).');
end
grid=sixgr.phy.waveform.ofdmDemodulate(prepared.Tx.Carrier,wave);
assert(isequal(size(grid),size(rx.RxGrid)), ...
    'sixgr:truth:PDCCHReferenceGridMismatch','Score the exact received grid extent and RX branches.');
slotREs=K*double(rx.ReferenceGridSymbolsPerSlot);
sc=mod(idx-1,K); symbol=floor(mod(idx-1,slotREs)/K);
assert(all(symbol<L) && numel(idx)==numel(pilots) && all(pilots~=0), ...
    'sixgr:truth:InvalidPDCCHScoringPilots','Use complete received DM-RS coordinates and symbols.');
sc=repmat(sc,R,1); symbol=repmat(symbol,R,1);
rxPort=repelem((0:R-1).',numel(idx));
at=sc+1+K*symbol+K*L*rxPort;
ideal=grid(at)./repmat(pilots,R,1); estimate=h(at);
errorEnergy=abs(estimate-ideal).^2; referenceEnergy=abs(ideal).^2;
assert(all(isfinite(ideal)) && all(isfinite(estimate)) && sum(referenceEnergy)>0, ...
    'sixgr:truth:InvalidPDCCHChannelReference','An executed nonzero reference is required; never use a scalar proxy.');
paired=table(sc,symbol,rxPort,zeros(size(sc)),real(ideal),imag(ideal), ...
    errorEnergy,referenceEnergy,'VariableNames',{'SubcarrierIndex0','SymbolIndex0', ...
    'RxPortIndex0','ReferencePortIndex0','ReferenceHReal','ReferenceHImag', ...
    'ChannelErrorEnergy','ChannelReferenceEnergy'});
metrics.ChannelNMSEErrorEnergy=sum(errorEnergy);
metrics.ChannelNMSEReferenceEnergy=sum(referenceEnergy);
metrics.NMSE_dB=10*log10(sum(errorEnergy)/sum(referenceEnergy));
metrics.NMSEScoringAvailable=true;
metrics.ChannelNMSEQualificationMode="same_execution_effective_pilot_response_no_gain_or_phase_fit";
metrics.ChannelNMSEComparedComplexValues=numel(ideal);
metrics.ChannelNMSEPilotResourceCount=numel(idx);
metrics.PDCCHScoringRecordedRXDelay_samples=clock.RecordedReceiverTimingOffset_samples;
metrics.PDCCHScoringExecutedRXCFO_Hz=hz;
metrics.PDCCHScoringMeasuredCorrectionApplied=frequency.CFOCorrectionApplied;
metrics.PDCCHScoringMeasuredCorrection_Hz=frequency.CFOCorrectionApplied_Hz;
end
