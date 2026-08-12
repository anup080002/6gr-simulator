function testCSITDocArtifactReplay()
%TESTCSITDOCARTIFACTREPLAY Validate an existing bounded real-waveform run.
root=fullfile(fileparts(fileparts(mfilename("fullpath"))),"results","csi_tdoc");
runs=dir(fullfile(root,"ran1_10_5_3_1_bounded_qualification_*")); runs=runs([runs.isdir]);
assert(~isempty(runs),"A bounded CSI TDoc qualification run is required before artifact replay test.");
[~,i]=max([runs.datenum]); folder=fullfile(runs(i).folder,runs(i).name);
[audit,passed]=sixgr.csi.auditTDocRun(folder);
assert(passed && all(audit.Pass));
F=readtable(fullfile(folder,"manifests","figure_manifest.csv"), ...
    "Delimiter",",","VariableNamingRule","preserve");
beforeHashes=string(F.PNGSha256);
sixgr.csi.runTDocSuite("figure_replay","RunFolder",string(folder));
F=readtable(fullfile(folder,"manifests","figure_manifest.csv"), ...
    "Delimiter",",","VariableNamingRule","preserve");
assert(isequal(beforeHashes,string(F.PNGSha256)), ...
    "CSV-identical raster replay must preserve every PNG SHA-256 hash.");
assert(height(F)==20 && all(F.DataReplayCheck) && all(F.NonBlankCheck));
f5=F(F.FigureId=="FIG-2.10-1",:); f15=F(F.FigureId=="FIG-2.10-2",:);
assert(f5.FilterExpression=="PhaseDegPerChip==5");
assert(f15.FilterExpression=="PhaseDegPerChip==15");
assert(string(f5.PNGSha256)~=string(f15.PNGSha256));
[imageAudit,imagePassed]=sixgr.csi.frameImageAudit(folder);
assert(imagePassed && height(imageAudit)==20 && all(imageAudit.HashUnique));
fprintf("testCSITDocArtifactReplay: PASS (%d checks, %d figures)\n",height(audit),height(F));
end
