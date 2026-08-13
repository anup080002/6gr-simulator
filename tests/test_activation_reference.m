function ok=test_activation_reference()
setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);sixgr.bwop.FocusedCheck.run("activation_reference");ok=true;
end
