function ok=testChannelArtifactExternalArchive()
% Actual executed operator evidence; external persistence is not a PHY model.
assert(ispc);
[passed,root,row]=testSharedIdentityAWGNRuntime(); assert(passed);
sixgr.util.jsonWrite(fullfile(root,'meta','scenario_config_identity.json'), ...
    struct('Scope','executed_operator_storage_fixture_not_scenario'));
before=sixgr.channel.validateSharedChannelObservationArtifact(root,row);
externalBase=string(getenv('SIXGR_TEST_ARCHIVE_ROOT'));
if strlength(externalBase)==0, externalBase=fullfile(pwd,'logs','external_archive_tests'); end
external=fullfile(externalBase,string(java.util.UUID.randomUUID));
script=fullfile(pwd,'scripts','move_lls_channel_archives.ps1');
[status,message]=system(sprintf(['pwsh -NoProfile -NonInteractive -ExecutionPolicy Bypass ' ...
    '-File "%s" -RunFolder "%s" -ArchiveFolder "%s"'],script,root,external));
assert(status==0,'Archive relocation failed: %s',message);
after=sixgr.channel.validateSharedChannelObservationArtifact(root,row);
assert(isequaln(before.Manifest,after.Manifest) && isequaln(before.Segments,after.Segments) && ...
    isequaln(before.PathMeanCoefficientPower,after.PathMeanCoefficientPower));
receiptPath=fullfile(root,'meta','channel_archive_storage.json');
receipt=jsondecode(fileread(receiptPath));
bad=receipt; bad.ExternalFolder=root;
sixgr.util.jsonWrite(receiptPath,bad);
localReject(@()sixgr.channel.validateSharedChannelObservationArtifact(root,row), ...
    'sixgr:util:RunArtifactOwnership');
sixgr.util.jsonWrite(receiptPath,receipt);
hidden=receiptPath+".test_preserved";
movefile(receiptPath,hidden);
localReject(@()sixgr.channel.validateSharedChannelObservationArtifact(root,row), ...
    'sixgr:util:RunArtifactOwnership');
movefile(hidden,receiptPath);
badRow=row; badRow.ChannelObservationMATFileSHA256=string(repmat('0',1,64));
localReject(@()sixgr.channel.validateSharedChannelObservationArtifact(root,badRow), ...
    'sixgr:channel:ChannelArtifactFileHashMismatch');
localReject(@()sixgr.util.resolveRunArtifactPath(root,'channel/mat/../../outside.mat'), ...
    'sixgr:util:RunArtifactPath');
sixgr.channel.validateSharedChannelObservationArtifact(root,row);
ok=true; disp('CHANNEL_ARTIFACT_EXTERNAL_ARCHIVE_PASS');
end

function localReject(action,identifier)
try
    action();
catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s, got %s.',identifier,cause.identifier);
    return;
end
error('test:ExpectedRejection','Expected %s.',identifier);
end
