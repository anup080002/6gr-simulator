classdef UCIReportSerializer
    %UCIREPORTSERIALIZER TS 38.212 ordered UCI sequence serialization.

    methods (Static)
        function result = serialize(report)
            if ~isa(report, "sixgr.phy.pucch.UCIReport")
                error("sixgr:phy:pucch:MissingUCIReportContext", ...
                    "Serialization requires a typed UCIReport.");
            end
            d = report.Data;
            [harqBits, harqNames] = sixgr.phy.pucch.UCIReportSerializer.harq(d.HARQACKReport);
            [srBits, srNames] = sixgr.phy.pucch.UCIReportSerializer.sr(d.SchedulingRequestReports);
            [csi1, csi1Names, csi2, csi2Names] = ...
                sixgr.phy.pucch.UCIReportSerializer.csi(d.CSIReports);
            bits1 = [harqBits; srBits; csi1];
            owners1 = [repmat("HARQ_ACK",numel(harqBits),1); ...
                repmat("SR",numel(srBits),1); ...
                repmat("CSI_PART1",numel(csi1),1)];
            names1 = [harqNames; srNames; csi1Names];
            padding = max(0, 3-numel(csi2)) * double(~isempty(csi2));
            bits2 = [csi2; zeros(padding,1,"int8")];
            owners2 = [repmat("CSI_PART2",numel(csi2),1); ...
                repmat("PADDING",padding,1)];
            names2 = [csi2Names; repmat("minimum_part2_padding",padding,1)];
            sequence1 = sixgr.phy.pucch.UCISequence(1,bits1,owners1,names1);
            sequence2 = sixgr.phy.pucch.UCISequence(2,bits2,owners2,names2);
            result = struct( ...
                "Sequence1", sequence1, "Sequence2", sequence2, ...
                "Sequences", {{sequence1, sequence2}}, ...
                "ExpectedSequenceCount", 1 + double(~isempty(bits2)), ...
                "InformationBitCount", numel(bits1)+numel(csi2), ...
                "PaddingBitCount", padding);
            result.Layout = sixgr.phy.pucch.UCIReportSerializer.layout( ...
                report.ReportID, sequence1, sequence2);
            result.Digest = sixgr.phy.pucch.PUCCHUtil.hash(struct( ...
                "Sequence1", bits1.', "Sequence2", bits2.', ...
                "LayoutOwners", string(result.Layout.BitOwner).'));
        end

        function result = serializeVector(row)
            harqBits = sixgr.phy.pucch.PUCCHUtil.bits( ...
                sixgr.phy.pucch.PUCCHUtil.text(row,"HARQACKBits",""));
            srBits = sixgr.phy.pucch.PUCCHUtil.bits( ...
                sixgr.phy.pucch.PUCCHUtil.text(row,"SRBits",""));
            csi1 = sixgr.phy.pucch.PUCCHUtil.bits( ...
                sixgr.phy.pucch.PUCCHUtil.text(row,"CSIPart1Bits",""));
            csi2 = sixgr.phy.pucch.PUCCHUtil.bits( ...
                sixgr.phy.pucch.PUCCHUtil.text(row,"CSIPart2Bits",""));
            state = struct( ...
                "ReportID", sixgr.phy.pucch.PUCCHUtil.text(row,"CaseID"), ...
                "RNTI", 1, "ServingCell", 0, "ComponentCarrier", 0, ...
                "ULBWP", 0, "ConfigurationEpoch", ...
                sixgr.phy.pucch.PUCCHUtil.number(row,"ConfigurationEpoch",1), ...
                "TargetSlot", 0, "PriorityIndex", ...
                sixgr.phy.pucch.PUCCHUtil.number(row,"HARQPriority",0), ...
                "HARQACKReport", struct("Bits",harqBits), ...
                "SchedulingRequestReports", struct("Bits",srBits), ...
                "CSIReports", struct("Part1Bits",csi1,"Part2Bits",csi2, ...
                    "Priority",sixgr.phy.pucch.PUCCHUtil.number( ...
                    row,"CSIReportPriority",0),"ReportID",1), ...
                "ReportSource", "independent_vector_procedure_state", ...
                "TriggeringEventIDs", string.empty(1,0));
            result = sixgr.phy.pucch.UCIReportSerializer.serialize( ...
                sixgr.phy.pucch.UCIReport(state));
        end

        function result = extractDecodedInformationBits(serialized, decodedWireBits)
            %EXTRACTDECODEDINFORMATIONBITS Invert the owned wire layout.
            % Padding remains part of waveform evidence but is not CSI
            % information delivered to the report parser.
            if ~isstruct(serialized) || ~isfield(serialized, "Layout") || ...
                    ~istable(serialized.Layout) || ...
                    ~ismember("BitOwner", string(serialized.Layout.Properties.VariableNames))
                error("sixgr:phy:pucch:InvalidUCISerializedLayout", ...
                    "Decoded UCI extraction requires the serializer-owned bit layout.");
            end
            decodedWireBits = sixgr.phy.pucch.PUCCHUtil.bits(decodedWireBits);
            owners = string(serialized.Layout.BitOwner(:));
            if numel(decodedWireBits) ~= numel(owners)
                error("sixgr:phy:pucch:UCILengthMismatch", ...
                    "Decoded PUCCH wire payload has %d bits; the frozen UCI layout requires %d.", ...
                    numel(decodedWireBits), numel(owners));
            end
            result = struct( ...
                "WireBits", decodedWireBits, ...
                "InformationBits", decodedWireBits(owners ~= "PADDING"), ...
                "HARQACKBits", decodedWireBits(owners == "HARQ_ACK"), ...
                "SRBits", decodedWireBits(owners == "SR"), ...
                "CSIPart1Bits", decodedWireBits(owners == "CSI_PART1"), ...
                "CSIPart2Bits", decodedWireBits(owners == "CSI_PART2"), ...
                "PaddingBits", decodedWireBits(owners == "PADDING"), ...
                "BitOwners", owners);
        end
    end

    methods (Static, Access=private)
        function [bits, names] = harq(input)
            bits = int8(zeros(0,1)); names = strings(0,1);
            if isempty(input), return; end
            if isa(input, "sixgr.phy.pucch.HARQACKCodebookState")
                bits = input.Bits;
                names = "HARQ_ACK_" + string((0:numel(bits)-1).');
            elseif isstruct(input) && isfield(input,"Bits")
                bits = sixgr.phy.pucch.PUCCHUtil.bits(input.Bits);
                names = "HARQ_ACK_" + string((0:numel(bits)-1).');
            end
        end

        function [bits, names] = sr(input)
            bits = int8(zeros(0,1)); names = strings(0,1);
            if isempty(input), return; end
            if isa(input, "sixgr.phy.pucch.SchedulingRequestState")
                input = arrayfun(@(x) x.Data, input);
            end
            if isstruct(input)
                for index = 1:numel(input)
                    if isfield(input(index),"Bits")
                        next = sixgr.phy.pucch.PUCCHUtil.bits(input(index).Bits);
                    elseif isfield(input(index),"Value")
                        next = int8(logical(input(index).Value));
                    else
                        continue;
                    end
                    bits = [bits; next]; %#ok<AGROW>
                    names = [names; repmat("SR_" + string(index),numel(next),1)]; %#ok<AGROW>
                end
            end
        end

        function [part1, names1, part2, names2] = csi(input)
            part1 = int8(zeros(0,1)); part2 = int8(zeros(0,1));
            names1 = strings(0,1); names2 = strings(0,1);
            if isempty(input), return; end
            if isa(input, "sixgr.phy.pucch.CSIReportState")
                input = arrayfun(@(x) x.Data, input);
            end
            [~,order] = sortrows([[input.Priority].' [input.ReportID].'],[1 2]);
            input = input(order);
            for index = 1:numel(input)
                p1 = sixgr.phy.pucch.PUCCHUtil.bits(input(index).Part1Bits);
                p2 = sixgr.phy.pucch.PUCCHUtil.bits(input(index).Part2Bits);
                part1 = [part1;p1]; %#ok<AGROW>
                part2 = [part2;p2]; %#ok<AGROW>
                names1 = [names1; repmat("CSI_" + string(input(index).ReportID) + ...
                    "_PART1",numel(p1),1)]; %#ok<AGROW>
                names2 = [names2; repmat("CSI_" + string(input(index).ReportID) + ...
                    "_PART2",numel(p2),1)]; %#ok<AGROW>
            end
        end

        function value = layout(reportID, sequence1, sequence2)
            sequences = [repmat(1,numel(sequence1.Bits),1); ...
                repmat(2,numel(sequence2.Bits),1)];
            bitIndex = [(0:numel(sequence1.Bits)-1).'; ...
                (0:numel(sequence2.Bits)-1).'];
            value = table();
            value.ReportID = repmat(string(reportID),numel(sequences),1);
            value.SequenceIndex = sequences;
            value.BitIndex = bitIndex;
            value.BitOwner = [sequence1.Owners;sequence2.Owners];
            value.FieldName = [sequence1.FieldNames;sequence2.FieldNames];
            value.BitValue = [sequence1.Bits;sequence2.Bits];
        end
    end
end
