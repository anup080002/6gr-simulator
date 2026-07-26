function pValue = computeMcNemarTest(baselineErrors, treatmentErrors)
%COMPUTEMCNEMARTEST Exact paired McNemar p-value.
a = logical(baselineErrors(:));
b = logical(treatmentErrors(:));
if numel(a) ~= numel(b) || isempty(a)
    error("sixgr:pusch:ImpactStatisticsInvalid", ...
        "McNemar inputs must be nonempty paired vectors.");
end
n01 = nnz(~a & b);
n10 = nnz(a & ~b);
n = n01 + n10;
if n == 0
    pValue = 1;
else
    k = min(n01, n10);
    indices = (0:k).';
    logTerms = gammaln(n + 1) - gammaln(indices + 1) ...
        - gammaln(n - indices + 1) - n * log(2);
    pValue = min(1, 2 * sum(exp(logTerms)));
end
end
