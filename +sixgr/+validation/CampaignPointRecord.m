classdef CampaignPointRecord
    %CAMPAIGNPOINTRECORD Canonical point row constructor.
    methods (Static)
        function row = create(identity,counts,evidence,decision,metadata)
            key = sixgr.validation.OperatingPointKey.canonical(identity);
            required = ["RunID","TaskID","IndependentDropID","Seed", ...
                "MeasuredSINR_dB","MeasuredSINRProvenance", ...
                "MeasuredSINRSampleCount","SourceCommit","ScenarioSHA256"];
            for name = required
                if ~isfield(metadata,char(name)) && ...
                        ~isfield(evidence,char(name))
                    error("sixgr:validation:SchemaMissingColumn", ...
                        "Campaign record field %s is missing.",name);
                end
            end
            interval = decision;
            row = identity;
            row.SchemaVersion = "1.0.0";
            row.RunID = metadata.RunID;
            row.TaskID = metadata.TaskID;
            row.PointKey = key;
            row.IndependentDropID = metadata.IndependentDropID;
            row.Seed = metadata.Seed;
            row.TrialCount = counts.TrialCount;
            row.ErrorCount = counts.ErrorCount;
            row.Estimate = interval.Estimate;
            row.CILow = interval.Lower;
            row.CIHigh = interval.Upper;
            row.ConfidenceLevel = interval.ConfidenceLevel;
            row.IntervalMethod = interval.Method;
            row.PointStatus = decision.PointStatus;
            row.StopReason = decision.StopReason;
            row.MeasuredSINR_dB = evidence.MeasuredSINR_dB;
            row.MeasuredSINRProvenance = evidence.MeasuredSINRProvenance;
            row.MeasuredSINRSampleCount = evidence.MeasuredSINRSampleCount;
            row.SourceCommit = metadata.SourceCommit;
            row.ScenarioSHA256 = metadata.ScenarioSHA256;
        end
    end
end
