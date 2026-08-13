function ok=test_rf_span_containment()
setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);sixgr.bwop.FocusedCheck.run("rf_span_containment");ok=true;
end
