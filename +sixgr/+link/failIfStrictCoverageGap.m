function failIfStrictCoverageGap(cfg, identifier, message)
%FAILIFSTRICTCOVERAGEGAP Throw when strict mode would otherwise report a skip.

if nargin < 3
    error("sixgr:link:StrictCoverageBadCall", ...
        "cfg, identifier, and message are required.");
end

if logical(sixgr.util.structGet(cfg, "run.strictMode", false)) || ...
        logical(sixgr.util.structGet(cfg, "run.noProxyTruthContract", false))
    error(char(string(identifier)), "%s", char(string(message)));
end
end
