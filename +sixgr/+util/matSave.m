function matSave(filePath, data)
%MATSAVE Unified MAT export (creates parent directories).
%
%   sixgr.util.matSave("results/run1/mat/run.mat", struct("cfg",cfg,"kpi",kpi))

arguments
    filePath {mustBeTextScalar}
    data
end

filePath = char(filePath);
sixgr.util.ensureDir(filePath);

if builtin("isstruct", data) && isscalar(data)
    save(filePath, "-struct", "data");
else
    save(filePath, "data");
end

end

function mustBeTextScalar(x)
if ~(ischar(x) || (isstring(x) && isscalar(x)))
    error("sixgr:util:matSave:BadType","filePath must be char or string scalar.");
end
end
