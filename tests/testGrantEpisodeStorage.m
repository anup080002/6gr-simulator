function ok=testGrantEpisodeStorage(retainedEpisodePath)
% Lossless storage must preserve native bits, evidence and physical features.
arguments
    retainedEpisodePath (1,1) string=""
end
mode="lossless_path_gains_xor_v1";
stream=RandStream('mt19937ar','Seed',801);
cases={zeros(0,0),single(zeros(0,2)),reshape(randn(stream,840,1),[35 4 3 2]), ...
    complex(randn(stream,35,4,3,2),randn(stream,35,4,3,2)), ...
    complex(single(randn(stream,17,2)),single(randn(stream,17,2))), ...
    [0 -0 Inf -Inf NaN realmin realmax]};
for k=1:numel(cases)
    e=struct('Schema',"sixgr.frozen_grant_calibration_episode/v1", ...
        'Captures',{{struct('Propagation',struct('PathGains',cases{k}))}}, ...
        'CRCError',true,'CalibrationQualified',false,'UnrelatedEvidence',[1 3 7]);
    stored=sixgr.calibration.encodeGrantEpisodeStorage(e,mode);
    recovered=sixgr.calibration.decodeGrantEpisodeStorage(stored,mode);
    assert(isequaln(e,recovered));
    gains=recovered.Captures{1}.Propagation.PathGains;
    assert(isequal(typecast(real(cases{k}(:)),'uint8'),typecast(real(gains(:)),'uint8')));
    assert(isequal(typecast(imag(cases{k}(:)),'uint8'),typecast(imag(gains(:)),'uint8')));
    assert(isequaln(sixgr.calibration.encodeGrantEpisodeStorage(e,"raw"),e));
    assert(isequaln(sixgr.calibration.decodeGrantEpisodeStorage(e,"raw"),e));
    reject(@()sixgr.calibration.decodeGrantEpisodeStorage(stored,"raw"), ...
        'sixgr:calibration:EpisodeStorageSchema');
    reject(@()sixgr.calibration.decodeGrantEpisodeStorage(e,mode), ...
        'sixgr:calibration:EpisodeStorageSchema');
    if ~isempty(cases{k})
        bad=stored;
        bad.Episode.Captures{1}.Propagation.PathGains.Real.BytePlanes(1)= ...
            bitxor(bad.Episode.Captures{1}.Propagation.PathGains.Real.BytePlanes(1),uint8(1));
        reject(@()sixgr.calibration.decodeGrantEpisodeStorage(bad,mode), ...
            'sixgr:calibration:EpisodeStorageDigest');
    end
end
% MATLAB's MAT compression must preserve the encoding through save/load.
path=string(tempname(fullfile(pwd,'logs')))+"_storage_codec.mat";
save(path,'stored','-v7.3'); loaded=load(path,'stored');
assert(isequaln(sixgr.calibration.decodeGrantEpisodeStorage(loaded.stored,mode),e));
if strlength(retainedEpisodePath)>0
    % Optional retained physical benchmark: never overwrite its sealed source.
    sixgr.calibration.verifyEpisodeFile(retainedEpisodePath);
    saved=load(retainedEpisodePath,'episode'); e=saved.episode;
    stored=sixgr.calibration.encodeGrantEpisodeStorage(e,mode);
    path=string(tempname(fullfile(pwd,'logs')))+"_lossless_episode.mat";
    episode=stored; %#ok<NASGU>
    save(path,'episode','-v7.3');
    clear stored episode
    loaded=load(path,'episode');
    restored=sixgr.calibration.decodeGrantEpisodeStorage(loaded.episode,mode);
    clear loaded
    assert(isequaln(e,restored),'Storage changed retained physical evidence.');
    % Reconstruct both binding and features from restored native path gains.
    for j=1:numel(restored.Captures)
        checked=sixgr.system.waveform.bindCalibrationReceiverIdentity(restored.Captures{j},restored.ResolvedConfig);
        [key,feature]=sixgr.system.waveform.extractGrantCalibrationBinding(checked);
        assert(isequaln(key,e.CalibrationBindings{j}) && ...
            isequaln(feature,e.SpatialPredictorFeatures{j}), ...
            'Storage changed a physical calibration key or predictor.');
    end
    before=dir(retainedEpisodePath); after=dir(path);
    fprintf('GRANT_STORAGE_RETAINED_PASS original_bytes=%d encoded_bytes=%d artifact=%s qualification=0\n', ...
        before.bytes,after.bytes,path);
end
fprintf('GRANT_EPISODE_STORAGE_PASS bit_exact_cases=%d qualification=0\n',numel(cases));
ok=true;
end

function reject(fn,id)
try
    fn(); error('test:NotRejected','Expected %s',id);
catch err
    assert(strcmp(err.identifier,id),'Expected %s, got %s',id,err.identifier);
end
end
