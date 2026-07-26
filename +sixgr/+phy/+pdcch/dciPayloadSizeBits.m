function [payloadBits, details] = dciPayloadSizeBits(nSizeGrid, dciFormats)
%DCIPAYLOADSIZEBITS Resolve one exact contextual payload size per DCI format.
%
% This compatibility entry point delegates to the contextual Release-18
% schema/alignment engines. It returns a scalar only when one format was
% requested or every requested format resolves to the same aligned size.

if nargin < 2 || isempty(dciFormats)
    dciFormats = ["1_0","0_0"];
end
nSizeGrid = double(nSizeGrid);
if ~(isscalar(nSizeGrid) && isfinite(nSizeGrid) && nSizeGrid >= 1 && ...
        nSizeGrid == fix(nSizeGrid))
    error("sixgr:phy:pdcch:missing_dci_context", ...
        "NSizeGrid must be a positive integer to derive a DCI context.");
end
formats = string(dciFormats(:));
for ii = 1:numel(formats)
    formats(ii) = sixgr.phy.pdcch.normalizeDCIFormat(formats(ii));
end
formats = unique(formats, "stable");
legacyCfg = struct("NSizeGrid", nSizeGrid, "MonitoredFormats", formats);
rows = repmat(localRow(), numel(formats), 1);
contexts = cell(numel(formats), 1);
for ii = 1:numel(formats)
    context = sixgr.phy.pdcch.DCIContext.fromLegacy(legacyCfg, formats(ii));
    schema = sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
    alignment = sixgr.phy.pdcch.DCISizeAlignmentEngine.resolve(context);
    selected = alignment.Selected;
    rows(ii) = struct( ...
        "DCIFormat", formats(ii), ...
        "RawBits", double(schema.RawBits), ...
        "AlignedBits", double(selected.AlignedBits), ...
        "PaddingBits", double(selected.PaddingBits), ...
        "TruncatedFrequencyBits", double(selected.TruncatedFrequencyBits), ...
        "ContextDigest", string(context.Digest));
    contexts{ii} = context;
end
sizes = [rows.AlignedBits].';
if isscalar(sizes) || all(sizes == sizes(1))
    payloadBits = double(sizes(1));
else
    payloadBits = double(sizes);
end

details = struct();
details.NSizeGrid = nSizeGrid;
details.Formats = formats(:).';
details.FormatRows = rows;
details.PayloadBitsByFormat = double(sizes);
details.Contexts = contexts;
details.FrequencyResourceAssignmentBits = ...
    sixgr.phy.pdcch.DCISchemaEngine.frequencyWidth(nSizeGrid, "type1_riv");
details.PayloadBits = payloadBits;
details.SizeSource = "sixgr_contextual_dci_schema_alignment_release18";
details.DCI10PayloadBits = localSize(rows, "1_0");
details.DCI00UnpaddedPayloadBits = localRaw(rows, "0_0");
details.DCI00PaddedPayloadBits = localSize(rows, "0_0");
details.DCI11PayloadBits = localSize(rows, "1_1");
details.DCI01PayloadBits = localSize(rows, "0_1");
end

function row = localRow()
row = struct("DCIFormat", "", "RawBits", NaN, "AlignedBits", NaN, ...
    "PaddingBits", NaN, "TruncatedFrequencyBits", NaN, "ContextDigest", "");
end

function value = localSize(rows, format)
idx = find(string({rows.DCIFormat}) == string(format), 1);
if isempty(idx)
    value = NaN;
else
    value = double(rows(idx).AlignedBits);
end
end

function value = localRaw(rows, format)
idx = find(string({rows.DCIFormat}) == string(format), 1);
if isempty(idx)
    value = NaN;
else
    value = double(rows(idx).RawBits);
end
end
