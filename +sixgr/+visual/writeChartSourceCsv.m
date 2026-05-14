function logicalPath = writeChartSourceCsv(runFolder, logicalPath, T)
%WRITECHARTSOURCECSV Persist a chart-source CSV when the source table is real.

if ~(istable(T) && ~isempty(T))
    return;
end
csvPath = fullfile(runFolder, char(string(logicalPath)));
sixgr.util.csvWriteTable(csvPath, T);
end
