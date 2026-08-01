function profile = resolveConcreteProfile(cfg)
%RESOLVECONCRETEPROFILE Resolve an explicitly configured channel profile.
%
% Bare TDL/CDL family tokens are never returned. The concrete profile must
% already be present in the validated configuration.

if logical(sixgr.util.structGet(cfg, "channel.awgnOnly", false))
    profile = "AWGN";
    return;
end

model = upper(strtrim(string(sixgr.util.structGet(cfg, "channel.model", ""))));
if any(model == ["AWGN", "NONE", "OFF"])
    profile = "AWGN";
    return;
end

tdlAllowed = ["TDL-A", "TDL-B", "TDL-C", "TDL-D", "TDL-E"];
cdlAllowed = ["CDL-A", "CDL-B", "CDL-C", "CDL-D", "CDL-E"];
if any(model == [tdlAllowed, cdlAllowed])
    profile = model;
    return;
end

candidates = upper(strtrim([ ...
    string(sixgr.util.structGet(cfg, "channel.tdlProfile", "")), ...
    string(sixgr.util.structGet(cfg, "channel.cdlProfile", "")), ...
    string(sixgr.util.structGet(cfg, "channel.delayProfile", "")), ...
    string(sixgr.util.structGet(cfg, "channel.fading.profile", "")), ...
    string(sixgr.util.structGet(cfg, "channel.fading.model", ""))]));
candidates = candidates(strlength(candidates) > 0);
tdl = unique(candidates(ismember(candidates, tdlAllowed)), "stable");
cdl = unique(candidates(ismember(candidates, cdlAllowed)), "stable");

if numel(tdl) > 1 || numel(cdl) > 1 || (~isempty(tdl) && ~isempty(cdl))
    error("sixgr:config:BadChannelProfile", ...
        "Channel profile fields contain conflicting concrete TDL/CDL values: %s.", ...
        char(strjoin([tdl, cdl], ", ")));
end
if model == "TDL" && numel(tdl) == 1
    profile = tdl(1);
    return;
end
if model == "CDL" && numel(cdl) == 1
    profile = cdl(1);
    return;
end
if strlength(model) == 0 && numel(tdl) == 1 && isempty(cdl)
    profile = tdl(1);
    return;
end
if strlength(model) == 0 && numel(cdl) == 1 && isempty(tdl)
    profile = cdl(1);
    return;
end

if any(model == ["TDL", "CDL"])
    error("sixgr:config:BadChannelProfile", ...
        "channel.model='%s' requires an explicitly configured concrete %s-* profile.", ...
        char(model), char(model));
end
error("sixgr:config:BadChannelProfile", ...
    "Unsupported channel model '%s'; expected AWGN or a concrete TDL-*/CDL-* profile.", ...
    char(model));
end
