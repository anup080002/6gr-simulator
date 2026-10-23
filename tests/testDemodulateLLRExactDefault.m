function ok = testDemodulateLLRExactDefault()
%TESTDEMODULATELLREXACTDEFAULT Ensure LLR demapping defaults to exact mode.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

[~, nrInfo] = sixgr.phy.mod.demodulateLLR([1+1i; -1-1i], "QPSK", 0.25);
assert(~logical(nrInfo.Approx), ...
    "demodulateLLR must default Approx=false so faithful LLS paths do not opt into approximate demapping.");
% Metadata alone cannot prove exact demapping; QPSK exact and max-log coincide.
% Exercise a QAM operating point where the two likelihoods actually differ.
symbols = [.12+.23i; -.6+.01i];
[exactQAM, exactNR] = sixgr.phy.mod.demodulateLLR(symbols,"16QAM",.5);
maxLogQAM = nrSymbolDemodulate(symbols,'16QAM',.5);
assert(exactNR.LLRAlgorithmApplied=="exact_log_sum_exp");
assert(max(abs(exactQAM-maxLogQAM))>.01, ...
    "An Exact label must not conceal MATLAB's max-log QAM demapper.");

if exist("qamdemod", "file") == 2
    rxSym = [0.1+0.05i; -0.25+0.2i];
    [~, exactInfo] = sixgr.phy.mod.demodulateLLR(rxSym, "1024QAM", 0.5, "Engine", "comm");
    assert(~logical(exactInfo.Approx), ...
        "Communications Toolbox demapper must default to exact qamdemod LLR mode.");

    [~, approxInfo] = sixgr.phy.mod.demodulateLLR(rxSym, "1024QAM", 0.5, ...
        "Engine", "comm", "Approx", true);
    assert(logical(approxInfo.Approx), ...
        "Approximate qamdemod LLR mode must remain explicit for approximation-labeled studies.");
end

ok = true;
end
