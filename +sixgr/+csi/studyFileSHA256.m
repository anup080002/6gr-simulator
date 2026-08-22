function value=studyFileSHA256(path)
%FILESHA256 Binary-safe SHA-256 for artifact lineage.
fid=fopen(path,"rb");
if fid<0, error("sixgr:csi:MissingArtifact","Cannot open artifact %s.",path); end
cleanup=onCleanup(@() fclose(fid)); %#ok<NASGU>
bytes=fread(fid,Inf,"*uint8"); value=string(sixgr.util.sha256Hex(bytes));
end
