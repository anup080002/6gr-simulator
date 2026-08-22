function ok = testRuntimeRAMCSAuthority()
%TESTRUNTIMERAMCSAUTHORITY Guard YAML-to-DCI-to-PDSCH MCS authority for RA.

scenarioPath = fullfile("simulator", "configs", "scenarios", ...
    "lls_causal_access_to_data_wiring.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
runRoot = tempname;
mkdir(runRoot);
cleanup = onCleanup(@() localCleanup(runRoot)); %#ok<NASGU>
cfg = sixgr.config.normalizeConfig( ...
    sixgr.lls6g.buildInternalConfig(scfg, runRoot));
ra = sixgr.mac.ra.RAConfig(cfg, "RunId", "runtime_ra_mcs_authority", ...
    "ScenarioName", "runtime_ra_mcs_authority", "UEId", 1, ...
    "CellId", 1, "AttemptId", 1);
grant = sixgr.mac.ra.buildRARULGrant(ra);
rar = sixgr.mac.ra.encodeMACRAR("RAPID", double(ra.PreambleIndex), ...
    "TimingAdvanceCommand", 0, ...
    "TemporaryCRNTI", double(ra.TempCRNTI), "ULGrant", grant);

[tx, sched] = sixgr.phy.ra.generateMsg2RARWaveform(cfg, ra, rar);
assert(double(sched.MCS) == double(ra.Msg2PDSCH.MCS), ...
    "Msg2 scheduler must preserve the YAML-owned MCS index.");
assert(string(sched.MCSTable) == string(ra.Msg2PDSCH.MCSTable), ...
    "Msg2 scheduler must preserve the YAML-owned MCS table.");
assert(abs(double(sched.TargetCodeRate) - 120/1024) < eps, ...
    "Msg2 MCS 0 must use the exact table-1 target code rate 120/1024.");
assert(~isempty(tx.Waveform) && all(isfinite(tx.Waveform(:))), ...
    "The strict Msg2 producer must emit a finite waveform.");

raBad = ra;
raBad.Msg2PDSCH.TargetCodeRate = 0.11719;
threw = false;
try
    sixgr.phy.ra.generateMsg2RARWaveform(cfg, raBad, rar);
catch ME
    threw = true;
    assert(string(ME.identifier) == "sixgr:pdsch:MCSAssignmentMismatch", ...
        "A contradictory YAML MCS/rate pair must retain its typed error.");
    assert(contains(string(ME.message), "configured modulation") && ...
        contains(string(ME.message), "decoded modulation"), ...
        "The typed mismatch must disclose configured and decoded values.");
end
assert(threw, "A contradictory YAML MCS/rate pair must fail closed.");

ok = true;
fprintf('%s\n', ['PASS testRuntimeRAMCSAuthority: exact YAML MCS table, ' ...
    'index, modulation, and code rate reached strict Msg2 materialization.']);
end

function localCleanup(pathText)
if isfolder(pathText)
    rmdir(pathText, "s");
end
end
