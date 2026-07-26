function [layout, sizeDetails] = dciPayloadLayout(dciFormat, pdcchCfg)
%DCIPAYLOADLAYOUT Resolve the exact contextual Release-18 DCI field layout.

context = localContext(pdcchCfg, dciFormat);
schema = sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
alignment = sixgr.phy.pdcch.DCISizeAlignmentEngine.resolve(context);
definitions = schema.Definitions;
layout = repmat(struct("Name", "", "Width", 0, "Generated", false), ...
    numel(definitions), 1);
for ii = 1:numel(definitions)
    layout(ii).Name = char(definitions(ii).Name);
    layout(ii).Width = double(definitions(ii).Width);
    layout(ii).Generated = logical(definitions(ii).Generated);
end
if alignment.Selected.PaddingBits > 0
    layout(end+1,1) = struct("Name", "padding", ...
        "Width", double(alignment.Selected.PaddingBits), "Generated", true);
end
sizeDetails = alignment.Selected;
sizeDetails.FrequencyResourceAssignmentBits = schema.FrequencyAssignmentBits;
sizeDetails.ContextDigest = context.Digest;
sizeDetails.SchemaVersion = schema.SchemaVersion;
end

function context = localContext(pdcchCfg, dciFormat)
if isa(pdcchCfg, "sixgr.phy.pdcch.DCIContext")
    if string(pdcchCfg.Data.DCIFormat) ~= ...
            sixgr.phy.pdcch.normalizeDCIFormat(dciFormat)
        error("sixgr:phy:pdcch:wrong_dci_context", ...
            "DCIContext format does not match requested format.");
    end
    context = pdcchCfg;
elseif isstruct(pdcchCfg) && isfield(pdcchCfg, "SpecRelease")
    context = sixgr.phy.pdcch.DCIContext(pdcchCfg);
else
    context = sixgr.phy.pdcch.DCIContext.fromLegacy(pdcchCfg, dciFormat);
end
end
