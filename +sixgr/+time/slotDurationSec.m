function slotDuration_s = slotDurationSec(scsOrCfg)
%SLOTDURATIONSEC NR slot duration from subcarrier spacing.
%   The input can be an SCS value in kHz or a simulator config struct.

if nargin < 1 || isempty(scsOrCfg)
    scs_kHz = 15;
elseif isnumeric(scsOrCfg)
    scs_kHz = double(scsOrCfg);
else
    cfg = scsOrCfg;
    scs_kHz = double(sixgr.util.structGet(cfg, "phy.carrier.SubcarrierSpacing", NaN));
    if ~(isfinite(scs_kHz) && scs_kHz > 0)
        scs_kHz = double(sixgr.util.structGet(cfg, "carrier.SubcarrierSpacing", NaN));
    end
    if ~(isfinite(scs_kHz) && scs_kHz > 0)
        scs_kHz = double(sixgr.util.structGet(cfg, "phy.numerology.scs_khz", NaN));
    end
    if ~(isfinite(scs_kHz) && scs_kHz > 0)
        scs_kHz = double(sixgr.util.structGet(cfg, "frame_timing.scs_khz", NaN));
    end
    if ~(isfinite(scs_kHz) && scs_kHz > 0)
        scsHz = double(sixgr.util.structGet(cfg, "global_radio_scope.scs_hz", NaN));
        if isfinite(scsHz) && scsHz > 0
            scs_kHz = scsHz / 1e3;
        end
    end
    if ~(isfinite(scs_kHz) && scs_kHz > 0)
        scs_kHz = 15;
    end
end

if isscalar(scs_kHz) && isfinite(scs_kHz) && scs_kHz > 1000
    scs_kHz = scs_kHz / 1e3;
end
if ~(isscalar(scs_kHz) && isfinite(scs_kHz) && scs_kHz > 0)
    error("sixgr:time:InvalidSCS", "Subcarrier spacing must be a positive finite scalar.");
end

mu = round(log2(double(scs_kHz) / 15));
slotDuration_s = 1e-3 / (2 ^ mu);
end
