function ok = testTruthValidationControlCoverage()
%TESTTRUTHVALIDATIONCONTROLCOVERAGE Strict truth validation config must keep control cases executable.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg = sixgr.truth.prepareValidationConfig(cfg, struct("SaveFigures", false, "LinkSNR_dB", 30));

assert(double(cfg.phy.carrier.NSizeGrid) >= 48, ...
    "Truth validation config must allocate enough carrier bandwidth for the default PDCCH BWP.");

[tx, ~] = sixgr.phy.dl.PDCCH_Tx(cfg, "K", 64);
[rxWave, nVar] = localAddAwgn(tx.Waveform, 30);
[rx, ~] = sixgr.phy.dl.PDCCH_Rx(rxWave, cfg, ...
    "Carrier", tx.Carrier, "PDCCH", tx.PDCCH, "K", numel(tx.DCIBits), ...
    "ListLength", 16, "NoiseVar", nVar);
[be, bt] = localBitErrors(tx.DCIBits, rx.DCIBits);
assert(logical(rx.Ok) && be == 0 && bt > 0, ...
    "Truth validation PDCCH control case must decode cleanly without crashes.");

prach = sixgr.link.runPRACHDetection(cfg, "SNR_dB", 100);
assert(logical(prach.Ok), "Truth validation PRACH case must complete cleanly.");
assert(~logical(prach.Skipped), "Truth validation PRACH case must not be reported as skipped.");
assert(logical(sixgr.util.structGet(prach, "Detected", false)), ...
    "Truth validation PRACH case must produce a real detection at high SNR.");

ok = true;
end

function [y, nVar] = localAddAwgn(x, snr_dB)
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
