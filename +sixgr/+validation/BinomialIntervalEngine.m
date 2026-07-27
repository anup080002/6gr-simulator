classdef BinomialIntervalEngine
    %BINOMIALINTERVALENGINE Configurable binomial confidence intervals.
    methods (Static)
        function result = compute(errorCount,trialCount,confidenceLevel,method,varargin)
            parser = inputParser;
            parser.addParameter("LookIndex",0,@localNonnegativeInteger);
            parser.addParameter("AlphaSpent",1-double(confidenceLevel),@localProbabilityOrZero);
            parser.addParameter("DesignID","fixed_sample",@(x)ischar(x)||isstring(x));
            parser.parse(varargin{:});
            [k,n,cl] = localInputs(errorCount,trialCount,confidenceLevel);
            method = upper(strtrim(string(method)));
            estimate = k/n;
            switch method
                case "WILSON_TWO_SIDED"
                    alpha = 1-cl;
                    z = -sqrt(2)*erfcinv(2*(1-alpha/2));
                    denominator = 1 + z^2/n;
                    center = (estimate + z^2/(2*n))/denominator;
                    halfWidth = z*sqrt(estimate*(1-estimate)/n + ...
                        z^2/(4*n^2))/denominator;
                    lowerBound = max(0,center-halfWidth);
                    upperBound = min(1,center+halfWidth);
                    sidedness = "TWO_SIDED";
                case "CLOPPER_PEARSON_TWO_SIDED"
                    center = estimate;
                    alpha = 1-cl;
                    if k == 0, lowerBound = 0; ...
                    else, lowerBound = betaincinv(alpha/2,k,n-k+1); end
                    if k == n, upperBound = 1; ...
                    else, upperBound = betaincinv(1-alpha/2,k+1,n-k); end
                    sidedness = "TWO_SIDED";
                case "CLOPPER_PEARSON_ONE_SIDED_UPPER"
                    center = estimate;
                    lowerBound = 0;
                    if k == n
                        upperBound = 1;
                    elseif k == 0
                        upperBound = 1-(1-cl)^(1/n);
                    else
                        upperBound = betaincinv(cl,k+1,n-k);
                    end
                    sidedness = "ONE_SIDED_UPPER";
                otherwise
                    error("sixgr:validation:UnknownIntervalMethod", ...
                        "Unknown binomial interval method '%s'.",method);
            end
            result = struct( ...
                "Method",method,"ConfidenceLevel",cl, ...
                "Sidedness",sidedness,"Convention","ERROR_COUNT", ...
                "ErrorCount",k,"TrialCount",n,"Estimate",estimate, ...
                "Center",double(center), ...
                "Lower",double(lowerBound),"Upper",double(upperBound), ...
                "HalfWidth",double((upperBound-lowerBound)/2), ...
                "LookIndex",double(parser.Results.LookIndex), ...
                "AlphaSpent",double(parser.Results.AlphaSpent), ...
                "DesignID",string(parser.Results.DesignID));
        end
        function result = wilson(k,n,confidenceLevel,varargin)
            result = sixgr.validation.BinomialIntervalEngine.compute( ...
                k,n,confidenceLevel,"WILSON_TWO_SIDED",varargin{:});
        end
        function result = exactTwoSided(k,n,confidenceLevel,varargin)
            result = sixgr.validation.BinomialIntervalEngine.compute( ...
                k,n,confidenceLevel,"CLOPPER_PEARSON_TWO_SIDED",varargin{:});
        end
        function result = exactUpper(k,n,confidenceLevel,varargin)
            result = sixgr.validation.BinomialIntervalEngine.compute( ...
                k,n,confidenceLevel,"CLOPPER_PEARSON_ONE_SIDED_UPPER",varargin{:});
        end
    end
end

function [k,n,cl] = localInputs(k,n,cl)
k = double(k); n = double(n); cl = double(cl);
if ~(isscalar(k)&&isscalar(n)&&isfinite(k)&&isfinite(n)&& ...
        k==fix(k)&&n==fix(n)&&n>0&&k>=0&&k<=n)
    error("sixgr:validation:InvalidBinomialCounts", ...
        "Binomial counts require integer 0 <= ErrorCount <= TrialCount.");
end
if ~(isscalar(cl)&&isfinite(cl)&&cl>0&&cl<1)
    error("sixgr:validation:InvalidConfidenceLevel", ...
        "ConfidenceLevel must be finite and strictly between zero and one.");
end
end
function tf = localNonnegativeInteger(x)
tf = isnumeric(x)&&isscalar(x)&&isfinite(x)&&x>=0&&x==fix(x);
end
function tf = localProbabilityOrZero(x)
tf = isnumeric(x)&&isscalar(x)&&isfinite(x)&&x>=0&&x<1;
end
