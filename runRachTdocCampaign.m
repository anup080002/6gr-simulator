function result=runRachTdocCampaign(configPath,varargin)
%RUNRACHTDOCCAMPAIGN Public config-only RAN1 10.5.1.2 entry point.
result=sixgr.rach.tdoc10512.runCampaign(configPath,varargin{:});
end
