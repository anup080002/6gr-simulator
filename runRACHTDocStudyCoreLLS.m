function result=runRACHTDocStudyCoreLLS(configPath,varargin)
%RUNRACHTDOCCORELLS Fail-closed entry point for decision-quality work.
if nargin<1||strlength(strtrim(string(configPath)))==0
    configPath=fullfile("simulator","configs","rach_tdoc10512","campaign_core.yaml");
end
result=runRACHTDocStudyCampaign(configPath,varargin{:});
end
