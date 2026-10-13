function stored=encodeGrantEpisodeStorage(episode,mode)
%ENCODEGRANTEPISODESTORAGE Lossless on-disk coding, never channel resampling.
% MAT compression operates on byte planes of XOR differences of successive
% native samples. Every original floating-point bit remains recoverable.
% All other waveform/decoder evidence is retained without modification.
arguments
    episode (1,1) struct
    mode (1,1) string {mustBeMember(mode,["raw","lossless_path_gains_xor_v1","lossless_path_gains_xor_dedup_v1"])}
end
assert(string(episode.Schema)=="sixgr.frozen_grant_calibration_episode/v1", ...
    'sixgr:calibration:EpisodeStorageSchema','Require an original waveform episode.');
stored=episode;
if mode=="raw", return; end
if mode=="lossless_path_gains_xor_dedup_v1"
    encoded=sixgr.calibration.encodeGrantEpisodeStorage(episode,"lossless_path_gains_xor_v1");
    stored=struct('Schema',"sixgr.grant_episode_storage/v1",'Mode',mode, ...
        'ArrayPool',sixgr.calibration.encodeEvidenceArrayPool(encoded));
    return;
end
for k=1:numel(stored.Captures)
    gains=stored.Captures{k}.Propagation.PathGains;
    assert((isa(gains,'double') || isa(gains,'single')) && ~issparse(gains), ...
        'sixgr:calibration:EpisodeStorageType','Retain native single/double path gains.');
    [~,~,endian]=computer;
    encoded=struct('Schema',"sixgr.path_gains_xor/v1",'Class',string(class(gains)), ...
        'Size',size(gains),'IsReal',isreal(gains),'Endian',string(endian), ...
        'Real',encodePart(real(gains)),'Imaginary',[]);
    if ~isreal(gains), encoded.Imaginary=encodePart(imag(gains)); end
    stored.Captures{k}.Propagation.PathGains=encoded;
end
stored=struct('Schema',"sixgr.grant_episode_storage/v1",'Mode',mode,'Episode',stored);
end

function p=encodePart(values)
bytes=typecast(values(:),'uint8');
digest=sixgr.util.sha256Hex(bytes);
word='uint64'; width=8;
if isa(values,'single'), word='uint32'; width=4; end
bits=reshape(typecast(bytes,word),size(values));
if ~isempty(bits)
    flat=reshape(bits,size(values,1),[]);
    flat(2:end,:)=bitxor(flat(2:end,:),flat(1:end-1,:));
    bytes=typecast(flat(:),'uint8');
end
% Transpose to keep each significance byte contiguous in the compressed MAT.
planes=reshape(bytes,width,[]).';
p=struct('BytePlanes',planes,'DecodedSHA256',digest);
end
