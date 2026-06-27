function [y, replay, state] = applyRuntimeFadingChannel(x, state)
%APPLYRUNTIMEFADINGCHANNEL Apply persistent runtime fading state when available.

y = x;
replay = struct( ...
    "ChannelFadingApplied", false, ...
    "ChannelFadingExecutionStatus", "not_requested", ...
    "ChannelFadingObjectClass", "", ...
    "ChannelPathGainsAvailable", false, ...
    "RuntimeChannelStateUsed", false, ...
    "RuntimeChannelLinkKey", "", ...
    "RuntimeChannelSeed", NaN, ...
    "RuntimeChannelResetCount", NaN, ...
    "RuntimeChannelStartSample", NaN, ...
    "RuntimeChannelEndSample", NaN, ...
    "RuntimeChannelIdleAdvancedSamples", NaN);

if ~(isstruct(state) && ~isempty(fieldnames(state)))
    replay.ChannelFadingExecutionStatus = "state_unavailable";
    return;
end

runtimeState = sixgr.util.structGet(state, "RuntimeChannelState", struct());
if isstruct(runtimeState) && isfield(runtimeState, "ContractVersion")
    [y, replay, runtimeState] = sixgr.channel.ChannelFactory.applyRuntimeChannelState(runtimeState, x);
    state.RuntimeChannelState = runtimeState;
    state.UseFading = logical(sixgr.util.structGet(runtimeState, "UseFading", false));
    state.Obj = sixgr.util.structGet(runtimeState, "Obj", []);
    state.ChannelPadSamples = double(sixgr.util.structGet(runtimeState, "ChannelPadSamples", 0));
    state.ChannelTrimSamples = double(sixgr.util.structGet(runtimeState, "ChannelTrimSamples", 0));
    state.SampleRate_Hz = double(sixgr.util.structGet(runtimeState, "SampleRate_Hz", sixgr.util.structGet(state, "SampleRate_Hz", NaN)));
    return;
end

if ~(logical(sixgr.util.structGet(state, "UseFading", false)) && isfield(state, "Obj") && ~isempty(state.Obj))
    replay.ChannelFadingExecutionStatus = "awgn_or_no_fading_object";
    return;
end

replay.ChannelFadingExecutionStatus = "applied_legacy_state_without_reset";
replay.ChannelFadingObjectClass = class(state.Obj);
xIn = x;
padSamples = max(0, round(double(sixgr.util.structGet(state, "ChannelPadSamples", 0))));
trimSamples = max(0, round(double(sixgr.util.structGet(state, "ChannelTrimSamples", 0))));
if padSamples > 0
    xIn = [x; zeros(padSamples, size(x, 2), "like", x)];
end
try
    [yRaw, pathGains] = state.Obj(xIn);
catch
    yRaw = state.Obj(xIn);
    pathGains = [];
end
if trimSamples > 0 && size(yRaw, 1) >= (trimSamples + size(x, 1))
    y = yRaw(1+trimSamples:trimSamples+size(x, 1), :);
else
    y = yRaw;
    if size(y, 1) > size(x, 1)
        y = y(1:size(x, 1), :);
    elseif size(y, 1) < size(x, 1)
        y(end+1:size(x, 1), :) = cast(0, "like", y); %#ok<AGROW>
    end
end
replay.ChannelFadingApplied = true;
replay.ChannelPathGainsAvailable = ~isempty(pathGains);
end
