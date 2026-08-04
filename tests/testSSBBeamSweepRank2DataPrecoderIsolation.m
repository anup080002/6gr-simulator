function ok = testSSBBeamSweepRank2DataPrecoderIsolation()
%TESTSSBBEAMSWEEPRANK2DATAPRECODERISOLATION Keep SI and data grants separate.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
scenario = sixgr.lls6g.config.loadScenarioConfig(fullfile(pwd, ...
    "simulator", "configs", "scenarios", ...
    "webgui_sinr_sweep_64x4_mu_mimo_full.yaml"));
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@() localCleanup(tmp)); %#ok<NASGU>
cfg = sixgr.lls6g.buildInternalConfig(scenario, tmp);

assert(double(sixgr.util.structGet(cfg, "phy.pdsch.numLayers", NaN)) == 2, ...
    "Regression precondition requires target data-PDSCH rank 2.");
% CoupledTruthRuntime freezes this exact-shaped immutable matrix when the
% rank-2 DL grant is materialized.  Reproduce the persisted post-runtime
% configuration passed to bundle finalization.
cfg = sixgr.util.structSet(cfg, "phy.pdsch.precoding.matrix", eye(2));
cfg = sixgr.util.structSet(cfg, "phy.pdsch.precodingMatrix", eye(2));
cfg = sixgr.util.structSet(cfg, "phy.pdsch.W", eye(2));

% SIB1 is SI-RNTI common PDSCH and is independently materialized as a
% single-layer broadcast allocation.  A data-grant matrix must neither be
% reshaped nor silently reused at this procedure boundary.
cfg = sixgr.util.structSet(cfg, "channel.snr_dB", 20);
out = sixgr.link.runSSBBeamSweep(cfg, ...
    "SNR_dB", 20, "NumSubframes", 5, "MaxBeams", 1);
assert(istable(out.TrialTable) && height(out.TrialTable) == 1, ...
    "Focused SSB beam sweep did not produce its measured trial row.");
assert(~logical(out.TrialTable.Crash(1)), ...
    "SIB1 broadcast context inherited the rank-2 data-PDSCH precoder: %s", ...
    string(out.TrialTable.FailureReason(1)));
assert(logical(out.TrialTable.BCHCrcPass(1)) && ...
    logical(out.TrialTable.MIBDecoded(1)) && ...
    logical(out.TrialTable.SIB1StrictOk(1)), ...
    "Focused SSB/PBCH/MIB/SIB1 waveform acquisition did not pass.");
ok = true;
end

function localCleanup(pathText)
if isfolder(pathText)
    rmdir(pathText, "s");
end
end
