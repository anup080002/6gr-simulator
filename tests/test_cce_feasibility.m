function ok=test_cce_feasibility()
setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);sixgr.bwop.FocusedCheck.run("cce_feasibility");ok=true;
end
