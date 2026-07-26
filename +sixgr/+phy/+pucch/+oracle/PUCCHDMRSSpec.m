classdef PUCCHDMRSSpec
    %PUCCHDMRSSPEC Independent zero-based DM-RS RE-key construction.
    methods (Static)
        function keys = keys(startPRB,numPRBs,symbols,subcarriers)
            keys=strings(0,1);
            for l=reshape(double(symbols),1,[])
                for p=double(startPRB)+(0:double(numPRBs)-1)
                    for k=reshape(double(subcarriers),1,[])
                        keys(end+1,1)=string(l)+":"+string(p)+":"+string(k); %#ok<AGROW>
                    end
                end
            end
        end
    end
end
