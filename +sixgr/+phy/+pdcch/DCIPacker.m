classdef DCIPacker
    %DCIPACKER Strict contextual DCI serializer.

    methods (Static)
        function dci = pack(fields, context)
            context = sixgr.phy.pdcch.DCISchemaEngine.requireContext(context);
            if ~(isstruct(fields) && isscalar(fields))
                error("sixgr:phy:pdcch:missing_required_field", ...
                    "DCI fields must be provided as one scalar structure.");
            end
            schema = sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
            alignment = sixgr.phy.pdcch.DCISizeAlignmentEngine.resolve(context);
            definitions = schema.Definitions;
            allowed = string(arrayfun(@(x) x.Name, definitions, "UniformOutput", false));
            supplied = string(fieldnames(fields));
            unexpected = setdiff(supplied, allowed);
            if ~isempty(unexpected)
                error("sixgr:phy:pdcch:unexpected_field", ...
                    "DCI %s contains unexpected fields: %s.", ...
                    context.Data.DCIFormat, strjoin(unexpected, ", "));
            end
            bits = zeros(alignment.Selected.AlignedBits, 1, "int8");
            rows = repmat(localFieldRow(), 0, 1);
            cursor = 1;
            for ii = 1:numel(definitions)
                definition = definitions(ii);
                name = char(definition.Name);
                if ~isfield(fields, name)
                    error("sixgr:phy:pdcch:missing_required_field", ...
                        "DCI %s requires field '%s' in context %s.", ...
                        context.Data.DCIFormat, name, context.Digest);
                end
                value = fields.(name);
                if ~(isnumeric(value) || islogical(value)) || ~isscalar(value) || ~isfinite(double(value))
                    error("sixgr:phy:pdcch:field_not_integer", ...
                        "DCI field '%s' must be one finite integer scalar.", name);
                end
                value = double(value);
                if value ~= fix(value)
                    error("sixgr:phy:pdcch:field_not_integer", ...
                        "DCI field '%s' must be integer-valued; got %g.", name, value);
                end
                if value < definition.ValueMin || value > definition.ValueMax
                    error("sixgr:phy:pdcch:field_out_of_range", ...
                        "DCI field '%s'=%g is outside [%g,%g] for context %s.", ...
                        name, value, definition.ValueMin, definition.ValueMax, context.Digest);
                end
                fieldBits = localUIntToBits(value, definition.Width);
                stop = cursor + definition.Width - 1;
                bits(cursor:stop) = fieldBits;
                rows(end+1,1) = localMakeRow(definition, value, cursor, stop); %#ok<AGROW>
                cursor = stop + 1;
            end
            if alignment.Selected.TruncatedFrequencyBits > 0
                error("sixgr:phy:pdcch:dci_size_alignment_failure", ...
                    "Frequency-field truncation requires an explicit Release-18 context not enabled by this schema.");
            end
            if alignment.Selected.PaddingBits > 0
                pad = alignment.Selected.PaddingBits;
                stop = cursor + pad - 1;
                bits(cursor:stop) = 0;
                generated = sixgr.phy.pdcch.DCIFieldDefinition( ...
                    "padding", pad, 0, 0, "TS 38.212 monitored-size alignment", ...
                    "38.212 7.3.1.0", true);
                rows(end+1,1) = localMakeRow(generated, 0, cursor, stop); %#ok<AGROW>
                cursor = stop + 1;
            end
            if cursor - 1 ~= alignment.Selected.AlignedBits
                error("sixgr:phy:pdcch:dci_size_alignment_failure", ...
                    "Resolved field widths consume %d bits but aligned K is %d.", ...
                    cursor - 1, alignment.Selected.AlignedBits);
            end
            dci = struct( ...
                "Format", string(context.Data.DCIFormat), ...
                "Direction", string(ternary(startsWith(context.Data.DCIFormat,"0_"),"UL","DL")), ...
                "GrantType", string(ternary(startsWith(context.Data.DCIFormat,"0_"),"PUSCH","PDSCH")), ...
                "Fields", fields, ...
                "Bits", bits, ...
                "PayloadHex", sixgr.phy.pdcch.payloadBitsToHex(bits), ...
                "PayloadHash", string(sixgr.rrc.asn1.asn1SHA256Hex(uint8(bits(:)))), ...
                "FieldTable", struct2table(rows, "AsArray", true), ...
                "BitExactPDCCHPayload", true, ...
                "StandardProfile", "3gpp_ts_38_212_v18_8_0_contextual", ...
                "ContextDigest", context.Digest, ...
                "Schema", schema, ...
                "SizeDetails", alignment.Selected, ...
                "Alignment", alignment);
        end
    end
end

function bits = localUIntToBits(value, width)
value = uint64(value);
bits = zeros(width, 1, "int8");
for ii = 1:width
    bits(ii) = int8(bitget(value, width - ii + 1));
end
end

function row = localFieldRow()
row = struct("FieldOrder", NaN, "FieldName", "", "Present", true, ...
    "WidthBits", NaN, "BitStart", NaN, "BitEnd", NaN, "Value", NaN, ...
    "ValueMin", NaN, "ValueMax", NaN, "SemanticSource", "", ...
    "ReleaseClause", "", "Generated", false, ...
    "BitOffsetStart", NaN, "BitOffsetEnd", NaN);
end

function row = localMakeRow(definition, value, cursor, stop)
row = localFieldRow();
row.FieldOrder = NaN;
row.FieldName = definition.Name;
row.WidthBits = definition.Width;
row.BitStart = cursor - 1;
row.BitEnd = stop - 1;
row.Value = value;
row.ValueMin = definition.ValueMin;
row.ValueMax = definition.ValueMax;
row.SemanticSource = definition.SemanticSource;
row.ReleaseClause = definition.ReleaseClause;
row.Generated = definition.Generated;
row.BitOffsetStart = row.BitStart;
row.BitOffsetEnd = row.BitEnd;
end

function value = ternary(condition, a, b)
if condition
    value = a;
else
    value = b;
end
end
