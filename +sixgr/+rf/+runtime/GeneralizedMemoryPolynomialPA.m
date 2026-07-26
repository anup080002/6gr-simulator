classdef GeneralizedMemoryPolynomialPA
%GENERALIZEDMEMORYPOLYNOMIALPA Main and lag/lead envelope PA kernel.

    methods(Static)
        function output = apply(input, profile)
            required = ["MainCoefficients","MainOrders","CrossCoefficients", ...
                "CrossOrders","CrossDelays"];
            if ~isstruct(profile) || ~all(isfield(profile, required))
                error("RF:PAProfileDimensionMismatch", ...
                    "GMP profile is incomplete.");
            end
            [main,~] = sixgr.rf.runtime.MemoryPolynomialPA.apply(input, ...
                profile.MainCoefficients, profile.MainOrders, []);
            crossCoefficients = double(profile.CrossCoefficients(:));
            crossOrders = double(profile.CrossOrders(:));
            crossDelays = double(profile.CrossDelays(:));
            if numel(crossCoefficients) ~= numel(crossOrders) || ...
                    numel(crossOrders) ~= numel(crossDelays) || ...
                    any(~isfinite([crossCoefficients;crossOrders;crossDelays])) || ...
                    any(crossOrders < 1) || any(crossDelays ~= round(crossDelays))
                error("RF:PAProfileDimensionMismatch", ...
                    "GMP cross-term profile is invalid.");
            end
            output = double(main);
            n = size(input,1);
            for k=1:numel(crossCoefficients)
                delayedEnvelope = sixgr.rf.runtime. ...
                    GeneralizedMemoryPolynomialPA.shiftEnvelope( ...
                    abs(double(input)), crossDelays(k));
                output = output + crossCoefficients(k).*double(input).* ...
                    delayedEnvelope.^(crossOrders(k)-1);
            end
            if size(output,1) ~= n
                error("RF:PAProfileDimensionMismatch", ...
                    "GMP kernel changed the waveform length.");
            end
            output = cast(output,"like",input);
        end
    end

    methods(Static,Access=private)
        function shifted = shiftEnvelope(envelope, delay)
            n=size(envelope,1);
            shifted=zeros(size(envelope));
            if delay>=0 && delay<n
                shifted(delay+1:end,:)=envelope(1:end-delay,:);
            elseif delay<0 && -delay<n
                shifted(1:end+delay,:)=envelope(1-delay:end,:);
            end
        end
    end
end
