classdef StopReason
    %STOPREASON Canonical validation campaign stop-reason tokens.
    properties (Constant)
        NONE = "NONE"
        MIN_TRIALS_NOT_MET = "MIN_TRIALS_NOT_MET"
        MIN_ERRORS_AND_CI_MET = "MIN_ERRORS_AND_CI_MET"
        ZERO_ERROR_UPPER_BOUND_MET = "ZERO_ERROR_UPPER_BOUND_MET"
        MAX_TRIALS_REACHED_INCOMPLETE = "MAX_TRIALS_REACHED_INCOMPLETE"
        MAX_TRIALS_REACHED_CENSORED_PASS = "MAX_TRIALS_REACHED_CENSORED_PASS"
        MAX_RUNTIME_REACHED = "MAX_RUNTIME_REACHED"
        INVALID_CONFIGURATION = "INVALID_CONFIGURATION"
        NUMERICAL_FAILURE = "NUMERICAL_FAILURE"
        ORACLE_FAILURE = "ORACLE_FAILURE"
        PROVENANCE_FAILURE = "PROVENANCE_FAILURE"
        DUPLICATE_TASK_CONFLICT = "DUPLICATE_TASK_CONFLICT"
        STALE_ARTIFACT = "STALE_ARTIFACT"
        TOOLCHAIN_UNAVAILABLE = "TOOLCHAIN_UNAVAILABLE"
        USER_ABORT = "USER_ABORT"
    end
    methods (Static)
        function out = values()
            out = ["NONE","MIN_TRIALS_NOT_MET","MIN_ERRORS_AND_CI_MET", ...
                "ZERO_ERROR_UPPER_BOUND_MET", ...
                "MAX_TRIALS_REACHED_INCOMPLETE", ...
                "MAX_TRIALS_REACHED_CENSORED_PASS","MAX_RUNTIME_REACHED", ...
                "INVALID_CONFIGURATION","NUMERICAL_FAILURE", ...
                "ORACLE_FAILURE","PROVENANCE_FAILURE", ...
                "DUPLICATE_TASK_CONFLICT","STALE_ARTIFACT", ...
                "TOOLCHAIN_UNAVAILABLE","USER_ABORT"];
        end
        function out = parse(input)
            out = upper(strtrim(string(input)));
            if ~(isscalar(out) && strlength(out) > 0 && ...
                    ismember(out,sixgr.validation.StopReason.values()))
                error("sixgr:validation:UnknownStopReason", ...
                    "Unknown canonical StopReason '%s'.",string(input));
            end
        end
        function out = migrate(input)
            raw=string(input);
            if isempty(raw)||any(ismissing(raw))
                token="";
            else
                token=lower(strtrim(raw));
            end
            switch token
                case {"max_tb_per_point_reached","max_trials_reached"}
                    out = struct("PointStatus","INCOMPLETE_MAX_TRIALS", ...
                        "StopReason","MAX_TRIALS_REACHED_INCOMPLETE", ...
                        "Action","MIGRATE");
                case "confidence_and_error_targets_met"
                    out = struct("PointStatus","COMPLETE", ...
                        "StopReason","MIN_ERRORS_AND_CI_MET","Action","MIGRATE");
                case "zero_error_bound_met"
                    out = struct("PointStatus","CENSORED_COMPLETE", ...
                        "StopReason","ZERO_ERROR_UPPER_BOUND_MET","Action","MIGRATE");
                case "max_runtime_reached"
                    out = struct("PointStatus","INCOMPLETE_MAX_TRIALS", ...
                        "StopReason","MAX_RUNTIME_REACHED","Action","MIGRATE");
                case "blocked_matlab"
                    out = struct("PointStatus","BLOCKED_TOOLCHAIN", ...
                        "StopReason","TOOLCHAIN_UNAVAILABLE","Action","MIGRATE");
                case "not_applicable"
                    out = struct("PointStatus","SKIPPED_NOT_APPLICABLE", ...
                        "StopReason","NONE","Action","MIGRATE");
                case "running"
                    out = struct("PointStatus","RUNNING", ...
                        "StopReason","NONE","Action","MIGRATE");
                otherwise
                    error("sixgr:validation:LegacyTokenUnmapped", ...
                        "Legacy validation token '%s' has no explicit mapping.", ...
                        char(token));
            end
        end
    end
end
