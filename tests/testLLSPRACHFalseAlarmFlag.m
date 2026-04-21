function ok = testLLSPRACHFalseAlarmFlag()
%TESTLLSPRACHFALSEALARMFLAG PRACH runtime detection must export observed false-alarm flags.

setup6GRSimToolkit("Verbose", false);

cfg = sixgr.config.defaultConfig();
cfg.run.shortRun = true;
cfg.outputs.saveCSV = false;
cfg.outputs.saveMAT = false;
cfg.outputs.saveFigures = false;
cfg = sixgr.util.structSet(cfg, "phy.prach.enable", true);

res = sixgr.link.runPRACHDetection(cfg, "SNR_dB", 12);
assert(isfield(res, "FalseAlarmFlag"), "PRACH detection result must export FalseAlarmFlag.");
if ~logical(sixgr.util.structGet(res, "Skipped", false))
    flag = double(res.FalseAlarmFlag);
    assert(isfinite(flag) && any(abs(flag - [0 1]) < 1e-9), ...
        "PRACH false-alarm flag must be a finite binary observation when PRACH executes.");
end

ok = true;
end
