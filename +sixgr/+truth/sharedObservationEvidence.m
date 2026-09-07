function [post,pre,tx,replay,receiver]=sharedObservationEvidence(planes)
% Keep segment provenance. Only flatten quantities invariant across the
% actual observation; block-average powers are NOT whole-window metrics.
ids=string({planes.ReceiverID});
postIndex=find(endsWith(ids,':post_rf')); preIndex=find(endsWith(ids,':pre_rf'));
txIndex=find(endsWith(ids,':tx'));
if numel(postIndex)~=1 || numel(preIndex)~=1 || numel(txIndex)~=1
    error('sixgr:truth:IncompletePhysicalObservationPlanes','One complete TX, pre-RF and post-RF observation are required.');
end
post=planes(postIndex).Observation; pre=planes(preIndex).Observation; tx=planes(txIndex).Observation;
for b={post,pre,tx}
    v=b{1};
    if ~v.isComplete() || v.SampleRateHz~=post.SampleRateHz || ...
            v.StartSample~=post.StartSample || v.EndSampleExclusive~=post.EndSampleExclusive
        error('sixgr:truth:PhysicalObservationClockMismatch','Measurement and decode planes must cover one actual interval.');
    end
end
segments=planes(postIndex).Segments;
rxID=extractBefore(ids(postIndex),':post_rf');
rx=cell(numel(segments),1); txReplay=cell(numel(segments),1); linkReplay=cell(0,1);
txID=extractBefore(ids(txIndex),':tx');
intervals=zeros(numel(segments),2);
for k=1:numel(segments)
    e=segments{k}.Execution;
    index=find(string({e.RX.ID})==rxID,1);
    if isempty(index), error('sixgr:truth:MissingReceiverExecution','No physical receiver owns this interval.'); end
    rx{k}=e.RX(index).Replay;
    index=find(string({e.TX.ID})==txID,1);
    if isempty(index), error('sixgr:truth:MissingTransmitterExecution','No physical transmitter owns this interval.'); end
    txReplay{k}=e.TX(index).Replay;
    links=e.Links(string({e.Links.RX})==rxID);
    for link=links, linkReplay{end+1,1}=link.Replay; end %#ok<AGROW>
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
end
