classdef EVMReferenceSpec
%EVMREFERENCESPEC Pure-math normalized RMS EVM reference.
    methods(Static)
        function evm_pct=measure(reference,observed,removeLeakage)
            if numel(reference)~=numel(observed)||isempty(reference)|| ...
                    any(~isfinite(reference(:)))||any(~isfinite(observed(:)))
                error("RFOracle:EVMInvalid","EVM reference inputs are invalid.");
            end
            reference=double(reference(:));
            observed=double(observed(:));
            if logical(removeLeakage)
                observed=observed-mean(observed-reference);
            end
            evm_pct=100*sqrt(sum(abs(observed-reference).^2)/ ...
                max(sum(abs(reference).^2),realmin));
        end
    end
end
