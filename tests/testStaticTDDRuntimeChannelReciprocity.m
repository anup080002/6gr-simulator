function ok = testStaticTDDRuntimeChannelReciprocity()
%TESTSTATICTDDRUNTIMECHANNELRECIPROCITY Exact UL/DL transpose and seed binding.

setup6GRSimToolkit("Verbose",false);
if exist("nrCDLChannel","class") ~= 8
    warning("testStaticTDDRuntimeChannelReciprocity:Missing5G", ...
        "nrCDLChannel is unavailable; skipping reciprocal CDL test.");
    ok = true;
    return;
end

cfg = sixgr.config.defaultConfig();
cfg.run.seed = 104729;
cfg.channel.seed = 104729;
cfg.channel.model = "CDL-C";
cfg.channel.cdlProfile = "CDL-C";
cfg.channel.delayProfile = "CDL-C";
cfg.channel.fading.model = "CDL";
cfg.channel.fading.profile = "CDL-C";
cfg.channel.delaySpread_s = 30e-9;
cfg.channel.doppler_Hz = 0;
cfg.channel.channelFiltering = true;
cfg.channel.normalizePathGains = true;
cfg.phy.fc_Hz = 3.5e9;
cfg.phy.carrier.NSizeGrid = 24;
cfg.phy.carrier.SubcarrierSpacing = 30;
cfg.phy.duplex.mode = "TDD";
cfg.lls6g.mimo.reciprocity_mode = "TDD";
cfg.lls6g.reference_signals.operation_orientation = "tdd_reciprocity";

dlKey = sixgr.channel.ChannelFactory.runtimeChannelKey(cfg,"DL", ...
    "UEIndex",1,"ServingCell",1);
ulKey = sixgr.channel.ChannelFactory.runtimeChannelKey(cfg,"UL", ...
    "UEIndex",1,"ServingCell",1);
dlSeed = sixgr.channel.ChannelFactory.runtimeChannelSeed(cfg,dlKey);
ulSeed = sixgr.channel.ChannelFactory.runtimeChannelSeed(cfg,ulKey);
assert(dlSeed == ulSeed, ...
    "TDD reciprocal endpoints must share one canonical link seed.");
assert(sixgr.channel.ChannelFactory.supportsRuntimeTDDReciprocity(cfg), ...
    "Static TDD CDL configuration must select the exact reciprocal adapter.");

fs = 7.68e6;
txInfo = struct("OFDM",struct("SampleRate",fs));
dl = sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,"DL", ...
    "LinkKey",dlKey,"Seed",dlSeed,"UEIndex",1,"ServingCell",1);
ul = sixgr.channel.ChannelFactory.createRuntimeChannelState(cfg,"UL", ...
    "LinkKey",ulKey,"Seed",ulSeed,"UEIndex",1,"ServingCell",1);
dl = sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
    dl,cfg,complex(zeros(128,4)),txInfo,"NumTxAnt",4,"NumRxAnt",2);
ul = sixgr.channel.ChannelFactory.materializeRuntimeChannelState( ...
    ul,cfg,complex(zeros(128,2)),txInfo,"NumTxAnt",2,"NumRxAnt",4);

assert(isa(dl.Obj,"sixgr.channel.StaticReciprocalMIMOChannel") && ...
    isa(ul.Obj,"sixgr.channel.StaticReciprocalMIMOChannel"), ...
    "Both static TDD directions must use reciprocal runtime endpoints.");
hDL = double(dl.Obj.ImpulseResponse);
hUL = double(ul.Obj.ImpulseResponse);
expectedUL = permute(hDL,[1 3 2]);
relativeError = norm(hUL(:)-expectedUL(:)) / max(norm(expectedUL(:)),eps);
assert(relativeError <= 1e-12, ...
    "UL impulse response must equal the exact nonconjugate transpose of DL (error %.3g).", ...
    relativeError);
assert(logical(dl.Meta.RuntimeTDDReciprocityExact) && ...
    logical(ul.Meta.RuntimeTDDReciprocityExact), ...
    "Runtime metadata must disclose exact TDD reciprocity.");
assert(string(dl.Meta.RuntimeTDDReciprocityApproximationMode) == ...
    "none_static_lti_exact", ...
    "Exact sampled CDL impulse truth must not be labeled as a proxy.");

% Causal SRS and its later PUSCH must acquire one shared UL runtime state,
% rather than materializing two channels with unrelated CDL realizations.
cfg.phy.srs.enable = true;
cfg.phy.srs.nPorts = 2;
cfg.phy.srs.period_slots = 4;
cfg.scenario.ue.nTxAnt = 2;
cfg.scenario.bs.nRxAnt = 4;
cfg.channel.ul.nTxAnt = 2;
cfg.channel.ul.nRxAnt = 4;
cfg.phy.ul.nTxAnt = 2;
cfg.phy.ul.nRxAnt = 4;
cfg.run.noiseOperatingMode = "standalone_awgn_snr_argument";
runtime = struct( ...
    "CurrentServingIdx", 1, ...
    "CurrentSlot", 3, ...
    "CurrentFrame", 0, ...
    "SlotDuration_s", sixgr.time.slotDurationSec(cfg), ...
    "RuntimeChannelStates", repmat( ...
    sixgr.channel.ChannelFactory.emptyRuntimeChannelState(), 0, 1));
[runtime, srsState] = ...
    sixgr.truth.CoupledTruthRuntime.acquireRuntimeChannelStateForControl( ...
    runtime, cfg, 1, "UL");
srsOut = sixgr.link.runSRSChannelEstimation(cfg, ...
    "SNR_dB", 30, "SlotIndex", 3, "ChannelState", srsState);
srsState = srsOut.ChannelState;
assert(isstruct(srsState) && isfield(srsState, "ContractVersion") && ...
    logical(srsState.Materialized) && string(srsState.LinkKey) == string(ulKey), ...
    "SRS must materialize the canonical UL ChannelFactory state for the UE link.");
assert(double(srsState.NumTxAnt) == 2 && double(srsState.NumRxAnt) == 4, ...
    "Focused SRS runtime state must retain the configured 2x4 UL channel dimensions.");
runtime = sixgr.truth.CoupledTruthRuntime.commitRuntimeChannelState(runtime, srsState);
[runtime, puschState] = ...
    sixgr.truth.CoupledTruthRuntime.acquireRuntimeChannelStateForControl( ...
    runtime, cfg, 1, "UL"); %#ok<ASGLU>
assert(string(puschState.LinkKey) == string(srsState.LinkKey) && ...
    double(puschState.Seed) == double(srsState.Seed) && ...
    double(puschState.ResetCount) == double(srsState.ResetCount) && ...
    double(puschState.CurrentSampleIndex) == double(srsState.CurrentSampleIndex), ...
    "PUSCH acquisition must recover the exact state advanced by causal SRS.");

% A trailing singleton Tx dimension is represented as a 2-D array by
% MATLAB. It remains a valid L-by-NRx-by-1 MIMO FIR and is required by
% single-port PRACH/SRS/PUCCH runtime endpoints.
hSingleTx = complex(reshape(1:(3*64),3,64), ...
    reshape((3*64):-1:1,3,64)) ./ 100;
singleTxEndpoint = sixgr.channel.StaticReciprocalMIMOChannel( ...
    hSingleTx,fs,"Direction","UL");
assert(singleTxEndpoint.NumTransmitAntennas == 1 && ...
    singleTxEndpoint.NumReceiveAntennas == 64, ...
    "A trailing singleton Tx dimension must resolve as 1x64 UL MIMO.");
x = complex(zeros(16,1));
x(1) = 1;
[y,applied] = singleTxEndpoint(x);
assert(isequal(size(y),[16 64]) && ...
    isequal(size(applied,1),3) && size(applied,2) == 64 && ...
    size(applied,3) == 1 && norm(y(:)) > 0, ...
    "The single-port reciprocal endpoint must apply its nonzero impulse response.");

% Persist a locked endpoint with nonzero FIR memory and prove that the
% deserialized object continues from the identical physical channel state.
tmpFile = string(tempname) + ".mat";
cleanupFile = onCleanup(@()localDeleteFile(tmpFile)); %#ok<NASGU>
save(char(tmpFile), "singleTxEndpoint");
loaded = load(char(tmpFile), "singleTxEndpoint");
restoredEndpoint = loaded.singleTxEndpoint;
continuation = complex((1:9).', (9:-1:1).') ./ 13;
[expectedContinuation, expectedImpulse] = singleTxEndpoint(continuation);
[actualContinuation, actualImpulse] = restoredEndpoint(continuation);
assert(isequal(expectedImpulse, actualImpulse) && ...
    norm(expectedContinuation(:) - actualContinuation(:)) <= ...
        1e-13 * max(norm(expectedContinuation(:)), 1), ...
    "Locked reciprocal-channel serialization must preserve the exact FIR continuation state.");

ok = true;
end

function localDeleteFile(pathValue)
pathValue = char(string(pathValue));
if isfile(pathValue)
    delete(pathValue);
end
end
