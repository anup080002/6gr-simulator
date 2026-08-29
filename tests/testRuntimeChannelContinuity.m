function ok = testRuntimeChannelContinuity()
%TESTRUNTIMECHANNELCONTINUITY Guard persistent fading state across grants.

setup6GRSimToolkit("Verbose", false);

if exist("nrTDLChannel", "class") ~= 8
    warning("testRuntimeChannelContinuity:Missing5G", ...
        "nrTDLChannel is unavailable; skipping runtime channel continuity check.");
    ok = true;
    return;
end

cfg = localTDLConfig();
fs = 15.36e6;
txInfo = struct("OFDM", struct("SampleRate", fs));
x = localDeterministicWaveform(1024, 1, 991);

stateA = sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg, "DL", ...
    "LinkKey", "dir=DL;tx=gNB1;rx=UE1;carrier=test", "Seed", 12031);
stateA = sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
    stateA, cfg, x, txInfo, "NumTxAnt", 1, "NumRxAnt", 1);
[yA1, replayA1, stateA] = sixgr.channel.ChannelFactory.applyRuntimeChannelState(stateA, x);
[yA2, replayA2, stateA] = sixgr.channel.ChannelFactory.applyRuntimeChannelState(stateA, x);

assert(replayA1.RuntimeChannelStateUsed && replayA2.RuntimeChannelStateUsed, ...
    "Runtime channel replay must identify persistent state usage.");
assert(replayA1.RuntimeChannelResetCount == 1 && replayA2.RuntimeChannelResetCount == 1, ...
    "Persistent channel must reset once at materialization, not once per grant.");
assert(replayA1.RuntimeChannelStartSample == 0, ...
    "First grant must start at runtime sample zero.");
assert(replayA2.RuntimeChannelStartSample == size(x, 1), ...
    "Second adjacent grant must start after the first grant samples.");
assert(stateA.CurrentSampleIndex == 2 * size(x, 1), ...
    "Runtime sample index must advance monotonically across adjacent grants.");
assert(localRelativeNorm(yA2 - yA1) > 1e-6, ...
    "Adjacent grants through one TDL process must not replay an identical reset response.");

stateB = sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg, "DL", ...
    "LinkKey", "dir=DL;tx=gNB1;rx=UE1;carrier=test", "Seed", 12031);
stateB = sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
    stateB, cfg, x, txInfo, "NumTxAnt", 1, "NumRxAnt", 1);
[yB1, ~, stateB] = sixgr.channel.ChannelFactory.applyRuntimeChannelState(stateB, x); %#ok<ASGLU>
assert(localRelativeNorm(yB1 - yA1) < 1e-12, ...
    "Same link seed/drop must reproduce the first channel realization exactly.");

stateC = sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg, "DL", ...
    "LinkKey", "dir=DL;tx=gNB1;rx=UE1;carrier=test", "Seed", 12032);
stateC = sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
    stateC, cfg, x, txInfo, "NumTxAnt", 1, "NumRxAnt", 1);
[yC1, ~, stateC] = sixgr.channel.ChannelFactory.applyRuntimeChannelState(stateC, x); %#ok<ASGLU>
assert(localRelativeNorm(yC1 - yA1) > 1e-6, ...
    "Different hierarchical channel seed must produce a different fading process.");

idleSamples = 256;
stateIdle = sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg, "DL", ...
    "LinkKey", "dir=DL;tx=gNB1;rx=UE1;carrier=test", "Seed", 12031);
stateIdle = sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
    stateIdle, cfg, x, txInfo, "NumTxAnt", 1, "NumRxAnt", 1);
[~, ~, stateIdle] = sixgr.channel.ChannelFactory.applyRuntimeChannelState(stateIdle, x);
stateIdle = sixgr.channel.ChannelFactory.advanceRuntimeChannelState(stateIdle, idleSamples, 1, x);
[yIdle2, replayIdle2, stateIdle] = sixgr.channel.ChannelFactory.applyRuntimeChannelState(stateIdle, x);

assert(replayIdle2.RuntimeChannelStartSample == size(x, 1) + idleSamples, ...
    "Idle-slot advancement must preserve absolute sample time before the next grant.");
assert(stateIdle.TotalIdleAdvancedSamples == idleSamples, ...
    "Runtime state must account for idle samples advanced through the fading process.");
assert(localRelativeNorm(yIdle2 - yA2) > 1e-6, ...
    "Idle advancement must affect the later channel response instead of reusing adjacent-slot state.");

didThrow = false;
try
    sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
        stateA, cfg, complex(ones(32, 2), zeros(32, 2)), txInfo, "NumTxAnt", 2, "NumRxAnt", 1);
catch ME
    didThrow = strcmp(ME.identifier, "ChannelFactory:RuntimeChannelDimensionChange");
end
assert(didThrow, ...
    "A runtime link must reject waveform-port dimension changes after channel materialization.");

% The channel-state contract is duplex-neutral.  Repeat an exact state
% creation/application under explicit TDD authority so this fixture cannot
% accidentally depend on an FDD default while the shared state machine is
% used by both profiles.
cfgTDD = cfg;
cfgTDD.phy.duplex.mode = "TDD";
stateTDD = sixgr.channel.ChannelFactory.createRuntimeChannelState( ...
    cfgTDD, "DL", ...
    "LinkKey", "dir=DL;tx=gNB1;rx=UE1;carrier=test_tdd", ...
    "Seed", 12031);
stateTDD = sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
    stateTDD, cfgTDD, x, txInfo, "NumTxAnt", 1, "NumRxAnt", 1);
[yTDD, replayTDD] = ...
    sixgr.channel.ChannelFactory.applyRuntimeChannelState(stateTDD, x);
assert(replayTDD.RuntimeChannelStateUsed && ...
    all(isfinite(real(yTDD(:)))) && all(isfinite(imag(yTDD(:)))), ...
    "Explicit TDD authority must use the same finite runtime channel path.");

ok = true;
end

function cfg = localTDLConfig()
cfg = struct();
cfg.run.seed = 17;
cfg.channel.model = "TDL";
cfg.channel.tdlProfile = "TDL-C";
cfg.channel.delaySpread_s = 30e-9;
cfg.channel.doppler_Hz = 120;
cfg.channel.channelFiltering = true;
cfg.channel.normalizePathGains = true;
cfg.phy.fc_Hz = 4.0e9;
cfg.phy.carrier.NSizeGrid = 24;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.duplex.mode = "FDD";
end

function x = localDeterministicWaveform(n, p, seed)
rs = RandStream("mt19937ar", "Seed", seed);
x = complex(randn(rs, n, p), randn(rs, n, p)) / sqrt(2);
end

function e = localRelativeNorm(x)
e = norm(double(x(:))) / max(1, sqrt(numel(x)));
end
