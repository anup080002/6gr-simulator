classdef DCIParser
    %DCIPARSER Exact-length contextual DCI parser and semantic resolver.

    methods (Static)
        function dci = parse(bits, context)
            context = sixgr.phy.pdcch.DCISchemaEngine.requireContext(context);
            if ~(isnumeric(bits) || islogical(bits)) || ~isreal(bits) || ...
                    ~isvector(bits) || any(~isfinite(bits(:))) || any(bits(:) ~= 0 & bits(:) ~= 1)
                error("sixgr:phy:pdcch:payload_length_mismatch", ...
                    "DCI payload must contain binary values only.");
            end
            bits = int8(bits(:));
            schema = sixgr.phy.pdcch.DCISchemaEngine.resolve(context);
            alignment = sixgr.phy.pdcch.DCISizeAlignmentEngine.resolve(context);
            K = alignment.Selected.AlignedBits;
            if numel(bits) ~= K
                error("sixgr:phy:pdcch:payload_length_mismatch", ...
                    "DCI %s requires exactly %d bits in context %s; received %d.", ...
                    context.Data.DCIFormat, K, context.Digest, numel(bits));
            end
            definitions = schema.Definitions;
            fields = struct();
            rows = repmat(localFieldRow(), 0, 1);
            cursor = 1;
            for ii = 1:numel(definitions)
                definition = definitions(ii);
                stop = cursor + definition.Width - 1;
                value = localBitsToUInt(bits(cursor:stop));
                if value < definition.ValueMin || value > definition.ValueMax
                    error("sixgr:phy:pdcch:field_out_of_range", ...
                        "Decoded field '%s'=%g is outside [%g,%g].", ...
                        definition.Name, value, definition.ValueMin, definition.ValueMax);
                end
                fields.(char(definition.Name)) = value;
                rows(end+1,1) = localMakeRow(definition, value, cursor, stop); %#ok<AGROW>
                cursor = stop + 1;
            end
            padding = alignment.Selected.PaddingBits;
            if padding > 0
                padBits = bits(cursor:cursor+padding-1);
                if any(padBits ~= 0)
                    error("sixgr:phy:pdcch:dci_size_alignment_failure", ...
                        "DCI alignment padding contains nonzero bits.");
                end
                cursor = cursor + padding;
            end
            if cursor - 1 ~= K
                error("sixgr:phy:pdcch:dci_size_alignment_failure", ...
                    "Parser consumed %d of %d aligned payload bits.", cursor - 1, K);
            end
            derived = sixgr.phy.pdcch.DCIParser.resolveSemantics(fields, context);
            dci = struct( ...
                "Format", string(context.Data.DCIFormat), ...
                "Direction", string(derived.direction), ...
                "GrantType", string(derived.grant_type), ...
                "Fields", localMerge(fields, derived), ...
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

        function derived = resolveSemantics(fields, context)
            data = context.Data;
            if string(data.RNTIType)=="TC-RNTI" && isfield(data,'FrequencyReferenceSize')
                derived = sixgr.phy.pdcch.TCMsg4DCIContext.resolveSemantics(fields,context);
                return;
            end
            if string(data.RNTIType) == "RA-RNTI"
                derived = sixgr.phy.pdcch.RARDCIContext.resolveSemantics(fields,context);
                return;
            end
            fmt = string(data.DCIFormat);
            if startsWith(fmt, "0_")
                nBWP = double(data.ActiveULBWPSize);
                allocations = data.ULTimeDomainAllocations;
                direction = "UL";
                grantType = "PUSCH";
            else
                nBWP = double(data.ActiveDLBWPSize);
                allocations = data.DLTimeDomainAllocations;
                direction = "DL";
                grantType = "PDSCH";
            end
            if ~ismember(lower(string(data.FrequencyAllocationType)), ["type1","type1_riv"])
                error("sixgr:phy:pdcch:field_out_of_range", ...
                    "Grant materialization currently requires type1_riv allocation.");
            end
            [prbStart, numPRB, valid] = sixgr.phy.pdcch.rivDecode( ...
                fields.frequency_resource_assignment, nBWP);
            if ~valid
                error("sixgr:phy:pdcch:field_out_of_range", ...
                    "Decoded frequency_resource_assignment is not a valid RIV for BWP size %d.", nBWP);
            end
            if ~isfield(fields,'time_resource_assignment') && isfield(data,'ConnectedPolicy') && size(allocations,1)==1
                index=0;
            else
                index = double(fields.time_resource_assignment);
            end
            row = allocations(allocations(:,1) == index, :);
            if size(row, 1) ~= 1
                error("sixgr:phy:pdcch:field_out_of_range", ...
                    "Time-domain allocation index %d is absent from the installed %s list.", ...
                    index, direction);
            end
            derived = struct( ...
                "prb_start", double(prbStart), ...
                "num_prb", double(numPRB), ...
                "frequency_resource_assignment_valid", true, ...
                "symbol_start", double(row(1,2)), ...
                "num_symbols", double(row(1,3)), ...
                "timing_offset_slots", double(row(1,min(4,size(row,2)))), ...
                "direction", direction, ...
                "grant_type", grantType, ...
                "scheduled_serving_cell", double(data.ScheduledServingCell), ...
                "scheduled_carrier", double(data.ScheduledCarrier), ...
                "scheduled_bwp", double(data.ScheduledBWP), ...
                "configuration_epoch", double(data.ConfigurationEpoch));
            if isfield(data,'ConnectedPolicy')
                derived.time_domain_assignment_index=index;
                if fmt=="1_1"
                    indicator=0;
                    if isfield(fields,'pdsch_to_harq_feedback_timing'), indicator=fields.pdsch_to_harq_feedback_timing; end
                    derived.pdsch_to_harq_feedback_timing_slots=data.DLDataToULACK(indicator+1);
                end
            end
            if direction=="DL" && isfield(data,'HARQFeedbackTimingConfigured')
                indicator=[];
                if isfield(fields,'pdsch_to_harq_feedback_timing')
                    indicator=fields.pdsch_to_harq_feedback_timing;
                end
                derived.pdsch_to_harq_feedback_timing_slots = ...
                    sixgr.phy.pdcch.HARQFeedbackTiming.decode(data,indicator);
            end
            if isfield(fields, "tpc_command_for_pusch")
                derived.tpc = double(fields.tpc_command_for_pusch);
            elseif isfield(fields, "tpc_command_for_pucch")
                derived.tpc = double(fields.tpc_command_for_pucch);
            end
            if fmt == "0_1" && isfield(fields, ...
                    "precoding_information_and_number_of_layers")
                combined = double(fields.precoding_information_and_number_of_layers);
                if isfield(data,'ULPrecoding')
                    [rank,tpmi]=sixgr.phy.pdcch.ULPrecodingField.decode(data,combined);
                    derived.precoding_information_and_number_of_layers_tpmi=tpmi;
                    derived.precoding_information_and_number_of_layers_rank_minus1=rank-1;
                else
                    derived.precoding_information_and_number_of_layers_tpmi = mod(combined, 16);
                    derived.precoding_information_and_number_of_layers_rank_minus1 = floor(combined / 16);
                end
            end
            if fmt=="1_1" && isfield(data,'DLReferenceSignaling')
                [ports,groups,rank]=sixgr.phy.pdcch.DLReferenceSignaling.decodeAntenna(data,fields.antenna_ports);
                derived.dmrs_port_set=ports;
                derived.dmrs_num_cdm_groups_without_data=groups;
                derived.dmrs_front_load_symbols=1;
                derived.num_layers=rank;
            end
            if fmt=="0_1" && isfield(data,'ULReferenceSignaling')
                ref=sixgr.phy.pdcch.ULReferenceSignaling.resolve(data);
                rank=derived.precoding_information_and_number_of_layers_rank_minus1+1;
                [ports,groups]=sixgr.phy.pdcch.ULReferenceSignaling.decodeAntenna(data,rank,fields.antenna_ports);
                derived.dmrs_port_set=ports;
                derived.dmrs_num_cdm_groups_without_data=groups;
                derived.dmrs_front_load_symbols=1;
                if ref.SRIWidth==0
                    derived.srs_resource_index0based=0;
                    derived.srs_resource_selection_source="implicit_single_configured_resource";
                else
                    derived.srs_resource_index0based=fields.srs_resource_indicator;
                    derived.srs_resource_selection_source="received_srs_resource_indicator";
                end
            end
        end
    end
end

function value = localBitsToUInt(bits)
value = uint64(0);
for ii = 1:numel(bits)
    value = bitshift(value, 1) + uint64(bits(ii) ~= 0);
end
value = double(value);
end

function out = localMerge(a, b)
out = a;
names = fieldnames(b);
for ii = 1:numel(names)
    out.(names{ii}) = b.(names{ii});
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
