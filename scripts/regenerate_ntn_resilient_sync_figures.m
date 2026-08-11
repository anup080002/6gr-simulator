function regenerate_ntn_resilient_sync_figures(runDirectory)
setup6GRSimToolkit('Verbose',false);
sixgr.ntn.resilientsync.report.generateTdocFigures(string(runDirectory));
sixgr.ntn.resilientsync.report.generateConfidentialFigures(string(runDirectory));
end
