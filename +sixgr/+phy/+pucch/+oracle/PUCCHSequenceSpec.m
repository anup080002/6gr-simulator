classdef PUCCHSequenceSpec
    %PUCCHSEQUENCESPEC Independent length-31 Gold sequence generator.
    methods (Static)
        function bits = gold(cinit,lengthValue)
            n=double(lengthValue);nc=1600;
            x1=zeros(n+nc+31,1,'uint8');x2=x1;x1(1)=1;
            value=uint32(cinit);
            for k=1:31,x2(k)=bitget(value,k);end
            for k=1:n+nc
                x1(k+31)=bitxor(x1(k+3),x1(k));
                x2(k+31)=mod(double(x2(k+3))+double(x2(k+2))+ ...
                    double(x2(k+1))+double(x2(k)),2);
            end
            bits=int8(bitxor(x1(nc+(1:n)),x2(nc+(1:n))));
        end
    end
end
