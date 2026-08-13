function ok=testUL10523Config()
%TESTUL10523CONFIG Validate authoritative catalog/contract ingestion.
setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
root=fileparts(fileparts(mfilename("fullpath")));
base=fullfile(root,"simulator","configs","tdoc_ul_10523");
catalog=sixgr.lls6g.config.readConfigFile(fullfile(base, ...
    "RAN1_10_5_2_3_UL_SIMULATION_SCENARIO_CATALOG.yaml"));
rawCampaigns=catalog.campaigns;
if iscell(rawCampaigns)
    campaignIds=cellfun(@(x)string(x.id),rawCampaigns(:));
else
    campaignIds=string({rawCampaigns.id}).';
end
assert(string(catalog.schema_version)=="1.0");
assert(numel(campaignIds)==27,"Catalog must contain C00-C26.");
assert(isequal(campaignIds,compose("C%02d",0:26).'));
contract=readtable(fullfile(base,"RAN1_10_5_2_3_TDOC_FIGURE_AND_RESULT_CONTRACT.csv"), ...
    "Delimiter",",","VariableNamingRule","preserve");
assert(height(contract)==86 && nnz(startsWith(string(contract.FigureId),"TFIG-"))==22);
assert(nnz(startsWith(string(contract.FigureId),"RFIG-"))==64);
assert(all(endsWith(string(contract.PNGPath),".png","IgnoreCase",true)));
proposal=readtable(fullfile(base,"RAN1_10_5_2_3_PROPOSAL_TO_CAMPAIGN_TRACEABILITY.csv"), ...
    "Delimiter",",","VariableNamingRule","preserve");
assert(height(proposal)==30 && isequal(double(proposal.ProposalNumber),(1:30).'));
[quick,~]=sixgr.lls.loadConfig("configs/lls/tdoc_ul_10523_quick.yaml");
[bounded,~]=sixgr.lls.loadConfig("configs/lls/tdoc_ul_10523_bounded.yaml");
assert(isequal(double(quick.simulation.snrDb),20) && quick.simulation.maxTransportBlocks==1);
assert(isequal(double(bounded.simulation.snrDb(:)).',[-10 0 20]) && bounded.simulation.maxTransportBlocks==1);
ok=true; fprintf("UL10523Config: 27 campaigns, 30 proposals, 22 TFIG + 64 RFIG rows PASS.\n");
end
