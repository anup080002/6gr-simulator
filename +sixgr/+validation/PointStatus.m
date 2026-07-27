classdef PointStatus
    %POINTSTATUS Canonical validation campaign point-state tokens.
    properties (Constant)
        NOT_STARTED = "NOT_STARTED"
        RUNNING = "RUNNING"
        COMPLETE = "COMPLETE"
        CENSORED_COMPLETE = "CENSORED_COMPLETE"
        INCOMPLETE_MAX_TRIALS = "INCOMPLETE_MAX_TRIALS"
        FAILED_SCHEMA = "FAILED_SCHEMA"
        FAILED_ORACLE = "FAILED_ORACLE"
        FAILED_PROVENANCE = "FAILED_PROVENANCE"
        FAILED_STATISTICS = "FAILED_STATISTICS"
        BLOCKED_TOOLCHAIN = "BLOCKED_TOOLCHAIN"
        SKIPPED_NOT_APPLICABLE = "SKIPPED_NOT_APPLICABLE"
    end
    methods (Static)
        function out = values()
            out = ["NOT_STARTED","RUNNING","COMPLETE", ...
                "CENSORED_COMPLETE","INCOMPLETE_MAX_TRIALS", ...
                "FAILED_SCHEMA","FAILED_ORACLE","FAILED_PROVENANCE", ...
                "FAILED_STATISTICS","BLOCKED_TOOLCHAIN", ...
                "SKIPPED_NOT_APPLICABLE"];
        end
        function out = parse(input)
            out = upper(strtrim(string(input)));
            if ~(isscalar(out) && strlength(out) > 0 && ...
                    ismember(out,sixgr.validation.PointStatus.values()))
                error("sixgr:validation:UnknownPointStatus", ...
                    "Unknown canonical PointStatus '%s'.",string(input));
            end
        end
    end
end
