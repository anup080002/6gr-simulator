function out = localTernary(cond, a, b)
%LOCALTERNARY Small package-local ternary helper.

if logical(cond)
    out = a;
else
    out = b;
end
end
