function eq = PDCCHEqualizer(rxSym, hMean, noiseVar, equalizerType)
%PDCCHEqualizer Equalize one-layer control symbols across receive antennas.

rxSym = squeeze(rxSym);
if isvector(rxSym)
    rxSym = rxSym(:);
end
hMean = reshape(hMean, 1, []);
nRE = size(rxSym, 1);
nRx = size(rxSym, 2);
if numel(hMean) ~= nRx
    hMean = repmat(mean(hMean(:)), 1, nRx);
end

H = repmat(hMean, nRE, 1);
switch upper(string(equalizerType))
    case {"MMSE","MMSE-IRC"}
        w = conj(H) ./ max(sum(abs(H).^2, 2) + noiseVar, eps);
    case "ZF"
        w = conj(H) ./ max(sum(abs(H).^2, 2), eps);
    otherwise
        error("sixgr:ctrl:PDCCHEqualizer:BadType", ...
            "Unsupported equalizer type '%s'.", equalizerType);
end

eqSym = sum(w .* rxSym, 2);
csi = sum(abs(H).^2, 2) ./ max(sum(abs(H).^2, 2) + noiseVar, eps);

% Post-equalization EVM against nearest QPSK point.
dec = sign(real(eqSym)) + 1j * sign(imag(eqSym));
dec(dec == 0) = 1;
ref = dec ./ sqrt(2);
evm = sqrt(mean(abs(eqSym - ref).^2) / max(mean(abs(ref).^2), eps));

eq = struct();
eq.Symbols = eqSym(:);
eq.CSI = csi(:);
eq.PostEqEVM = double(evm);
eq.EstimatedSINR_dB = 10 * log10(max(mean(abs(eqSym).^2) / max(noiseVar, eps), eps));
end
