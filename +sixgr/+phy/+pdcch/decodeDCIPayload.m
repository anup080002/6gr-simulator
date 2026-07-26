function dci = decodeDCIPayload(bits, dciFormat, pdcchCfg)
%DECODEDCIPAYLOAD Strict exact-length contextual DCI payload parsing.

context = localContext(pdcchCfg, dciFormat);
dci = sixgr.phy.pdcch.DCIParser.parse(bits, context);
end

function context = localContext(pdcchCfg, dciFormat)
if isa(pdcchCfg, "sixgr.phy.pdcch.DCIContext")
    context = pdcchCfg;
elseif isstruct(pdcchCfg) && isfield(pdcchCfg, "SpecRelease")
    context = sixgr.phy.pdcch.DCIContext(pdcchCfg);
else
    context = sixgr.phy.pdcch.DCIContext.fromLegacy(pdcchCfg, dciFormat);
end
requested = sixgr.phy.pdcch.normalizeDCIFormat(dciFormat);
if string(context.Data.DCIFormat) ~= requested
    error("sixgr:phy:pdcch:wrong_dci_context", ...
        "Requested DCI format %s does not match context format %s.", ...
        requested, context.Data.DCIFormat);
end
end
