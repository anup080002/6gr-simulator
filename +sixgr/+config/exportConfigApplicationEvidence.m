function out = exportConfigApplicationEvidence(runFolder)
%EXPORTCONFIGAPPLICATIONEVIDENCE Write runtime config-consumer evidence to CSV.

layout = sixgr.report.resultLayout(runFolder);
sixgr.util.ensureFolder(layout.ReportCSVDir);

T = sixgr.config.publishConfigApplicationEvidence("snapshot");
path = fullfile(layout.ReportCSVDir, "runtime_config_application_evidence.csv");
sixgr.util.csvWriteTable(path, T);

out = struct();
out.Table = T;
out.Path = string(path);
end
