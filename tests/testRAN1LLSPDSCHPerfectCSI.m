function ok = testRAN1LLSPDSCHPerfectCSI()
%TESTRAN1LLSPDSCHPERFECTCSI Qualify the explicit DL perfect-CSI boundary.

setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
[cfg,provenance] = sixgr.lls.loadConfig( ...
    "configs/lls/pdsch_cdlc_rank2_perfect_regression.yaml");
assert(string(cfg.receiver.channelEstimation) == "perfect");
assert(string(cfg.channel.model) == "CDL-C");
assert(strlength(provenance.ConfigSHA256) == 64);

tmp = string(tempname);
mkdir(tmp);
cleanup = onCleanup(@() localCleanup(tmp)); %#ok<NASGU>
result = sixgr.lls.runLLS( ...
    "configs/lls/pdsch_cdlc_rank2_perfect_regression.yaml", ...
    "OutputRoot",tmp,"RunTag","perfect_csi","GeneratePlots",false);

trials = result.TrialTable;
assert(result.Status == "complete_valid");
assert(height(trials) == 2 && all(~trials.CRCError));
assert(all(trials.NumLayers == 2) && all(trials.NumTxPorts == 2) ...
    && all(trials.NumRxAntennas == 2));
assert(all(trials.TrueChannelGridAvailable) ...
    && all(trials.TrueChannelGridVariance > 0));
assert(all(trials.ChannelEstimateSource == ...
    "runtime_true_channel_grid_oracle"));
assert(all(trials.ChannelEstimateEngine == ...
    "ideal_true_channel_runtime_oracle"));
assert(all(contains(trials.RxProcessChain, ...
    "true_channel_oracle_precoder_projection")));
assert(all(abs(trials.MeasuredSNRdB-trials.TargetSNRdB) < 0.5));
assert(~result.TruthContractTable.UsesBLERLookupTable ...
    && ~result.TruthContractTable.UsesSyntheticBLER);

fprintf("RAN1LLSPDSCHPerfectCSI: %d exact-channel rank-2 CDL-C trials passed.\n", ...
    height(trials));
ok = true;
end

function localCleanup(path)
if exist(path,"dir") == 7
    rmdir(path,"s");
end
end
