function ok=testChannelArtifactLongPath()
% Actual small channel observation, serialized in the large-run MAT format.
% This checks persistence/validation, not a new throughput scenario.
[passed,sourceRoot,row]=testSharedIdentityAWGNRuntime();
assert(passed);
saved=load(fullfile(sourceRoot,row.ChannelObservationMATFile),'ManifestJSON','Captures');
parent=string(tempname)+"_channel_artifact_long_path";
mkdir(parent);
cleanup=onCleanup(@()localCleanup(parent)); %#ok<NASGU>
root=parent;
while strlength(fullfile(root,row.ChannelObservationMATFile))<=310
    root=fullfile(root,'retained_runtime_channel_evidence');
end
target=fullfile(root,row.ChannelObservationMATFile);
sixgr.util.matSave(target,saved,'UseArtifactStore',false,'ForceV73',true);
csvTarget=fullfile(root,row.ChannelObservationSegmentsCSV);
sixgr.util.ensureDir(csvTarget);
copyfile(fullfile(sourceRoot,row.ChannelObservationSegmentsCSV),csvTarget);
row.ChannelObservationMATFileSHA256=sixgr.phy.waveform.WaveformHash.file(target);
before=sixgr.phy.waveform.WaveformHash.file(target);
previousFolder=pwd;
verified=sixgr.channel.validateSharedChannelObservationArtifact(root,row);
assert(verified.Manifest.Source=="executed_identity_AWGN_operator" && ...
    verified.MATPath==string(java.io.File(target).getCanonicalPath()) && ...
    sixgr.phy.waveform.WaveformHash.file(target)==before && strcmp(pwd,previousFolder), ...
    'Long-path validation must use the same immutable archive without changing the working folder.');
[manifestOnly,readback]=sixgr.util.loadVerifiedMAT(target,before,"ManifestJSON");
assert(isequal(string(fieldnames(manifestOnly)),"ManifestJSON") && ...
    manifestOnly.ManifestJSON==saved.ManifestJSON && ...
    readback.UsedShortReadback==ispc && ...
    (readback.TemporaryFilePath=="" || ~isfile(readback.TemporaryFilePath)), ...
    'Selective readback must preserve exact variables and remove only its temporary copy.');

bad=row; bad.ChannelObservationMATFileSHA256=string(repmat('0',1,64));
rejected=false;
try
    sixgr.channel.validateSharedChannelObservationArtifact(root,bad);
catch cause
    rejected=strcmp(cause.identifier,'sixgr:channel:ChannelArtifactFileHashMismatch');
end
assert(rejected,'Long-path support must not bypass the original file-hash gate.');
localReject(@()sixgr.util.loadVerifiedMAT(target,string(repmat('0',1,64)),"ManifestJSON"), ...
    'sixgr:util:VerifiedMATHashMismatch');
localReject(@()sixgr.util.loadVerifiedMAT(target,before,"UnrecordedMeasurement"), ...
    'sixgr:util:VerifiedMATVariableMissing');
localReject(@()sixgr.util.loadVerifiedMAT(target,before,"-regexp"), ...
    'sixgr:util:VerifiedMATVariableName');
assert(sixgr.phy.waveform.WaveformHash.file(target)==before && strcmp(pwd,previousFolder), ...
    'Rejected readback requests must not change the original archive or current folder.');
ok=true;
fprintf('CHANNEL_ARTIFACT_LONG_PATH_PASS pathLength=%d original_bytes_unchanged=1\n',strlength(target));
end

function localReject(action,identifier)
rejected=false;
try
    action();
catch cause
    rejected=strcmp(cause.identifier,identifier);
end
assert(rejected,'Expected exact readback rejection %s.',identifier);
end

function localCleanup(root)
if isfolder(root), rmdir(root,'s'); end
end
