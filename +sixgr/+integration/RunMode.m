classdef RunMode
    %RUNMODE Canonical two-mode integration values.
    properties (Constant)
        FixedSNRSweep = "FIXED_SNR_SWEEP"
        GeometryNetwork = "GEOMETRY_NETWORK"
    end
    methods (Static)
        function value = resolve(input)
            values = string(input);
            values = unique(upper(strtrim(values(:))));
            values(values == "") = [];
            known = [sixgr.integration.RunMode.FixedSNRSweep; ...
                sixgr.integration.RunMode.GeometryNetwork];
            if numel(values) ~= 1 || ~ismember(values,known)
                error("sixgr:integration:RunModeConflict", ...
                    "Exactly one supported RunMode is required.");
            end
            value = values(1);
        end
    end
end
