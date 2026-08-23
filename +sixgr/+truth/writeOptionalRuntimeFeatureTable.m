function written = writeOptionalRuntimeFeatureTable(cfg, featureName, paths, T, options)
%WRITEOPTIONALRUNTIMEFEATURETABLE Persist only observed primary truth tables.

arguments
    cfg (1,1) struct
    featureName (1,1) string
    paths string
    T table
    options.PreserveSchema (1,1) logical = false
end

paths = paths(:);
% Read the authority path so misspelled/non-scalar feature entries still
% fail through the ordinary configuration validators before this writer;
% this writer itself decides only from observed row count.
sixgr.util.structGet(cfg, "runtime.features." + featureName, struct());
hasRows = height(T) > 0;
% Feature intent is exported by the resolved config and runtime authority
% ledger.  An enabled-but-not-yet-observed signal must not create an empty
% primary CSV that the browser could mistake for executed evidence.
written = hasRows;

for path = paths.'
    if written
        sixgr.util.csvWriteTable(path, T, ...
            "PreserveSchema", options.PreserveSchema);
    elseif isfile(path)
        delete(path);
    end
end
end
