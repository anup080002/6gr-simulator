function ok = testProductionTruthEntrypointParseIntegrity()
%TESTPRODUCTIONTRUTHENTRYPOINTPARSEINTEGRITY Guard production file structure.

setup6GRSimToolkit("Verbose", false);
assert(nargin("sixgr.truth.runWaveformLinkBundle") == 3, ...
    "The production waveform bundle must parse as a three-input function.");
assert(nargin("sixgr.truth.recoverLLSRunArtifacts") == -3, ...
    "The failed-run recovery entry point must parse with two required inputs.");
assert(nargin("sixgr.truth.applyPersistedMIMOConfiguredEffectiveStatus") == 3, ...
    "The persisted MIMO status reducer must remain directly callable.");
ok = true;
end
