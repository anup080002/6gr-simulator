function ok = testRAN1LLSInterference()
%TESTRAN1LLSINTERFERENCE Prove cochannel interference is a real waveform.

setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
tmp = string(tempname);
mkdir(tmp);
cleanup = onCleanup(@() localCleanup(tmp)); %#ok<NASGU>
configPath = "configs/lls/pusch_awgn_interference_regression.yaml";
result = sixgr.lls.runLLS(configPath,"OutputRoot",tmp, ...
    "RunTag","interference","GeneratePlots",false);

assert(result.Status == "complete_valid");
T = result.TrialTable;
assert(all(T.InterferenceEnabled) && all(T.InterfererWaveformCount == 1));
assert(all(T.InterferenceSource == ...
    "independent_transport_block_waveform_and_channel"));
assert(all(abs(T.ConfiguredDIRdB-T.MeasuredDIRdB) <= 0.05));
assert(all(isfinite(T.MeasuredPreEqualizationSINRdB)));
assert(all(T.MeasuredPreEqualizationSINRdB < T.TargetSNRdB-20), ...
    "A -10 dB D/I waveform must materially lower pre-equalization SINR.");
assert(result.TruthContractTable.ActualInterference);

[cfg,~] = sixgr.lls.loadConfig(configPath);
cfg.interference.rnti = cfg.pusch.rnti;
assertError(@()sixgr.lls.validateConfig(cfg), ...
    "sixgr:lls:InterfererIdentityCollision");
fprintf("RAN1LLSInterference: TB=%d errors=%d mean D/I=%.4f dB.\n", ...
    result.SummaryTable.NumTB,result.SummaryTable.NumBlockErrors,mean(T.MeasuredDIRdB));
ok = true;
end

function assertError(fn,identifier)
try
    fn();
catch ex
    assert(string(ex.identifier) == string(identifier), ...
        "Expected %s, got %s.",identifier,ex.identifier);
    return;
end
error("testRAN1LLSInterference:MissingError", ...
    "Expected %s but no error was thrown.",identifier);
end

function localCleanup(path)
if exist(path,"dir") == 7
    rmdir(path,"s");
end
end
