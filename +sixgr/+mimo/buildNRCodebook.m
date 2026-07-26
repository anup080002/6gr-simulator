function [W_rank1, W_rank2, info] = buildNRCodebook(N1, N2, O1, O2)
%BUILDNRCODEBOOK Compatibility facade for the bounded MIMO codebook engine.
%
% For two ports this returns the exact TS 38.214 Type-I floor. Larger
% layouts retain the historical compact DFT candidates as explicitly
% non-normative study output; strict profiles must use CodebookEngine.
%
% The returned matrices are deterministic wideband candidates:
%   W_rank1: [N1*N2 x N1*O1*N2*O2]
%   W_rank2: [N1*N2 x 2 x N1*O1*N2*O2*4]

if nargin < 1 || isempty(N1), N1 = 8; end
if nargin < 2 || isempty(N2), N2 = 8; end
if nargin < 3 || isempty(O1), O1 = 4; end
if nargin < 4 || isempty(O2), O2 = 4; end
values = double([N1 N2 O1 O2]);
if any(~isfinite(values) | values < 1 | values ~= round(values))
    error("sixgr:mimo:InvalidPanelGeometry", ...
        "N1, N2, O1 and O2 must be explicit positive integers.");
end
N1 = values(1); N2 = values(2); O1 = values(3); O2 = values(4);

nPorts = N1 * N2;
if nPorts == 2
    exactRank1 = sixgr.phy.mimo.TypeI2PortCodebook.enumerate(1);
    exactRank2 = sixgr.phy.mimo.TypeI2PortCodebook.enumerate(2);
    W_rank1 = reshape(exactRank1, 2, size(exactRank1,3));
    W_rank2 = exactRank2;
    info = struct( ...
        "N1", N1, "N2", N2, "O1", O1, "O2", O2, ...
        "NumPorts", 2, ...
        "NumRank1Candidates", size(W_rank1,2), ...
        "NumRank2Candidates", size(W_rank2,3), ...
        "CodebookType", "typeI-SinglePanel", ...
        "NormativeSubset", true, ...
        "GenericDFTApproximationUsed", false, ...
        "Specification", "TS38.214-V18.9.0-Table5.2.2.2.1-1");
    return;
end

nBeamsH = N1 * O1;
nBeamsV = N2 * O2;
v = localDFT(N1, nBeamsH);
u = localDFT(N2, nBeamsV);

W_rank1 = complex(zeros(nPorts, nBeamsH * nBeamsV));
idx = 1;
for l1 = 1:nBeamsH
    for l2 = 1:nBeamsV
        w = kron(v(:, l1), u(:, l2));
        W_rank1(:, idx) = w ./ max(norm(w), realmin);
        idx = idx + 1;
    end
end

coPhase = [1, 1i, -1, -1i];
W_rank2 = complex(zeros(nPorts, 2, nBeamsH * nBeamsV * numel(coPhase)));
idx = 1;
for l1 = 1:nBeamsH
    l1b = mod(l1 - 1 + floor(nBeamsH / 2), nBeamsH) + 1;
    for l2 = 1:nBeamsV
        w1 = kron(v(:, l1), u(:, l2));
        w2 = kron(v(:, l1b), u(:, l2));
        w1 = w1 ./ max(norm(w1), realmin);
        w2 = w2 ./ max(norm(w2), realmin);
        for ph = 1:numel(coPhase)
            W = [w1, coPhase(ph) .* w2] ./ sqrt(2);
            W_rank2(:, :, idx) = W;
            idx = idx + 1;
        end
    end
end

info = struct();
info.N1 = double(N1);
info.N2 = double(N2);
info.O1 = double(O1);
info.O2 = double(O2);
info.NumPorts = double(nPorts);
info.NumRank1Candidates = double(size(W_rank1, 2));
info.NumRank2Candidates = double(size(W_rank2, 3));
info.CodebookType = "study_compact_dft_non_normative";
info.NormativeSubset = false;
info.GenericDFTApproximationUsed = true;
info.Specification = "study_only_not_a_3gpp_codebook_claim";
end

function B = localDFT(nElem, nBeams)
B = complex(zeros(nElem, nBeams));
elem = (0:nElem-1).';
for beam = 0:nBeams-1
    B(:, beam + 1) = exp(1i * 2 * pi * beam .* elem ./ nBeams);
end
end
