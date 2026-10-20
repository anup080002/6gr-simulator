function [duration,basis] = resolveTrialExposureSeconds(T,cfg)
%RESOLVETRIALEXPOSURESECONDS Retained exposure or explicitly configured slots.
% This is a per-trial denominator, not unique elapsed time across UE grants.
% A present but invalid duration is never repaired with a configured default.
if nargin<2, cfg=struct(); end
if ismember('AirInterfaceTTI_ms',T.Properties.VariableNames)
    duration=localNumeric(T.AirInterfaceTTI_ms)/1e3;
    basis="sum_retained_AirInterfaceTTI_ms";
else
    [seconds,source]=localConfiguredSlot(cfg);
    duration=repmat(seconds,height(T),1);
    basis="sum_configured_slot_exposure:"+source;
end
if ~isreal(duration)||numel(duration)~=height(T)
    duration=nan(height(T),1);
else
    duration(~isfinite(duration)|duration<=0)=NaN;
end
end

function [seconds,source]=localConfiguredSlot(cfg)
seconds=NaN; source="unavailable";
for path=["phy.numerology.slotDuration_s","frame.slot_duration_s", ...
        "frame_timing.slot_duration_ms","numerology.slot_duration_ms"]
    value=sixgr.util.structGet(cfg,path,[]);
    if isempty(value), continue; end
    source=path; value=localNumeric(value);
    if isscalar(value)&&isreal(value)&&isfinite(value)&&value>0
        seconds=value;
        if endsWith(path,"_ms"), seconds=seconds/1e3; end
    end
    return;
end
for path=["phy.carrier.SubcarrierSpacing_kHz","phy.carrier.SubcarrierSpacing", ...
        "carrier.SubcarrierSpacing","phy.numerology.scs_kHz", ...
        "phy.numerology.scs_khz","frame.scs_khz","frame_timing.scs_khz", ...
        "global_radio_scope.scs_hz"]
    if ~isempty(sixgr.util.structGet(cfg,path,[]))
        seconds=sixgr.time.slotDurationSec(cfg); source="exact_numerology:"+path; return;
    end
end
end

function value=localNumeric(value)
if isnumeric(value)||islogical(value), value=double(value(:));
else, value=str2double(string(value(:))); end
end
