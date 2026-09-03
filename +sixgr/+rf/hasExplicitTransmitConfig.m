function tf = hasExplicitTransmitConfig(cfg)
%HASEXPLICITTRANSMITCONFIG True when the configured TX RF chain is active.
%
% This is the single authority used by DL, UL, and coupled shared-slot
% waveform generation.  Keeping the decision here prevents a desired
% waveform from traversing an enabled TX impairment while an interferer
% generated for the same physical slot silently bypasses it.

arguments
    cfg (1,1) struct
end

numericPaths = [ ...
    "rf.tx.cfo_Hz", ...
    "rf.tx.cfoHz", ...
    "rf.tx.loOffset_Hz", ...
    "rf.tx.timingOffsetSamples", ...
    "rf.tx.sampleTimingOffset_samples", ...
    "rf.tx.timing_offset_samples", ...
    "rf.tx.iqImbalance.gainImbalance_dB", ...
    "rf.tx.iqImbalance.ampImb_dB", ...
    "rf.tx.iqImbalance.amp_imbalance_db", ...
    "rf.tx.iqImbalance.phaseImbalance_deg", ...
    "rf.tx.iqImbalance.phaseImb_deg", ...
    "rf.tx.iqImbalance.phase_imbalance_deg"];
for path = numericPaths
    value = sixgr.util.structGet(cfg, char(path), []);
    if isnumeric(value) && ~isempty(value)
        value = double(value(1));
        if isfinite(value) && abs(value) > 1e-12
            tf = true;
            return;
        end
    end
end

flagPaths = [ ...
    "rf.tx.iqImbalance.enable", ...
    "rf.tx.iqImbalance.enabled", ...
    "rf.tx.phaseNoise.enable", ...
    "rf.tx.phaseNoise.enabled"];
for path = flagPaths
    value = sixgr.util.structGet(cfg, char(path), []);
    if localTruthy(value)
        tf = true;
        return;
    end
end
tf = false;
end

function tf = localTruthy(value)
tf = false;
if isempty(value)
    return;
end
if islogical(value) || isnumeric(value)
    tf = logical(value(1));
elseif ischar(value) || isstring(value)
    token = lower(strtrim(string(value(1))));
    tf = any(token == ["true","1","yes","on","enabled"]);
end
end
