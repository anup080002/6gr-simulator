function [tbsBits, tbsBytes, nrePerPRB] = sixgr_l2_mac_estimateTBSApprox_entry(qm, nLayers, nPRB, nSym, targetCodeRate)
%#codegen
% sixgr_l2_mac_estimateTBSApprox_entry
% Coder-friendly TBS approximation kernel for scheduler hot loops.

qm = double(qm);
nLayers = double(nLayers);
nPRB = double(nPRB);
nSym = double(nSym);
targetCodeRate = double(targetCodeRate);

if ~(isfinite(qm) && qm >= 1)
    qm = 2;
end
if ~(isfinite(nLayers) && nLayers >= 1)
    nLayers = 1;
end
if ~(isfinite(nPRB) && nPRB >= 1)
    nPRB = 1;
end
if ~(isfinite(nSym) && nSym >= 1)
    nSym = 14;
end
if ~(isfinite(targetCodeRate) && targetCodeRate > 0)
    targetCodeRate = 0.5;
end

nrePerPRB = 12 * floor(nSym);
eff = qm * nLayers * targetCodeRate;
tbsBits = floor(nPRB * nrePerPRB * eff);
tbsBits = 8 * floor(tbsBits / 8);
tbsBytes = floor(tbsBits / 8);
end
