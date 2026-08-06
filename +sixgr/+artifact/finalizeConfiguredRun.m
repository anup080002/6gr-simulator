function result = finalizeConfiguredRun(runFolder, evidence, scenarioConfig, runtimeIdentity)
%FINALIZECONFIGUREDRUN Invoke the new publisher from YAML-owned policy.

if nargin < 4 || isempty(runtimeIdentity)
    runtimeIdentity = struct();
end
if ~(isstruct(runtimeIdentity) && isscalar(runtimeIdentity))
    error("sixgr:artifact:RuntimeIdentityRequired", ...
        "Artifact finalization runtime identity must be a scalar struct.");
end

if ~isa(evidence, "sixgr.artifact.EvidenceRegistry")
    error("sixgr:artifact:EvidenceRegistryRequired", ...
        "Configured artifact finalization requires an in-memory EvidenceRegistry.");
end
% canonical_control is the leaf/master YAML authority.  The ordinary
% output tree may still contain the disabled global default after config
% inheritance, so reading that default first would silently bypass an
% explicitly enabled contract engine in the master scenario.
engine = localGet(scenarioConfig, ...
    "canonical_control.output.artifact_contract_engine", struct());
if ~isstruct(engine) || isempty(fieldnames(engine))
    engine = localGet(scenarioConfig, "output.artifact_contract_engine", struct());
end
if ~isstruct(engine) || isempty(fieldnames(engine))
    error("sixgr:artifact:ArtifactEngineConfigurationMissing", ...
        "Scenario YAML does not define output.artifact_contract_engine.");
end
if ~logical(sixgr.util.structGet(engine, "enabled", false))
    result = struct("Ok", true, "Enabled", false, "Status", "DISABLED_BY_YAML");
    return;
end

localRequireLiteral(engine, "source_policy", "runtime_memory_only");
localRequireLiteral(engine, "image_format", "png");
localRequireLiteral(engine, "publish_root", "components");
localRequireLiteral(engine, "legacy_reference_usage", "coverage_inventory_only");
if logical(sixgr.util.structGet(engine, "allow_svg", true))
    error("sixgr:artifact:SVGOutputForbidden", ...
        "The production artifact engine must keep allow_svg=false.");
end
if logical(sixgr.util.structGet(engine, "allow_placeholder_evidence", true))
    error("sixgr:artifact:PlaceholderEvidenceForbidden", ...
        "The production artifact engine must keep allow_placeholder_evidence=false.");
end
if ~logical(sixgr.util.structGet(engine, "atomic_replace", false))
    error("sixgr:artifact:AtomicPublicationRequired", ...
        "The production artifact engine requires atomic_replace=true.");
end

repositoryRoot = sixgr.artifact.ContractCatalog.repositoryRoot();
contractRoot = string(sixgr.util.structGet(engine, "contract_root", ""));
expectedContractRoot = "tests/vectors";
if replace(contractRoot, "\\", "/") ~= expectedContractRoot
    error("sixgr:artifact:UnsupportedContractRoot", ...
        "Configured contract_root must be %s; received %s.", ...
        expectedContractRoot, contractRoot);
end
if ~isfolder(fullfile(repositoryRoot, contractRoot))
    error("sixgr:artifact:ContractRootMissing", ...
        "Configured artifact contract root is missing: %s", ...
        fullfile(repositoryRoot, contractRoot));
end
catalog = sixgr.artifact.ContractCatalog.load(repositoryRoot);
profiles = string(sixgr.util.structGet(engine, "profiles", "base"));
domains = string(sixgr.util.structGet(engine, "domains", "all"));
mode = localRuntimeMode(scenarioConfig);
identity = localExpectedIdentity(scenarioConfig, engine, runtimeIdentity);
result = sixgr.artifact.ContractArtifactGenerator.generate( ...
    runFolder, evidence, ...
    "Catalog", catalog, ...
    "Profiles", profiles, ...
    "Domains", domains, ...
    "Mode", mode, ...
    "PublishRoot", string(sixgr.util.structGet(engine, "publish_root", "components")), ...
    "FailOnMissingRequired", logical(sixgr.util.structGet( ...
        engine, "fail_on_missing_required", true)), ...
    "TruthOnly", logical(sixgr.util.structGet(engine, "truth_only", true)), ...
    "ExpectedIdentity", identity, ...
    "RequireIdentityColumns", logical(sixgr.util.structGet( ...
        engine, "require_identity_columns", true)), ...
    "RequireRadioIdentityColumns", logical(sixgr.util.structGet( ...
        engine, "require_radio_identity_columns", true)));
result.Enabled = true;
result.Status = "FINALIZED_FROM_RUNTIME_EVIDENCE";
end

function mode = localRuntimeMode(config)
% The master YAML selects exactly one runtime mode.  Artifact contracts
% marked ALL or BOTH apply to either mode; mode-specific contracts must not
% leak into the other run's publication gate.
paths = ["canonical_control.integration.run_mode", ...
    "integration.run_mode", ...
    "canonical_control.launch.scenario_mode", ...
    "launch.scenario_mode", ...
    "scenario.scenario_mode"];
raw = "";
for path = paths
    candidate = string(localGet(config, path, ""));
    if isscalar(candidate) && strlength(strtrim(candidate)) > 0
        raw = upper(strtrim(candidate));
        break;
    end
end
switch raw
    case {"FIXED_SNR_SWEEP", "FIXED-SNR-SWEEP", "SINR_SWEEP", ...
            "FIXED_SINR_SWEEP"}
        mode = "FIXED_SNR_SWEEP";
    case {"GEOMETRY_NETWORK", "GEOMETRY-NETWORK", ...
            "UE_PLACEMENT_GEOMETRY", "GEOMETRY_BASED"}
        mode = "GEOMETRY_NETWORK";
    case ""
        error("sixgr:artifact:ArtifactRunModeMissing", ...
            ["Enabled artifact finalization requires the master YAML to " ...
             "define canonical_control.integration.run_mode as " ...
             "FIXED_SNR_SWEEP or GEOMETRY_NETWORK."]);
    otherwise
        error("sixgr:artifact:UnsupportedArtifactRunMode", ...
            "Unsupported artifact finalization run mode '%s'.", raw);
end
end

function identity = localExpectedIdentity(config, engine, runtimeIdentity)
if isobject(config) && ismethod(config, "toStruct")
    normalized = config.toStruct();
elseif isstruct(config) && isscalar(config)
    normalized = config;
else
    error("sixgr:artifact:ScenarioConfigurationRequired", ...
        "Cannot derive artifact identity from this scenario configuration.");
end
configHash = "";
if isobject(config) && isprop(config, "ConfigHash")
    configHash = string(config.ConfigHash);
end
if strlength(strtrim(configHash)) == 0
    configHash = string(sixgr.util.structGet(normalized, "ConfigHash", ...
        sixgr.util.structGet(normalized, "meta.configHash", "")));
end
if strlength(strtrim(configHash)) == 0
    configHash = sixgr.integration.IntegrationHash.data(normalized);
end
identity = struct( ...
    "ScenarioID", localFirstText(normalized, ...
        ["scenario_id","meta.scenario_id","scenario.id"]), ...
    "RunID", localFirstText(normalized, ...
        ["run.runID","run.runId","meta.runID"]), ...
    "ExecutionID", localFirstText(normalized, ...
        ["run.executionID","meta.executionID"]), ...
    "ConfigHash", configHash, ...
    "EvidenceScope", string(sixgr.util.structGet(engine, ...
        "evidence_scope", "in_path")), ...
    "CenterFrequencyHz", localFirstNumber(normalized, ...
        ["frequency.center_frequency_hz","carrier_frequency_hz", ...
         "channel.center_frequency_hz","random_access.carrier_frequency_hz"], 1), ...
    "BandwidthHz", localFirstNumber(normalized, ...
        ["frequency.channel_bandwidth_hz","frequency.bandwidth_hz", ...
         "channel_bandwidth_hz"], 1), ...
    "SubcarrierSpacingHz", localFirstNumber(normalized, ...
        ["numerology.subcarrier_spacing_hz","subcarrier_spacing_hz", ...
         "frame.scs_hz"], 1), ...
    "NormalizedConfig", normalized);
% Run/execution identities are lifecycle values, not scenario defaults.
% They may therefore be supplied only by the coordinator that owns this
% concrete execution/finalization attempt.
for field = ["RunID", "ExecutionID"]
    override = string(sixgr.util.structGet(runtimeIdentity, field, ""));
    if ~isscalar(override)
        error("sixgr:artifact:RuntimeIdentityRequired", ...
            "Runtime identity %s must be a text scalar.", field);
    end
    override = strtrim(override);
    if strlength(override) > 0
        identity.(field) = override;
    end
end
runtimeConfigHash = string(sixgr.util.structGet(runtimeIdentity, "ConfigHash", ""));
if ~isscalar(runtimeConfigHash)
    error("sixgr:artifact:RuntimeIdentityRequired", ...
        "Runtime identity ConfigHash must be a text scalar.");
end
runtimeConfigHash = lower(strtrim(runtimeConfigHash));
if strlength(runtimeConfigHash) > 0 && runtimeConfigHash ~= lower(identity.ConfigHash)
    error("sixgr:artifact:RuntimeConfigIdentityMismatch", ...
        "Runtime ConfigHash %s does not match the normalized YAML hash %s.", ...
        runtimeConfigHash, identity.ConfigHash);
end
if ~isfinite(identity.BandwidthHz)
    identity.BandwidthHz = localFirstNumber(normalized, ...
        ["frequency.channel_bandwidth_mhz","channel_bandwidth_mhz", ...
         "bandwidth_mhz"], 1e6);
end
if ~isfinite(identity.SubcarrierSpacingHz)
    identity.SubcarrierSpacingHz = localFirstNumber(normalized, ...
        ["numerology.scs_khz","frequency.scs_khz","frame.scs_khz", ...
         "subcarrier_spacing_khz","random_access.carrier_scs_khz"], 1e3);
end
end

function value = localFirstText(S, paths)
value = "";
for path = string(paths(:)).'
    candidate = strtrim(string(sixgr.util.structGet(S, path, "")));
    if isscalar(candidate) && strlength(candidate) > 0
        value = candidate;
        return;
    end
end
end

function value = localFirstNumber(S, paths, scale)
value = NaN;
for path = string(paths(:)).'
    raw = sixgr.util.structGet(S, path, []);
    if isempty(raw)
        continue;
    end
    candidate = double(raw(1)) * scale;
    if isfinite(candidate)
        value = candidate;
        return;
    end
end
end

function value = localGet(config, path, defaultValue)
if isobject(config) && ismethod(config, "get")
    value = config.get(path, defaultValue);
elseif isstruct(config)
    value = sixgr.util.structGet(config, path, defaultValue);
else
    error("sixgr:artifact:ScenarioConfigurationRequired", ...
        "Scenario configuration must be a ScenarioConfig object or scalar struct.");
end
end

function localRequireLiteral(engine, fieldName, expected)
actual = string(sixgr.util.structGet(engine, fieldName, ""));
if ~isscalar(actual) || actual ~= string(expected)
    error("sixgr:artifact:UnsafeArtifactEnginePolicy", ...
        "artifact_contract_engine.%s must equal '%s'; received '%s'.", ...
        fieldName, expected, strjoin(actual, ","));
end
end
