function [W_rank1, W_rank2, info] = buildNRCodebook(N1, N2, O1, O2)
%BUILDNRCODEBOOK Build a compact NR Type-I single-panel DFT codebook.
%
% The returned matrices are deterministic wideband precoder candidates:
%   W_rank1: [N1*N2 x N1*O1*N2*O2]
%   W_rank2: [N1*N2 x 2 x N1*O1*N2*O2*4]

if nargin < 1 || isempty(N1), N1 = 8; end
if nargin < 2 || isempty(N2), N2 = 8; end
if nargin < 3 || isempty(O1), O1 = 4; end
if nargin < 4 || isempty(O2), O2 = 4; end
N1 = max(1, round(double(N1)));
N2 = max(1, round(double(N2)));
O1 = max(1, round(double(O1)));
O2 = max(1, round(double(O2)));

nPorts = N1 * N2;
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
info.CodebookType = "TypeI_SinglePanel_DFT";
end

function B = localDFT(nElem, nBeams)
B = complex(zeros(nElem, nBeams));
elem = (0:nElem-1).';
for beam = 0:nBeams-1
    B(:, beam + 1) = exp(1i * 2 * pi * beam .* elem ./ nBeams);
end
end
