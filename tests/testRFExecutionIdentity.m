function ok=testRFExecutionIdentity()
% Actual bounded RF processing: no assumed campaign or positive-test label.
setup6GRSimToolkit('Verbose',false);
cfg=struct(); samples=complex(zeros(8,2));
stream=sixgr.rf.runtime.RFImpairmentStream(cfg,'rx','UL',7.68e6,2,17,3,false);
out=stream.apply(sixgr.phy.waveform.WaveformChunk(samples,17),3);
assert(string(out.Row.TrialId)~="positive_rf_impairment" && ...
    string(out.Row.RunId)~="channel_rf_strict", ...
    'test:InventedRFExecutionIdentity', ...
    'A runtime RF interval is not the strict positive RF component trial.');
assert(string(out.Row.RunId)=="" && ...
    string(out.Row.TrialId)=="rf_stream/rx/UL/samples_17_25");
identity=struct('RunId',"declared_run",'TrialId',"absent_UE_episode");
stream=sixgr.rf.runtime.RFImpairmentStream(cfg,'rx','UL',7.68e6,2,17,3,false,identity);
named=stream.apply(sixgr.phy.waveform.WaveformChunk(samples,17),3);
assert(isequal(named.Waveform,out.Waveform) && ...
    named.Row.RunId=="declared_run" && ...
    named.Row.TrialId=="absent_UE_episode/rx/UL/samples_17_25");
next=stream.apply(sixgr.phy.waveform.WaveformChunk(samples,25),3);
assert(next.Row.TrialId=="absent_UE_episode/rx/UL/samples_25_33");
direct=sixgr.rf.applyRFImpairmentChain(samples,cfg,'SampleRateHz',7.68e6, ...
    'Endpoint','rx','UseLegacyGlobalConfig',false,'StrictMutationRequired',false);
assert(direct.Row.RunId=="" && direct.Row.TrialId=="");
strict=sixgr.rf.applyRFImpairmentChain(samples,cfg,'SampleRateHz',7.68e6, ...
    'Endpoint','rx','UseLegacyGlobalConfig',false,'StrictMutationRequired',false, ...
    'RunId',"explicit_component_run",'TrialId',"positive_rf_impairment");
assert(strict.Row.RunId=="explicit_component_run" && strict.Row.TrialId=="positive_rf_impairment");
assert(isequal(strict.Waveform,direct.Waveform));
bad=identity; bad.SignalPresent=false;
try
    sixgr.rf.runtime.RFImpairmentStream(cfg,'rx','UL',7.68e6,2,17,3,false,bad);
    error('test:ExpectedRFIdentityRejection');
catch err
    assert(strcmp(err.identifier,'RF:InvalidExecutionIdentity'));
end
ok=true;
fprintf('RF_EXECUTION_IDENTITY_PASS actual_interval_not_assumed_positive_trial\n');
end
