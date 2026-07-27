classdef KPISampleLedger
    %KPISAMPLELEDGER Raw sample ownership and reconstruction authority.
    methods (Static)
        function out=classify(input,contract)
            required=["RunID","SampleID","Timestamp","KPIName","Value","OwnerEventID"];
            if ~istable(input)||any(~ismember(required,string(input.Properties.VariableNames)))
                error("sixgr:validation:SchemaMissingColumn", ...
                    "KPI ledger input is missing mandatory columns.");
            end
            phase=strings(height(input),1); included=false(height(input),1);
            for index=1:height(input)
                rule=contract.inclusion(input.Timestamp(index));
                phase(index)=rule.Phase;
                switch upper(string(input.KPIName(index)))
                    case {"BLER","ERROR_RATE"}
                        included(index)=rule.IncludeBLER;
                    case {"THROUGHPUT","GOODPUT","DELIVERED_GOODPUT"}
                        included(index)=rule.IncludeThroughput;
                    case "ACQUISITION_DELAY"
                        included(index)=rule.IncludeAcquisitionDelay;
                    case "QUEUE_DRAIN"
                        included(index)=rule.IncludeQueueDrain;
                    otherwise
                        included(index)=false;
                end
            end
            out=input; out.Phase=phase; out.Included=included;
            out.Status=repmat("PASS",height(out),1);
        end
        function result=reconstruct(input,kpiName)
            required=["KPIName","Value","Included"];
            if ~istable(input)||any(~ismember(required,string(input.Properties.VariableNames)))
                error("sixgr:validation:SchemaMissingColumn", ...
                    "Canonical KPI sample ledger is required.");
            end
            rows=upper(string(input.KPIName))==upper(string(kpiName)) & ...
                logical(input.Included);
            if ~any(rows)
                error("sixgr:validation:IncompleteMandatoryPoint", ...
                    "No included raw samples exist for KPI %s.",string(kpiName));
            end
            values=double(input.Value(rows));
            if any(~isfinite(values))
                error("sixgr:validation:SchemaNonFinite", ...
                    "KPI samples contain NaN or Inf.");
            end
            result=struct("KPIName",string(kpiName),"SampleCount",sum(rows), ...
                "Mean",mean(values),"Sum",sum(values),"Status","PASS");
        end
    end
end
