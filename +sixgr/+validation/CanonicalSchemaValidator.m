classdef CanonicalSchemaValidator
    %CANONICALSCHEMAVALIDATOR Fail-closed validation table checks.
    methods (Static)
        function result = validateCampaignPoint(input)
            schema = sixgr.validation.ValidationSchemaRegistry.campaignPoint();
            if ~istable(input) || height(input) == 0
                error("sixgr:validation:SchemaMissingColumn", ...
                    "A nonempty canonical campaign-point table is required.");
            end
            names = string(input.Properties.VariableNames);
            missing = setdiff(schema.RequiredColumns,names,"stable");
            if ~isempty(missing)
                error("sixgr:validation:SchemaMissingColumn", ...
                    "Missing canonical campaign-point columns: %s.", ...
                    strjoin(missing,", "));
            end
            if any(string(input.SchemaVersion) ~= "1.0.0")
                error("sixgr:validation:SchemaVersionMismatch", ...
                    "Campaign-point SchemaVersion must be 1.0.0.");
            end
            localText(input,["RunID","TaskID","ProfileID","ChannelModel", ...
                "Receiver","IndependentDropID","SourceCommit"]);
            localNumeric(input,["CarrierFrequency_Hz","Bandwidth_Hz", ...
                "SCS_kHz","MCS","Rank","SNR_dB","Seed","TrialCount", ...
                "ErrorCount","Estimate","CILow","CIHigh","ConfidenceLevel", ...
                "MeasuredSINR_dB","MeasuredSINRSampleCount"]);
            localRelations(input);
            for index = 1:height(input)
                sixgr.validation.RunClass.parse(input.RunClass(index));
                direction = upper(strtrim(string(input.Direction(index))));
                if ~ismember(direction,["DL","UL"])
                    error("sixgr:validation:SchemaWrongType", ...
                        "Direction must be DL or UL.");
                end
                status = sixgr.validation.PointStatus.parse( ...
                    input.PointStatus(index));
                reason = sixgr.validation.StopReason.parse( ...
                    input.StopReason(index));
                localPair(status,reason);
                provenance = input.MeasuredSINRProvenance(index);
                if ~sixgr.validation.EvidenceProvenanceClass. ...
                        qualifiesRuntime(provenance)
                    error("sixgr:validation:MeasuredSINRInvalidProvenance", ...
                        "Measured SINR requires qualifying runtime provenance.");
                end
                sixgr.validation.BinomialIntervalEngine.compute( ...
                    input.ErrorCount(index),input.TrialCount(index), ...
                    input.ConfidenceLevel(index),input.IntervalMethod(index));
            end
            key = string(input.RunID) + "|" + string(input.TaskID);
            if numel(unique(key)) ~= numel(key)
                error("sixgr:validation:SchemaDuplicateKey", ...
                    "Canonical campaign RunID/TaskID keys must be unique.");
            end
            result = struct("Valid",true,"SchemaID",schema.SchemaID, ...
                "Rows",height(input),"Status","PASS");
        end
    end
end

function localText(input,names)
for name = names
    values = string(input.(char(name)));
    if numel(values) ~= height(input) || any(strlength(strtrim(values)) == 0)
        error("sixgr:validation:SchemaWrongType", ...
            "Column %s must contain nonempty scalar text values.",name);
    end
end
end

function localNumeric(input,names)
for name = names
    values = input.(char(name));
    if ~(isnumeric(values)||islogical(values)) || ...
            numel(values) ~= height(input)
        error("sixgr:validation:SchemaWrongType", ...
            "Column %s must be numeric.",name);
    end
    if any(~isfinite(double(values(:))))
        error("sixgr:validation:SchemaNonFinite", ...
            "Column %s contains NaN or Inf.",name);
    end
end
end

function localRelations(input)
n = double(input.TrialCount);
k = double(input.ErrorCount);
estimate = double(input.Estimate);
lo = double(input.CILow);
hi = double(input.CIHigh);
cl = double(input.ConfidenceLevel);
sampleCount = double(input.MeasuredSINRSampleCount);
integerFields = [n(:),k(:),double(input.MCS(:)), ...
    double(input.Rank(:)),double(input.Seed(:)),sampleCount(:)];
bad = any(integerFields ~= fix(integerFields),2) | ...
    n(:) <= 0 | k(:) < 0 | k(:) > n(:) | ...
    estimate(:) < 0 | estimate(:) > 1 | ...
    lo(:) < 0 | lo(:) > estimate(:) | ...
    hi(:) < estimate(:) | hi(:) > 1 | ...
    cl(:) <= 0 | cl(:) >= 1 | sampleCount(:) < 1 | ...
    double(input.CarrierFrequency_Hz(:)) <= 0 | ...
    double(input.Bandwidth_Hz(:)) <= 0 | ...
    double(input.SCS_kHz(:)) <= 0 | ...
    double(input.MCS(:)) < 0 | double(input.Rank(:)) < 1;
if any(bad)
    error("sixgr:validation:SchemaWrongType", ...
        "Canonical campaign-point relational constraints failed.");
end
hashes = lower(string(input.ScenarioSHA256));
if any(strlength(hashes) ~= 64 | ...
        ~arrayfun(@(x)~isempty(regexp(char(x),"^[0-9a-f]{64}$","once")),hashes))
    error("sixgr:validation:SchemaWrongType", ...
        "ScenarioSHA256 must contain 64 lowercase hexadecimal digits.");
end
end

function localPair(status,reason)
switch status
    case "NOT_STARTED"
        allowed = reason == "NONE";
    case "RUNNING"
        allowed = ismember(reason,["NONE","MIN_TRIALS_NOT_MET"]);
    case "COMPLETE"
        allowed = reason == "MIN_ERRORS_AND_CI_MET";
    case "CENSORED_COMPLETE"
        allowed = ismember(reason,["ZERO_ERROR_UPPER_BOUND_MET", ...
            "MAX_TRIALS_REACHED_CENSORED_PASS"]);
    case "INCOMPLETE_MAX_TRIALS"
        allowed = ismember(reason,["MAX_TRIALS_REACHED_INCOMPLETE", ...
            "MAX_RUNTIME_REACHED"]);
    case "FAILED_SCHEMA"
        allowed = reason == "INVALID_CONFIGURATION";
    case "FAILED_ORACLE"
        allowed = reason == "ORACLE_FAILURE";
    case "FAILED_PROVENANCE"
        allowed = reason == "PROVENANCE_FAILURE";
    case "FAILED_STATISTICS"
        allowed = reason == "NUMERICAL_FAILURE";
    case "BLOCKED_TOOLCHAIN"
        allowed = reason == "TOOLCHAIN_UNAVAILABLE";
    case "SKIPPED_NOT_APPLICABLE"
        allowed = reason == "NONE";
    otherwise
        allowed = false;
end
if ~allowed
    error("sixgr:validation:IllegalStatusStopReasonPair", ...
        "PointStatus %s cannot use StopReason %s.",status,reason);
end
end
