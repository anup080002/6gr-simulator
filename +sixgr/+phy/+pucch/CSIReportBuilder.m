classdef CSIReportBuilder
    %CSIREPORTBUILDER Build and order CSI reports from configured state.

    methods (Static)
        function states = build(reports,configurationEpoch)
            if isempty(reports)
                states = sixgr.phy.pucch.CSIReportState.empty(0,1);
                return;
            end
            states = sixgr.phy.pucch.CSIReportState.empty(0,1);
            for index = 1:numel(reports)
                reports(index).ConfigurationEpoch = configurationEpoch;
                states(end+1,1) = sixgr.phy.pucch.CSIReportState(reports(index)); %#ok<AGROW>
            end
            priorities = arrayfun(@(x) double(x.Data.Priority),states);
            ids = arrayfun(@(x) double(x.Data.ReportID),states);
            [~,order] = sortrows([priorities(:) ids(:)],[1 2]);
            states = states(order);
        end

        function states = buildVector(row)
            reports = jsondecode(char(sixgr.phy.pucch.PUCCHUtil.text( ...
                row,"ReportsJSON","[]")));
            states = sixgr.phy.pucch.CSIReportBuilder.build(reports, ...
                sixgr.phy.pucch.PUCCHUtil.number(row,"ConfigurationEpoch",0));
        end
    end
end
