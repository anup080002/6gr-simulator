function ok = testDemodulateLLRExactDefault()
%TESTDEMODULATELLREXACTDEFAULT Ensure LLR demapping defaults to exact mode.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);

[~, nrInfo] = sixgr.phy.mod.demodulateLLR([1+1i; -1-1i], "QPSK", 0.25);
assert(~logical(nrInfo.Approx), ...
    "demodulateLLR must default Approx=false so faithful LLS paths do not opt into approximate demapping.");

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
