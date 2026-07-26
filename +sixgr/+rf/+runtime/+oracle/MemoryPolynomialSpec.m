classdef MemoryPolynomialSpec
%MEMORYPOLYNOMIALSPEC Direct-loop memory-polynomial reference.
    methods(Static)
        function output=apply(input,coefficients,orders)
            coefficients=double(coefficients);
            orders=double(orders(:));
            if isvector(coefficients), coefficients=coefficients(:); end
            if size(coefficients,1)~=numel(orders)|| ...
                    any(~isfinite(coefficients(:)))||any(~isfinite(orders))
                error("RFOracle:PAInvalid", ...
                    "Memory-polynomial reference dimensions are invalid.");
            end
            output=complex(zeros(size(input)));
            for n=1:size(input,1)
                for memoryIndex=1:size(coefficients,2)
                    sourceIndex=n-memoryIndex+1;
                    if sourceIndex<1, continue; end
                    source=input(sourceIndex,:);
                    for orderIndex=1:numel(orders)
                        output(n,:)=output(n,:)+ ...
                            coefficients(orderIndex,memoryIndex).*source.* ...
                            abs(source).^(orders(orderIndex)-1);
                    end
                end
            end
        end
    end
end
