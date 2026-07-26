classdef RFStageLedger < handle
%RFSTAGELEDGER Ordered, reference-plane-aware RF stage ledger.

    properties(SetAccess=private)
        Rows struct = struct.empty(0, 1)
        ConfigurationEpoch (1,1) double
    end

    methods
        function obj = RFStageLedger(configurationEpoch)
            arguments
                configurationEpoch (1,1) double {mustBeFinite} = 1
            end
            obj.ConfigurationEpoch = configurationEpoch;
        end

        function append(obj, row)
            required = ["Stage","InputReferencePlane","OutputReferencePlane", ...
                "InputSHA256","OutputSHA256","StateID","StateEpoch", ...
                "AppliedParameters"];
            if ~isstruct(row) || ~all(isfield(row, required))
                error("RF:StageLedgerInvalid", ...
                    "RF stage ledger row is incomplete.");
            end
            sixgr.rf.runtime.RFReferencePlane.validate(row.InputReferencePlane);
            sixgr.rf.runtime.RFReferencePlane.validate(row.OutputReferencePlane);
            if double(row.StateEpoch) ~= obj.ConfigurationEpoch
                error("RF:StateEpochMismatch", ...
                    "RF stage state epoch does not match the ledger epoch.");
            end
            if ~isempty(obj.Rows)
                prior = obj.Rows(end);
                if string(prior.OutputReferencePlane) ~= ...
                        string(row.InputReferencePlane) || ...
                        string(prior.OutputSHA256) ~= string(row.InputSHA256)
                    error("RF:StageLedgerDiscontinuity", ...
                        "RF stage ledger reference planes or sample hashes are discontinuous.");
                end
            end
            if isempty(obj.Rows)
                obj.Rows = row;
            else
                obj.Rows(end+1,1) = row;
            end
        end

        function value = asTable(obj)
            if isempty(obj.Rows)
                value = table();
            else
                value = struct2table(obj.Rows);
            end
        end
    end
end
