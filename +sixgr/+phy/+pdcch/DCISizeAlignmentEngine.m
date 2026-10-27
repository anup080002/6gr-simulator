classdef DCISizeAlignmentEngine
    %DCISIZEALIGNMENTENGINE Release-18 monitored DCI size alignment.

    methods (Static)
        function result = resolve(context)
            context = sixgr.phy.pdcch.DCISchemaEngine.requireContext(context);
            data = context.Data;
            formats = string(data.MonitoredFormats(:));
            if isempty(formats)
                formats = string(data.DCIFormat);
            end
            rows = repmat(localRow(), numel(formats), 1);
            for ii = 1:numel(formats)
                peerData = data;
                peerData.DCIFormat = formats(ii);
                peer = sixgr.phy.pdcch.DCIContext(peerData);
                schema = sixgr.phy.pdcch.DCISchemaEngine.resolve(peer);
                rows(ii).DCIFormat = formats(ii);
                rows(ii).ContextDigest = peer.Digest;
                rows(ii).RawBits = schema.RawBits;
                rows(ii).AlignedBits = schema.RawBits;
                rows(ii).PaddingBits = 0;
                rows(ii).TruncatedFrequencyBits = 0;
                rows(ii).AlignmentGroup = localGroup(formats(ii), data.SearchSpaceType);
            end

            idx00 = find(string({rows.DCIFormat}) == "0_0", 1);
            idx10 = find(string({rows.DCIFormat}) == "1_0", 1);
            if ~isempty(idx00) && ~isempty(idx10)
                common=any(upper(string(data.SearchSpaceType))==["CSS","TYPE0","TYPE0A","TYPE1","TYPE2","TYPE3"]);
                if common
                    % Step0 aligns UL to the DL common size, including
                    % leading FDRA truncation. It never pads common 1_0.
                    target=rows(idx10).RawBits;
                else
                    target = max(rows(idx00).RawBits, rows(idx10).RawBits);
                end
                rows(idx00).AlignedBits = target;
                rows(idx10).AlignedBits = target;
                if rows(idx00).RawBits < target
                    rows(idx00).PaddingBits = target - rows(idx00).RawBits;
                elseif rows(idx00).RawBits > target
                    rows(idx00).TruncatedFrequencyBits = rows(idx00).RawBits - target;
                end
                if rows(idx10).RawBits < target
                    rows(idx10).PaddingBits = target - rows(idx10).RawBits;
                end
            end

            uniqueSizes = unique([rows.AlignedBits]);
            cRNTIFormats = ismember(string({rows.DCIFormat}), ["0_0","0_1","1_0","1_1"]) ...
                & string(data.RNTIType) == "C-RNTI";
            cRNTISizes = unique([rows(cRNTIFormats).AlignedBits]);
            if numel(uniqueSizes) > 4 || numel(cRNTISizes) > 3
                error("sixgr:phy:pdcch:too_many_monitored_dci_sizes", ...
                    "The monitored set resolves to %d total and %d C-RNTI DCI sizes; limits are 4 and 3.", ...
                    numel(uniqueSizes), numel(cRNTISizes));
            end
            selected = find(string({rows.DCIFormat}) == string(data.DCIFormat), 1);
            if isempty(selected)
                error("sixgr:phy:pdcch:dci_size_alignment_failure", ...
                    "Selected format %s is absent from MonitoredFormats.", data.DCIFormat);
            end
            result = struct( ...
                "Rows", rows, ...
                "Selected", rows(selected), ...
                "UniqueMonitoredSizes", uniqueSizes, ...
                "UniqueCRNTISizes", cRNTISizes, ...
                "Status", "PASS");
        end

        function definitions = wireDefinitions(schema,selected)
            definitions=schema.Definitions;
            cut=selected.TruncatedFrequencyBits;
            if cut==0, return; end
            assert(schema.Format=="0_0" && cut==fix(cut) && cut>0, ...
                'sixgr:phy:pdcch:dci_size_alignment_failure','Only fallback UL FDRA can be truncated.');
            hit=find(string({definitions.Name})=="frequency_resource_assignment");
            assert(isscalar(hit) && definitions(hit).Width>=cut, ...
                'sixgr:phy:pdcch:dci_size_alignment_failure','Truncation must fit the original FDRA.');
            d=definitions(hit); width=d.Width-cut;
            definitions(hit)=sixgr.phy.pdcch.DCIFieldDefinition(d.Name,width,0, ...
                min(d.ValueMax,2^width-1),d.SemanticSource, ...
                "TS38.212 V18.8.0 7.3.1.0 leading FDRA truncation",d.Generated);
        end
    end
end

function row = localRow()
row = struct("DCIFormat", "", "ContextDigest", "", "RawBits", NaN, ...
    "AlignedBits", NaN, "PaddingBits", 0, "TruncatedFrequencyBits", 0, ...
    "AlignmentGroup", "");
end

function value = localGroup(format, searchSpaceType)
if any(string(format) == ["0_0","1_0"])
    value = "common_0_0_1_0_" + upper(string(searchSpaceType));
else
    value = "contextual_" + string(format) + "_" + upper(string(searchSpaceType));
end
end
