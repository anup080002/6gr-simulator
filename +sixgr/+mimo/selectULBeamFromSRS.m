function [W_UL, beamIdx, beamHit, gainGap_dB, info] = selectULBeamFromSRS(~, ~, H_SRS, bestBeamIdx_oracle, mimoCfg)
%SELECTULBEAMFROMSRS Select a UL precoder/beam from measured SRS channel.
%
% Oracle beam input is used only to score beamHit/gainGap_dB for evidence.

if nargin < 4 || isempty(bestBeamIdx_oracle)
    bestBeamIdx_oracle = NaN;
end
if nargin < 5 || ~isstruct(mimoCfg)
    mimoCfg = struct();
end
H = localWideband(H_SRS);
if isempty(H)
    error("sixgr:mimo:selectULBeamFromSRS:EmptyChannel", ...
        "UL beam selection requires a non-empty SRS channel estimate.");
end
nUEPorts = size(H, 2);
maxRank = max(1, round(double(sixgr.util.structGet(mimoCfg, "MaxRank", min(2, size(H, 1))))));
maxRank = min([maxRank, size(H, 1), nUEPorts]);

[~, ~, V] = svd(double(H), "econ");
rankValue = localSelectRank(H, maxRank, mimoCfg);
W_UL = V(:, 1:rankValue);

numBeams = max(2 * nUEPorts, double(sixgr.util.structGet(mimoCfg, "ULBeamCount", 2 * nUEPorts)));
codebook = localDFTCodebook(nUEPorts, numBeams);
gains = sum(abs(H * codebook).^2, 1);
[bestGain, bestIdx] = max(gains);
selectedGain = norm(H * W_UL, "fro")^2;
beamIdx = double(bestIdx - 1);

beamHit = NaN;
gainGap_dB = NaN;
if isfinite(double(bestBeamIdx_oracle)) && double(bestBeamIdx_oracle) >= 0
    oracleIdx = min(max(1, round(double(bestBeamIdx_oracle)) + 1), size(codebook, 2));
    oracleGain = sum(abs(H * codebook(:, oracleIdx)).^2, "all");
    beamHit = logical(beamIdx == round(double(bestBeamIdx_oracle)));
    gainGap_dB = 10 * log10(max(oracleGain, realmin)) - 10 * log10(max(selectedGain, realmin));
else
    gainGap_dB = 10 * log10(max(bestGain, realmin)) - 10 * log10(max(selectedGain, realmin));
end

info = struct();
info.RI = double(rankValue);
info.NumUEPorts = double(nUEPorts);
info.NumGNBPorts = double(size(H, 1));
info.SelectedBeamIndex = double(beamIdx);
info.SelectedBeamGain_dB = 10 * log10(max(selectedGain, realmin));
info.BestDFTBeamIndex = double(bestIdx - 1);
info.BestDFTBeamGain_dB = 10 * log10(max(bestGain, realmin));
info.BeamHit = beamHit;
info.BeamGainGap_dB = double(gainGap_dB);
info.RuntimeEvidenceSource = "svd_of_srs_measured_channel";
end

function H = localWideband(Hin)
H = [];
if isempty(Hin)
    return;
end
if ismatrix(Hin)
    H = double(Hin);
elseif ndims(Hin) == 3
    H = mean(double(Hin), 3, "omitnan");
elseif ndims(Hin) >= 4
    H = squeeze(mean(mean(double(Hin), 1, "omitnan"), 2, "omitnan"));
end
if isvector(H)
    H = reshape(H(:), numel(H), 1);
end
if ~ismatrix(H)
    H = [];
end
end

function rankValue = localSelectRank(H, maxRank, cfg)
noiseVar = double(sixgr.util.structGet(cfg, "NoiseVar", NaN));
if ~(isfinite(noiseVar) && noiseVar > 0)
    snr_dB = double(sixgr.util.structGet(cfg, "SNR_configured_dB", 12));
    noiseVar = 1 / max(10.^(snr_dB / 10), realmin);
end
decision = sixgr.mimo.resolveNominalVsEffectiveMIMO([], [], H, noiseVar, maxRank, cfg);
rankValue = max(1, min(maxRank, round(double(decision.EffectiveRank))));
end

function W = localDFTCodebook(nPorts, nBeams)
nPorts = max(1, round(double(nPorts)));
nBeams = max(1, round(double(nBeams)));
idx = (0:nPorts-1).';
W = complex(zeros(nPorts, nBeams));
for b = 0:nBeams-1
    w = exp(1i * 2 * pi * b .* idx ./ nBeams);
    W(:, b + 1) = w ./ max(norm(w), realmin);
end
end
