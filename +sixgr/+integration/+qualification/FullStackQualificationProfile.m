classdef FullStackQualificationProfile
    %FULLSTACKQUALIFICATIONPROFILE Resolve the checked-in Phase-18 contract.
    methods (Static)
        function profile = load(scfg)
            arguments
                scfg (1,1) sixgr.lls6g.config.ScenarioConfig
            end
            q = scfg.get("qualification");
            if ~isstruct(q)
                error("FULLSTACK:MissingQualificationConfiguration", ...
                    "The resolved scenario must contain qualification configuration.");
            end
            preset = string(sixgr.util.structGet(q, "suite.preset", ""));
            if ~ismember(preset, ["comprehensive_smoke","deep_acceptance"])
                error("FULLSTACK:UnsupportedPreset", ...
                    "Unsupported qualification preset '%s'.", preset);
            end
            root = sixgr.integration.qualification.FullStackQualificationProfile.repoRoot();
            packRoot = fullfile(root, "audit", ...
                "6gr_webgui_full_stack_qualification_pack");
            if ~isfolder(packRoot)
                error("FULLSTACK:ContractPackMissing", ...
                    "Qualification contract pack is missing: %s", packRoot);
            end

            profile = struct();
            profile.RepositoryRoot = string(root);
            profile.PackRoot = string(packRoot);
            profile.Configuration = q;
            profile.Preset = preset;
            profile.PresetConfiguration = sixgr.util.structGet( ...
                q, "suite.presets." + preset, struct());
            profile.Subcases = localRead(packRoot, "full_stack_subcase_matrix.csv");
            profile.Components = localRead(packRoot, ...
                "full_stack_component_coverage_matrix.csv");
            profile.ValueChecks = localRead(packRoot, ...
                "full_stack_value_correctness_contract.csv");
            profile.NegativeCases = localRead(packRoot, ...
                "full_stack_negative_fault_injection_matrix.csv");
            profile.AcceptanceRules = localRead(packRoot, ...
                "full_stack_acceptance_rules.csv");
            profile.ArtifactRegistry = localRead(packRoot, ...
                "full_stack_required_artifact_registry.csv");
            profile.WebGUIPages = localRead(packRoot, ...
                "full_stack_webgui_page_contract.csv");
            if preset == "comprehensive_smoke"
                flag = "RequiredInComprehensiveSmoke";
                expected = [746 447 299];
            else
                flag = "RequiredInDeepAcceptance";
                expected = [1248 623 625];
            end
            selected = localTruth(profile.ArtifactRegistry.(flag));
            profile.SelectedArtifactRegistry = profile.ArtifactRegistry(selected,:);
            profile.RequiredArtifactFlag = flag;
            actual = [height(profile.SelectedArtifactRegistry), ...
                nnz(profile.SelectedArtifactRegistry.ArtifactType == "CSV"), ...
                nnz(profile.SelectedArtifactRegistry.ArtifactType == "PNG")];
            if ~isequal(actual, expected)
                error("FULLSTACK:ArtifactRegistryCountMismatch", ...
                    "Preset %s resolved %d artifacts (%d CSV/%d PNG), expected %d (%d/%d).", ...
                    preset, actual(1), actual(2), actual(3), ...
                    expected(1), expected(2), expected(3));
            end
            counts = [height(profile.Subcases), height(profile.Components), ...
                height(profile.ValueChecks), height(profile.NegativeCases), ...
                height(profile.AcceptanceRules), height(profile.WebGUIPages)];
            if ~isequal(counts, [31 163 107 77 387 13])
                error("FULLSTACK:PackContractCountMismatch", ...
                    "Qualification pack matrix counts changed: %s.", mat2str(counts));
            end
            profile.ExpectedArtifactCount = expected(1);
            profile.ExpectedCSVCount = expected(2);
            profile.ExpectedPNGCount = expected(3);
        end

        function root = repoRoot()
            here = fileparts(mfilename("fullpath"));
            root = fileparts(fileparts(fileparts(here)));
        end
    end
end

function T = localRead(root, name)
path = fullfile(root, name);
if ~isfile(path)
    error("FULLSTACK:ContractFileMissing", ...
        "Qualification contract file is missing: %s", path);
end
T = readtable(path, "Delimiter", ",", "TextType", "string", ...
    "VariableNamingRule", "preserve");
end

function tf = localTruth(value)
tf = ismember(lower(strtrim(string(value))), ...
    ["true","1","yes","pass","required"]);
end
