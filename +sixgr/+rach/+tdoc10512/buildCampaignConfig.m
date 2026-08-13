function campaign = buildCampaignConfig(configPath)
%BUILDCAMPAIGNCONFIG Load one validated RAN1 10.5.1.2 campaign YAML.
%
% This adapter deliberately retains the existing ScenarioConfig and
% buildInternalConfig path.  It does not create a second PRACH config or
% receiver authority.

if nargin < 1 || strlength(strtrim(string(configPath))) == 0
    configPath = fullfile("simulator","configs","rach_tdoc10512", ...
        "campaign_smoke.yaml");
end
scenarioConfig = sixgr.lls6g.config.loadScenarioConfig(configPath);
resolved = scenarioConfig.toStruct();
sixgr.rach.tdoc10512.validateCampaignConfig(resolved);

campaign = struct();
campaign.ScenarioConfig = scenarioConfig;
campaign.Resolved = resolved;
campaign.TDoc = resolved.tdoc10512;
campaign.ConfigHash = string(scenarioConfig.ConfigHash);
campaign.SourceFiles = string(scenarioConfig.SourceFiles(:));
campaign.ConfigPath = string(scenarioConfig.ConfigPath);
campaign.ScenarioID = string(scenarioConfig.ScenarioID);
campaign.Mode = lower(string(resolved.tdoc10512.campaign_mode));
campaign.CampaignID = string(resolved.tdoc10512.campaign_id);
end
