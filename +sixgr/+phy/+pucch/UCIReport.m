classdef UCIReport
    %UCIREPORT Immutable typed UCI report constructed from procedure state.

    properties (SetAccess=private)
        Data
        Digest
    end

    properties (Dependent)
        ReportID
        ConfigurationEpoch
        PriorityIndex
    end

    methods
        function obj = UCIReport(data)
            if nargin ~= 1 || ~isstruct(data) || numel(data) ~= 1
                error("sixgr:phy:pucch:MissingUCIReportContext", ...
                    "UCIReport requires one complete procedure-state structure.");
            end
            required = ["ReportID","RNTI","ServingCell","ComponentCarrier", ...
                "ULBWP","ConfigurationEpoch","TargetSlot","PriorityIndex", ...
                "HARQACKReport","SchedulingRequestReports","CSIReports", ...
                "ReportSource","TriggeringEventIDs"];
            sixgr.phy.pucch.UCIReport.requireFields(data, required);
            sixgr.phy.pucch.PUCCHUtil.assertInteger(double(data.RNTI), ...
                1, 65535, "sixgr:phy:pucch:WrongRNTI", "RNTI");
            sixgr.phy.pucch.PUCCHUtil.assertInteger( ...
                double(data.ConfigurationEpoch), 0, flintmax, ...
                "sixgr:phy:pucch:StaleConfiguration", "ConfigurationEpoch");
            obj.Data = data;
            obj.Digest = sixgr.phy.pucch.PUCCHUtil.hash(data);
        end

        function value = get.ReportID(obj)
            value = string(obj.Data.ReportID);
        end

        function value = get.ConfigurationEpoch(obj)
            value = double(obj.Data.ConfigurationEpoch);
        end

        function value = get.PriorityIndex(obj)
            value = double(obj.Data.PriorityIndex);
        end
    end

    methods (Static)
        function obj = fromProcedureState(state)
            obj = sixgr.phy.pucch.UCIReport(state);
        end

        function requireFields(data, names)
            missing = names(~isfield(data, cellstr(names)));
            if ~isempty(missing)
                error("sixgr:phy:pucch:MissingUCIReportContext", ...
                    "UCI report context is missing: %s.", join(missing, ", "));
            end
        end
    end
end
