function ok = testMMSEUnitGainDemapperContract()
%TESTMMSEUNITGAINDEMAPPERCONTRACT Guard the MMSE-to-demapper symbol domain.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
if exist("nrSymbolModulate", "file") ~= 2 || exist("nrSymbolDemodulate", "file") ~= 2
    warning("testMMSEUnitGainDemapperContract:Missing5G", ...
        "Skipping MMSE demapper contract test because 5G Toolbox modulation APIs are unavailable.");
    ok = true;
    return;
end

localSISOConstellationAnchors();
localMIMOAnalyticAnchor();

fprintf("MMSEUnitGainDemapperContract: QPSK/64QAM/256QAM and 2x2 analytic anchors verified.\n");
ok = true;
end

function localSISOConstellationAnchors()
mods = ["QPSK", "64QAM", "256QAM"];
h = 0.8 + 0.6i;
nVar = 1;
for m = 1:numel(mods)
    q = localBitsPerSymbol(mods(m));
    bits = int8(dec2bin(0:(2^q - 1), q).' - '0');
    bits = bits(:);
    symbols = nrSymbolModulate(bits, char(mods(m)));
    deterministicNoise = 0.01 .* exp(1i .* (1:numel(symbols)).' .* 0.37);
    rx = h .* symbols + deterministicNoise;
    hest = repmat(reshape(h, 1, 1, 1), numel(symbols), 1, 1);

    [got, ~, info] = sixgr.phy.rx.mimoDetect(rx, hest, nVar, "Algorithm", "MMSE");
    expected = symbols + deterministicNoise ./ h;
    localAssertNear(got, expected, 2e-12, mods(m) + " unit-gain symbols");

    result = info.EqualizerResult;
    assert(string(result.DemapperSymbolDomain) == "unit_desired_gain", ...
        "%s must declare unit desired-gain demapper symbols.", mods(m));
    assert(double(result.DesiredResponseGainInvalidCount) == 0, ...
        "%s scalar anchor must have no invalid desired-response gains.", mods(m));

    perREdB = 10 .* log10(double(result.PostEqSINRLinear));
    [effectiveNVar, nInfo] = sixgr.phy.rx.postEqualizationNoiseVariance(nVar, ...
        "PostEqSINRPerRE_dB", perREdB);
    expectedNVar = nVar ./ abs(h).^2;
    localAssertNear(effectiveNVar, expectedNVar, 2e-12, mods(m) + " effective variance");
    assert(string(nInfo.Source) == "post_equalization_sinr_per_re", ...
        "%s effective variance must be derived from post-EQ SINR.", mods(m));

    gotLLR = nrSymbolDemodulate(got, char(mods(m)), effectiveNVar, "DecisionType", "soft");
    refLLR = nrSymbolDemodulate(expected, char(mods(m)), expectedNVar, "DecisionType", "soft");
    localAssertNear(gotLLR, refLLR, 2e-11, mods(m) + " unit-gain LLRs");

    if mods(m) ~= "QPSK"
        rawLLR = nrSymbolDemodulate(result.RawEqualizedSymbols, char(mods(m)), ...
            effectiveNVar, "DecisionType", "soft");
        assert(any(int8(rawLLR < 0) ~= int8(refLLR < 0)), ...
            "%s regression fixture must distinguish the old biased MMSE demapper input.", mods(m));
    end
end
end

function localMIMOAnalyticAnchor()
H = [1.0 + 0.1i, 0.35 - 0.2i; -0.15 + 0.25i, 0.9 - 0.05i];
nVar = 0.2;
nRE = 23;
k = (1:nRE).';
symbols = [exp(1i .* 0.17 .* k), exp(-1i .* 0.23 .* k)];
noise = 0.02 .* [exp(1i .* 0.31 .* k), exp(-1i .* 0.29 .* k)];
rx = symbols * H.' + noise;
hest = repmat(reshape(H, 1, 2, 2), nRE, 1, 1);

[got, ~, info] = sixgr.phy.rx.mimoDetect(rx, hest, nVar, "Algorithm", "MMSE");
result = info.EqualizerResult;
raw = result.RawEqualizedSymbols;
gain = result.DesiredResponseGain;
expected = raw ./ gain;
localAssertNear(got, expected, 2e-11, "2x2 unit-gain symbols");
assert(all(result.DesiredResponseGainValidMask, "all"), ...
    "2x2 analytic anchor must have valid desired-response gains.");

W = squeeze(result.W(1, :, :));
WH = W * H;
directRaw = rx * W.';
directGain = repmat(diag(WH).', nRE, 1);
localAssertNear(raw, directRaw, 2e-11, "2x2 raw W*y symbols");
localAssertNear(gain, directGain, 2e-11, "2x2 diag(W*H) gain");
end

function q = localBitsPerSymbol(modulation)
switch upper(string(modulation))
    case "QPSK"
        q = 2;
    case "64QAM"
        q = 6;
    case "256QAM"
        q = 8;
    otherwise
        error("testMMSEUnitGainDemapperContract:BadModulation", ...
            "Unsupported modulation %s.", modulation);
end
end

function localAssertNear(actual, expected, tolerance, label)
err = max(abs(double(actual(:)) - double(expected(:))), [], "omitnan");
assert(isfinite(err) && err <= tolerance, ...
    "%s mismatch %.6g exceeds tolerance %.6g.", label, err, tolerance);
end
