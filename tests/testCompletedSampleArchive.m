function ok=testCompletedSampleArchive()
% Exact archived samples and cached identities must survive restoration.
% Profiling counts prove bounded hash ownership, not waveform qualification
% or a wall-clock speedup on a different machine.
root=tempname; mkdir(root);
cachedHashRecomputations=0;
for type=["single","double"]
    x=complex(cast(reshape(sin(1:400),100,4),type),cast(reshape(cos(1:400),100,4),type));
    o=sixgr.phy.waveform.WaveformObservationBuffer(19,119,30720000,4);
    o.append(sixgr.phy.waveform.WaveformChunk(x(1:50,:),19),30720000);
    reject(@()o.archiveCompleted(root),'WAVEFORM:IncompleteObservation');
    o.append(sixgr.phy.waveform.WaveformChunk(x(51:100,:),69),30720000);
    h=o.sampleHash();
    receipt=o.archiveCompleted(root);
    serialized=jsondecode(jsonencode(receipt));
    assert(isequaln(sixgr.phy.waveform.CompletedSampleArchive.read(serialized),x), ...
        'CSV JSON receipts must verify and reload the same exact samples.');
    assert(o.storageInfo().RetainedArrays==0 && o.storageInfo().Archived);
    assert(isequaln(o.readComplete(),x) && o.sampleHash()==h);
    state=fullfile(root,"buffer_"+type+".mat");
    sixgr.util.matSave(state,struct('Observation',o),'UseArtifactStore',false,'ForceV73',true);
    restored=sixgr.util.loadVerifiedMAT(state,sixgr.util.sha256File(state),"Observation");
    assert(isequaln(restored.Observation.readComplete(),x));
    assert(restored.Observation.storageInfo().RetainedArrays==0);
    mutated=restored.Observation.readComplete(); mutated(1)=0;
    assert(~isequaln(mutated,x),'The caller-owned copy must actually change in this test.');
    assert(isequaln(o.readComplete(),x),'Caller mutation cannot change archived samples.');
    % Asking for an already bound digest must not load/hash the whole sample
    % array again. It must still verify the archived file on every request:
    % caching alone must never turn corrupted evidence into a valid hash.
    profileRoot=fullfile(root,"cached_hash_"+type);
    session=sixgr.runtime.ExecutionStageProfiler.start(profileRoot,true); %#ok<NASGU> Cleanup owns the timing session.
    for repeat=1:2
        assert(restored.Observation.sampleHash()==h);
    end
    clear session
    profile=readtable(fullfile(profileRoot,'reports','csv', ...
        'execution_stage_profile.csv'),'TextType','string');
    cachedHashRecomputations=cachedHashRecomputations+sum( ...
        profile.ScopeExitCount(profile.Stage=="hashing" & profile.Operation=="runtime_array"));
    assert(sum(profile.ScopeExitCount(profile.Stage=="hashing" & ...
        ismember(profile.Operation,["SHA256_file","waveform_file"])))>=2, ...
        'WAVEFORM:CachedArchiveHashNotVerified', ...
        'Every cached-hash request must verify the complete archived file, not size or mtime.');
    assert(restored.Observation.storageInfo().RetainedArrays==0, ...
        'WAVEFORM:CachedArchiveRetainedSamples', ...
        'A hash-only request must not recreate resident completed sample owners.');
    % Preserve file length while changing bytes. A size-only integrity
    % shortcut would miss this; both hash access and sample access reject it.
    archivePath=fullfile(receipt.Root,receipt.RelativePath);
    flipFinalByte(archivePath);
    reject(@()restored.Observation.sampleHash(),'sixgr:util:VerifiedMATHashMismatch');
    reject(@()o.readComplete(),'sixgr:util:VerifiedMATHashMismatch');
    % Corruption must fail on retrieval, never silently regenerate samples.
    sixgr.util.writeTextFile(archivePath,'corrupted');
    reject(@()o.readComplete(),'WAVEFORM:ArchiveMissing');
    reject(@()restored.Observation.sampleHash(),'WAVEFORM:ArchiveMissing');
end
assert(cachedHashRecomputations==0,'WAVEFORM:CachedArchiveSampleRehash', ...
    'Cached hash access recomputed %d complete sample-array hashes.',cachedHashRecomputations);
ok=true; disp('COMPLETED_SAMPLE_ARCHIVE_PASS');
end
function flipFinalByte(path)
% Only the test-owned temporary archive is deliberately damaged.
fid=fopen(path,'r+'); assert(fid>=0);
closeFile=onCleanup(@()fclose(fid));
assert(fseek(fid,-1,'eof')==0);
value=fread(fid,1,'*uint8'); assert(isscalar(value));
assert(fseek(fid,-1,'eof')==0);
assert(fwrite(fid,bitxor(value,uint8(1)),'uint8')==1);
end
function reject(action,id)
try
    action();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s',id,cause.identifier);
    return;
end
error('test:ExpectedFailure','Expected %s',id);
end
