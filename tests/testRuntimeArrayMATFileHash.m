function ok=testRuntimeArrayMATFileHash()
% Serialization equivalence only; these numeric arrays are not PHY results.
root=string(tempname)+"_mat_array_hash"; mkdir(root);
cleanup=onCleanup(@()rmdir(root,'s')); %#ok<NASGU>
path=fullfile(root,'arrays.mat');
payload=struct('scalar',single(3),'real',reshape(1:210,7,5,3,2), ...
    'complex',reshape(complex(sin(1:315),cos(1:315)),7,5,3,3), ...
    'singleComplex',reshape(complex(single(sin(1:210)),single(cos(1:210))),7,5,3,2), ...
    'tx64rx4',reshape(complex(sin(1:104448),cos(1:104448)),17,24,64,4));
sixgr.util.matSave(path,payload,'ForceV73',true,'UseArtifactStore',false);
archive=matfile(path,'Writable',false);
cases=0;
for name=string(fieldnames(payload)).'
    if name=="tx64rx4", budgets=[4096 10000 1048576]; else, budgets=[3 7 37 1048576]; end
    for budget=budgets
        [digest,e]=sixgr.phy.waveform.runtimeArrayMATFileHash(archive,name,budget);
        assert(digest==sixgr.phy.waveform.WaveformHash.runtimeArray(payload.(name)) && ...
            e.ElementCount==numel(payload.(name)) && e.AllFinite && ...
            e.MaxBlockElements<=budget && ~e.FullArrayLoaded && ...
            isequal(e.Dimensions,size(payload.(name))), ...
            'MAT-file hashing must preserve every class, dimension, real and imaginary byte.');
        cases=cases+1;
    end
end
% Same shape but changed coefficient must not retain the original digest.
changed=payload.complex; changed(end)=changed(end)+1i;
writable=matfile(path,'Writable',true); writable.complex=changed;
[digest,~]=sixgr.phy.waveform.runtimeArrayMATFileHash(archive,'complex',37);
assert(digest~=sixgr.phy.waveform.WaveformHash.runtimeArray(payload.complex));
changed(1)=NaN; writable.complex=changed;
[~,e]=sixgr.phy.waveform.runtimeArrayMATFileHash(archive,'complex',37);
assert(~e.AllFinite,'Nonfinite values must remain observable to the validator.');
legacyPath=fullfile(root,'legacy.mat');
legacy=payload.real; save(legacyPath,'legacy','-v7');
rejected=false;
try
    sixgr.phy.waveform.runtimeArrayMATFileHash(matfile(legacyPath),'legacy',37);
catch cause
    rejected=strcmp(cause.identifier,'sixgr:channel:ChannelArtifactStreamingFormat');
end
assert(rejected,'A v7 read must not silently exceed the bounded-memory contract.');
ok=true;
fprintf('MAT_ARRAY_STREAM_HASH_PASS equivalence_cases=%d changed_and_nonfinite_rejected=1\n',cases);
end
