function result = runBWOPAI10513Campaign(configPath,options)
%RUNBWOPAI10513CAMPAIGN Public front door for RAN1 AI 10.5.1.3.

arguments
    configPath (1,1) string = "simulator/configs/bwop_ai10513/master_campaign.yaml"
    options.OutputRoot (1,1) string = ""
    options.RunID (1,1) string = ""
    options.Mode (1,1) string = ""
    options.Resume (1,1) logical = false
end

result = sixgr.bwop.CampaignRunner.run(configPath, ...
    "OutputRoot",options.OutputRoot,"RunID",options.RunID, ...
    "Mode",options.Mode,"Resume",options.Resume);
end
