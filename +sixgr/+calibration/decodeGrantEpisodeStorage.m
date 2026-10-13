function episode=decodeGrantEpisodeStorage(stored,mode)
%DECODEGRANTEPISODESTORAGE Restore exact native evidence before all validators.
arguments
    stored (1,1) struct
    mode (1,1) string {mustBeMember(mode,["raw","lossless_path_gains_xor_v1","lossless_path_gains_xor_dedup_v1"])}
end
if mode=="lossless_path_gains_xor_dedup_v1"
    assert(all(isfield(stored,{'Schema','Mode','ArrayPool'})) && ...
        isequal(string(stored.Schema),"sixgr.grant_episode_storage/v1") && ...
        isequal(string(stored.Mode),mode), ...
        'sixgr:calibration:EpisodeStorageSchema','Wrong deduplicated evidence envelope.');
    encoded=sixgr.calibration.decodeEvidenceArrayPool(stored.ArrayPool);
    episode=sixgr.calibration.decodeGrantEpisodeStorage(encoded,"lossless_path_gains_xor_v1");
    return;
end
if mode=="raw"
    assert(string(stored.Schema)=="sixgr.frozen_grant_calibration_episode/v1", ...
        'sixgr:calibration:EpisodeStorageSchema','Raw policy cannot adopt encoded evidence.');
    episode=stored; return;
end
assert(string(stored.Schema)=="sixgr.grant_episode_storage/v1" && ...
    stored.Mode==mode && string(stored.Episode.Schema)=="sixgr.frozen_grant_calibration_episode/v1", ...
    'sixgr:calibration:EpisodeStorageSchema','Storage policy/schema disagrees with the frozen manifest.');
episode=stored.Episode;
for k=1:numel(episode.Captures)
    p=episode.Captures{k}.Propagation.PathGains;
    assert(isstruct(p) && string(p.Schema)=="sixgr.path_gains_xor/v1" && ...
        any(string(p.Class)==["single","double"]) && ...
        any(string(p.Endian)==["L","B"]) && ...
        isrow(p.Size) && numel(p.Size)>=2 && all(isfinite(p.Size)) && ...
        all(p.Size>=0 & p.Size==fix(p.Size)) && ...
        islogical(p.IsReal) && isscalar(p.IsReal), ...
        'sixgr:calibration:EpisodeStorageEncoding','Invalid native path-gain encoding.');
    values=decodePart(p.Real,p);
    if ~p.IsReal
        values=complex(values,decodePart(p.Imaginary,p));
    else
        assert(isempty(p.Imaginary),'sixgr:calibration:EpisodeStorageEncoding', ...
            'Real path gains cannot contain an imaginary payload.');
    end
    episode.Captures{k}.Propagation.PathGains=values;
end
end

function values=decodePart(part,p)
word='uint64'; width=8;
if p.Class=="single", word='uint32'; width=4; end
assert(isa(part.BytePlanes,'uint8') && isequal(size(part.BytePlanes),[prod(p.Size) width]), ...
    'sixgr:calibration:EpisodeStorageEncoding','Encoded bytes do not match native dimensions.');
bytes=reshape(part.BytePlanes.',[],1);
[~,~,endian]=computer;
bits=typecast(bytes,word);
if string(endian)~=p.Endian, bits=swapbytes(bits); end
if ~isempty(bits)
    flat=reshape(bits,p.Size(1),[]);
    % Parallel prefix XOR: integer operations only, no floating-point delta
    % arithmetic, interpolation, quantization or regenerated channel state.
    stride=1;
    while stride<size(flat,1)
        flat(stride+1:end,:)=bitxor(flat(stride+1:end,:),flat(1:end-stride,:));
        stride=2*stride;
    end
    bits=flat(:);
end
originalBytes=typecast(bits,'uint8');
if string(endian)~=p.Endian, originalBytes=typecast(swapbytes(bits),'uint8'); end
assert(string(sixgr.util.sha256Hex(originalBytes))==string(part.DecodedSHA256), ...
    'sixgr:calibration:EpisodeStorageDigest','Restored path-gain bits fail their original digest.');
values=reshape(typecast(bits,char(p.Class)),p.Size);
end
