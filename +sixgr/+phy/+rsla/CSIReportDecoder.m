classdef CSIReportDecoder
    %CSIREPORTDECODER Reconstruct typed fields after canonical UCI decoding.

    methods (Static)
        function result = decode(bits,configuration,crcValid,semanticValid)
            if ~crcValid || ~semanticValid
                error("RSLA:CSIReportDecodeFailure", ...
                    "CSI report failed CRC or semantic validation.");
            end
            bits = int8(bits(:));
            expected = configuration.Data.Part1Bits+configuration.Data.Part2Bits;
            if numel(bits)~=expected
                error("RSLA:InvalidCSIPayloadLength", ...
                    "Decoded CSI length %d does not match configured length %d.", ...
                    numel(bits),expected);
            end
            offset = 0;
            fields = struct();
            allNames = [configuration.Data.Part1Fields ...
                configuration.Data.Part2Fields];
            allWidths = [configuration.Data.Part1Widths ...
                configuration.Data.Part2Widths];
            for index = 1:numel(allNames)
                width = allWidths(index);
                raw = double(bits(offset+(1:width))).';
                fields.(char(allNames(index))) = bi2de(raw,"left-msb");
                offset = offset+width;
            end
            result = struct("Fields",fields,"CRCValid",true, ...
                "SemanticValid",true, ...
                "ConfigurationEpoch",configuration.Data.ConfigurationEpoch, ...
                "Source","decoded_canonical_uci_transport");
        end
    end
end
