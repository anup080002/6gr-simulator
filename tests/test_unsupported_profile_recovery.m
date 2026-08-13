function ok=test_unsupported_profile_recovery()
setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);sixgr.bwop.FocusedCheck.run("unsupported_profile_recovery");ok=true;
end
