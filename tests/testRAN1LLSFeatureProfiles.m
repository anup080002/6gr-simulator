function ok = testRAN1LLSFeatureProfiles()
%TESTRAN1LLSFEATUREPROFILES Exercise non-baseline waveform capabilities.

setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
tmp = string(tempname);
mkdir(tmp);
cleanup = onCleanup(@() localCleanup(tmp)); %#ok<NASGU>

ul = sixgr.lls.runLLS( ...
    "configs/lls/pusch_dfts_ofdm_64qam_ptrs_regression.yaml", ...
    "OutputRoot",tmp,"RunTag","ul_dfts_ptrs","GeneratePlots",false);
assert(ul.Status == "complete_valid" && all(~ul.TrialTable.CRCError));
assert(all(ul.TrialTable.ModulationOrder == 6));
assert(all(ul.TrialTable.PTRSRE > 0));
assert(contains(string(ul.AssumptionsTable.Waveform),"DFT-s-OFDM"));
assert(logical(ul.AssumptionsTable.PTRSEnabled));

dl = sixgr.lls.runLLS( ...
    "configs/lls/pdsch_cdlc_rank4_256qam_ptrs_regression.yaml", ...
    "OutputRoot",tmp,"RunTag","dl_rank4_ptrs","GeneratePlots",false);
assert(dl.Status == "complete_valid" && all(~dl.TrialTable.CRCError));
assert(all(dl.TrialTable.ModulationOrder == 8));
assert(all(dl.TrialTable.NumLayers == 4));
assert(all(dl.TrialTable.PTRSRE > 0));
assert(all(dl.TrialTable.ChannelEstimateEngine == ...
    "ideal_true_channel_runtime_oracle"));
assert(all(dl.TrialTable.ChannelTransmissionDirection == "Downlink"));

fprintf("RAN1LLSFeatureProfiles: DFT-s-OFDM/PT-RS UL and rank-4 256QAM/PT-RS DL passed.\n");
ok = true;
end

function localCleanup(path)
if exist(path,"dir") == 7
    rmdir(path,"s");
end
end
