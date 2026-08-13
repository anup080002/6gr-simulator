function result=runRachTdocFull(configPath,varargin)
%RUNRACHTDOCFULL Fail-closed full-campaign entry point.
if nargin<1||strlength(strtrim(string(configPath)))==0
    configPath=fullfile("simulator","configs","rach_tdoc10512","campaign_full.yaml");
end
result=runRachTdocCampaign(configPath,varargin{:});
end
