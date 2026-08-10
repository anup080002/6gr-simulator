function ok = testRAN1LLSDopplerComparison()
%TESTRAN1LLSDOPPLERCOMPARISON Verify paired low/high-Doppler PHY execution.

setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
tmp = string(tempname);
mkdir(tmp);
cleanup = onCleanup(@()localCleanup(tmp)); %#ok<NASGU>
low = sixgr.lls.runLLS("configs/lls/pusch_cdlc_low_doppler_regression.yaml", ...
    "OutputRoot",tmp,"RunTag","low","GeneratePlots",false);
high = sixgr.lls.runLLS("configs/lls/pusch_cdlc_high_doppler_regression.yaml", ...
    "OutputRoot",tmp,"RunTag","high","GeneratePlots",false);

c = 299792458;
expectedLow = (low.Config.channel.velocityKmph/3.6)*low.Config.carrier.frequencyHz/c;
expectedHigh = (high.Config.channel.velocityKmph/3.6)*high.Config.carrier.frequencyHz/c;
assert(all(abs(low.TrialTable.MaximumDopplerHz-expectedLow) < 1e-10));
assert(all(abs(high.TrialTable.MaximumDopplerHz-expectedHigh) < 1e-10));
assert(all(low.TrialTable.ChannelModel == "CDL-C") && ...
    all(high.TrialTable.ChannelModel == "CDL-C"));
assert(all(low.TrialTable.ChannelEstimateEngine == "nrChannelEstimate") && ...
    all(high.TrialTable.ChannelEstimateEngine == "nrChannelEstimate"));
assert(all(low.TrialTable.TrueChannelGridAvailable) && ...
    all(high.TrialTable.TrueChannelGridAvailable));
assert(any(low.TrialTable.TrueChannelGridSHA256 ~= high.TrialTable.TrueChannelGridSHA256), ...
    "Changing only velocity must alter at least one exact runtime fading grid.");
fprintf("RAN1LLSDopplerComparison: %.6f Hz vs %.6f Hz, actual CDL-C waveforms.\n", ...
    expectedLow,expectedHigh);
ok = true;
end

function localCleanup(path)
if exist(path,"dir") == 7
    rmdir(path,"s");
end
end
