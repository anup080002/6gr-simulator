function [y, replay, state, reference] = applyRuntimeFadingChannel(x, state, varargin)
%APPLYRUNTIMEFADINGCHANNEL Apply persistent runtime fading state when available.
% Continuous receivers retain channel/filter delay on their absolute sample
% clock. Only the legacy grant interface may use delay-aligned output.

ip = inputParser;
ip.addParameter("OutputSampleAlignment", "grant_delay_aligned", ...
    @(v) ischar(v) || isstring(v));
ip.addParameter("InputSampleDomain", "logical_ports", ...
    @(v) ischar(v) || isstring(v));
ip.addParameter("CaptureChannelReference",false,@(v)islogical(v) && isscalar(v));
ip.parse(varargin{:});
reference=struct();
capture=ip.Results.CaptureChannelReference;
assert(~capture || nargout>=4,'sixgr:link:ChannelReferenceOutputRequired', ...
    'Independent channel evidence must be returned separately from receiver replay.');
inputDomain = string(ip.Results.InputSampleDomain);
if ~isscalar(inputDomain) || ismissing(inputDomain) || ...
        ~any(inputDomain == ["logical_ports", "materialized_channel_ports"])
    error("ChannelFactory:InvalidInputSampleDomain", ...
        "InputSampleDomain must be logical_ports or materialized_channel_ports.");
end
alignment = string(ip.Results.OutputSampleAlignment);
if ~isscalar(alignment) || ismissing(alignment) || ...
        ~any(alignment == ["grant_delay_aligned", "continuous_raw_samples"])
    error("ChannelFactory:InvalidOutputSampleAlignment", ...
        "OutputSampleAlignment must be grant_delay_aligned or continuous_raw_samples.");
end
if capture || alignment == "continuous_raw_samples" || inputDomain == "materialized_channel_ports"
    runtime = sixgr.util.structGet(state, "RuntimeChannelState", struct());
    if ~isstruct(state) || ~isscalar(state) || ~isstruct(runtime) || ...
            ~isscalar(runtime) || ~isfield(runtime, "ContractVersion")
        error("ChannelFactory:UninitializedContinuousChannel", ...
            "Continuous reception requires authoritative runtime channel state; legacy or missing state cannot bypass fading.");
    end
end

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
    [y, replay, runtimeState, reference] = sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
        runtimeState, x, "OutputSampleAlignment", alignment, ...
        "InputSampleDomain", inputDomain,"CaptureChannelReference",capture);
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
