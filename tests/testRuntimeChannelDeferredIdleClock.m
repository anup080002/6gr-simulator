function ok = testRuntimeChannelDeferredIdleClock()
% Deferred creation must not change absolute channel time or its waveform.
setup6GRSimToolkit("Verbose", false);
assert(exist("nrCDLChannel", "class") == 8 && exist("nrTDLChannel", "class") == 8, ...
    "The deferred-clock regression requires actual 5G Toolbox fading objects.");
for duplex = ["TDD", "FDD"]
    for profile = ["CDL-A", "TDL-C"]
        localCheckFading(duplex, profile);
    end
end
localCheckAWGN();
ok = true;
fprintf("PASS testRuntimeChannelDeferredIdleClock: deferred/initial-offset clocks and waveforms match immediate materialization.\n");
end

function localCheckAWGN()
cfg = sixgr.config.defaultConfig();
cfg.channel.model = 'AWGN';
cfg.channel.awgnOnly = true;
fs = 7.68e6;
x = complex((1:16).', -(1:16).');
s = sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg, "DL", ...
    "LinkKey", "dir=DL;tx=gNB1;rx=UE1;carrier=awgn_clock_fixture", ...
    "AbsoluteSampleIndex", 21);
s = sixgr.channel.ChannelFactory.advanceRuntimeChannelState(s, 9, 1, x);
assert(isnan(s.CurrentTime_s), "Unknown sample rate must not produce an invented time.");
localReject(@() sixgr.channel.ChannelFactory.advanceRuntimeChannelStateToTime(s, 1, 1, x), ...
    "sixgr:channel:UnresolvedRuntimeSampleClock");
s = sixgr.channel.ChannelFactory.materializeRuntimeChannelState(s, cfg, x, ...
    struct("OFDM", struct("SampleRate", fs)), "NumTxAnt", 1, "NumRxAnt", 1);
assert(s.CurrentSampleIndex == 30 && s.PendingIdleSamples == 0 && ...
    s.TotalIdleAdvancedSamples == 30 && abs(s.CurrentTime_s - 30/fs) < 1e-15);
s = sixgr.channel.ChannelFactory.advanceRuntimeChannelState(s, 7, 1, x);
[y, replay, s] = sixgr.channel.ChannelFactory.applyRuntimeChannelState(s, x);
assert(isequal(y, x) && replay.RuntimeChannelStartSample == 37 && ...
    replay.RuntimeChannelEndSample == 53 && s.TotalAppliedSamples == 16 && ...
    s.TotalIdleAdvancedSamples == 37 && s.PendingIdleSamples == 0 && ...
    abs(s.CurrentTime_s - 53/fs) < 1e-15, ...
    "Explicit AWGN must preserve samples and account idle/applied time exactly once.");
localCheckClockRejection(s, x, fs);
end

function localCheckFading(duplex, profile)
cfg = sixgr.config.defaultConfig();
cfg.channel.model = char(profile);
cfg.channel.delayProfile = char(profile);
cfg.channel.fading.model = char(extractBefore(profile, "-"));
cfg.channel.fading.profile = char(profile);
if startsWith(profile, "CDL")
    cfg.channel.cdlProfile = char(profile);
else
    cfg.channel.tdlProfile = char(profile);
end
cfg.channel.awgnOnly = false;
cfg.channel.delaySpread_s = 100e-9;
cfg.channel.doppler_Hz = 37;
cfg.channel.channelFiltering = true;
cfg.channel.normalizePathGains = false;
cfg.channel.normalizeChannelOutputs = false;
cfg.phy.duplex.mode = char(duplex);
cfg.phy.fc_Hz = 3.5e9;
fs = 7.68e6;
txInfo = struct("OFDM", struct("SampleRate", fs));
x = exp(1i * (0:127).' / 13);
key = "dir=DL;tx=gNB1;rx=UE1;carrier=deferred_clock_fixture";
newState = @() sixgr.channel.ChannelFactory.createRuntimeChannelState( ...
    cfg, "DL", "LinkKey", key, "Seed", 12031);
materialize = @(s) sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
    s, cfg, x, txInfo, "NumTxAnt", 1, "NumRxAnt", 1);

early = materialize(newState());
late = newState();
for n = [187, 23]
    early = sixgr.channel.ChannelFactory.advanceRuntimeChannelState(early, n, 1, x);
    late = sixgr.channel.ChannelFactory.advanceRuntimeChannelState(late, n, 1, x);
end
late = materialize(late);
assert(late.CurrentSampleIndex == 210 && early.CurrentSampleIndex == 210, ...
    "%s/%s: materialization must not add deferred idle samples to the logical clock twice (got %g).", ...
    duplex, profile, late.CurrentSampleIndex);
assert(late.TotalIdleAdvancedSamples == 210 && late.PendingIdleSamples == 0 && ...
    late.TotalObjectInputSamples == late.WarmupSamples + late.CurrentSampleIndex, ...
    "Deferred idle must be consumed physically and accounted once, without resetting the fading object.");
assert(abs(late.CurrentTime_s - 210/fs) < 1e-15 && late.ResetCount == 1, ...
    "Resolved time and reset count must retain actual sample/seed authority.");
[expected, ~, early] = sixgr.channel.ChannelFactory.applyRuntimeChannelState(early, x);
[observed, replay, late] = sixgr.channel.ChannelFactory.applyRuntimeChannelState(late, x);
assert(replay.RuntimeChannelStartSample == 210 && replay.RuntimeChannelObjectClockExact, ...
    "The first waveform after deferred creation must begin at the requested sample.");
assert(norm(observed-expected, "fro") <= 1e-11 * max(norm(expected, "fro"), eps), ...
    "Deferred and immediate creation must produce the same actual fading waveform.");

offset = sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg, "DL", ...
    "LinkKey", key, "Seed", 12031, "AbsoluteSampleIndex", 210);
offset = materialize(offset);
[offsetWave, offsetReplay] = sixgr.channel.ChannelFactory.applyRuntimeChannelState(offset, x);
assert(offsetReplay.RuntimeChannelStartSample == 210 && offsetReplay.RuntimeChannelObjectClockExact && ...
    norm(offsetWave-expected, "fro") <= 1e-11 * max(norm(expected, "fro"), eps), ...
    "An initial absolute sample index must advance the real channel, not only its reported counter.");
% A rejected rewind must not advance/reset the handle-backed fading object.
% Prove that by comparing the next real waveform with an untouched twin.
localCheckClockRejection(late, x, fs);
[expectedNext, ~] = sixgr.channel.ChannelFactory.applyRuntimeChannelState(early, x);
[observedNext, nextReplay] = sixgr.channel.ChannelFactory.applyRuntimeChannelState(late, x);
assert(nextReplay.RuntimeChannelStartSample == 338 && ...
    norm(observedNext-expectedNext, "fro") <= 1e-11 * max(norm(expectedNext, "fro"), eps), ...
    "Rejected clock requests must leave both the logical and real fading-object clocks unchanged.");
end

function localCheckClockRejection(state, x, fs)
now = double(state.CurrentSampleIndex);
localReject(@() sixgr.channel.ChannelFactory.advanceRuntimeChannelStateToTime(state, (now-1)/fs, 1, x), ...
    "sixgr:channel:RuntimeChannelTimeReversal");
for invalidTime = [NaN, Inf, -1]
    localReject(@() sixgr.channel.ChannelFactory.advanceRuntimeChannelStateToTime(state, invalidTime, 1, x), ...
        "sixgr:channel:InvalidRuntimeTargetTime");
end
for invalidSamples = [-1, -0.1, NaN, Inf, 0.5]
    localReject(@() sixgr.channel.ChannelFactory.advanceRuntimeChannelState(state, invalidSamples, 1, x), ...
        "sixgr:channel:InvalidRuntimeAdvanceSamples");
end
same = sixgr.channel.ChannelFactory.advanceRuntimeChannelStateToTime(state, now/fs, 1, x);
assert(same.CurrentSampleIndex == now && same.LastIdleAdvancedSamples == 0 && ...
    same.ResetCount == state.ResetCount && same.TotalObjectInputSamples == state.TotalObjectInputSamples, ...
    "An exact same-sample request is a no-op, not a channel reset or replay.");
end

function localReject(action, identifier)
try
    action();
catch ME
    assert(string(ME.identifier) == identifier, "Unexpected clock failure: %s", ME.message);
    return;
end
error("testRuntimeChannelDeferredIdleClock:MissingError", "Expected clock rejection %s.", identifier);
end
