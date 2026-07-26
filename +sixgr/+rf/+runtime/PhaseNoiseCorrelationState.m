classdef PhaseNoiseCorrelationState
%PHASENOISECORRELATIONSTATE Validated multi-chain LO correlation model.

    methods(Static)
        function result = factor(chainCount, correlation)
            chainCount = double(chainCount);
            correlation = double(correlation);
            if ~(isscalar(chainCount) && isfinite(chainCount) && ...
                    chainCount == round(chainCount) && chainCount >= 1) || ...
                    ~(isscalar(correlation) && isfinite(correlation) && ...
                    correlation >= -1/max(chainCount-1,1) && correlation <= 1)
                error("RF:PhaseNoiseCorrelationInvalid", ...
                    "LO correlation and RF-chain count are invalid.");
            end
            covariance = (1-correlation)*eye(chainCount) + ...
                correlation*ones(chainCount);
            if correlation == 1
                factor=zeros(chainCount);
                factor(:,1)=1;
            elseif correlation == 0
                factor=eye(chainCount);
            else
                [vectors,values]=eig((covariance+covariance')/2);
                eigenvalues=diag(values);
                if min(eigenvalues)<-1e-12
                    error("RF:PhaseNoiseCorrelationInvalid", ...
                        "Configured LO correlation is not positive semidefinite.");
                end
                factor=vectors*diag(sqrt(max(eigenvalues,0)));
            end
            if any(~isfinite(factor(:)))
                error("RF:PhaseNoiseCorrelationInvalid", ...
                    "Configured LO correlation is not positive semidefinite.");
            end
            result = struct("Covariance", covariance, "Factor", factor, ...
                "ChainCount", chainCount, "Correlation", correlation);
        end

        function correlated = apply(independentInnovations, correlation)
            if isempty(independentInnovations) || ...
                    any(~isfinite(independentInnovations(:)))
                error("RF:NonFiniteSamples", ...
                    "LO correlation requires finite innovation samples.");
            end
            state = sixgr.rf.runtime.PhaseNoiseCorrelationState.factor( ...
                size(independentInnovations,2), correlation);
            correlated = double(independentInnovations) * state.Factor.';
        end
    end
end
