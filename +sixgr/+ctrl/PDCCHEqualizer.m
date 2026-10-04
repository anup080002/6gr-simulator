function eq = PDCCHEqualizer(rxSym, H, noiseVar, equalizerType)
%PDCCHEqualizer Equalize one-layer control symbols across receive antennas.

assert(ismatrix(rxSym) && ~isempty(rxSym) && isequal(size(H),size(rxSym)) && ...
    all(isfinite(H(:))) && all(isfinite(rxSym(:))), ...
    'sixgr:ctrl:PDCCHEqualizer:ChannelDimensions', ...
    'One received channel estimate is required per payload RE and receive antenna.');
assert(isscalar(noiseVar) && isfinite(noiseVar) && noiseVar>0, ...
    'sixgr:ctrl:PDCCHEqualizer:NoiseVariance','Require positive grid-domain noise variance.');
switch upper(string(equalizerType))
    case {"MMSE","MMSE-IRC"}
        w = conj(H) ./ max(sum(abs(H).^2, 2) + noiseVar, eps);
    case "ZF"
        w = conj(H) ./ max(sum(abs(H).^2, 2), eps);
    otherwise
        error("sixgr:ctrl:PDCCHEqualizer:BadType", ...
            "Unsupported equalizer type '%s'.", equalizerType);
end

gain = sum(w .* H,2);
assert(all(abs(gain)>0),'sixgr:ctrl:PDCCHEqualizer:ZeroChannel', ...
    'A zero channel has no finite equalized-symbol observation.');
% Unit-gain symbols and propagated noise must share the demapper plane.
w = w ./ gain;
eqSym = sum(w .* rxSym, 2);
postNoise = noiseVar*sum(abs(w).^2,2);
csi = sum(abs(H).^2, 2) ./ max(sum(abs(H).^2, 2) + noiseVar, eps);

% Post-equalization EVM against nearest QPSK point.
dec = sign(real(eqSym)) + 1j * sign(imag(eqSym));
dec(dec == 0) = 1;
ref = dec ./ sqrt(2);
evm = sqrt(mean(abs(eqSym - ref).^2) / max(mean(abs(ref).^2), eps));

eq = struct();
eq.Symbols = eqSym(:);
eq.CSI = csi(:);
eq.PostEqualizationNoiseVariance = postNoise(:);
eq.PostEqEVM = double(evm);
eq.EstimatedSINR_dB = 10 * log10(mean(1./postNoise));
eq.EstimatedSINRSource = "received_channel_unit_symbol_power_over_post_equalization_noise";
end
