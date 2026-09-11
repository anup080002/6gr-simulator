function [post,pre,tx,replay,receiver]=sharedObservationEvidence(planes,prepared)
% Keep segment provenance. Only flatten quantities invariant across the
% actual observation; block-average powers are NOT whole-window metrics.
ids=string({planes.ReceiverID});
postIndex=find(endsWith(ids,':post_rf')); preIndex=find(endsWith(ids,':pre_rf'));
txIndex=find(endsWith(ids,':tx'));
if numel(postIndex)~=1 || numel(preIndex)~=1 || numel(txIndex)~=1
    error('sixgr:truth:IncompletePhysicalObservationPlanes','One complete TX, pre-RF and post-RF observation are required.');
end
post=planes(postIndex).Observation; pre=planes(preIndex).Observation; tx=planes(txIndex).Observation;
buffers={post,pre,tx};
if nargin>=2
    if isa(prepared,'sixgr.link.PreparedUplinkControlTransmission')
        prepared.readObservation(tx,"transmitter");
        prepared.readObservation(post,"receiver");
    elseif isa(prepared,'sixgr.link.PreparedDataTransmission')
        prepared.readObservation(tx,prepared.NumPhysicalTransmitAntennas,"transmitter");
        prepared.readObservation(post, ...
            prepared.RequestBinding.PHYGrant.AntennaArchitecture.NumRxAntennas,"receiver");
    else
        assert(isstruct(prepared) && isscalar(prepared) && ...
            string(sixgr.util.structGet(prepared,'ExecutionStage',''))=="pdcch_waveform_prepared_not_received" && ...
            isfield(prepared,'TransmitObservationStartSample') && ...
            isfield(prepared,'TransmitObservationEndSampleExclusive'), ...
            'sixgr:truth:InvalidPhysicalULObservationAuthority', ...
            'Distinct TX/RX intervals require retained preparation and clock authority.');
        assert(tx.isComplete() && tx.SampleRateHz==prepared.SampleRateHz && ...
            tx.StartSample==prepared.RuntimeStartSample && ...
            tx.StartSample==prepared.TransmitObservationStartSample && ...
            tx.EndSampleExclusive==prepared.RuntimeStartSample+prepared.MinimumReceiveSamples && ...
            tx.EndSampleExclusive==prepared.TransmitObservationEndSampleExclusive && ...
            tx.NumReceiveAntennas==size(prepared.TransmitSamples,2), ...
            'sixgr:truth:PDCCHTransmitObservationMismatch', ...
            'Control TX evidence must cover the actual transmitted monitoring prefix.');
        receiveFirst=prepared.RuntimeStartSample;
        if isfield(prepared,'ReceivedTimingAlignment')
            receiveFirst=prepared.ReceivedTimingAlignment.ReceiveStartSample;
        end
        assert(post.StartSample==receiveFirst && post.SampleRateHz==prepared.SampleRateHz && ...
            post.EndSampleExclusive>=receiveFirst+prepared.MinimumReceiveSamples, ...
            'sixgr:truth:PDCCHReceiveObservationMismatch', ...
            'The actual receive capture must cover the monitored symbols on the declared UE clock.');
    end
    buffers={post,pre};
end
for b=buffers
    v=b{1};
    if ~v.isComplete() || v.SampleRateHz~=post.SampleRateHz || ...
            v.StartSample~=post.StartSample || v.EndSampleExclusive~=post.EndSampleExclusive
        error('sixgr:truth:PhysicalObservationClockMismatch','Measurement and decode planes must cover one actual interval.');
    end
end
segments=planes(postIndex).Segments;
rxID=extractBefore(ids(postIndex),':post_rf');
rx=cell(numel(segments),1); txReplay=cell(numel(segments),1); linkReplay=cell(0,1); lossReplay=cell(0,1);
txID=extractBefore(ids(txIndex),':tx');
intervals=zeros(numel(segments),2);
for k=1:numel(segments)
    e=segments{k}.Execution;
    % The before/after desired-link energies are independent validation
    % evidence, not a practical receiver's signal-power oracle.
    for j=1:numel(e.Links)
        if isfield(e.Links(j).LossReplay,'GainStageMeasurement')
            e.Links(j).LossReplay=rmfield(e.Links(j).LossReplay,'GainStageMeasurement');
        end
    end
    % Applied channel tensors belong to independent scoring/export only.
    % Do not deliver them to a practical receiver through nested replay.
    if isfield(e,'ChannelReferences')
        e=rmfield(e,'ChannelReferences');
    end
    segments{k}.Execution=e;
    index=find(string({e.RX.ID})==rxID,1);
    if isempty(index), error('sixgr:truth:MissingReceiverExecution','No physical receiver owns this interval.'); end
    rx{k}=e.RX(index).Replay;
    index=find(string({e.TX.ID})==txID,1);
    if isempty(index), error('sixgr:truth:MissingTransmitterExecution','No physical transmitter owns this interval.'); end
    txReplay{k}=e.TX(index).Replay;
    links=e.Links(string({e.Links.RX})==rxID);
    for link=links
        linkReplay{end+1,1}=link.Replay; %#ok<AGROW>
        if string(link.TX)==txID, lossReplay{end+1,1}=link.LossReplay; end %#ok<AGROW>
    end
    intervals(k,:)=[segments{k}.StartSample segments{k}.EndSampleExclusive];
end
if isempty(segments) || intervals(1,1)>post.StartSample || ...
        intervals(end,2)<post.EndSampleExclusive || any(intervals(2:end,1)~=intervals(1:end-1,2))
    error('sixgr:truth:IncompletePhysicalExecutionEvidence','Actual execution must cover the complete receive window without a gap.');
end
replay=struct('RuntimeChannelStartSample',post.StartSample, ...
    'RuntimeChannelEndSample',post.EndSampleExclusive, ...
    'ReceiveStreamChunkIntervals',intervals,'ReceiveStreamExecutionSegments',{segments}, ...
    'RuntimeChannelStateUsed',~isempty(linkReplay),'ChannelFadingApplied',false, ...
    'AppliedAWGNSNR_dB',NaN,'InjectedCFO_Hz',NaN,'InjectedTimingOffset_samples',NaN);
for name=["InjectedNoiseVariance","InjectedNoiseVarianceDomain", ...
        "SampleNoiseVariance","SampleNoiseVarianceDomain","NoiseVarianceSource"]
    values=cellfun(@(x)x.(name),rx,'UniformOutput',false);
    if ~all(cellfun(@(x)isequaln(x,values{1}),values))
        error('sixgr:truth:TimeVaryingObservationLedger', ...
            'Do not flatten time-varying receiver %s; retain segment-domain evidence.',name);
    end
    replay.(name)=values{1};
end
for name=["InjectedCFO_Hz","InjectedTimingOffset_samples"]
    values=cellfun(@(r,t)double(r.(name))+double(t.(name)),rx,txReplay);
    if all(values==values(1)), replay.(name)=values(1); end
end
for k=1:numel(linkReplay)
    replay.ChannelFadingApplied=replay.ChannelFadingApplied || ...
        logical(sixgr.util.structGet(linkReplay{k},'ChannelFadingApplied',false));
end
if ~isempty(linkReplay)
    for name=["RuntimeChannelLinkKey","RuntimeChannelSeed"]
        values=cellfun(@(x)x.(name),linkReplay,'UniformOutput',false);
        if all(cellfun(@(x)isequaln(x,values{1}),values)), replay.(name)=values{1}; end
    end
end
if nargout>=5
    [receiver,replay.ReceiverGainCompensation]=sixgr.phy.rx.compensateReceivedAGC(post,segments,rxID);
    replay.SampleNoiseVariance=NaN;
    replay.SampleNoiseVarianceDomain='requires_estimation_on_digital_gain_compensated_received_reference_REs';
end
% Stationary execution metadata can be exported directly. Per-block means,
% time-varying AGC and component powers must not become guessed scalars.
mapping={'NoiseOperatingMode',rx,'NoiseOperatingMode'; ...
    'ThermalSampleNoiseBandwidth_Hz',rx,'ThermalSampleNoiseBandwidth_Hz'; ...
    'ThermalNoisePSD_mWPerHz',rx,'ThermalNoisePSD_mWPerHz'; ...
    'RequestedAWGNReferenceSNR_dB',rx,'RequestedAWGNReferenceSNR_dB'; ...
    'SignalEnergyPerOccupiedRE',rx,'SignalEnergyPerOccupiedRE'; ...
    'GridNoiseVariance',rx,'GridNoiseVariance'; ...
    'ReferenceAWGNGridNoiseVariance',rx,'ReferenceAWGNGridNoiseVariance'; ...
    'ReferenceAWGNSampleNoiseVariance',rx,'ReferenceAWGNSampleNoiseVariance'; ...
    'SampleToGridNoiseVarianceGain',rx,'SampleToGridNoiseVarianceGain'; ...
    'SharedNoiseCalibrationSource',rx,'SharedNoiseCalibrationSource'; ...
    'TxRFExecutionStatus',txReplay,'RFExecutionStatus'; ...
    'TxRFStageOrder',txReplay,'RFStageOrder'; ...
    'TxRFAppliedStageCount',txReplay,'RFAppliedStageCount'; ...
    'CompositeReceiverFrontEndStatus',rx,'RFExecutionStatus'; ...
    'AppliedLargeScaleGain_dB',lossReplay,'AppliedLargeScaleGain_dB'; ...
    'AppliedLargeScaleLoss_dB',lossReplay,'AppliedLargeScaleLoss_dB'; ...
    'AppliedBasePathloss_dB',lossReplay,'AppliedBasePathloss_dB'; ...
    'AppliedPathloss_dB',lossReplay,'AppliedPathloss_dB'; ...
    'PathlossModelSource',lossReplay,'PathlossModelSource'; ...
    'PathlossComplianceStatus',lossReplay,'PathlossComplianceStatus'; ...
    'FallbackUsedForPathloss',lossReplay,'FallbackUsedForPathloss'; ...
    'AppliedShadowFading_dB',lossReplay,'AppliedShadowFading_dB'; ...
    'AppliedO2I_dB',lossReplay,'AppliedO2I_dB'; ...
    'AppliedLargeScaleGainSource',lossReplay,'AppliedLargeScaleGainSource'};
for k=1:size(mapping,1)
    values=mapping{k,2}; field=mapping{k,3};
    if isempty(values) || ~all(cellfun(@(v)isfield(v,field),values)), continue; end
    values=cellfun(@(v)v.(field),values,'UniformOutput',false);
    if all(cellfun(@(v)isequaln(v,values{1}),values)), replay.(mapping{k,1})=values{1}; end
end
replay.CompositeReceiverFrontEndApplied=any(cellfun(@(v)v.RFAppliedStageCount>0,rx));
% Geometry is a paired input from the desired physical link. Do not choose
% the first interval or copy a slant range into horizontal range when the
% link moved during the capture. Full segment records remain above.
replay.RuntimeGeometryDistance2D_m=NaN;
replay.RuntimeGeometryDistance3D_m=NaN;
replay.RuntimeGeometrySource='unavailable_or_time_varying_executed_link_geometry';
if ~isempty(lossReplay) && all(cellfun(@(v)all(isfield(v, ...
        {'RuntimeGeometryDistance2D_m','RuntimeGeometryDistance3D_m','RuntimeGeometrySource'})),lossReplay))
    d2=cellfun(@(v)v.RuntimeGeometryDistance2D_m,lossReplay);
    d3=cellfun(@(v)v.RuntimeGeometryDistance3D_m,lossReplay);
    sources=string(cellfun(@(v)v.RuntimeGeometrySource,lossReplay,'UniformOutput',false));
    if all(isfinite(d2)) && all(isfinite(d3)) && all(d2==d2(1)) && ...
            all(d3==d3(1)) && all(sources==sources(1))
        replay.RuntimeGeometryDistance2D_m=d2(1);
        replay.RuntimeGeometryDistance3D_m=d3(1);
        replay.RuntimeGeometrySource=char(sources(1));
    end
end
end
