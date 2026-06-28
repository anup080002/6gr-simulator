function ok = pureMathAcceptance()
%PUREMATHACCEPTANCE Analytical equalizer and SINR anchors.

H0 = [1.0 0.25; -0.1 0.85];
R = [0.31 0.04; 0.04 0.22];
NRE = 16;
H = repmat(reshape(H0, 1, 2, 2), NRE, 1, 1);
rx = complex(ones(NRE, 2), zeros(NRE, 2));

[~, csi, info] = sixgr.phy.rx.equalizeMMSE(rx, H, 0.01, ...
    "Algorithm", "MMSE", "Rint", R, "RIncludesNoise", true);
res = info.EqualizerResult;

RinvH = R \ H0;
Wref = (H0' * RinvH + eye(2)) \ RinvH';
WH = Wref * H0;
Cout = Wref * R * Wref';
gamma = zeros(2, 1);
for layer = 1:2
    sig = abs(WH(layer, layer)).^2;
    inter = max(sum(abs(WH(layer, :)).^2) - sig, 0);
    gamma(layer) = sig / max(inter + real(Cout(layer, layer)), eps);
end

Wgot = squeeze(res.W(1, :, :));
assert(max(abs(Wgot(:) - Wref(:))) < 1e-10, ...
    "MMSE/IRC W must match direct linear algebra within 1e-10.");
assert(max(abs(double(res.PostEqSINRLinear(1, :)).' - gamma)) < 1e-10, ...
    "Post-EQ SINR must match direct layer SINR formula.");
assert(max(abs(double(csi(1, :)).' - gamma ./ (1 + gamma))) < 1e-12, ...
    "CSI reliability must be gamma/(1+gamma) from the same equalizer result.");

[sinrA, perA, infoA] = sixgr.phy.rx.computePostEqSINR(H, 0.01, ...
    "Method", "mmse", "Rint", R, "RIncludesNoise", true, "Layers", 2);
[sinrB, perB, infoB] = sixgr.phy.rx.computePostEqSINR(H, 0.01, ...
    "Method", "mmse", "Rint", R, "RIncludesNoise", true, "Layers", 2);
assert(isequaln(sinrA, sinrB) && max(abs(perA(:) - perB(:))) < 1e-15 && ...
    ~logical(infoA.CacheHit) && logical(infoB.CacheHit), ...
    "Post-EQ SINR cache must preserve exact numerical output for identical immutable inputs.");
ok = true;
end
