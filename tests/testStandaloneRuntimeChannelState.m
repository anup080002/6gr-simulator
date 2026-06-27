function ok = testStandaloneRuntimeChannelState()
%TESTSTANDALONERUNTIMECHANNELSTATE Verify standalone diagnostics use persistent fading state.

setup6GRSimToolkit("Verbose", false);

if exist("nrTDLChannel", "class") ~= 8
    warning("testStandaloneRuntimeChannelState:Missing5G", ...
        "nrTDLChannel is unavailable; skipping standalone runtime channel check.");
    ok = true;
    return;
end

cfg = struct();
cfg.run.seed = 707;
cfg.channel.model = "TDL";
cfg.channel.tdlProfile = "TDL-C";
cfg.channel.delaySpread_s = 30e-9;
cfg.channel.doppler_Hz = 90;
cfg.channel.channelFiltering = true;
cfg.channel.normalizePathGains = true;
cfg.phy.fc_Hz = 4e9;
cfg.phy.nRxAnt = 1;
cfg.phy.carrier.NSizeGrid = 24;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.lls6g.userContext.RuntimeCurrentDirection = "DL";
cfg.lls6g.userContext.UEIndex = 1;
cfg.lls6g.userContext.RuntimeServingCellIndex = 1;

txInfo = struct("OFDM", struct("SampleRate", 15.36e6));
x = localWaveform(768, 1, 9141);
tx = struct("Waveform", x);

state = sixgr.link.initWaveformTruthChannelState(cfg, tx, txInfo);
assert(logical(state.RuntimeChannelStateUsed), ...
    "Standalone truth channel state must materialize ChannelFactory runtime state.");
assert(logical(state.UseFading), ...
    "TDL standalone truth channel state must use a fading runtime object.");
assert(double(state.RuntimeChannelState.ResetCount) == 1, ...
    "Runtime channel must reset exactly once at materialization.");

[y1, r1, state] = sixgr.link.applyRuntimeFadingChannel(x, state);
[y2, r2, state] = sixgr.link.applyRuntimeFadingChannel(x, state);

assert(logical(r1.RuntimeChannelStateUsed) && logical(r2.RuntimeChannelStateUsed), ...
    "Standalone applications must disclose runtime channel state usage.");
assert(double(r1.RuntimeChannelResetCount) == 1 && double(r2.RuntimeChannelResetCount) == 1, ...
    "Standalone applications must not reset the channel per waveform.");
assert(double(r1.RuntimeChannelStartSample) == 0 && double(r2.RuntimeChannelStartSample) == size(x, 1), ...
    "Standalone runtime channel sample index must advance monotonically.");
assert(double(state.RuntimeChannelState.CurrentSampleIndex) == 2 * size(x, 1), ...
    "Runtime channel state must be returned with the advanced sample index.");
assert(localRelativeNorm(y2 - y1) > 1e-6, ...
    "Adjacent standalone applications must not replay an identical reset channel response.");

ok = true;
end

function x = localWaveform(n, p, seed)
rs = RandStream("mt19937ar", "Seed", seed);
x = complex(randn(rs, n, p), randn(rs, n, p)) / sqrt(2);
end

function e = localRelativeNorm(x)
e = norm(double(x(:))) / max(1, sqrt(numel(x)));
end
