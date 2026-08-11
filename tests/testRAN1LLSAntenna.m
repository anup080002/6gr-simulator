function ok = testRAN1LLSAntenna()
%TESTRAN1LLSANTENNA Focused physical-array/CDL waveform regression.

setup6GRSimToolkit("Verbose",false);
dlPath = fullfile("configs","lls", ...
    "pdsch_ntn_leo_cdl_d_64x4_antenna_example.yaml");
[cfg,~] = sixgr.lls.loadConfig(dlPath);
state = sixgr.lls.resolveAntennaState(cfg);
assert(state.Enabled);
assert(state.TxRole == "gnb" && state.RxRole == "ue");
assert(state.Tx.NumElements == 64 && state.Rx.NumElements == 4);
assert(isequal(size(state.Tx.PortToElementMatrix),[64 1]));
assert(abs(sum(abs(state.Tx.PortToElementMatrix).^2,"all")-1) <= 1e-12);
assert(strlength(state.Tx.PortToElementSHA256) == 64);

ulPath = fullfile("configs","lls", ...
    "pusch_ntn_leo_cdl_d_4x64_antenna_example.yaml");
[ulCfg,~] = sixgr.lls.loadConfig(ulPath);
ulState = sixgr.lls.resolveAntennaState(ulCfg);
assert(ulState.TxRole == "ue" && ulState.RxRole == "gnb");
assert(ulState.Tx.NumElements == 4 && ulState.Rx.NumElements == 64);

bad = cfg;
bad.channel.model = "NTN-TDL-D";
localAssertError(@()sixgr.lls.validateConfig(bad), ...
    "sixgr:lls:AntennaPatternRequiresCDL");
bad = cfg;
bad.channel.txAntennas = 63;
localAssertError(@()sixgr.lls.validateConfig(bad), ...
    "sixgr:lls:AntennaChannelDimensionMismatch");

root = string(tempname);
mkdir(root);
cleanup = onCleanup(@()localRemoveTree(root)); %#ok<NASGU>
result = sixgr.lls.runLLS(dlPath,"OutputRoot",root, ...
    "RunTag","focused_64x4_antenna_gate","GeneratePlots",false);
assert(result.Status == "complete_valid");
assert(height(result.TrialTable) == 1);
assert(result.TrialTable.AntennaEnabled);
assert(result.TrialTable.AntennaPhysicalElementChannelApplied);
assert(result.TrialTable.AntennaTxPhysicalElements == 64);
assert(result.TrialTable.AntennaRxPhysicalElements == 4);
assert(result.TrialTable.NumRxAntennas == 4);
assert(result.TruthContractTable.ActualAntennaArray);
assert(result.TruthContractTable.AntennaEvidenceValid);
assert(any(result.ValidityTable.Check == "antenna_array_authority" & ...
    result.ValidityTable.Pass));
assert(isfile(fullfile(result.RunFolder,"antenna_config_resolved.csv")));
assert(isfile(fullfile(result.RunFolder,"antenna_array_elements.csv")));
assert(isfile(fullfile(result.RunFolder,"antenna_pattern_samples.csv")));
assert(isfile(fullfile(result.RunFolder,"antenna_runtime_evidence.csv")));
assert(~any(endsWith(result.ArtifactManifest.RelativePath,".svg", ...
    "IgnoreCase",true)));
ok = true;
fprintf("testRAN1LLSAntenna: PASS\n");
end

function localAssertError(callback,identifier)
thrown = false;
try
    callback();
catch ME
    thrown = strcmp(ME.identifier,identifier);
end
assert(thrown,"Expected typed error %s.",identifier);
end

function localRemoveTree(path)
if isfolder(path)
    rmdir(path,"s");
end
end
