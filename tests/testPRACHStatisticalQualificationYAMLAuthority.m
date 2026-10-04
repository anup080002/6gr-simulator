function ok = testPRACHStatisticalQualificationYAMLAuthority()
%TESTPRACHSTATISTICALQUALIFICATIONYAMLAUTHORITY Guard PRACH campaign wiring.
%
% The canonical operator YAML owns the sequential statistical design.  The
% canonical-to-runtime projection must carry that complete nested structure
% into random_access; a strict PRACH runner must never fall back to an
% implicit trial count or threshold.

setup6GRSimToolkit("Verbose", false, "RunToolboxChecks", false);
scenarioRoot = fullfile(pwd, "simulator", "configs", "scenarios");
scenarioNames = [ ...
    "master_sinr_sweep.yaml"
    "master_geometry_based.yaml"
    "webgui_sinr_sweep_64x4_mu_mimo_repair_slice.yaml"];

tmp = string(tempname);
mkdir(tmp);
cleanup = onCleanup(@() localCleanup(tmp)); %#ok<NASGU>

for ii = 1:numel(scenarioNames)
    scenarioPath = fullfile(scenarioRoot, scenarioNames(ii));
    scenario = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
    resolved = scenario.toStruct();
    expected = sixgr.util.structGet(resolved, ...
        "canonical_control.random_access.statistical_qualification", []);
    projected = sixgr.util.structGet(resolved, ...
        "random_access.statistical_qualification", []);
    assert(double(sixgr.util.structGet(resolved, ...
        "random_access.msg1_fdm", NaN)) == 1, ...
        "Canonical YAML %s must explicitly own Msg1 FDM instead of using a MATLAB default.", ...
        scenarioNames(ii));
    assert(isstruct(expected) && isscalar(expected) && ...
        ~isempty(fieldnames(expected)), ...
        "Canonical YAML %s must define the complete PRACH statistical design.", ...
        scenarioNames(ii));
    assert(isequaln(projected, expected), ...
        "Canonical PRACH statistical design was not projected for %s.", ...
        scenarioNames(ii));

    internal = sixgr.lls6g.buildInternalConfig(scenario, ...
        fullfile(tmp, erase(scenarioNames(ii), ".yaml")));
    internalDesign = sixgr.util.structGet(internal, ...
        "random_access.statistical_qualification", []);
    assert(isequaln(internalDesign, expected), ...
        "buildInternalConfig changed the YAML-owned PRACH statistical design for %s.", ...
        scenarioNames(ii));
    assert(double(sixgr.util.structGet(internal, ...
        "phy.prach.msg1FDM", NaN)) == 1 && ...
        double(sixgr.util.structGet(internal, ...
        "prach_lls.Msg1FDM", NaN)) == 1, ...
        "buildInternalConfig did not carry the YAML-owned Msg1 FDM into both PRACH runtime views for %s.", ...
        scenarioNames(ii));

    if scenarioNames(ii) == ...
            "webgui_sinr_sweep_64x4_mu_mimo_repair_slice.yaml"
        strict = sixgr.phy.prach.buildPRACHConfigFromScenario(internal, ...
            "RunFolder", tmp, "ScenarioName", "prach_yaml_authority_regression");
        alternateRunFolder = fullfile(tmp, "alternate_runtime_root");
        strictAlternateRoot = sixgr.phy.prach.buildPRACHConfigFromScenario(internal, ...
            "RunFolder", alternateRunFolder, ...
            "ScenarioName", "prach_yaml_authority_regression");
        assert(logical(strict.StatisticalQualification.Enabled));
        assert(isequal(double(strict.StatisticalQualification.DeterministicSeeds(:)), ...
            double(expected.deterministic_seeds(:))));
        assert(double(strict.StatisticalQualification.MinimumTrials) == ...
            double(expected.minimum_trials));
        assert(double(strict.StatisticalQualification.MaximumTrials) == ...
            double(expected.maximum_trials));
        assert(string(strict.StrictConfigSource) == ...
            "resolved_scenario_random_access");
        assert(string(strict.RunFolder) == string(tmp) && ...
            string(strictAlternateRoot.RunFolder) == string(alternateRunFolder), ...
            "Strict PRACH runtime progress must retain the current run root.");
        assert(string(strict.ConfigHash) == string(strictAlternateRoot.ConfigHash), ...
            "Changing only the runtime output root must not change the physical PRACH config hash.");
    end
end

% These artifact/PHY scenarios previously requested the strict PRACH
% campaign but failed only after waveform execution because its population
% design was absent. Verify inheritance and the real strict builder without
% launching a detector campaign or claiming statistical qualification.
paths = [fullfile(scenarioRoot,"lls_100mhz_tdlc_bidirectional_truth.yaml"), ...
    fullfile(pwd,"simulator","configs","fixtures","lls_result_richness.yaml")];
for scenarioPath = paths
    scenario = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
    internal = sixgr.lls6g.buildInternalConfig(scenario,tmp);
    strict = sixgr.phy.prach.buildPRACHConfigFromScenario(internal, ...
        "RunFolder",tmp,"ScenarioName",scenario.ScenarioID);
    design = strict.StatisticalQualification;
    assert(design.Enabled && design.MinimumTrials==3000 && ...
        design.MaximumTrials==12000 && design.DetectionMinimumTrials==300 && ...
        design.DetectionMaximumTrials==2000);
    assert(design.TargetProbability==0.001 && design.DetectionTargetProbability==0.01);
    assert(isequal(design.DetectionRequiredSNRdB(:),[6;12]));
    bad=internal;
    bad.random_access=rmfield(bad.random_access,'statistical_qualification');
    localExpectConfigFailure(bad,"sixgr:phy:prach:MissingStatisticalQualificationConfig");
    bad=internal;
    bad.random_access.statistical_qualification.enabled=false;
    localExpectConfigFailure(bad,"sixgr:phy:prach:StatisticalQualificationDisabled");
    bad=internal;
    bad.random_access.statistical_qualification.planned_looks=1;
    localExpectConfigFailure(bad,"sixgr:phy:prach:InvalidStatisticalQualification");
end

ok = true;
end

function localExpectConfigFailure(cfg,identifier)
try
    sixgr.phy.prach.buildPRACHConfigFromScenario(cfg);
catch ME
    assert(string(ME.identifier)==identifier,'%s',ME.message);
    return;
end
error('testPRACHStatisticalQualificationYAMLAuthority:ExpectedFailure', ...
    'Malformed statistical design must remain rejected.');
end

function localCleanup(path)
if isfolder(path)
    rmdir(path, "s");
end
end
