classdef UnitaryDFTDespreader
    %UNITARYDFTDESPREADER Exact inverse of UnitaryDFTSpreader.
    methods (Static)
        function output=apply(input,m)
            m=double(m);
            if ~isfinite(m)||m<1||m~=fix(m)||mod(size(input,1),m)~=0
                error("WAVEFORM:InvalidDFTSize","DFT size or input shape is invalid.");
            end
            output=complex(zeros(size(input),"like",input));
            for offset=1:m:size(input,1)
                rows=offset:offset+m-1;
                output(rows,:)=ifft(input(rows,:),[],1)*sqrt(m);
            end
        end
    end
end
