classdef UCIReportContext
    %UCIREPORTCONTEXT Receiver schema with lengths and no payload values.

    properties (SetAccess=private)
        Data
        Digest
    end

    properties (Dependent)
        ReportID
        ConfigurationEpoch
        Sequence1Length
        Sequence2Length
        HARQACKBits
        SRBits
        CSIPart1Bits
        CSIPart2Bits
    end

    methods
        function obj = UCIReportContext(data)
            if nargin ~= 1 || ~isstruct(data) || numel(data) ~= 1
                error("sixgr:phy:pucch:MissingUCIReportContext", ...
                    "Receiver UCIReportContext is mandatory.");
            end
            forbidden = ["ExpectedUCIBits","TransmittedUCIBits", ...
                "TransmittedPayloadBits","ExpectedPayloadBits", ...
                "PayloadDigest","SerializedBits"];
            present = forbidden(isfield(data, cellstr(forbidden)));
            if ~isempty(present)
                error("sixgr:phy:pucch:OracleInputForbidden", ...
                    "Receiver context contains forbidden payload oracle field(s): %s.", ...
                    join(present, ", "));
            end
            required = ["ReportID","ConfigurationEpoch","Sequence1Length", ...
                "Sequence2Length","HARQACKBits","SRBits","CSIPart1Bits", ...
                "CSIPart2Bits","PriorityIndex"];
            sixgr.phy.pucch.UCIReport.requireFields(data, required);
            counts = double([data.HARQACKBits data.SRBits ...
                data.CSIPart1Bits data.CSIPart2Bits]);
            if any(~isfinite(counts) | counts < 0 | counts ~= fix(counts))
                error("sixgr:phy:pucch:UCILengthMismatch", ...
                    "All UCI report-context lengths must be nonnegative integers.");
            end
            if double(data.Sequence1Length) ~= sum(counts(1:3)) || ...
                    double(data.Sequence2Length) < counts(4)
                error("sixgr:phy:pucch:UCILengthMismatch", ...
                    "Sequence lengths do not agree with the owned report fields.");
            end
            obj.Data = data;
            obj.Digest = sixgr.phy.pucch.PUCCHUtil.hash(data);
        end

        function value = get.ReportID(obj), value = string(obj.Data.ReportID); end
        function value = get.ConfigurationEpoch(obj), value = double(obj.Data.ConfigurationEpoch); end
        function value = get.Sequence1Length(obj), value = double(obj.Data.Sequence1Length); end
        function value = get.Sequence2Length(obj), value = double(obj.Data.Sequence2Length); end
        function value = get.HARQACKBits(obj), value = double(obj.Data.HARQACKBits); end
        function value = get.SRBits(obj), value = double(obj.Data.SRBits); end
        function value = get.CSIPart1Bits(obj), value = double(obj.Data.CSIPart1Bits); end
        function value = get.CSIPart2Bits(obj), value = double(obj.Data.CSIPart2Bits); end
    end

    methods (Static)
        function obj = fromReport(report)
            if ~isa(report, "sixgr.phy.pucch.UCIReport")
                error("sixgr:phy:pucch:MissingUCIReportContext", ...
                    "fromReport requires a typed UCIReport.");
            end
            serialized = sixgr.phy.pucch.UCIReportSerializer.serialize(report);
            owners = string(serialized.Layout.BitOwner);
            data = struct( ...
                "ReportID", report.ReportID, ...
                "ConfigurationEpoch", report.ConfigurationEpoch, ...
                "Sequence1Length", numel(serialized.Sequence1.Bits), ...
                "Sequence2Length", numel(serialized.Sequence2.Bits), ...
                "HARQACKBits", sum(owners == "HARQ_ACK"), ...
                "SRBits", sum(owners == "SR"), ...
                "CSIPart1Bits", sum(owners == "CSI_PART1"), ...
                "CSIPart2Bits", sum(owners == "CSI_PART2"), ...
                "PriorityIndex", report.PriorityIndex, ...
                "FieldLayout", removevars(serialized.Layout, "BitValue"));
            obj = sixgr.phy.pucch.UCIReportContext(data);
        end
    end
end
