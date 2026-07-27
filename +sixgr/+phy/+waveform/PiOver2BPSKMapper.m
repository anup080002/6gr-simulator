classdef PiOver2BPSKMapper
    %PIOVER2BPSKMAPPER Procedure-index-aware pi/2-BPSK mapping.
    methods (Static)
        function [symbols,nextIndex]=map(bits,startSymbolIndex)
            if nargin<2 || isempty(startSymbolIndex)
                error("WAVEFORM:Pi2BPSKContextMissing", ...
                    "pi/2-BPSK requires the absolute starting symbol index.");
            end
            bits=double(bits(:));
            if any(bits~=0 & bits~=1) || ~isscalar(startSymbolIndex) || ...
                    ~isfinite(startSymbolIndex) || startSymbolIndex<0 || ...
                    startSymbolIndex~=fix(startSymbolIndex)
                error("WAVEFORM:Pi2BPSKContextMissing", ...
                    "Invalid pi/2-BPSK bits or symbol index.");
            end
            index=double(startSymbolIndex)+(0:numel(bits)-1).';
            base=(1-2*bits).*(1+1j)/sqrt(2);
            symbols=base.*exp(1j*pi/2*mod(index,2));
            nextIndex=double(startSymbolIndex)+numel(bits);
        end
    end
end
