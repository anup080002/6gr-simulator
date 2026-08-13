function ok=test_pdcch_al_capacity()
setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);sixgr.bwop.FocusedCheck.run("pdcch_al_capacity");ok=true;
end
