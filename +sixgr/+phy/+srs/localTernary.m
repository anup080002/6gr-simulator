function value = localTernary(condition, trueValue, falseValue)
%LOCALTERNARY Small string/value ternary helper for package-local use.
if logical(condition)
    value = trueValue;
else
    value = falseValue;
end
end
