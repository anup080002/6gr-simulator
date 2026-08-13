function result=runRachTdocSmoke(configPath,varargin)
%RUNRACHTDOCSMOKE Execute the bounded waveform-backed smoke profile.
if nargin<1||strlength(strtrim(string(configPath)))==0
    configPath=fullfile("simulator","configs","rach_tdoc10512","campaign_smoke.yaml");
end
result=runRachTdocCampaign(configPath,varargin{:});
end
