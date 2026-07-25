function ok = testPDSCHSoftDemodulationLLRSign()
%TESTPDSCHSOFTDEMODULATIONLLRSIGN Prove the production LLR convention.

setup6GRSimToolkit("Verbose", false);
modulations = ["QPSK","16QAM","64QAM","256QAM","1024QAM"];
qmValues = [2 4 6 8 10];
checkedBits = 0;
for index = 1:numel(modulations)
    qm = qmValues(index);
    bitCount = 32 * qm;
    positions = (0:bitCount-1).';
    bits = int8(mod(positions.^2 + 3*positions + 7*index, 2));
    symbols = sixgr.pdsch.PDSCHModulator(bits, modulations(index));
    [llr, info] = sixgr.pdsch.PDSCHModulator( ...
        symbols, modulations(index), "Operation", "soft-demap", ...
        "NoiseVariance", 1e-3, "Algorithm", "log-map");
    assert(all(isfinite(llr)) && all(llr(bits == 0) > 0) ...
        && all(llr(bits == 1) < 0), ...
        "%s production LLR signs violate positive-favours-zero.", ...
        modulations(index));
    assert(string(info.LLRConvention) == "positive_favours_bit_zero");
    checkedBits = checkedBits + bitCount;
end
fprintf("PDSCH soft-demodulation LLR convention: %d bits across 5 modulations pass\n", ...
    checkedBits);
ok = true;
end
