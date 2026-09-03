function context = resolveDCIContext(pdcchCfg, dciFormat)
%RESOLVEDCICONTEXT Select the exact immutable context for one DCI format.

requested = sixgr.phy.pdcch.normalizeDCIFormat(dciFormat);

if isa(pdcchCfg, "sixgr.phy.pdcch.DCIContext")
    context = pdcchCfg;
elseif isstruct(pdcchCfg) && isscalar(pdcchCfg)
    context = localFromConfiguredContexts(pdcchCfg, requested);
    if isempty(context)
        if isfield(pdcchCfg, "SpecRelease")
            context = sixgr.phy.pdcch.DCIContext(pdcchCfg);
        elseif isfield(pdcchCfg, "DCIContexts") || isfield(pdcchCfg, "DCIContext")
            error("sixgr:phy:pdcch:wrong_dci_context", ...
                "No configured DCIContext matches requested format %s.", ...
                requested);
        else
            context = sixgr.phy.pdcch.DCIContext.fromLegacy( ...
                pdcchCfg, requested);
        end
    end
else
    error("sixgr:phy:pdcch:missing_dci_context", ...
        "DCI serialization requires a DCIContext or scalar PDCCH configuration structure.");
end

if string(context.Data.DCIFormat) ~= requested
    error("sixgr:phy:pdcch:wrong_dci_context", ...
        "Requested DCI format %s does not match context format %s.", ...
        requested, context.Data.DCIFormat);
end
end

function context = localFromConfiguredContexts(cfg, requested)
context = [];
if isfield(cfg, "DCIContexts")
    candidates = cfg.DCIContexts;
    if ~iscell(candidates)
        candidates = num2cell(candidates);
    end
    for ii = 1:numel(candidates)
        candidate = candidates{ii};
        if isstruct(candidate) && isscalar(candidate)
            candidate = sixgr.phy.pdcch.DCIContext(candidate);
        end
        if isa(candidate, "sixgr.phy.pdcch.DCIContext") && ...
                string(candidate.Data.DCIFormat) == requested
            if ~isempty(context)
                error("sixgr:phy:pdcch:duplicate_dci_context", ...
                    "Multiple configured DCI contexts match format %s.", ...
                    requested);
            end
            context = candidate;
        end
    end
end
if isempty(context) && isfield(cfg, "DCIContext")
    candidate = cfg.DCIContext;
    if isstruct(candidate) && isscalar(candidate)
        candidate = sixgr.phy.pdcch.DCIContext(candidate);
    end
    if isa(candidate, "sixgr.phy.pdcch.DCIContext") && ...
            string(candidate.Data.DCIFormat) == requested
        context = candidate;
    end
end
end
