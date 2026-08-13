function ok=test_region_relations()
setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);sixgr.bwop.FocusedCheck.run("region_relations");ok=true;
end
