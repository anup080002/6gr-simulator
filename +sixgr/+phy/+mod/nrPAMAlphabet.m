function [amplitude, bits] = nrPAMAlphabet(qm)
%NRPAMALPHABET One axis of TS 38.211 V18.8.0 section 5.1 square QAM.
% Bits are ordered sign first, then nested amplitude bits. I/Q use alternating
% input bits. This is not Communications Toolbox's integer Gray labelling.
validateattributes(qm, {'numeric'}, {'scalar','integer'});
assert(ismember(qm, [2 4 6 8 10]), 'sixgr:phy:nrPAMAlphabet:BadQm', ...
    'NR square QAM requires Qm in [2 4 6 8 10].');
axisBits = qm/2;
labels = uint32((0:2^axisBits-1).');
bits = zeros(numel(labels), axisBits);
for k = 1:axisBits
    bits(:,k) = double(bitget(labels, axisBits-k+1));
end
amplitude = ones(size(labels));
for k = axisBits:-1:1
    amplitude = (1-2*bits(:,k)).*amplitude;
    if k > 1
        amplitude = 2^(axisBits-k+1)-amplitude;
    end
end
amplitude = amplitude/sqrt(2*(2^qm-1)/3);
end
