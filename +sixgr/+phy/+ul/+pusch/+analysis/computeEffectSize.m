function value = computeEffectSize(baseline, treatment)
%COMPUTEEFFECTSIZE Standardized treatment-minus-baseline effect.
a = double(baseline(:));
b = double(treatment(:));
a = a(isfinite(a));
b = b(isfinite(b));
if isempty(a) || isempty(b)
    value = 0;
    return;
end
pooled = sqrt((var(a, 1) + var(b, 1)) / 2);
if pooled <= eps
    value = sign(mean(b) - mean(a)) * double(mean(b) ~= mean(a));
else
    value = (mean(b) - mean(a)) / pooled;
end
end
