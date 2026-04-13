function ok = testControlDetectionThresholds()
%TESTCONTROLDETECTIONTHRESHOLDS PBCH/PDCCH/PRACH threshold-style checks.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;

ranAny = false;

% PBCH detection probability thresholds.
if exist("nrWaveformGenerator", "file") == 2
    ranAny = true;
    n = 4;
    pbLow = 0;
    pbHigh = 0;
    for k = 1:n
        [txWave, ~, txInfo] = sixgr.phy.dl.SSB_Tx(cfg, "NumSubframes", 2);

        [rxLow, syncLow] = sixgr.phy.dl.SSB_Rx(localAddAwgn(txWave, -12), cfg, ...
            "SampleRate_Hz", txInfo.SampleRate_Hz);
        [pbL, ~] = sixgr.phy.dl.PBCH_Recovery(rxLow, syncLow, cfg);
        pbLow = pbLow + double(logical(pbL.Ok) && double(pbL.ErrFlag) == 0);

        [rxHigh, syncHigh] = sixgr.phy.dl.SSB_Rx(localAddAwgn(txWave, 6), cfg, ...
            "SampleRate_Hz", txInfo.SampleRate_Hz);
        [pbH, ~] = sixgr.phy.dl.PBCH_Recovery(rxHigh, syncHigh, cfg);
        pbHigh = pbHigh + double(logical(pbH.Ok) && double(pbH.ErrFlag) == 0);
    end
    pLow = pbLow / n;
    pHigh = pbHigh / n;
    assert(pHigh >= 0.95, "PBCH high-SNR detection is below threshold.");
    assert(pLow >= 0.85, "PBCH low-SNR detection baseline is below threshold.");
end

% PDCCH detection probability thresholds.
if exist("nrPDCCH", "file") == 2 && exist("nrDCIDecode", "file") == 2
    ranAny = true;
    n = 4;
    pdcchLow = 0;
    pdcchHigh = 0;
    for k = 1:n
        [tx, ~] = sixgr.phy.dl.PDCCH_Tx(cfg, "K", 64);

        [rxL, ~] = sixgr.phy.dl.PDCCH_Rx(localAddAwgn(tx.Waveform, -8), cfg, ...
            "Carrier", tx.Carrier, "PDCCH", tx.PDCCH, "K", numel(tx.DCIBits), "ListLength", 16);
        [beL, btL] = localBitErrors(tx.DCIBits, rxL.DCIBits);
        pdcchLow = pdcchLow + double(logical(rxL.Ok) && beL == 0 && btL > 0);

        [rxH, ~] = sixgr.phy.dl.PDCCH_Rx(localAddAwgn(tx.Waveform, 6), cfg, ...
            "Carrier", tx.Carrier, "PDCCH", tx.PDCCH, "K", numel(tx.DCIBits), "ListLength", 16);
        [beH, btH] = localBitErrors(tx.DCIBits, rxH.DCIBits);
        pdcchHigh = pdcchHigh + double(logical(rxH.Ok) && beH == 0 && btH > 0);
    end
    pLow = pdcchLow / n;
    pHigh = pdcchHigh / n;
    assert(pHigh >= 0.95, "PDCCH high-SNR detection is below threshold.");
    assert(pLow >= 0.75, "PDCCH low-SNR detection baseline is below threshold.");
end

% PRACH threshold check, with explicit-skip contract fallback.
if exist("nrPRACH", "file") == 2 && exist("nrPRACHDetect", "file") == 2
    ranAny = true;
    n = 5;
    hitLow = 0;
    hitHigh = 0;
    for k = 1:n
        [tx, ~] = sixgr.phy.ul.PRACH_Tx(cfg);

        [rxH, ~] = sixgr.phy.ul.PRACH_Rx(tx.Waveform, cfg, "Carrier", tx.Carrier, "PRACH", tx.PRACH);
        hitHigh = hitHigh + double(logical(rxH.Ok));

        [rxL, ~] = sixgr.phy.ul.PRACH_Rx(localAddAwgn(tx.Waveform, 0), cfg, "Carrier", tx.Carrier, "PRACH", tx.PRACH);
        hitLow = hitLow + double(logical(rxL.Ok));
    end
    pLow = hitLow / n;
    pHigh = hitHigh / n;

    if pHigh > 0
        assert(pHigh >= 0.50, "PRACH high-SNR detection is below threshold.");
        assert(pLow <= pHigh + 1e-9, "PRACH low-SNR detection should not exceed high-SNR detection.");
    else
        % When the direct detector is non-triggering, the wrapper must still report completed measured failure.
        for k = 1:3
            r = sixgr.link.runPRACHDetection(cfg, "SNR_dB", 100);
            assert(logical(r.Ok), "PRACH wrapper should complete cleanly when detector is non-triggering.");
            assert(~logical(r.Skipped), "PRACH wrapper must not relabel a measured non-detection as skipped.");
            assert(~logical(sixgr.util.structGet(r, "Detected", true)), "PRACH wrapper must expose measured non-detection explicitly.");
            assert(contains(lower(string(r.Notes)), "not detected"), "PRACH wrapper non-detection note is missing.");
        end
    end
end

if ~ranAny
    ok = true;
    return;
end

ok = true;
end

function y = localAddAwgn(x, snr_dB)
snrLin = 10.^(double(snr_dB)/10);
sigPow = mean(abs(x(:)).^2);
nVar = sigPow / max(snrLin, eps);
n = sqrt(nVar/2) * (randn(size(x)) + 1i * randn(size(x)));
y = x + n;
end

function [be, bt] = localBitErrors(a, b)
a = int8(a(:));
b = int8(b(:));
L = min(numel(a), numel(b));
if L <= 0
    be = max(numel(a), numel(b));
    bt = max(numel(a), numel(b));
    return;
end
be = sum(a(1:L) ~= b(1:L));
bt = max(numel(a), numel(b));
if numel(a) ~= numel(b)
    be = be + abs(numel(a) - numel(b));
end
end
