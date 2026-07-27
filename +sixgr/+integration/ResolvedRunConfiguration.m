classdef ResolvedRunConfiguration
    %RESOLVEDRUNCONFIGURATION Immutable staged configuration/hash binding.
    properties (SetAccess=immutable)
        RunID (1,1) string
        ScenarioID (1,1) string
        SourceYAML (1,1) string
        ExecutedYAML (1,1) string
        SourceSHA256 (1,1) string
        EffectiveSHA256 (1,1) string
        ResolvedSHA256 (1,1) string
        ExecutedSHA256 (1,1) string
        ConfigurationEpoch (1,1) double
        ResolvedStruct (1,1) struct
        Planning
    end
    methods (Static)
        function obj = stage(sourceYAML,stagingRoot)
            sourceYAML = string(sourceYAML);
            stagingRoot = string(stagingRoot);
            if ~isfile(sourceYAML)
                error("sixgr:integration:IncompleteConfiguration", ...
                    "Source YAML does not exist: %s.",sourceYAML);
            end
            scenario = sixgr.lls6g.config.loadScenarioConfig(sourceYAML);
            resolved = scenario.toStruct();
            integration = sixgr.util.structGet(resolved,"integration",struct());
            planning = sixgr.integration.IntegrationSpecificationProfile.resolve( ...
                integration.run_mode,integration.radio_profile, ...
                integration.subprofile,integration.trace_profile);
            scenarioID = string(sixgr.util.structGet(resolved, ...
                "meta.scenario_id",sixgr.util.structGet(resolved, ...
                "scenario.scenario_id","scenario")));
            epoch = double(sixgr.util.structGet(integration, ...
                "configuration_epoch",1));
            sourceHash = sixgr.integration.IntegrationHash.file(sourceYAML);
            effectiveHash = sixgr.integration.IntegrationHash.data(resolved);
            configDirectory = fullfile(stagingRoot,"meta","executed_config");
            if ~isfolder(configDirectory), mkdir(configDirectory); end
            stagedPath = fullfile(configDirectory,"resolved_run.yaml");
            sixgr.lls6g.config.writeYAML(stagedPath,resolved);
            reloaded = sixgr.lls6g.config.loadScenarioConfig(stagedPath);
            resolved = reloaded.toStruct();
            resolvedHash = sixgr.integration.IntegrationHash.data(resolved);
            sixgr.lls6g.config.writeYAML(stagedPath,resolved);
            executedHash = sixgr.integration.IntegrationHash.file(stagedPath);
            verified = sixgr.lls6g.config.loadScenarioConfig(stagedPath);
            verifiedHash = sixgr.integration.IntegrationHash.data( ...
                verified.toStruct());
            if verifiedHash ~= resolvedHash
                error("sixgr:integration:ExecutedConfigHashMismatch", ...
                    "Staged configuration does not resolve to the immutable source object.");
            end
            runID = scenarioID + "-" + extractBefore(resolvedHash,13);
            obj = sixgr.integration.ResolvedRunConfiguration( ...
                runID,scenarioID,sourceYAML,string(stagedPath), ...
                sourceHash,effectiveHash,resolvedHash,executedHash, ...
                epoch,resolved,planning);
        end
    end
    methods
        function verifyExecuted(obj)
            if sixgr.integration.IntegrationHash.file(obj.ExecutedYAML) ~= ...
                    obj.ExecutedSHA256
                error("sixgr:integration:ExecutedConfigHashMismatch", ...
                    "Executed YAML bytes differ from the staged manifest hash.");
            end
        end
        function value = toStruct(obj)
            value = struct("RunID",obj.RunID,"ScenarioID",obj.ScenarioID, ...
                "SourceYAML",obj.SourceYAML,"ExecutedYAML",obj.ExecutedYAML, ...
                "SourceSHA256",obj.SourceSHA256, ...
                "EffectiveSHA256",obj.EffectiveSHA256, ...
                "ResolvedSHA256",obj.ResolvedSHA256, ...
                "ExecutedSHA256",obj.ExecutedSHA256, ...
                "ConfigurationEpoch",obj.ConfigurationEpoch, ...
                "Planning",obj.Planning.toStruct());
        end
    end
    methods (Access=private)
        function obj = ResolvedRunConfiguration(runID,scenarioID,sourceYAML, ...
                executedYAML,sourceHash,effectiveHash,resolvedHash, ...
                executedHash,epoch,resolved,planning)
            obj.RunID = runID; obj.ScenarioID = scenarioID;
            obj.SourceYAML = sourceYAML; obj.ExecutedYAML = executedYAML;
            obj.SourceSHA256 = sourceHash;
            obj.EffectiveSHA256 = effectiveHash;
            obj.ResolvedSHA256 = resolvedHash;
            obj.ExecutedSHA256 = executedHash;
            obj.ConfigurationEpoch = epoch;
            obj.ResolvedStruct = resolved;
            obj.Planning = planning;
        end
    end
end
