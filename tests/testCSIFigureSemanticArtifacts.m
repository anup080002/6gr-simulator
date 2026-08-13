function testCSIFigureSemanticArtifacts()
%TESTCSIFIGURESEMANTICARTIFACTS Audit the latest short semantic CSI run.
root=fullfile(fileparts(fileparts(mfilename("fullpath"))),"results","csi_tdoc");
runs=dir(fullfile(root,"ran1_10_5_3_1_figure_fix_short_*")); runs=runs([runs.isdir]);
assert(~isempty(runs),"A completed short CSI figure-fix run is required.");
[~,index]=max([runs.datenum]); folder=fullfile(runs(index).folder,runs(index).name);
F=readtable(fullfile(folder,"manifests","figure_manifest.csv"), ...
    "VariableNamingRule","preserve");
assert(height(F)==20 && numel(unique(string(F.FigureId)))==20);
assert(all(string(F.SemanticAuditStatus)=="PASS"));
assert(all(F.NonBlankCheck & F.DataReplayCheck));
assert(all(F.WidthPx==4000 & F.HeightPx==2375));
assert(all(strlength(string(F.PNGSha256))==64));
assert(all(strlength(string(F.PDFSha256))==64));
assert(all(strlength(string(F.PerceptualHash))==16));
assert(numel(unique(string(F.PNGSha256)))==20);
assert(numel(unique(string(F.PDFSha256)))==20);
[A,passed]=sixgr.csi.auditTDocRun(folder);
assert(passed && all(A.Pass));
P=readtable(fullfile(folder,"csv","lls","pdsch_anchor_trials.csv"), ...
    "VariableNamingRule","preserve");
assert(height(P)==3 && ~any(P.FallbackUsed));
assert(all(string(P.LLRSource)=="nrPDSCHDecode_soft_llr"));
fprintf("testCSIFigureSemanticArtifacts: PASS (%d figures, %d audit checks)\n", ...
    height(F),height(A));
end
