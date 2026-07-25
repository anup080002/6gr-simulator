function ok = testPDSCHHARQCombiningGain()
%TESTPDSCHHARQCOMBININGGAIN Deterministic confidence-bounded combining gain.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
nTrials = 240;
nBits = 32;
singleSuccess = 0;
combinedSuccess = 0;
for trial = 1:nTrials
    rng(91000 + trial, "twister");
    bits = randi([0 1], nBits, 1);
    signal = 1 - 2 * bits;
    sigma = 0.70;
    llr0 = 2 * (signal + sigma * randn(nBits,1)) / sigma^2;
    llr2 = 2 * (signal + sigma * randn(nBits,1)) / sigma^2;
    singleSuccess = singleSuccess + all((llr0 < 0) == bits);

    manager = sixgr.pdsch.PDSCHHARQManager(struct("MaxProcesses", 16));
    manager.process(PDSCHPhaseTestSupport.harqObservation( ...
        "TBS", nBits, "RateRecoveredLLR", llr0, ...
        "ValidPositionMask", true(nBits,1)));
    [context, ~] = manager.process(PDSCHPhaseTestSupport.harqObservation( ...
        "TBS", nBits, "NewData", false, "RV", 2, ...
        "RateRecoveredLLR", llr2, "ValidPositionMask", true(nBits,1)));
    combined = context.toStruct().CircularBufferLLR;
    combinedSuccess = combinedSuccess + all((combined < 0) == bits);
end
[singleLow, singleHigh] = localWilson(singleSuccess, nTrials);
[combinedLow, combinedHigh] = localWilson(combinedSuccess, nTrials);
assert(combinedSuccess > singleSuccess, ...
    "Combined HARQ must improve successful packet count.");
assert(combinedLow > singleLow && combinedHigh > singleHigh, ...
    "The 95%% Wilson interval must shift upward after combining.");
assert((combinedSuccess - singleSuccess) / nTrials >= 0.25, ...
    "HARQ combining gain must improve packet success by at least 25 percentage points.");
fprintf("PDSCH HARQ gain: single=%d/%d CI=[%.3f %.3f], combined=%d/%d CI=[%.3f %.3f].\\n", ...
    singleSuccess, nTrials, singleLow, singleHigh, ...
    combinedSuccess, nTrials, combinedLow, combinedHigh);
ok = true;
end

function [low, high] = localWilson(k, n)
z = 1.95996398454005;
p = k / n;
den = 1 + z^2 / n;
center = (p + z^2/(2*n)) / den;
half = z * sqrt(p*(1-p)/n + z^2/(4*n^2)) / den;
low = max(0, center - half);
high = min(1, center + half);
end
