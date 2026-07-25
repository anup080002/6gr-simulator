function ok = testSIB1TruthContractStrictGate()
%TESTSIB1TRUTHCONTRACTSTRICTGATE Strict contract gates SIB1 evidence.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.config.defaultConfig();
cfg.run.strictMode = true;
cfg.phy.sib1.enable = true;
cfg.initial_access.type0 = struct("monitoring_occasion_ordinal",2);
cfg.initial_access.sib1.pdsch = struct("prb_start",0, ...
    "num_prb",24,"symbol_start",2,"num_symbols",12,"mcs",0,"rv",0);
scfg = struct("meta", struct("tags", ["truth","no-proxy"]), "scenario", struct("honesty_mode", "strict"));
tmpMissing = fullfile(tempdir, "sixgr_test_sib1_missing_gate");
if exist(tmpMissing, "dir")
    rmdir(tmpMissing, "s");
end
sixgr.util.ensureFolder(tmpMissing);
vMissing = sixgr.truth.evaluateLLSRuntimeTruthContract(tmpMissing, scfg, cfg);
assert(~logical(vMissing.Ok), "Strict contract must fail when mandatory SIB1 artifacts are missing.");
assert(any(contains(string(vMissing.Failures), "sib1_strict_waveform_evidence")), ...
    "Missing SIB1 evidence must be named in truth-contract failures.");

if exist("nrWaveformGenerator", "file") == 2 && sixgr.phy.broadcast.siRNTIWaveformSupported()
    tmpPass = fullfile(tempdir, "sixgr_test_sib1_gate_pass");
    if exist(tmpPass, "dir")
        rmdir(tmpPass, "s");
    end
    sixgr.phy.broadcast.runSIB1StrictMiniAnchor(tmpPass, cfg);
    vPass = sixgr.truth.evaluateLLSRuntimeTruthContract(tmpPass, scfg, cfg);
    assert(~any(contains(string(vPass.Failures), "sib1_strict_waveform_evidence")), ...
        "SIB1 gate must pass when positive strict artifacts exist.");
end
ok = true;
end
