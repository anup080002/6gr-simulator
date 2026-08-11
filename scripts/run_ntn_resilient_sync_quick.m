setup6GRSimToolkit('Verbose',false);
result = sixgr.ntn.resilientsync.runAllCampaigns( ...
    "configs/ntn_resilient_sync/quick.yaml");
disp(result.Status);
disp(result.RunDirectory);
