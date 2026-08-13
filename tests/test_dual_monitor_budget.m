function ok=test_dual_monitor_budget()
setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);sixgr.bwop.FocusedCheck.run("dual_monitor_budget");ok=true;
end
