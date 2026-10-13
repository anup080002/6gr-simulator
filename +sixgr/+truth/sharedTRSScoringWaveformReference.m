function [grids,evidence,preRFGrids,preRFEvidence]=sharedTRSScoringWaveformReference(prepared,observation,timing,det,ch,recordedReceiverTiming,receiverExecution,frequency)
% Exact post-reception TRS reference from the same executed desired-link IQ.
arguments
    prepared (1,1) struct
    observation (1,1) sixgr.phy.waveform.WaveformObservationBuffer
    timing (1,1) struct
    det (1,1) struct
    ch (1,1) struct
    recordedReceiverTiming (1,1) double = NaN
    receiverExecution (1,1) struct = struct()
    frequency (1,1) struct = struct()
end
assert(observation.isComplete() && observation.SampleRateHz==prepared.SampleRateHz && ...
    observation.StartSample==prepared.TransmitStartSample && ...
    numel(det.SlotDetections)==numel(ch.ChannelEstimates), ...
    'sixgr:truth:InvalidTRSScoringWaveformReference', ...
    'Use the complete desired-link TRS observation and matching practical estimates.');
waveform=observation.readComplete();
grids=cell(numel(det.SlotDetections),1); evidence=grids;
preRFGrids=grids; preRFEvidence=grids;
hasCorrectionClock=all(isfield(frequency,{'CorrectionApplied','CorrectionApplied_Hz','CorrectionSampleOrigin'}));
rxCFO=0;
if hasCorrectionClock
    rxCFO=localExecutedRXCFO(receiverExecution);
end
for k=1:numel(grids)
    d=det.SlotDetections(k);
    hit=find(double(timing.Table.Slot)==double(d.Slot));
    assert(isscalar(hit) && logical(timing.Table.TRSTimingEstimateAvailable(hit)), ...
        'sixgr:truth:MissingTRSScoringTiming', ...
        'Independent TRS scoring must use the practical receiver timing decision.');
    offset=double(timing.Table.EstimatedTimingOffset_samples(hit));
    [wave,window]=sixgr.phy.trs.extractTRSReceiveWindow( ...
        waveform,prepared.Tx,k,offset,prepared.Tx.SlotResources(k));
    delay=recordedReceiverTiming;
    if ~isfinite(delay) && isfield(receiverExecution,'ReceiveStreamExecutionSegments')
        source=struct('Source',"actual_executed_link_contribution", ...
            'ReceiverID',receiverExecution.ReceiverID, ...
            'TransmitterID',receiverExecution.TransmitterID, ...
            'ReceiverEstimatorInput',false,'AdditionalChannelExecutions',0, ...
            'AdditionalRFExecutions',0);
        [wave,clockEvidence]=sixgr.truth.sharedReceiverClockScoringWindow( ...
            observation,source,receiverExecution, ...
            observation.StartSample+window.StartSample1Based-1,size(wave,1));
        delay=clockEvidence.RecordedReceiverTimingOffset_samples;
    end
    preRFGrid=sixgr.phy.waveform.ofdmDemodulate( ...
        prepared.Tx.SlotResources(k).Carrier,wave);
    % Channel NMSE compares the SAME acquisition coordinate system, not an
    % untracked Doppler channel against a tracked Hest. Apply only the
    % independently executed RX oscillator and the recorded receiver
    % correction to this post-decode scoring copy. No frequency is fitted
    % to Hest; PN/IQ/converter distortion and channel-estimation errors stay.
    % Preserve the former pre-RX-RF comparison separately below. Its phase
    % difference is not a pure channel-estimation error after tracking.
    referenceRxGrid=preRFGrid;
    if hasCorrectionClock
        receiverSamples=observation.StartSample+window.StartSample1Based-1+(0:size(wave,1)-1).';
        if rxCFO~=0
            assert(isfinite(delay),'sixgr:truth:MissingTRSRXFrequencyClock', ...
                'Executed RX CFO scoring requires the recorded RX delay before the sample clock can be reconciled.');
            % RX chain applies its timing filter BEFORE oscillator rotation.
            % The CFO clock is the receiver sample n, not source sample n-d.
            wave=wave.*exp(2i*pi*rxCFO/prepared.SampleRateHz*receiverSamples);
        end
        if frequency.CorrectionApplied
            assert(frequency.CorrectionSampleOrigin==observation.StartSample && ...
                isfinite(frequency.CorrectionApplied_Hz), ...
                'sixgr:truth:TRSScoringCorrectionClock','Use the actual recorded receiver correction clock.');
            wave=wave.*exp(-2i*pi*frequency.CorrectionApplied_Hz/prepared.SampleRateHz*receiverSamples);
        end
        referenceRxGrid=sixgr.phy.waveform.ofdmDemodulate(prepared.Tx.SlotResources(k).Carrier,wave);
    end
    estimate=ch.ChannelEstimates{k};
    K=size(estimate,1); L=size(estimate,2); R=size(estimate,3); P=size(estimate,4);
    indices=double(d.ReferenceIndices(:)); symbols=d.ReferenceSymbols(:);
    [subcarrier,symbolIndex,port]=ind2sub([K L P],indices);
    reference=complex(nan(size(estimate),'like',estimate));
    preRFReference=reference;
    for r=1:R
        atRx=sub2ind([K L R],subcarrier,symbolIndex,repmat(r,size(subcarrier)));
        atRef=sub2ind([K L R P],subcarrier,symbolIndex,repmat(r,size(subcarrier)),port);
        reference(atRef)=referenceRxGrid(atRx)./symbols;
        preRFReference(atRef)=preRFGrid(atRx)./symbols;
    end
    assert(all(isfinite(reference(sub2ind([K L R P], ...
        repmat(subcarrier,R,1),repmat(symbolIndex,R,1), ...
        repelem((1:R).',numel(subcarrier)),repmat(port,R,1))))), ...
        'sixgr:truth:IncompleteTRSScoringReference', ...
        'Every practical TRS pilot estimate needs its same-clock noiseless reference.');
    grids{k}=reference;
    evidence{k}=struct( ...
        'Source',"same_executed_desired_link_waveform_post_decode_TRS_pilot_ratio", ...
        'ReferencePlane',"effective_TRS_port_channel_from_actual_tx_RF_channel_loss_before_noise_rx_RF", ...
        'RFImpairmentsIncluded',true,'ReceiverEstimatorInput',false, ...
        'GainOrPhaseFitted',false,'AdditionalChannelExecutions',0, ...
        'AdditionalRFExecutions',0,'TimingOffsetRelativeTX_samples',offset);
    evidence{k}.RecordedReceiverTimingOffset_samples=delay;
    evidence{k}.ReceiverTimingIncluded=isfinite(delay);
    evidence{k}.ReceiverCFOIncluded=false;
    if isfinite(delay)
        evidence{k}.ReferencePlane= ...
            "effective_TRS_port_channel_on_recorded_RX_timing_clock_before_noise_and_other_rx_RF";
    end
    preRFGrids{k}=preRFReference; preRFEvidence{k}=evidence{k};
    if hasCorrectionClock
        evidence{k}.ReferencePlane= ...
            "effective_TRS_port_channel_on_recorded_RX_timing_clock_with_executed_RX_CFO_and_received_frequency_correction_before_other_RX_RF";
        evidence{k}.ReceiverCFOIncluded=true;
        evidence{k}.ExecutedReceiverCFO_Hz=rxCFO;
        evidence{k}.ReceivedFrequencyCorrectionApplied=frequency.CorrectionApplied;
        evidence{k}.ReceivedFrequencyCorrection_Hz=frequency.CorrectionApplied_Hz;
        evidence{k}.ResidualOscillatorQualification=false;
    end
end
end

function hz=localExecutedRXCFO(execution)
% Scoring authority is the ACTUAL RX endpoint, never merged TX+RX labels.
if isfield(execution,'ReceiveStreamExecutionSegments')
    segments=execution.ReceiveStreamExecutionSegments;
    values=nan(numel(segments),1);
    for k=1:numel(segments)
        endpoints=segments{k}.Execution.RX;
        endpoint=endpoints(string({endpoints.ID})==string(execution.ReceiverID));
        assert(isscalar(endpoint),'sixgr:truth:TRSScoringRXIdentity','One executed receiver must own the scoring clock.');
        values(k)=localAppliedCFO(endpoint.Replay);
    end
    assert(~isempty(values) && all(values==values(1)), ...
        'sixgr:truth:TRSScoringRXFrequencyTransition', ...
        'A changing oscillator needs its retained phase accumulator, not one scalar frequency.');
    hz=values(1);
else
    hz=localAppliedCFO(execution);
end
end

function hz=localAppliedCFO(replay)
assert(isfield(replay,'CFOApplied') && isscalar(replay.CFOApplied), ...
    'sixgr:truth:MissingExecutedTRSRXCFO','Retain executed RX frequency-operator evidence for channel scoring.');
hz=0;
if replay.CFOApplied
    hz=double(replay.InjectedCFO_Hz);
    validateattributes(hz,{'numeric'},{'scalar','real','finite'});
end
end
