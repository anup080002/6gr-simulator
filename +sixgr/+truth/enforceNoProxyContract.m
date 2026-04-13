function info = enforceNoProxyContract(cfg, context)
%ENFORCENOPROXYCONTRACT Reject unsupported proxy/fallback truth combinations.

if nargin < 1 || ~isstruct(cfg)
    cfg = struct();
end
if nargin < 2 || ~isstruct(context)
    context = struct();
end

enabled = logical(sixgr.util.structGet(context, "Enabled", ...
    sixgr.util.structGet(cfg, "run.noProxyTruthContract", false)));
info = struct();
info.Enabled = enabled;
info.Ok = true;
info.Violations = strings(0,1);
if ~enabled
    return;
end

violations = strings(0,1);

if logical(sixgr.util.structGet(context, "UseFastLinkModel", false))
    violations(end+1,1) = "UseFastLinkModel=true is proxy-only and forbidden under the no-proxy truth contract."; %#ok<AGROW>
end

if logical(sixgr.util.structGet(context, "RunSystem", false))
    sysPhyBackend = lower(strtrim(char(string(sixgr.util.structGet(context, "SystemPHYBackend", ...
        sixgr.util.structGet(cfg, "system.phyBackend", "waveform"))))));
    if ~strcmp(sysPhyBackend, "waveform")
        violations(end+1,1) = "System PHY backend must be 'waveform' under the no-proxy truth contract."; %#ok<AGROW>
    end
end

profileMode = lower(strtrim(char(string(sixgr.util.structGet(context, "CampaignProfileMode", "")))));
if strcmp(profileMode, "stress_proxy")
    violations(end+1,1) = "CampaignProfileMode='stress_proxy' is forbidden under the no-proxy truth contract."; %#ok<AGROW>
end

if logical(sixgr.util.structGet(context, "RunE2E", false))
    airModel = lower(strtrim(char(string(sixgr.util.structGet(context, "E2EAirModel", "truth")))));
    if ~strcmp(airModel, "truth")
        violations(end+1,1) = "E2E air model must be 'truth' under the no-proxy truth contract."; %#ok<AGROW>
    end

    trafficModel = lower(strtrim(char(string(sixgr.util.structGet(context, "TrafficModel", ...
        sixgr.util.structGet(cfg, "traffic.model", "fullBuffer"))))));
    if ~strcmp(trafficModel, "tracereplay")
        violations(end+1,1) = "E2E traffic model must be 'traceReplay' under the no-proxy truth contract."; %#ok<AGROW>
    end

    couplingMode = lower(strtrim(char(string(sixgr.util.structGet(context, "CouplingMode", "")))));
    if strcmp(couplingMode, "standalone_scheduler_replay")
        violations(end+1,1) = "standalone_scheduler_replay is not allowed under the no-proxy truth contract."; %#ok<AGROW>
    end

    if strcmp(airModel, "truth") && ~logical(sixgr.util.structGet(context, "E2ESystemCoupled", false))
        violations(end+1,1) = "Truth E2E must be system-coupled under the no-proxy truth contract."; %#ok<AGROW>
    end
end

textFields = { ...
    sixgr.util.structGet(context, "ExecutionBackend", ""), ...
    sixgr.util.structGet(context, "PHYMode", ""), ...
    sixgr.util.structGet(context, "ApproximationMode", ""), ...
    sixgr.util.structGet(context, "Source", ""), ...
    sixgr.util.structGet(context, "Notes", "") ...
    };
for i = 1:numel(textFields)
    txt = lower(strtrim(char(string(textFields{i}))));
    if strlength(string(txt)) == 0
        continue;
    end
    if contains(txt, "proxy") || contains(txt, "fallback") || contains(txt, "synthetic") || ...
            contains(txt, "logistic") || contains(txt, "lut") || contains(txt, "abstract")
        violations(end+1,1) = "Forbidden no-proxy token found in context text: " + string(txt); %#ok<AGROW>
    end
end

info.Ok = isempty(violations);
info.Violations = unique(violations, "stable");
if ~info.Ok
    error("sixgr:truth:NoProxyContractViolation", "%s", strjoin(cellstr(info.Violations), " "));
end
end
