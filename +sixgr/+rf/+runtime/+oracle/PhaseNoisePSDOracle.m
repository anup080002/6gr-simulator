classdef PhaseNoisePSDOracle
%PHASENOISEPSDORACLE Log-frequency mask interpolation and integration.
    methods(Static)
        function levels=interpolate(offsetsHz,maskOffsetsHz,maskLevels_dBcHz)
            offsets=double(offsetsHz(:));
            maskOffsets=double(maskOffsetsHz(:));
            maskLevels=double(maskLevels_dBcHz(:));
            if numel(maskOffsets)~=numel(maskLevels)||numel(maskOffsets)<2|| ...
                    any(~isfinite([offsets;maskOffsets;maskLevels]))|| ...
                    any(offsets<=0)||any(maskOffsets<=0)|| ...
                    any(diff(maskOffsets)<=0)
                error("RFOracle:PhaseNoiseMaskInvalid", ...
                    "Phase-noise mask reference inputs are invalid.");
            end
            levels=interp1(log10(maskOffsets),maskLevels, ...
                log10(offsets),"linear","extrap");
        end
        function variance=integratedVariance(maskOffsetsHz,maskLevels_dBcHz)
            offsets=double(maskOffsetsHz(:));
            levels=double(maskLevels_dBcHz(:));
            if numel(offsets)~=numel(levels)||numel(offsets)<2|| ...
                    any(diff(offsets)<=0)
                error("RFOracle:PhaseNoiseMaskInvalid", ...
                    "Phase-noise integration mask is invalid.");
            end
            variance=2*trapz(offsets,10.^(levels/10));
        end
    end
end
