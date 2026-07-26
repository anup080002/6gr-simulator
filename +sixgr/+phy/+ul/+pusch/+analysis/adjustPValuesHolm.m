function adjusted = adjustPValuesHolm(values)
%ADJUSTPVALUESHOLM Holm family-wise multiplicity correction.
p = double(values(:));
if any(~isfinite(p) | p < 0 | p > 1)
    error("sixgr:pusch:ImpactStatisticsInvalid", ...
        "Holm adjustment requires finite p-values in [0,1].");
end
[ordered, order] = sort(p);
m = numel(p);
scaled = min(1, (m - (1:m).' + 1) .* ordered);
scaled = cummax(scaled);
adjusted = zeros(size(p));
adjusted(order) = scaled;
end
