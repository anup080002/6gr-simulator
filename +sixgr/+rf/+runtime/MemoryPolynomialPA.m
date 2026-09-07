classdef MemoryPolynomialPA
%MEMORYPOLYNOMIALPA Explicit memory-polynomial PA kernel.

    methods(Static)
        function [output, state] = apply(input, coefficients, orders, state)
            coefficients = double(coefficients);
            orders = double(orders(:));
            % Rows index polynomial orders; columns index memory taps.
            % A single-order multi-tap row must remain a row.
            if isvector(coefficients) && numel(orders)>1 && numel(coefficients)==numel(orders)
                coefficients = coefficients(:);
            end
            if isempty(coefficients) || isempty(orders) || ~ismatrix(coefficients) || ...
                    size(coefficients,1) ~= numel(orders) || ...
                    any(~isfinite(coefficients(:))) || any(~isfinite(orders)) || ...
                    any(orders < 1) || any(orders ~= round(orders))
                error("RF:PAProfileDimensionMismatch", ...
                    "Memory-polynomial coefficient/order dimensions are invalid.");
            end
            memoryDepth = size(coefficients,2);
            if nargin < 4 || isempty(state)
                state = zeros(max(0,memoryDepth-1),size(input,2));
            end
            if size(state,1) ~= max(0,memoryDepth-1) || ...
                    size(state,2) ~= size(input,2)
                error("RF:PAStateInvalid", ...
                    "Memory-polynomial PA state dimensions are invalid.");
            end
            extended = [state; double(input)];
            output = complex(zeros(size(input)));
            for memoryIndex=1:memoryDepth
                delayed = extended(memoryDepth-memoryIndex+1: ...
                    memoryDepth-memoryIndex+size(input,1),:);
                for orderIndex=1:numel(orders)
                    output = output + coefficients(orderIndex,memoryIndex) .* ...
                        delayed .* abs(delayed).^(orders(orderIndex)-1);
                end
            end
            if memoryDepth > 1
                state = extended(end-memoryDepth+2:end,:);
            else
                state = zeros(0,size(input,2));
            end
            output = cast(output,"like",input);
        end
    end
end
