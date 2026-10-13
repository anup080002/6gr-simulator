function [data,evidence]=loadVerifiedMAT(filePath,expectedSHA256,variables)
%LOADVERIFIEDMAT Read exact archived bytes, including long Windows HDF5 paths.
% A short-path readback is byte-identical file access, not replacement PHY
% data. Never change the original file, current folder, or requested fields.
arguments
    filePath (1,1) string
    expectedSHA256 (1,1) string
    variables (1,:) string = strings(1,0)
end
assert(all(arrayfun(@(name)isvarname(char(name)),variables)), ...
    'sixgr:util:VerifiedMATVariableName','Use explicit variable names, not load options or patterns.');
[data,evidence]=sixgr.util.withVerifiedMAT(filePath,expectedSHA256, ...
    @(path)localLoad(path,variables));
evidence.LoadedVariables=string(fieldnames(data)).';
end

function data=localLoad(readPath,variables)
names=cellstr(variables);
data=load(readPath,names{:});
assert(all(isfield(data,names)), ...
    'sixgr:util:VerifiedMATVariableMissing','MAT archive lacks a requested variable.');
end
