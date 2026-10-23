function row = collectDataChannelExecutionEvidence(replay)
%COLLECTDATACHANNELEXECUTIONEVIDENCE Project original desired-link execution.
% Called only after the actual receiver returns. Shared aggregate fading can
% include interferers: it is never authority for the desired data link.
% Missing, reversed-tail or nonstationary history remains unavailable; this
% helper neither executes a channel nor reconstructs it from configuration.
row=struct('ChannelModelApplied',"",'ChannelFadingApplied',NaN, ...
    'ChannelFadingExecutionStatus',"",'ChannelExecutionEvidenceAvailable',false, ...
    'ChannelExecutionEvidenceStatus',"executed_replay_not_retained", ...
    'ChannelExecutionEvidenceSource',"",'ChannelExecutionTransmitterID',"", ...
    'ChannelExecutionReceiverID',"",'ChannelExecutionLinkID',"", ...
    'ChannelExecutionStartSample',NaN,'ChannelExecutionEndSampleExclusive',NaN, ...
    'ChannelExecutionSampleRateHz',NaN,'ChannelExecutionConfigurationEpoch',"", ...
    'ChannelExecutionSegmentCount',0,'ChannelExecutionDesiredSegmentCount',0);
if nargin==0 || isempty(replay), return; end
assert(isstruct(replay) && isscalar(replay),'sixgr:link:DataChannelReplayInput', ...
    'Use the original scalar completed-channel replay.');
if ~isfield(replay,'ReceiveStreamExecutionSegments')
    row=localValues(row,{replay});
    row.ChannelExecutionEvidenceSource="returned_direct_channel_replay_endpoint_scope_not_retained";
    return;
end
row.ChannelExecutionEvidenceSource="original_shared_execution_desired_TX_RX_link";
tx=localText(replay,'TransmitterID'); rx=localText(replay,'ReceiverID');
row.ChannelExecutionTransmitterID=tx; row.ChannelExecutionReceiverID=rx;
segments=replay.ReceiveStreamExecutionSegments;
first=localNumber(replay,'RuntimeChannelStartSample');
stop=localNumber(replay,'RuntimeChannelEndSample');
if strlength(tx)==0 || strlength(rx)==0 || ~iscell(segments) || isempty(segments) || ...
        ~localInterval(first,stop)
    row.ChannelExecutionEvidenceStatus="missing_original_shared_endpoint_or_interval"; return;
end
row.ChannelExecutionStartSample=first; row.ChannelExecutionEndSampleExclusive=stop;
values=cell(0,1); intervals=zeros(0,2); linkIDs=strings(0,1);
epochs=strings(0,1); rates=zeros(0,1);
for k=1:numel(segments)
    segment=segments{k};
    if ~isstruct(segment) || ~isscalar(segment) || ~isfield(segment,'Execution')
        row.ChannelExecutionEvidenceStatus="missing_original_execution_segment"; return;
    end
    e=segment.Execution;
    a=localNumber(segment,'StartSample'); b=localNumber(segment,'EndSampleExclusive');
    if ~localInterval(a,b) || ~isstruct(e) || ~isscalar(e) || ...
            a~=localNumber(e,'StartSample') || b~=localNumber(e,'EndSampleExclusive')
        row.ChannelExecutionEvidenceStatus="execution_segment_interval_mismatch"; return;
    end
    if b<=first || a>=stop, continue; end
    row.ChannelExecutionSegmentCount=row.ChannelExecutionSegmentCount+1;
    if localText(e,'Source')~="composed_tx_retained_rf_per_link_channel_sum_receiver_noise_rf" || ...
            localText(e,'ApproximationMode')~="none"
        row.ChannelExecutionEvidenceStatus="not_original_shared_physical_execution"; return;
    end
    if ~localEndpoint(e,'TX',tx) || ~localEndpoint(e,'RX',rx) || ...
            ~isfield(e,'Links') || ~isstruct(e.Links) || ...
            ~all(isfield(e.Links,{'TX','RX','ID','Replay'}))
        row.ChannelExecutionEvidenceStatus="missing_original_endpoint_execution"; return;
    end
    links=e.Links(string({e.Links.TX})==tx & string({e.Links.RX})==rx);
    if numel(links)~=1
        row.ChannelExecutionEvidenceStatus="desired_link_absent_or_ambiguous_in_capture"; return;
    end
    fs=localNumber(e,'SampleRateHz'); epoch=localText(e,'ConfigurationEpoch');
    if ~isfinite(fs) || fs<=0 || strlength(epoch)==0
        row.ChannelExecutionEvidenceStatus="missing_original_execution_clock"; return;
    end
    linkReplay=links.Replay;
    if ~isstruct(linkReplay) || ~isscalar(linkReplay) || ...
            localNumber(linkReplay,'RuntimeChannelStartSample')~=a || ...
            localNumber(linkReplay,'RuntimeChannelEndSample')~=b
        row.ChannelExecutionEvidenceStatus="desired_link_execution_interval_mismatch"; return;
    end
    intervals(end+1,:)=[a b]; %#ok<AGROW>
    values{end+1,1}=linkReplay; %#ok<AGROW>
    linkIDs(end+1,1)=string(links.ID); %#ok<AGROW>
    rates(end+1,1)=fs; epochs(end+1,1)=epoch; %#ok<AGROW>
    row.ChannelExecutionDesiredSegmentCount=numel(values);
end
if isempty(intervals) || intervals(1,1)>first || intervals(end,2)<stop || ...
        any(intervals(2:end,1)~=intervals(1:end-1,2))
    row.ChannelExecutionEvidenceStatus="desired_execution_does_not_cover_capture"; return;
end
if any(linkIDs~=linkIDs(1)) || strlength(linkIDs(1))==0 || ...
        any(rates~=rates(1)) || any(epochs~=epochs(1))
    row.ChannelExecutionEvidenceStatus="nonuniform_original_link_or_clock"; return;
end
row.ChannelExecutionLinkID=linkIDs(1);
row.ChannelExecutionSampleRateHz=rates(1);
% This is the retained PHYSICAL configuration epoch, not an invented clock ID.
row.ChannelExecutionConfigurationEpoch=epochs(1);
row=localValues(row,values);
end

function row=localValues(row,values)
names=["ChannelModelApplied","ChannelFadingApplied","ChannelFadingExecutionStatus"];
complete=true;
for name=names
    if ~all(cellfun(@(x)isfield(x,name),values)), complete=false; continue; end
    v=cellfun(@(x)x.(name),values,'UniformOutput',false);
    if name=="ChannelFadingApplied"
        valid=cellfun(@(x)(isnumeric(x)||islogical(x)) && isscalar(x) && ...
            isfinite(double(x)) && (double(x)==0||double(x)==1),v);
        if ~all(valid), complete=false; continue; end
        v=cellfun(@double,v,'UniformOutput',false);
    else
        v=cellfun(@string,v,'UniformOutput',false);
        valid=cellfun(@(x)isscalar(x) && ~ismissing(x) && strlength(x)>0,v);
        if ~all(valid), complete=false; continue; end
    end
    if ~all(cellfun(@(x)isequaln(x,v{1}),v))
        % Do not publish a partial scalar interpretation of varying models.
        row.ChannelModelApplied=""; row.ChannelFadingApplied=NaN;
        row.ChannelFadingExecutionStatus="";
        row.ChannelExecutionEvidenceStatus="nonuniform_original_execution_values"; return;
    end
    row.(name)=v{1};
end
row.ChannelExecutionEvidenceAvailable=complete;
if complete
    row.ChannelExecutionEvidenceStatus="retained_original_execution_values";
else
    row.ChannelExecutionEvidenceStatus="original_execution_fields_not_fully_retained";
end
end

function tf=localEndpoint(e,name,id)
tf=false;
if isfield(e,name) && isstruct(e.(name)) && isfield(e.(name),'ID')
    endpoints=e.(name);
    tf=nnz(string({endpoints.ID})==id)==1;
end
end
function value=localText(s,name)
value="";
if isfield(s,name)
    v=string(s.(name));
    if isscalar(v) && ~ismissing(v), value=v; end
end
end
function value=localNumber(s,name)
value=NaN;
if isfield(s,name)
    v=s.(name);
    if isnumeric(v) && isscalar(v), value=double(v); end
end
end
function tf=localInterval(a,b)
tf=isfinite(a)&&isfinite(b)&&a>=0&&b>a&&fix(a)==a&&fix(b)==b;
end
