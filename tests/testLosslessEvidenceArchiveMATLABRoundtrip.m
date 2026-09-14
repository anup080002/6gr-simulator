function ok=testLosslessEvidenceArchiveMATLABRoundtrip()
% Declared MAT/class fixtures only; no RF or qualification evidence.
runtime=sixgr.lls6g.config.ensureYAMLRuntime('RequireYAML',true,'ConfigurePyEnv',true);
root=tempname(fullfile(pwd,'logs')); mkdir(root);
source=fullfile(root,'declared_source'); mkdir(source);
values=reshape(complex(1:64,-64:-1),32,2)/256;
observation=sixgr.phy.waveform.WaveformObservationBuffer(12,44,1e6,2);
observation.append(sixgr.phy.waveform.WaveformChunk(values,12),1e6);
record=struct('Scope','declared_archive_fixture_not_RF','MissingMetric',NaN, ...
    'EmptyBits',int8([]),'ComplexValues',values,'SingleValues',single(values));
sourceFile=fullfile(source,'declared_observation.mat');
save(sourceFile,'observation','record','-v7.3');
sourceHash=sixgr.util.sha256File(sourceFile);
container=fullfile(root,'archive'); restored=fullfile(root,'restored');
script=fullfile(pwd,'scripts','lossless_evidence_archive.py');
job=struct('operation','create','input',source,'policy_path', ...
    fullfile(pwd,'simulator','configs','validation','lossless_evidence_archive.yaml'));
jobPath=fullfile(root,'create.json'); sixgr.util.jsonWrite(jobPath,job);
localRun(runtime.PythonExecutable,script,jobPath,container);
job=struct('operation','restore','input',container,'policy_path',[]);
% JSON null is an explicit absent policy: restoration reads the frozen
% container policy, never caller overrides. Encode null without coercing []
% into an array, which would be a different API input.
jobText=strrep(jsonencode(job),'"policy_path":[]','"policy_path":null');
jobPath=fullfile(root,'restore.json'); sixgr.util.writeTextFile(jobPath,jobText);
localRun(runtime.PythonExecutable,script,jobPath,restored);
assert(sourceHash==sixgr.util.sha256File(sourceFile) && ...
    sourceHash==sixgr.util.sha256File(fullfile(restored,'declared_observation.mat')));
loaded=load(fullfile(restored,'declared_observation.mat'),'observation','record');
assert(isequaln(record,loaded.record) && isa(loaded.observation,class(observation)) && ...
    loaded.observation.isComplete() && isequal(values,loaded.observation.readComplete()));
for field=["StartSample","EndSampleExclusive","ReceivedThroughSample","SampleRateHz","NumReceiveAntennas"]
    assert(observation.(field)==loaded.observation.(field));
end
ok=true;
fprintf('LOSSLESS_ARCHIVE_MATLAB_ROUNDTRIP_PASS root=%s byte_exact=1 RF_episodes=0\n',root);
end
function localRun(python,script,job,output)
[status,message]=system(sprintf('"%s" "%s" --config "%s" --output "%s"',python,script,job,output));
fprintf('%s\n',message);
assert(status==0,'test:EvidenceArchiveRoundtrip','Lossless archive operation failed.');
end
