function [slotDuration_s, numerology] = slotDurationSec(scsOrCfg)
%SLOTDURATIONSEC Exact NR slot duration from the canonical numerology table.
%   Input is either an SCS value in kHz or a resolved simulator config.  No
%   unit guessing, logarithmic rounding, or mu-0 substitution is performed.

if nargin < 1 || isempty(scsOrCfg)
    error("sixgr:time:MissingSCS", ...
        "Provide an explicit SCS value in kHz or a config containing one.");
end

cyclicPrefix = "normal";
if isnumeric(scsOrCfg) || islogical(scsOrCfg)
    scs_kHz = scsOrCfg;
else
    cfg = scsOrCfg;
    scs_kHz = localFirstNumeric(cfg, [ ...
        "phy.carrier.SubcarrierSpacing_kHz", ...
        "phy.carrier.SubcarrierSpacing", ...
        "carrier.SubcarrierSpacing", ...
        "phy.numerology.scs_kHz", ...
        "phy.numerology.scs_khz", ...
        "frame.scs_khz", ...
        "frame_timing.scs_khz"]);
    if ~isfinite(scs_kHz)
        scsHz = localFirstNumeric(cfg, "global_radio_scope.scs_hz");
        if isfinite(scsHz)
            scs_kHz = scsHz / 1e3;
        end
    end
    cyclicPrefix = string(sixgr.util.structGet(cfg, ...
        "phy.carrier.CyclicPrefix", ...
        sixgr.util.structGet(cfg, "frame.cp_type", "normal")));
end

if ~(isnumeric(scs_kHz) || islogical(scs_kHz)) || ...
        ~isscalar(scs_kHz) || ~isfinite(double(scs_kHz)) || ...
        double(scs_kHz) <= 0
    error("sixgr:time:InvalidSCS", ...
        "Subcarrier spacing must be a positive finite scalar in kHz.");
end
numerology = sixgr.phy.frame.NumerologyCatalog.resolve( ...
    double(scs_kHz), cyclicPrefix, "generic_waveform_test", "");
slotDuration_s = double(numerology.SlotDurationSeconds);
end

function value = localFirstNumeric(cfg, paths)
value = NaN;
for path = string(paths)
    candidate = sixgr.util.structGet(cfg, path, []);
    if isempty(candidate)
        continue;
    end
    if ~(isnumeric(candidate) || islogical(candidate)) || ...
            ~isscalar(candidate) || ~isfinite(double(candidate))
        error("sixgr:time:InvalidSCS", ...
            "%s must be a finite numeric scalar.", path);
    end
    value = double(candidate);
    return;
end
end
