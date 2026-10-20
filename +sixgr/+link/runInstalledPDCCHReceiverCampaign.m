function receipt=runInstalledPDCCHReceiverCampaign(configPath,outputRoot,runTag)
% Installed physical PDCCH campaign; policy belongs to the supplied YAML.
receipt=sixgr.link.runInstalledControlReceiverCampaign(configPath,outputRoot,runTag,"PDCCH");
end
