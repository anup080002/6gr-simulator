function ok = testSharedSlotRuntimeChannelFork()
%TESTSHAREDSLOTRUNTIMECHANNELFORK Concurrent sources must not serialize time.

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "webgui_sinr_sweep_64x4_mu_mimo_full.yaml");
scenario = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
seedCfg = sixgr.lls6g.buildInternalConfig(scenario, tempdir);
assert(double(seedCfg.channel.seed) == 104729 && ...
    string(seedCfg.channel.seedSource) == "seeds.channel_seed", ...
    "The YAML-owned physical-channel seed was not installed canonically.");
linkKey = sixgr.channel.ChannelFactory.runtimeChannelKey(seedCfg, "DL", ...
    "UEIndex", 1, "ServingCell", 1);
canonicalSeed = sixgr.channel.ChannelFactory.runtimeChannelSeed(seedCfg, linkKey);
peerPayloadCfg = seedCfg;
peerPayloadCfg.run.seed = seedCfg.run.seed + 17;
peerSeed = sixgr.channel.ChannelFactory.runtimeChannelSeed(peerPayloadCfg, linkKey);
assert(peerSeed == canonicalSeed, ...
    "A per-UE payload seed changed the canonical physical-channel realization.");

unmaterialized = sixgr.channel.ChannelFactory.emptyRuntimeChannelState();
unmaterialized.LinkKey = "dir=DL;tx=gNB1;rx=UE1;carrier=unmaterialized";
unmaterialized.Initialized = true;
localAssertThrows(@() sixgr.channel.ChannelFactory.forkRuntimeChannelState( ...
    unmaterialized), ...
    "ChannelFactory:RuntimeChannelForkBeforeMaterialization");

h = complex(zeros(3, 2, 2));
h(1,:,:) = reshape([1.0, 0.2; -0.1, 0.8], 1, 2, 2);
h(2,:,:) = reshape([0.15, -0.05; 0.07, 0.12], 1, 2, 2);
h(3,:,:) = reshape([0.02, 0.03; -0.04, 0.01], 1, 2, 2);

state = sixgr.channel.ChannelFactory.emptyRuntimeChannelState();
state.LinkKey = "dir=DL;tx=gNB1;rx=UE1;carrier=unit";
state.Direction = "DL";
state.Seed = 17;
state.Initialized = true;
state.Materialized = true;
state.UseFading = true;
state.Obj = sixgr.channel.StaticReciprocalMIMOChannel(h, 1, ...
    "SourceChannelClass", "unit_test", "SourceChannelSeed", 17, ...
    "Direction", "DL");
state.NumTxAnt = 2;
state.NumRxAnt = 2;
state.SampleRate_Hz = 1;

% Advance the absolute time origin through an idle interval.  At an OFDM
% slot boundary the prior FIR memory is zero; every concurrently launched
% source must start from this same canonical state without serializing the
% other sources ahead of it.
prefix = complex(zeros(2, 2));
[~, ~, state] = sixgr.channel.ChannelFactory.applyRuntimeChannelState(state, prefix);
canonicalIndex = state.CurrentSampleIndex;

sourceA = complex([1 2; 3 4; 5 6]);
sourceB = complex([2 -1; 0.5 3; -2 1]);
forkA = sixgr.channel.ChannelFactory.forkRuntimeChannelState(state);
forkB = sixgr.channel.ChannelFactory.forkRuntimeChannelState(state);
[yA, replayA, forkA] = sixgr.channel.ChannelFactory.applyRuntimeChannelState(forkA, sourceA); %#ok<ASGLU>
[yB, replayB, forkB] = sixgr.channel.ChannelFactory.applyRuntimeChannelState(forkB, sourceB); %#ok<ASGLU>

assert(state.CurrentSampleIndex == canonicalIndex, ...
    "Evaluating concurrent source forks advanced the canonical channel state.");
assert(replayA.RuntimeChannelStartSample == canonicalIndex && ...
    replayB.RuntimeChannelStartSample == canonicalIndex, ...
    "Concurrent source forks did not use one shared slot-start time origin.");

aggregateFork = sixgr.channel.ChannelFactory.forkRuntimeChannelState(state);
[yAggregate, replayAggregate] = sixgr.channel.ChannelFactory.applyRuntimeChannelState( ...
    aggregateFork, sourceA + sourceB);
assert(replayAggregate.RuntimeChannelStartSample == canonicalIndex, ...
    "Aggregate waveform did not use the shared slot-start time origin.");
assert(max(abs(yAggregate - (yA + yB)), [], "all") < 1e-12, ...
    "Forked per-source channel responses violate linear shared-slot superposition.");

[~, replayCanonical, stateAfter] = ...
    sixgr.channel.ChannelFactory.applyRuntimeChannelState(state, sourceA);
assert(replayCanonical.RuntimeChannelStartSample == canonicalIndex && ...
    stateAfter.CurrentSampleIndex == canonicalIndex + size(sourceA, 1), ...
    "Canonical desired-link execution did not advance exactly once.");

ok = true;
end

function localAssertThrows(fcn, expectedId)
threw = false;
try
    fcn();
catch ME
    threw = true;
    assert(string(ME.identifier) == string(expectedId), ...
        "Expected %s but observed %s.", expectedId, ME.identifier);
end
assert(threw, "Expected %s to be thrown.", expectedId);
end
