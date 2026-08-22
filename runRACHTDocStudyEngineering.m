function result=runRACHTDocStudyEngineering(configPath,varargin)
%RUNRACHTDOCENGINEERING Bounded production-waveform TDoc engineering run.
if nargin<1||strlength(strtrim(string(configPath)))==0
    configPath=fullfile("simulator","configs","rach_tdoc10512", ...
        "campaign_engineering.yaml");
end
result=runRACHTDocStudyCampaign(configPath,varargin{:});
end
