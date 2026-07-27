classdef RadioProfile
    %RADIOPROFILE Orthogonal radio-claim profile resolver.
    properties (Constant)
        NRRel18Strict = "nr_rel18_system_lls_strict"
        Rel19ExtensionStrict = "rel19_extension_strict"
        Rel20Study = "rel20_6g_study_context"
    end
    methods (Static)
        function value = resolve(input)
            values = string(input);
            values = unique(lower(strtrim(values(:))));
            values(values == "") = [];
            known = [sixgr.integration.RadioProfile.NRRel18Strict; ...
                sixgr.integration.RadioProfile.Rel19ExtensionStrict; ...
                sixgr.integration.RadioProfile.Rel20Study];
            if numel(values) ~= 1 || ~ismember(values,known)
                error("sixgr:integration:RadioProfileConflict", ...
                    "Exactly one supported RadioProfile is required.");
            end
            value = values(1);
        end
        function value = isNormative(profile)
            value = sixgr.integration.RadioProfile.resolve(profile) ~= ...
                sixgr.integration.RadioProfile.Rel20Study;
        end
    end
end
