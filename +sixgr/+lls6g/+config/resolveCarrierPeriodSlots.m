function [slots, source] = resolveCarrierPeriodSlots(s, slotPaths, msPaths, defaultSlots)
%RESOLVECARRIERPERIODSLOTS Exact calendar conversion on the carrier clock.
% For SSB/TRS/SRS/PRACH carrier-slot scheduling, not a CSI report's UL-BWP clock.
% Retain existing ordered alias precedence. Inheritance-aware resolution of
% contradictory aliases is a separate boundary, not silently inferred here.
arguments
    s (1,1) struct
    slotPaths string
    msPaths string
    defaultSlots = NaN
end
slots=NaN; source="";
for path=reshape(slotPaths,1,[])
    candidate=sixgr.util.structGet(s,path,[]);
    if isempty(candidate), continue; end
    slots=localInteger(candidate,path);
    source=path;
    return;
end
for path=reshape(msPaths,1,[])
    value=sixgr.util.structGet(s,path,[]);
    if isempty(value), continue; end
    localPositive(value,path);
    % Duration/horizon aliases may be independently rounded or censored;
    % they must never determine the physical NR slot duration.
    scs=sixgr.util.structGet(s,'frame.scs_khz',[]);
    localPositive(scs,"frame.scs_khz");
    mu=log2(double(scs)/15);
    assert(isfinite(mu)&&mu>=0&&mu==fix(mu), ...
        'sixgr:lls6g:config:PeriodCarrierNumerology', ...
        'frame.scs_khz must identify an NR carrier numerology before converting %s.',path);
    exact=double(value)*(double(scs)/15);
    assert(isfinite(exact)&&exact>=1&&exact<=flintmax&&exact==fix(exact), ...
        'sixgr:lls6g:config:NonIntegralCarrierPeriod', ...
        '%s=%g ms is not a positive integer carrier-slot period at %g kHz; no rounding is allowed.', ...
        path,double(value),double(scs));
    slots=exact; % NR slots/ms is a power of two; no rounding is necessary.
    source=path;
    return;
end
if isempty(defaultSlots)||(isnumeric(defaultSlots)&&isreal(defaultSlots)&&isscalar(defaultSlots)&&isnan(defaultSlots))
    return;
end
slots=localInteger(defaultSlots,"declared_default_slots");
source="declared_default_slots";
end

function slots=localInteger(value,path)
localPositive(value,path);
slots=double(value);
assert(slots<=flintmax&&slots==fix(slots), ...
    'sixgr:lls6g:config:NonIntegralCarrierPeriod', ...
    '%s must be an exactly representable positive integer slot period, not %g.',path,slots);
end

function localPositive(value,path)
assert(isnumeric(value)&&~islogical(value)&&isreal(value)&&isscalar(value)&& ...
    isfinite(value)&&value>0,'sixgr:lls6g:config:InvalidCarrierPeriod', ...
    '%s must be a finite positive numeric scalar.',path);
if isinteger(value)
    assert(value<=cast(flintmax,'like',value), ...
        'sixgr:lls6g:config:NonIntegralCarrierPeriod', ...
        '%s exceeds the exact integer coordinate range before conversion to double.',path);
end
end
