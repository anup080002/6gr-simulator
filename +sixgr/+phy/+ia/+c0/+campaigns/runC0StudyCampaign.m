function result = runC0StudyCampaign(scenarioId,varargin)
%RUNCAMPAIGN Execute one currently authorized C0 IA campaign.
p=inputParser;
p.addParameter("Mode","smoke",@(x)ischar(x)||isstring(x));
p.addParameter("ConfigPath", ...
    "simulator/configs/initial_access/c0/C0.yaml", ...
    @(x)ischar(x)||isstring(x));
p.addParameter("OutputRoot","",@(x)ischar(x)||isstring(x));
p.addParameter("RunId","",@(x)ischar(x)||isstring(x));
p.parse(varargin{:});
if ~strcmpi(string(scenarioId),"C0")
    error("sixgr:phy:ia:c0:campaign:PhaseGate", ...
        "Only C0 is implemented in approved Phase 1; scenario %s remains gated.",scenarioId);
end
result=sixgr.phy.ia.c0.campaigns.runC0Study( ...
    string(p.Results.ConfigPath),string(p.Results.Mode), ...
    "OutputRoot",string(p.Results.OutputRoot),"RunId",string(p.Results.RunId));
end
