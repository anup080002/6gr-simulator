function result = resolveType0MonitoringWindow(context, firstSlot, endSlot)
% Exact half-open monitoring horizon; NOT an SI transmission schedule.
% TS 38.213 V18.8.0 clause 13 / Table 13-11, bounded non-shared FR1
% pattern 1, 15/30-kHz PDCCH. A prior pair may contribute its second slot.
% The caller supplies configured or received-MIB-derived context explicitly;
% this arithmetic cannot confer received-MIB or actual-transmission authority.
firstSlot=localSlot(firstSlot); endSlot=localSlot(endSlot);
assert(endSlot>=firstSlot,'sixgr:phy:pdcch:InvalidMonitoringWindow', ...
    'Monitoring window must be half-open [firstSlot,endSlot) with end >= first.');
base=sixgr.phy.pdcch.Type0PDCCHResolver(context);
ctx=base.Context;
assert(~ctx.SharedSpectrum && base.MultiplexingPattern==1 && ...
    any(ctx.PDCCHSCSKHz==[15 30]) && ctx.SSBIndex<=7, ...
    'sixgr:phy:pdcch:UnsupportedMonitoringWindow', ...
    'This window requires non-shared FR1 pattern 1, 15/30-kHz PDCCH and SSB index 0..7.');
F=10*double(ctx.PDCCHSCSKHz)/15;
period=2*F;
q=base.O*(F/10)+floor(ctx.SSBIndex*base.M);
anchor=mod(floor(q/F),2)*F+mod(q,F);
% Start one pair early, then clip actual candidates, never pair starts.
kFirst=floor((firstSlot-anchor-1)/period);
kLast=floor((endSlot-1-anchor)/period);
if endSlot==firstSlot || kLast<kFirst
    pair=zeros(0,1); member=zeros(0,1);
else
    starts=anchor+(kFirst:kLast).'*period;
    pair=repelem(starts,2);
    % A scalar input makes repelem return a row. Keep event vectors columnar
    % so the pair/member addition cannot silently form a Cartesian product.
    pair=pair(:); member=repmat([0;1],numel(starts),1);
end
slots=pair+member;
keep=slots>=firstSlot & slots<endSlot;
slots=slots(keep);pair=pair(keep);member=member(keep);
% A pair anchor may be -1 when its second member is slot zero. It is a
% modulo-calendar identity only, never evidence of pre-run transmission.
frames=floor(slots/F); slotWithinFrame=mod(slots,F);
firstSymbol=base.SearchSpace0.StartSymbolWithinSlot;
ids="type0_frame"+string(frames)+"_slot"+string(slotWithinFrame)+"_sym"+string(firstSymbol);
rows=table(ids,mod(frames,1024),slotWithinFrame,slots, ...
    repmat(firstSymbol,numel(slots),1),repmat(period,numel(slots),1), ...
    repmat(base.SearchSpaceSetsPerSlot,numel(slots),1),frames,pair,member, ...
    'VariableNames',{'MonitoringOccasionID','SFN','Slot','AbsoluteSlot', ...
    'FirstSymbol','PeriodSlots','SearchSpaceSetsPerSlot','AbsoluteFrameNumber', ...
    'PairStartAbsoluteSlot','PairMember0Based'});
result=struct('ContractVersion',"sixgr_type0_monitoring_window/v1", ...
    'Context',ctx,'ContextSHA256',base.ContextSHA256, ...
    'BaseResolutionSHA256',base.ResolutionSHA256, ...
    'FirstAbsoluteSlot',firstSlot,'EndAbsoluteSlotExclusive',endSlot, ...
    'MonitoringOccasions',rows,'TransmissionScheduled',false, ...
    'Source',"Type0_table_monitoring_arithmetic_not_transmission_or_reception", ...
    'ProxyUsed',false,'FallbackUsed',false);
payload=result;payload.MonitoringOccasions=table2struct(rows);
result.WindowSHA256=sixgr.util.sha256Hex(jsonencode(payload));
end

function slot=localSlot(raw)
assert(isnumeric(raw) && isreal(raw) && isscalar(raw) && isfinite(raw) && ...
    raw>=0 && raw==fix(raw) && raw<=flintmax/4, ...
    'sixgr:phy:pdcch:InvalidMonitoringWindow', ...
    'Absolute window coordinates must be exact nonnegative numeric integers.');
slot=double(raw);
end
