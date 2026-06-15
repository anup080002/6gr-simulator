function ok = testLLRMagnitudeAfterFix()
%TESTLLRMAGNITUDEAFTERFIX Verify decoder LLRs are not collapsed by noise scaling.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
rng(42, "twister");

cfg = sixgr.config.defaultConfig();
cfg.channel.model = "AWGN";
cfg.channel.snr_dB = 15;
cfg.run.noiseOperatingMode = "standalone_awgn_snr_argument";
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;

out = sixgr.link.runDLPDSCHThroughput(cfg, "NumFrames", 8, "SNR_dB", 15);
if isfield(out, "Skipped") && out.Skipped
    ok = true;
    return;
end
T = out.TrialTable;
assert(ismember("LLRMeanAbs", string(T.Properties.VariableNames)), ...
    "Trial table must export LLRMeanAbs.");
llr = double(T.LLRMeanAbs);
llr = llr(isfinite(llr));
assert(~isempty(llr), "Trial table must contain finite LLRMeanAbs values.");
assert(median(llr) > 0.05, ...
    "Median LLRMeanAbs must be >0.05 at 15 dB; got %.3g.", median(llr));

if ismember("DecoderIterations", string(T.Properties.VariableNames))
    maxIter = double(sixgr.util.structGet(cfg, "phy.ldpc.maxIterations", 50));
    decIt = double(T.DecoderIterations);
    decIt = decIt(isfinite(decIt));
    if ~isempty(decIt)
        fracMaxed = mean(decIt >= maxIter);
        assert(fracMaxed < 0.75, ...
            "Too many trials hit max LDPC iterations after noise fix: %.1f%%.", fracMaxed * 100);
    end
end

ok = true;
end
