function ok=testGrantEpisodeArrayPool(retainedEpisodePath)
% Exact storage aliases must never merge differing types/shapes/native bits.
arguments
    retainedEpisodePath (1,1) string=""
end
base=reshape(1:2048,32,64);
input=struct('Grid',base,'Alias',base,'Nested',{{base,single(base),base.'}}, ...
    'Logical',true(32,64),'Sparse',sparse(eye(4)),'Empty',zeros(0,2), ...
    'Small',[NaN -Inf Inf],'Label',"physical_evidence_fixture");
encoded=sixgr.calibration.encodeEvidenceArrayPool(input);
decoded=sixgr.calibration.decodeEvidenceArrayPool(encoded);
assert(isequaln(input,decoded) && numel(encoded.Arrays)==4);
assert(encoded.Template.Grid.Index==encoded.Template.Alias.Index && ...
    encoded.Template.Grid.Index==encoded.Template.Nested{1}.Index && ...
    encoded.Template.Grid.Index~=encoded.Template.Nested{2}.Index && ...
    encoded.Template.Grid.Index~=encoded.Template.Nested{3}.Index);
positive=zeros(1,2048); negative=-positive;
assert(sixgr.calibration.evidenceArraySHA256(positive)~= ...
    sixgr.calibration.evidenceArraySHA256(negative),'Signed zero bits were merged.');
nanBits=repmat(bitor(bitshift(uint64(2047),52),uint64(1)),2048,1);
otherBits=nanBits+uint64(1);
nanOne=typecast(nanBits,'double'); nanTwo=typecast(otherBits,'double');
assert(sixgr.calibration.evidenceArraySHA256(nanOne)~= ...
    sixgr.calibration.evidenceArraySHA256(nanTwo),'Distinct NaN payloads were merged.');
special={nanOne,nanTwo,positive,negative,complex(base,-base),uint16(base)};
packed=sixgr.calibration.encodeEvidenceArrayPool(special);
assert(isscalar(packed),'A cell payload must not expand the storage envelope.');
restored=sixgr.calibration.decodeEvidenceArrayPool(packed);
for k=1:numel(special)
    assert(sixgr.calibration.evidenceArraySHA256(special{k})== ...
        sixgr.calibration.evidenceArraySHA256(restored{k}));
end
reject(rmfield(encoded,'SHA256'),'sixgr:calibration:ArrayPoolSchema');
bad=encoded; bad.Arrays{1}(1)=bad.Arrays{1}(1)+1;
reject(bad,'sixgr:calibration:ArrayPoolDigest');
bad=encoded; bad.Template.Grid.Index=2;
reject(bad,'sixgr:calibration:ArrayPoolReference');
bad=encoded; bad.Template.Grid.Index=NaN;
reject(bad,'sixgr:calibration:ArrayPoolReference');
bad=encoded; bad.Arrays{end+1,1}=base+5;
bad.SHA256(end+1,1)=sixgr.calibration.evidenceArraySHA256(base+5);
reject(bad,'sixgr:calibration:ArrayPoolUnused');
for value={struct(),cell(0,2),struct('Small',1), ...
        repmat(struct('Grid',base),2,3),reshape(base,8,8,32)}
    packed=sixgr.calibration.encodeEvidenceArrayPool(value{1});
    assert(isscalar(packed),'Every payload requires exactly one storage envelope.');
    assert(isequaln(value{1},sixgr.calibration.decodeEvidenceArrayPool(packed)));
end
episode=struct('Schema',"sixgr.frozen_grant_calibration_episode/v1", ...
    'Captures',{{struct('Propagation',struct('PathGains',complex(base,-base)), ...
    'Receiver',input)}},'CalibrationQualified',false,'PrimaryStudyAccepted',false);
mode="lossless_path_gains_xor_dedup_v1";
stored=sixgr.calibration.encodeGrantEpisodeStorage(episode,mode);
path=string(tempname(fullfile(pwd,'logs')))+"_array_pool.mat";
save(path,'stored','-v7.3'); loaded=load(path,'stored');
assert(isequaln(episode,sixgr.calibration.decodeGrantEpisodeStorage(loaded.stored,mode)));

if strlength(retainedEpisodePath)>0
    sixgr.calibration.verifyEpisodeFile(retainedEpisodePath);
    saved=load(retainedEpisodePath,'episode'); original=saved.episode;
    sourceMode="raw";
    if isfield(original,'Mode'), sourceMode=string(original.Mode); end
    original=sixgr.calibration.decodeGrantEpisodeStorage(original,sourceMode);
    stored=sixgr.calibration.encodeGrantEpisodeStorage(original,mode);
    physicalPath=string(tempname(fullfile(pwd,'logs')))+"_physical_array_pool.mat";
    save(physicalPath,'stored','-v7.3'); clear stored saved
    loaded=load(physicalPath,'stored');
    restored=sixgr.calibration.decodeGrantEpisodeStorage(loaded.stored,mode);
    assert(isequaln(original,restored),'Physical episode changed during lossless storage.');
    for k=1:numel(restored.Captures)
        checked=sixgr.system.waveform.bindCalibrationReceiverIdentity( ...
            restored.Captures{k},restored.ResolvedConfig);
        [key,feature]=sixgr.system.waveform.extractGrantCalibrationBinding(checked);
        assert(isequaln(key,original.CalibrationBindings{k}) && ...
            isequaln(feature,original.SpatialPredictorFeatures{k}));
    end
    before=dir(retainedEpisodePath); after=dir(physicalPath);
    fprintf('PHYSICAL_ARRAY_POOL_PASS old_bytes=%d new_bytes=%d qualification=0 path=%s\n', ...
        before.bytes,after.bytes,physicalPath);
end
fprintf('GRANT_ARRAY_POOL_PASS native_bits_types_shapes_and_corruption_guards=1\n');
ok=true;
end

function reject(value,id)
try
    sixgr.calibration.decodeEvidenceArrayPool(value);
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s',id,cause.identifier);
    return;
end
error('test:ExpectedArrayPoolFailure','Expected %s',id);
end
