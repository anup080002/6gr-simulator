function ok=test_distributed_prb_mapping()
setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);sixgr.bwop.FocusedCheck.run("distributed_prb_mapping");ok=true;
end
