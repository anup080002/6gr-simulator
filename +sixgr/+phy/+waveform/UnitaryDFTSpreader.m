classdef UnitaryDFTSpreader
    %UNITARYDFTSPREADER Exact blockwise unitary forward DFT.
    methods (Static)
        function output=apply(input,m)
            m=double(m);
            if ~sixgr.phy.waveform.TransformPrecodingPlan.isValidDFTSize(m) && ...
                    ~(isfinite(m)&&m>=1&&m==fix(m))
                error("WAVEFORM:InvalidDFTSize","DFT size is invalid.");
            end
            if mod(size(input,1),m)~=0
                error("WAVEFORM:InvalidDFTSize", ...
                    "Input rows must be a multiple of the DFT size.");
            end
            output=complex(zeros(size(input),"like",input));
            for offset=1:m:size(input,1)
                rows=offset:offset+m-1;
                output(rows,:)=fft(input(rows,:),[],1)/sqrt(m);
            end
        end
    end
end
