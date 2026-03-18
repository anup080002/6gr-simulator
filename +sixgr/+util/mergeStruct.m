function out = mergeStruct(base, over)
%MERGESTRUCT Deep merge struct 'over' into 'base'.
%
% Rules:
% - Non-struct values in 'over' overwrite 'base'
% - If both base.(k) and over.(k) are structs, merge recursively
% - Struct arrays are overwritten (not merged elementwise)

if ~builtin("isstruct", base) || ~isscalar(base)
    error("sixgr:util:mergeStruct:BaseNotScalarStruct","base must be a scalar struct.");
end
if ~builtin("isstruct", over) || ~isscalar(over)
    error("sixgr:util:mergeStruct:OverNotScalarStruct","over must be a scalar struct.");
end

out = base;
f = fieldnames(over);

for i = 1:numel(f)
    k = f{i};
    v = over.(k);

    if isfield(out, k) && builtin("isstruct", out.(k)) && isscalar(out.(k)) && builtin("isstruct", v) && isscalar(v)
        out.(k) = sixgr.util.mergeStruct(out.(k), v);
    else
        out.(k) = v;
    end
end

end
