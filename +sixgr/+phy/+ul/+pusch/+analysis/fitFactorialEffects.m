function result = fitFactorialEffects(design, response)
%FITFACTORIALEFFECTS Fit finite main/two-way effects for audit evidence.
x = double(design);
y = double(response(:));
if ~ismatrix(x) || size(x, 1) ~= numel(y) || ...
        any(~isfinite(x(:))) || any(~isfinite(y))
    error("sixgr:pusch:ImpactStatisticsInvalid", ...
        "Factorial design and response must be finite and row-aligned.");
end
terms = [ones(size(x, 1), 1), x];
labels = ["intercept", "main_" + string(1:size(x, 2))];
for first = 1:size(x, 2)
    for second = first+1:size(x, 2)
        terms(:, end+1) = x(:, first) .* x(:, second); %#ok<AGROW>
        labels(end+1) = "interaction_" + first + "_" + second; %#ok<AGROW>
    end
end
estimate = terms \ y;
residual = y - terms * estimate;
dof = max(1, size(terms, 1) - rank(terms));
variance = sum(residual.^2) / dof;
covariance = variance * pinv(terms.' * terms);
stderr = sqrt(max(0, diag(covariance)));
result = table(labels(:), estimate(:), stderr(:), ...
    'VariableNames', {'Term','Estimate','StdError'});
end
