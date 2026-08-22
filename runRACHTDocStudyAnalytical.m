function result=runRACHTDocStudyAnalytical(configPath,varargin)
%RUNRACHTDOCANALYTICAL Generate deterministic analytical evidence.
if nargin<1||strlength(strtrim(string(configPath)))==0
    configPath=fullfile("simulator","configs","rach_tdoc10512","campaign_analytical.yaml");
end
result=runRACHTDocStudyCampaign(configPath,varargin{:});
end
