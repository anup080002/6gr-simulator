function verifyEpisodeFile(file)
sidecar=string(file)+".sha256.json";
assert(isfile(sidecar),'sixgr:calibration:EpisodeCommit','Episode lacks a committed checksum; do not reuse it.');
s=jsondecode(fileread(sidecar));
assert(strcmpi(s.SHA256,sixgr.csi.studyFileSHA256(file)), ...
    'sixgr:calibration:EpisodeDigest','Retained physical episode was modified.');
end
