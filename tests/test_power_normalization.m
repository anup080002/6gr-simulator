function ok=test_power_normalization()
setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);sixgr.bwop.FocusedCheck.run("power_normalization");ok=true;
end
