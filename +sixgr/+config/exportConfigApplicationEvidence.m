function out = exportConfigApplicationEvidence(runFolder)
%EXPORTCONFIGAPPLICATIONEVIDENCE Write runtime config-consumer evidence to CSV.

layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ReportCSVDir);

path = fullfile(layout.ReportCSVDir, "runtime_config_application_evidence.csv");
T = sixgr.config.publishConfigApplicationEvidence("snapshot");
if height(T) == 0 && exist(path, "file") == 2
    T = localReadPersistedEvidence(path, T);
end
sixgr.util.csvWriteTable(path, T);

out = struct();
out.Table = T;
out.Path = string(path);
end

function T = localReadPersistedEvidence(path, fallbackT)
try
    opts = detectImportOptions(path, "Delimiter", ",");
    opts.VariableNamingRule = "preserve";
    opts = setvartype(opts, opts.VariableNames, "string");
    T = readtable(path, opts);
catch
    T = fallbackT;
end
end
