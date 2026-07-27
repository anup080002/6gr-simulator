classdef IndependentDropAggregator
    %INDEPENDENTDROPAGGREGATOR Deterministic hierarchical aggregation.
    methods (Static)
        function result = aggregate(input,minimumDrops,confidenceLevel)
            if nargin < 3, confidenceLevel = 0.95; end
            policy = sixgr.validation.IndependentDropPolicy.validate( ...
                input,minimumDrops);
            n = double(input.TrialCount);
            k = double(input.ErrorCount);
            if any(~isfinite(n)|~isfinite(k)|n<=0|k<0|k>n)
                error("sixgr:validation:SchemaWrongType", ...
                    "Drop counts violate 0 <= errors <= trials.");
            end
            totalN = sum(n);
            totalK = sum(k);
            interval = sixgr.validation.BinomialIntervalEngine.wilson( ...
                totalK,totalN,confidenceLevel);
            rates = k./n;
            result = policy;
            result.TotalTrials = totalN;
            result.TotalErrors = totalK;
            result.AggregateEstimate = totalK/totalN;
            result.AggregateCILow = interval.Lower;
            result.AggregateCIHigh = interval.Upper;
            result.BetweenDropVariance = var(rates,1);
            result.WithinDropTrials = sum(n);
        end
    end
end
