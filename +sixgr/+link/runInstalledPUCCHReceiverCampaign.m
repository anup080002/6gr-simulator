function receipt=runInstalledPUCCHReceiverCampaign(configPath,outputRoot,runTag)
% Public YAML-only PUCCH campaign entrypoint; shared immutable journal owner.
receipt=sixgr.link.runInstalledControlReceiverCampaign(configPath,outputRoot,runTag,"PUCCH");
end
