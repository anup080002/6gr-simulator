function sinr_dB=resolveDeliveredLinkQuality(state,ueIdx,direction)
% Read only delivered receiver feedback. This value never configures noise.
sinr_dB=NaN;
direction=upper(string(direction));
assert(isscalar(direction)&&any(direction==["DL","UL"]), ...
    'sixgr:truth:InvalidFeedbackDirection','Expected DL or UL.');
feedbacks=sixgr.util.structGet(state,"Latest"+direction+"Feedback",struct([]));
if ~isnumeric(ueIdx)||~isscalar(ueIdx)||~isreal(ueIdx)||~isfinite(ueIdx)|| ...
        ueIdx~=fix(ueIdx)||ueIdx<1||ueIdx>numel(feedbacks), return; end
feedback=feedbacks(ueIdx);
valid=sixgr.util.structGet(feedback,'Valid',false);
if ~(islogical(valid)||isnumeric(valid)) || ~isscalar(valid) || ...
        ~isreal(valid) || ~isfinite(valid) || double(valid)~=1, return; end
value=sixgr.util.structGet(feedback,'SINR_dB',NaN);
delivered=sixgr.util.structGet(feedback,'DeliveredSlot',NaN);
source=sixgr.util.structGet(feedback,'SourceSlot',NaN);
now=sixgr.util.structGet(state,'CurrentSlot',NaN);
scalars={value,source,delivered,now};
if all(cellfun(@(x)isnumeric(x)&&isreal(x)&&isscalar(x)&&isfinite(x),scalars)) && ...
        source<=delivered && delivered<=now
    sinr_dB=double(value);
end
end
