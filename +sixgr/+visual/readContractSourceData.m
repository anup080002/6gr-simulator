function [sourceT, info] = readContractSourceData(runFolder, sourceSpec)
%READCONTRACTSOURCEDATA Read and union a visual contract's source tables.
%
% SourceCSV may contain a pipe-delimited union (for example a DL and UL
% measured-curve table). Missing members are allowed when another member is
% present, which keeps direction-specific scenarios valid. Existing but
% unreadable or schema-incompatible members fail closed.

runFolder = char(string(runFolder));
sources = strtrim(split(string(sourceSpec), "|"));
sources = sources(strlength(sources) > 0);
sourceT = table();
available = strings(0, 1);
missing = strings(0, 1);
info = struct( ...
    "Ok", false, ...
    "Reason", "source_csv_missing", ...
    "AvailableSources", available, ...
    "MissingSources", missing, ...
    "AvailableSourceCount", 0, ...
    "MissingSourceCount", 0);

for source = sources(:).'
    relativePath = replace(source, ["/", "\"], filesep);
    sourcePath = fullfile(runFolder, char(relativePath));
    if exist(sourcePath, "file") ~= 2
        missing(end + 1, 1) = source; %#ok<AGROW>
        continue;
    end
    try
        % Contract sources are canonical schema-bearing CSVs.  R2026a can
        % otherwise infer ReadVariableNames=false when quoted prose in a
        % later row contains commas, turning the first data row into field
        % names and silently defeating required-column validation.
        nextT = readtable(sourcePath, "FileType", "text", ...
            "Delimiter", ",", "VariableNamingRule", "preserve", ...
            "ReadVariableNames", true);
    catch ME
        info.Reason = "source_csv_unreadable:" + source + ":" + string(ME.identifier);
        info.AvailableSources = available;
        info.MissingSources = missing;
        info.AvailableSourceCount = numel(available);
        info.MissingSourceCount = numel(missing);
        return;
    end
    try
        if isempty(available)
            sourceT = nextT;
        else
            sourceT = [sourceT; nextT]; %#ok<AGROW>
        end
    catch ME
        info.Reason = "source_csv_union_schema_mismatch:" + source + ":" + string(ME.identifier);
        info.AvailableSources = available;
        info.MissingSources = missing;
        info.AvailableSourceCount = numel(available);
        info.MissingSourceCount = numel(missing);
        return;
    end
    available(end + 1, 1) = source; %#ok<AGROW>
end

info.AvailableSources = available;
info.MissingSources = missing;
info.AvailableSourceCount = numel(available);
info.MissingSourceCount = numel(missing);
if ~isempty(available)
    info.Ok = true;
    info.Reason = "";
elseif isempty(sources)
    info.Reason = "source_csv_not_configured";
end
end
