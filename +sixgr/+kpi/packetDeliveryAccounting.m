function out=packetDeliveryAccounting(T, ids, payloadBits)
%PACKETDELIVERYACCOUNTING Unique delivered payload, without invented identity.
out=struct('Valid',false,'DeliveredBits',NaN,'DuplicateCount',NaN, ...
    'FirstCount',NaN,'FailureReason',"packet_delivery_schema_invalid");
if ~istable(T) || ~ismember('DeliverySuccess',T.Properties.VariableNames), return; end
ids=string(ids(:)); payloadBits=double(payloadBits(:));
if numel(ids)~=height(T) || numel(payloadBits)~=height(T)
    out.FailureReason="packet_delivery_population_width_mismatch"; return;
end
success=T.DeliverySuccess;
if isnumeric(success) || islogical(success), success=double(success);
else
    tokens=lower(strtrim(string(success)));
    tokens(tokens=="true")="1"; tokens(tokens=="false")="0";
    success=str2double(tokens);
end
if ~isvector(success) || numel(success)~=height(T) || any(~ismember(success,[0,1]))
    out.FailureReason="packet_delivery_success_flag_invalid"; return;
end
chosen=find(success==1);
if any(ismissing(ids(chosen)) | strlength(strtrim(ids(chosen)))==0 | lower(strtrim(ids(chosen)))=="nan")
    out.FailureReason="delivered_packet_identity_missing"; return;
end
if any(~isfinite(payloadBits(chosen)) | payloadBits(chosen)<=0 | payloadBits(chosen)~=fix(payloadBits(chosen)))
    out.FailureReason="delivered_packet_payload_size_invalid"; return;
end
seen=containers.Map('KeyType','char','ValueType','double');
bits=0; duplicate=0;
scopeFields=intersect(["Direction","SweepPointIndex","UEId","UEIndex","RNTI"], ...
    string(T.Properties.VariableNames),'stable');
for i=chosen(:)'
    identity=struct('PacketId',ids(i));
    for field=scopeFields
        value=string(T.(field)(i));
        if ismissing(value) || strlength(strtrim(value))==0 || lower(strtrim(value))=="nan"
            out.FailureReason="delivered_packet_scope_missing"; return;
        end
        identity.(field)=value;
    end
    key=jsonencode(identity);
    if isKey(seen,key)
        if seen(key)~=payloadBits(i)
            out.FailureReason="duplicate_packet_payload_size_disagrees"; return;
        end
        duplicate=duplicate+1;
    else
        seen(key)=payloadBits(i); bits=bits+payloadBits(i);
    end
end
out.Valid=true; out.DeliveredBits=bits; out.DuplicateCount=duplicate;
out.FirstCount=seen.Count; out.FailureReason="";
end
