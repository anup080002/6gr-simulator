classdef CSIReportState
    %CSIREPORTSTATE Immutable report-dependent CSI Part-1/Part-2 state.

    properties (SetAccess=private)
        Data
        Digest
    end

    methods
        function obj = CSIReportState(data)
            required = ["ReportID","Priority","Part1Fields","Part2Fields", ...
                "ConfigurationEpoch"];
            sixgr.phy.pucch.UCIReport.requireFields(data,required);
            [part1,names1,widths1] = localFields(data.Part1Fields);
            [part2,names2,widths2] = localFields(data.Part2Fields);
            padding = max(0,3-numel(part2))*double(~isempty(part2));
            data.Part1Bits = part1;
            data.Part2InformationBits = part2;
            data.Part2Bits = part2;
            data.Part2PaddingBits = padding;
            data.Part1FieldNames = names1;
            data.Part2FieldNames = names2;
            data.Part1Widths = widths1;
            data.Part2Widths = widths2;
            obj.Data = data;
            obj.Digest = sixgr.phy.pucch.PUCCHUtil.hash(data);
        end
    end
end

function [bits,names,widths] = localFields(fields)
bits = int8(zeros(0,1)); names = strings(0,1); widths = zeros(0,1);
if isempty(fields), return; end
for index = 1:numel(fields)
    width = double(fields(index).Width);
    value = sixgr.phy.pucch.PUCCHUtil.bits(fields(index).Bits);
    if width ~= numel(value)
        error("sixgr:phy:pucch:UCILengthMismatch", ...
            "CSI field %s declares width %d but carries %d bits.", ...
            string(fields(index).Name),width,numel(value));
    end
    bits = [bits;value]; %#ok<AGROW>
    names = [names;string(fields(index).Name)]; %#ok<AGROW>
    widths = [widths;width]; %#ok<AGROW>
end
end
