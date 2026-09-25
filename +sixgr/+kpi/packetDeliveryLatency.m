function out = packetDeliveryLatency(T)
%PACKETDELIVERYLATENCY First delivery of unique packets, from radio timestamps.
% No TB latency, configured delay or host execution time is a substitute.
out=struct('Values_ms',zeros(0,1),'FirstDeliveryRows',zeros(0,1), ...
    'Mean_ms',NaN,'P95_ms',NaN,'Sum_ms',0,'Count',0, ...
    'Valid',false,'Status',"missing_raw_data",'FailureReason',"packet_ledger_missing");
if ~istable(T) || isempty(T), return; end
names=string(T.Properties.VariableNames);
if ~all(ismember(["PacketId","DeliverySuccess"],names))
    out.FailureReason="packet_latency_identity_or_delivery_flag_missing"; return;
end
success=localNumbers(T.DeliverySuccess);
if any(~ismember(success,[0,1]))
    out.FailureReason="packet_latency_delivery_flag_invalid"; return;
end
if ~any(success)
    out.Valid=true; out.Status="unavailable_no_successful_delivery";
    out.FailureReason="no_successful_packet_delivery"; return;
end
if ~all(ismember(["EnqueueTime_s","DeliveryTime_s"],names))
    out.FailureReason="packet_latency_radio_timestamps_missing"; return;
end
start=localNumbers(T.EnqueueTime_s); finish=localNumbers(T.DeliveryTime_s);
chosen=find(success==1);
if any(~isfinite(start(chosen)) | ~isfinite(finish(chosen)))
    out.FailureReason="successful_packet_latency_timestamp_missing"; return;
end
if any(start(chosen)<0 | finish(chosen)<start(chosen))
    out.FailureReason="negative_successful_packet_latency"; return;
end
values=(finish-start)*1e3;
if ismember("Latency_ms",names)
    published=localNumbers(T.Latency_ms);
    valid=isfinite(published(chosen));
    if any(abs(published(chosen(valid))-values(chosen(valid)))>1e-6)
        out.FailureReason="packet_latency_precomputed_mismatch"; return;
    end
end
for pair={["EnqueueCanonicalSlot","DeliveryCanonicalSlot"], ["EnqueueSlot","DeliverySlot"]}
    fields=pair{1};
    if all(ismember(fields,names))
        enq=localNumbers(T.(fields(1))); delivered=localNumbers(T.(fields(2)));
        if any(isfinite(enq(chosen)) & isfinite(delivered(chosen)) & delivered(chosen)<enq(chosen))
            out.FailureReason="delivery_slot_before_enqueue_slot"; return;
        end
    end
end
ids=string(T.PacketId);
if ismember("ApplicationPacketId",names)
    app=string(T.ApplicationPacketId);
    use=~ismissing(app) & strlength(strtrim(app))>0;
    ids(use)=app(use);
end
if any(ismissing(ids(chosen)) | strlength(strtrim(ids(chosen)))==0)
    out.FailureReason="successful_packet_identity_missing"; return;
end
% Packet counters can restart for another UE or sweep point. Preserve the
% installed identity dimensions when present; do not merge across them.
keys=ids;
for field=["Direction","SweepPointIndex","UEId","UEIndex","RNTI"]
    if ismember(field,names)
        value=string(T.(field));
        if any(ismissing(value(chosen)) | strlength(strtrim(value(chosen)))==0)
            out.FailureReason="successful_packet_scope_missing"; return;
        end
        keys=keys+"|"+field+"="+value;
    end
end
first=zeros(0,1);
for key=unique(keys(chosen),'stable')'
    group=chosen(keys(chosen)==key);
    if any(abs(start(group)-start(group(1)))>1e-12)
        out.FailureReason="same_packet_enqueue_time_disagrees"; return;
    end
    [~,index]=min(finish(group)); first(end+1,1)=group(index); %#ok<AGROW>
end
out.Values_ms=values(first); out.FirstDeliveryRows=first;
out.Count=numel(first); out.Sum_ms=sum(out.Values_ms); out.Mean_ms=out.Sum_ms/out.Count;
% Match MATLAB prctile's midpoint empirical-CDF interpolation.
ordered=sort(out.Values_ms); location=.95*numel(ordered)+.5;
lo=max(1,min(numel(ordered),floor(location))); hi=max(1,min(numel(ordered),ceil(location)));
out.P95_ms=ordered(lo)+(location-floor(location))*(ordered(hi)-ordered(lo));
out.Valid=true; out.Status="pass"; out.FailureReason="";
end

function values=localNumbers(input)
if isnumeric(input) || islogical(input)
    values=double(input);
else
    tokens=lower(strtrim(string(input)));
    tokens(tokens=="true")="1"; tokens(tokens=="false")="0";
    values=str2double(tokens);
end
end
