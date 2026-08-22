function written = writeOptionalRuntimeFeatureTable(cfg, featureName, paths, T, options)
%WRITEOPTIONALRUNTIMEFEATURETABLE Persist only enabled or observed truth tables.

arguments
    cfg (1,1) struct
    featureName (1,1) string
    paths string
    T table
    options.PreserveSchema (1,1) logical = false
end

paths = paths(:);
feature = sixgr.util.structGet(cfg, ...
    "runtime.features." + featureName, struct());
authorityPresent = isstruct(feature) && isscalar(feature) && ...
    isfield(feature, "Enabled");
enabled = logical(sixgr.util.structGet(feature, "Enabled", false));
hasRows = height(T) > 0;
written = ~authorityPresent || enabled || hasRows;

for path = paths.'
    if written
        sixgr.util.csvWriteTable(path, T, ...
            "PreserveSchema", options.PreserveSchema);
    elseif isfile(path)
        delete(path);
    end
end
end
