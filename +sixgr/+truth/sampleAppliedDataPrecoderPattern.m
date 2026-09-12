function d=sampleAppliedDataPrecoderPattern(array,fc,az,el,transmitWeights)
% X=W*S is the physical transmit convention; pattern uses steering weights.
% The conjugation is diagnostic only and does not modify the executed IQ.
d=double(pattern(array,fc,az,el,'Weights',conj(transmitWeights), ...
    'Type','directivity','CoordinateSystem','rectangular'));
end
