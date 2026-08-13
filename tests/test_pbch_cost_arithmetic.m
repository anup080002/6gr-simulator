function ok=test_pbch_cost_arithmetic()
setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);sixgr.bwop.FocusedCheck.run("pbch_cost_arithmetic");ok=true;
end
