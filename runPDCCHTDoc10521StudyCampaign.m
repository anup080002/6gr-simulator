function result=runPDCCHTDoc10521StudyCampaign(configPath,varargin)
%RUNPDCCHTDOC10521CAMPAIGN Run the config-driven bounded PDCCH TDoc campaign.
if nargin<1||strlength(string(configPath))==0,configPath="simulator/configs/pdcch_tdoc10521/master.yaml";end
result=sixgr.phy.pdcch.tdoc.PDCCHTDocStudyCampaignRunner.run(string(configPath),varargin{:});
end
