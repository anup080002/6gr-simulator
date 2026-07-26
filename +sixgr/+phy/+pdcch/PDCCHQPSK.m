classdef PDCCHQPSK
    %PDCCHQPSK Strict QPSK modulation/demodulation for PDCCH.

    methods (Static)
        function symbols = modulate(bits)
            bits = int8(bits(:));
            if isempty(bits) || mod(numel(bits),2) ~= 0 || any(bits ~= 0 & bits ~= 1)
                error("sixgr:phy:pdcch:payload_length_mismatch", ...
                    "PDCCH QPSK requires a nonempty even-length binary vector.");
            end
            pairs = reshape(bits, 2, []).';
            symbols = complex(1 - 2*double(pairs(:,1)), ...
                1 - 2*double(pairs(:,2))) / sqrt(2);
        end

        function [bits, llr] = demodulate(symbols, noiseVariance)
            symbols = symbols(:);
            noiseVariance = double(noiseVariance);
            if ~(isscalar(noiseVariance) && isfinite(noiseVariance) && noiseVariance > 0)
                error("sixgr:phy:pdcch:field_out_of_range", ...
                    "PDCCH QPSK noise variance must be finite and positive.");
            end
            llr = reshape([2*real(symbols).'/noiseVariance; ...
                2*imag(symbols).'/noiseVariance], [], 1);
            bits = int8(llr < 0);
        end
    end
end
