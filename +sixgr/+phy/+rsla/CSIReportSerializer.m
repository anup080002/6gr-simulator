classdef CSIReportSerializer
    %CSIREPORTSERIALIZER Exact Part 1/Part 2 field serializer.

    methods (Static)
        function result = serialize(report)
            if ~isa(report,"sixgr.phy.rsla.CSIReport")
                error("RSLA:InvalidCSIReportConfiguration", ...
                    "Typed CSIReport input is required.");
            end
            [part1,owner1,field1,fieldBit1] = localSerialize(report.Part1);
            [part2,owner2,field2,fieldBit2] = localSerialize(report.Part2);
            result = struct("ReportID",report.ReportID, ...
                "Part1Bits",part1,"Part2Bits",part2, ...
                "Owners",[owner1;owner2],"FieldNames",[field1;field2], ...
                "FieldBitIndices",[fieldBit1;fieldBit2], ...
                "ConfigurationEpoch",report.Configuration.Data.ConfigurationEpoch, ...
                "Transport",report.Configuration.Data.Transport);
        end

        function roundTrip = transportRoundTrip(report)
            serialized = sixgr.phy.rsla.CSIReportSerializer.serialize(report);
            information = int8([serialized.Part1Bits;serialized.Part2Bits]);
            a = numel(information);
            if a==0
                error("RSLA:InvalidCSIPayloadLength","CSI payload must be nonempty.");
            end
            e = max(2048,8*a);
            sequence = sixgr.phy.pucch.UCISequence(1,information, ...
                repmat("CSI",a,1),repmat("typed_rsla_report",a,1));
            encoded = sixgr.phy.pucch.UCIEncoder.encode(sequence,e,"QPSK");
            coded = double(encoded.CodedBits(:));
            llr = zeros(size(coded));
            llr(coded==0) = 100;
            llr(coded==1) = -100;
            decoded = sixgr.phy.pucch.UCIDecoder.decode(llr,a);
            recovered = int8(decoded.Bits(:));
            common = min(numel(recovered),a);
            bitErrors = abs(numel(recovered)-a)+ ...
                sum(recovered(1:common)~=information(1:common));
            roundTrip = struct("InformationBits",a, ...
                "EncodedBits",numel(coded),"DecodedBits",numel(recovered), ...
                "RecoveredBits",recovered,"BitErrors",bitErrors, ...
                "CRCStatus",bitErrors==0,"SemanticStatus",bitErrors==0, ...
                "Transport",serialized.Transport);
        end
    end
end

function [bits,owners,names,fieldIndices] = localSerialize(part)
bits = zeros(sum(part.Widths),1,"int8");
owners = repmat("Part"+part.Part,numel(bits),1);
names = strings(numel(bits),1);
fieldIndices = zeros(numel(bits),1);
offset = 0;
for fieldIndex = 1:numel(part.Fields)
    width = part.Widths(fieldIndex);
    raw = de2bi(part.Values(fieldIndex),width,"left-msb").';
    range = offset+(1:width);
    bits(range) = int8(raw);
    names(range) = part.Fields(fieldIndex);
    fieldIndices(range) = (0:width-1).';
    offset = offset+width;
end
end
