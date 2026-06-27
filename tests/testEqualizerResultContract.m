function ok = testEqualizerResultContract()
%TESTEQUALIZERRESULTCONTRACT Validate unified MMSE/IRC EqualizerResult math.

setup6GRSimToolkit("Verbose", false);

localSISOAnchor();
localMIMOAnchor(2);
localMIMOAnchor(4);
localIRCNoiseIncludedAnchor();
localBadConditioningAnchor();
localPostEqReuseAnchor();

ok = true;
end

function localSISOAnchor()
rx = ones(32, 1);
H = repmat(reshape(1, 1, 1, 1), 32, 1, 1);
[eq, csi, info] = sixgr.phy.rx.equalizeMMSE(rx, H, 0.5, "Algorithm", "MMSE");
res = info.EqualizerResult;
Wref = 1 / 1.5;
assert(max(abs(squeeze(res.W(:, 1, 1)) - Wref)) < 1e-12, ...
    "SISO W must match h*/(|h|^2+nVar).");
assert(max(abs(eq(:) - Wref)) < 1e-12, "SISO equalized symbols must use EqualizerResult W.");
assert(max(abs(csi(:) - 2/3)) < 1e-12, ...
    "SISO demapper reliability must be gamma/(1+gamma) with gamma=2.");
assert(max(abs(res.PostEqSINRLinear(:) - 2)) < 1e-12, ...
    "SISO post-EQ SINR must be |WH|^2/(WRW^H).");
end

function localMIMOAnchor(n)
rng(1700 + n, "twister");
H0 = randn(n, n) + 1j * randn(n, n);
R = diag(0.2 + (1:n) ./ 10);
NRE = 64;
H = repmat(reshape(H0, 1, n, n), NRE, 1, 1);
rx = complex(randn(NRE, n), randn(NRE, n));

[~, csiMMSE, infoMMSE] = sixgr.phy.rx.mimoDetect(rx, H, 0.1, "Algorithm", "MMSE", "Rint", R, "RIncludesNoise", true);
[Wref, gammaRef, relRef, interRef, CoutRef] = localDirectMMSE(H0, R);
res = infoMMSE.EqualizerResult;
Wgot = squeeze(res.W(1, :, :));
assert(max(abs(Wgot(:) - Wref(:))) < 1e-10, sprintf("%dx%d MMSE W mismatch.", n, n));
assert(max(abs(res.PostEqSINRLinear(1, :).' - gammaRef)) < 1e-10, ...
    sprintf("%dx%d SINR mismatch.", n, n));
assert(max(abs(csiMMSE(1, :).' - relRef)) < 1e-12, ...
    "CSI must be the EqualizerResult demapper reliability.");
assert(max(abs(res.ResidualInterLayerPower(1, :).' - interRef)) < 1e-12, ...
    "Residual inter-layer power must be included per layer.");
assert(max(abs(squeeze(res.OutputNoiseInterferenceCovariance(1, :, :)) - CoutRef), [], "all") < 1e-10, ...
    "Output covariance must be W*R*W^H.");
assert(double(res.UniqueSolveCount) == 1 && logical(res.StaticChannelBatchApplied), ...
    "Repeated static channel/covariance must solve once and batch across REs.");
end

function localIRCNoiseIncludedAnchor()
H0 = [1 0.25; -0.1 0.9];
Rtotal = [0.50 0.07; 0.07 0.40];
H = repmat(reshape(H0, 1, 2, 2), 8, 1, 1);
rx = ones(8, 2);
[~, ~, info] = sixgr.phy.rx.mimoDetect(rx, H, 0.1, ...
    "Algorithm", "IRC", "Rint", Rtotal, "RIncludesNoise", true);
[Wref, gammaRef] = localDirectMMSE(H0, Rtotal);
res = info.EqualizerResult;
assert(max(abs(squeeze(res.W(1, :, :)) - Wref), [], "all") < 1e-10, ...
    "IRC must treat provided Rint as noise-included when declared.");
assert(max(abs(res.PostEqSINRLinear(1, :).' - gammaRef)) < 1e-10, ...
    "IRC SINR must not double-add nVar to a noise-included covariance.");
assert(logical(res.CovarianceIncludesNoise) && logical(res.NoiseAddedExactlyOnce), ...
    "EqualizerResult must declare the covariance/noise convention.");
end

function localBadConditioningAnchor()
H0 = [1 1; 1 1 + 1e-13];
H = repmat(reshape(H0, 1, 2, 2), 4, 1, 1);
rx = ones(4, 2);
[eq, csi, info] = sixgr.phy.rx.mimoDetect(rx, H, 1e-10, "Algorithm", "ZF");
assert(all(isfinite(real(eq(:)))) && all(isfinite(double(csi(:)))), ...
    "Badly conditioned equalizer must return finite symbols and CSI.");
assert(logical(info.EqualizerResult.RegularizationApplied), ...
    "Badly conditioned channel must disclose controlled regularization.");
end

function localPostEqReuseAnchor()
H0 = [1 0.6; 0.4 1];
H = repmat(reshape(H0, 1, 2, 2), 128, 1, 1);
rx = complex(ones(128, 2), zeros(128, 2));
[~, csi, detectInfo] = sixgr.phy.rx.mimoDetect(rx, H, 0.1, "Algorithm", "MMSE");
[sinr_dB, perRE, sinrInfo] = sixgr.phy.rx.computePostEqSINR(H, 0.1, ...
    "Method", "mmse", "Layers", 2, "EqualizerResult", detectInfo.EqualizerResult);
gamma = detectInfo.EqualizerResult.PostEqSINRLinear;
assert(max(abs(perRE(:) - 10 .* log10(gamma(:)))) < 1e-12, ...
    "computePostEqSINR must reuse EqualizerResult per-RE SINR.");
assert(strcmp(string(sinrInfo.EqualizerResultSource), "supplied_by_mimoDetect"), ...
    "computePostEqSINR must disclose supplied EqualizerResult reuse.");
assert(double(sinrInfo.EqualizerUniqueSolveCount) == 1, ...
    "Repeated channel performance path must reduce unique solves to one.");
assert(any(detectInfo.EqualizerResult.ResidualInterLayerPower(:) > 0), ...
    "Inter-layer interference must be nonzero for the coupled 2x2 anchor.");
assert(max(abs(csi(:) - gamma(:) ./ (1 + gamma(:)))) < 1e-12, ...
    "CSI weights must be the same-domain reliability derived from post-EQ SINR.");
assert(isfinite(double(sinr_dB)), "Wideband post-EQ SINR must be finite.");
end

function [W, gamma, rel, interLayer, Cout] = localDirectMMSE(H, R)
R = (R + R') ./ 2;
RinvH = R \ H;
W = (H' * RinvH + eye(size(H, 2))) \ RinvH';
WH = W * H;
Cout = W * R * W';
n = size(H, 2);
gamma = NaN(n, 1);
rel = NaN(n, 1);
interLayer = NaN(n, 1);
for ii = 1:n
    sig = abs(WH(ii, ii)).^2;
    interLayer(ii) = max(sum(abs(WH(ii, :)).^2) - sig, 0);
    gamma(ii) = sig / max(interLayer(ii) + real(Cout(ii, ii)), eps);
    rel(ii) = gamma(ii) / max(1 + gamma(ii), eps);
end
end
