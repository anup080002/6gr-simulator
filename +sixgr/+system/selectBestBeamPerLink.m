function [beamIdx, beamGain_dB] = selectBestBeamPerLink(uePos, bsPos, bsAzim_deg, nBeams, spanDeg, maxGain_dB)
% sixgr.system.selectBestBeamPerLink
% Select the strongest beam per UE-to-cell link.

K = size(uePos, 1);
B = size(bsPos, 1);
beamIdx = ones(K, B);
beamGain_dB = zeros(K, B);

nBeams = max(1, round(double(nBeams)));
spanDeg = max(30, min(240, double(spanDeg)));
maxGain_dB = double(maxGain_dB);

if nBeams == 1
    beamOffsets = 0;
else
    beamOffsets = linspace(-0.5 * spanDeg, 0.5 * spanDeg, nBeams);
end
beamBW = max(spanDeg / max(nBeams, 1), 5);
for b = 1:B
    dx = uePos(:,1) - bsPos(b,1);
    dy = uePos(:,2) - bsPos(b,2);
    linkAz = atan2d(dy, dx);
    beamCenters = double(bsAzim_deg(b)) + beamOffsets;
    delta = abs(localWrapTo180(linkAz - reshape(beamCenters, 1, [])));
    atten_dB = min(30, 12 .* (delta ./ beamBW).^2);
    [bestAtten, idx] = min(atten_dB, [], 2);
    beamIdx(:, b) = idx;
    beamGain_dB(:, b) = maxGain_dB - bestAtten;
end
end

function y = localWrapTo180(x)
y = mod(double(x) + 180, 360) - 180;
end
