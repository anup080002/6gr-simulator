function csvWriteTable(filePath, T, varargin)
%CSVWRITETABLE Unified CSV export for simulator KPIs and logs.
%
%   sixgr.util.csvWriteTable("results/run1/csv/kpis.csv", T)
%   MirrorPaths publishes additional destinations from the same serialized
%   bytes, with per-destination artifact registration and verified copies.

csvProfileScope=sixgr.runtime.ExecutionStageProfiler.scope("serialization","CSV_table"); %#ok<NASGU>
if ~(ischar(filePath) || (isstring(filePath) && isscalar(filePath)))
    error("sixgr:util:csvWriteTable:BadType", ...
        "filePath must be char or string scalar.");
end
if ~istable(T)
    error("sixgr:util:csvWriteTable:BadTable", "T must be a table.");
end
p = inputParser;
p.addParameter("PreserveSchema", false, ...
    @(x) islogical(x) && isscalar(x));
p.addParameter("RoundTripNumericText", false, ...
    @(x) islogical(x) && isscalar(x));
p.addParameter("MirrorPaths", strings(0,1), ...
    @(x) isstring(x) || ischar(x) || iscellstr(x));
p.parse(varargin{:});

filePath = char(filePath);
if ~sixgr.util.persistenceEnabled()
    return;
end
% An evaluated-but-empty artifact still needs a decodable header.  Pruning
% structurally blank columns from a zero-row table removes its entire
% schema and produces a two-byte, unreadable CSV.  Preserve typed empty
% schemas automatically; callers must explicitly define the columns they
% claim to export.
if ~p.Results.PreserveSchema && height(T) > 0
    T = sixgr.util.pruneStructurallyBlankTableColumns(T);
end
[unchanged,reuseTicket]=sixgr.util.CSVWriteReuse.check( ...
    filePath,T,p.Results.RoundTripNumericText,p.Results.MirrorPaths);
if unchanged, return; end
% Bound string conversion and writetable workspace independently of run
% length. A wide, million-row evidence table must not be duplicated as a
% second all-string table while the waveform/channel state is live.
writer=sixgr.util.CSVTableStream(filePath,p.Results.RoundTripNumericText);
cleanup=onCleanup(@()delete(writer)); %#ok<NASGU>
writer.append(T);
writer.finish(p.Results.MirrorPaths);
sixgr.util.CSVWriteReuse.commit(reuseTicket);
end
