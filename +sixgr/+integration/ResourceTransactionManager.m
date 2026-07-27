classdef ResourceTransactionManager < handle
    %RESOURCETRANSACTIONMANAGER Atomic pre-waveform RE ownership ledger.
    properties (SetAccess=immutable)
        RunID (1,1) string
        ConfigurationEpoch (1,1) double
    end
    properties (Access=private)
        Rows
        Sequence (1,1) double = 0
    end
    methods
        function obj = ResourceTransactionManager(runID,epoch)
            obj.RunID = string(runID); obj.ConfigurationEpoch = double(epoch);
            variableTypes = ["string","string","double","double", ...
                "double","double","double","double","string","string", ...
                "string","double","string"];
            variableNames = ["RunID","TransactionID","AbsoluteSample", ...
                "Frame","Slot","Symbol","PRB","Subcarrier","LogicalPort", ...
                "PhysicalPort","Owner","ConfigurationEpoch","Status"];
            obj.Rows = table('Size',[0 13], ...
                'VariableTypes',cellstr(variableTypes), ...
                'VariableNames',cellstr(variableNames));
        end
        function transactionID = commit(obj,rows)
            required = ["AbsoluteSample","Frame","Slot","Symbol","PRB", ...
                "Subcarrier","LogicalPort","PhysicalPort","Owner"];
            if ~istable(rows) || ~all(ismember(required, ...
                    string(rows.Properties.VariableNames))) || height(rows) == 0
                error("sixgr:integration:ResourceCollision", ...
                    "Resource transaction requires a nonempty exact ownership table.");
            end
            keyNames = ["AbsoluteSample","PRB","Subcarrier","PhysicalPort"];
            proposedKey = localKeys(rows,keyNames);
            if numel(unique(proposedKey)) ~= numel(proposedKey)
                error("sixgr:integration:ResourceCollision", ...
                    "A transaction contains duplicate RE ownership.");
            end
            if height(obj.Rows) > 0 && ...
                    any(ismember(proposedKey,localKeys(obj.Rows,keyNames)))
                error("sixgr:integration:ResourceCollision", ...
                    "A committed RE already has an owner.");
            end
            obj.Sequence = obj.Sequence + 1;
            transactionID = "RTX-" + compose("%06d",obj.Sequence);
            n = height(rows);
            appended = table(repmat(obj.RunID,n,1), ...
                repmat(transactionID,n,1),double(rows.AbsoluteSample), ...
                double(rows.Frame),double(rows.Slot),double(rows.Symbol), ...
                double(rows.PRB),double(rows.Subcarrier), ...
                string(rows.LogicalPort),string(rows.PhysicalPort), ...
                string(rows.Owner),repmat(obj.ConfigurationEpoch,n,1), ...
                repmat("PASS",n,1),'VariableNames', ...
                obj.Rows.Properties.VariableNames);
            obj.Rows = [obj.Rows;appended];
        end
        function value = table(obj)
            value = obj.Rows;
        end
    end
end

function value = localKeys(rows,names)
value = strings(height(rows),1);
for ii = 1:numel(names)
    value = value + "|" + string(rows.(names(ii)));
end
end
