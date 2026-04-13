function pOut = ensureFolder(p)
%ENSUREFOLDER Create exactly the requested directory and nothing else.
%
% Unlike ensureDir(), this helper never auto-creates csv/mat/fig/logs
% subtrees. It is intended for canonical structured result layouts.

arguments
    p {mustBeTextScalar}
end

pOut = char(p);
if strlength(string(pOut)) == 0
    return;
end

if ~isfolder(pOut)
    mkdir(pOut);
end
end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:util:ensureFolder:BadType", ...
        "Input must be a char vector or string scalar.");
end
end
