function ok = testPDCCHCORESETDurationAuthority()
%TESTPDCCHCORESETDURATIONAUTHORITY Modern YAML owns exact CORESET duration.

scenarioPath = fullfile(pwd, "simulator", "configs", "scenarios", ...
    "lls_mimo4x4_multiuser_beamformed.yaml");
scfg = sixgr.lls6g.config.loadScenarioConfig(scenarioPath);
tmp = tempname;
mkdir(tmp);
cleanup = onCleanup(@()rmdir(tmp, "s")); %#ok<NASGU>
cfg = sixgr.lls6g.buildInternalConfig(scfg, fullfile(tmp, "run"));
assert(double(sixgr.util.structGet(cfg, ...
    "phy.pdcch.coreset.duration", NaN)) == 2);
assert(double(sixgr.util.structGet(cfg, ...
    "phy.pdcch.numSymbols", NaN)) == 2);

raw = scfg.Data;
raw.pdcch.coreset_duration_symbols = 3;
bad = sixgr.lls6g.config.ScenarioConfig(raw, ...
    "SourceFiles", scfg.SourceFiles, "ConfigPath", scfg.ConfigPath, ...
    "ConfigHash", scfg.ConfigHash);
thrown = false;
try
    sixgr.lls6g.buildInternalConfig(bad, fullfile(tmp, "bad"));
catch ME
    thrown = strcmp(ME.identifier, ...
        "sixgr:phy:pdcch:ConflictingCORESETDurationAuthority");
end
assert(thrown, ...
    "Conflicting PDCCH/CORESET duration authorities must fail closed.");
ok = true;
end
