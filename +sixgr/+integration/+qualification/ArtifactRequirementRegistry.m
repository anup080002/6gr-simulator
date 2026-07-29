classdef ArtifactRequirementRegistry
    %ARTIFACTREQUIREMENTREGISTRY Selected preset artifact contract.
    methods (Static)
        function T = load(profile)
            T = profile.SelectedArtifactRegistry;
            if numel(unique(string(T.ArtifactID))) ~= height(T) || ...
                    numel(unique(string(T.FileName))) ~= height(T)
                error("FULLSTACK:DuplicateArtifactRequirement", ...
                    "Selected artifact IDs and file names must be unique.");
            end
            if any(~ismember(string(T.ArtifactType), ["CSV","PNG"]))
                error("FULLSTACK:UnsupportedArtifactType", ...
                    "The selected Phase-18 registry contains unsupported artifact types.");
            end
        end
    end
end
