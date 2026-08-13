function ok=test_early_cease()
setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);sixgr.bwop.FocusedCheck.run("early_cease");ok=true;
end
