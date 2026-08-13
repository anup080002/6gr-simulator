function ok=testPDCCHTDoc10521Artifacts(runRoot)
%TESTPDCCHTDOC10521ARTIFACTS Audit a completed bounded campaign.
setup6GRSimToolkit("Verbose",false);
if nargin<1||strlength(string(runRoot))==0
    runRoot=fullfile("results","pdcch_10_5_2_1","pdcch_10521_bounded_20260814_03");
end
audit=readtable(fullfile(runRoot,"tables","audit_checks.csv"),"TextType","string");
figures=readtable(fullfile(runRoot,"tables","figure_manifest.csv"),"TextType","string");
manifest=readtable(fullfile(runRoot,"tables","artifact_manifest.csv"),"TextType","string");
assert(all(audit.Pass));assert(sum(startsWith(figures.FigureFile,"tdoc_fig"))==15);
assert(all(figures.WidthPx>=1200&figures.HeightPx>=700));assert(height(manifest)>50);
for i=1:height(manifest)
    item=string(manifest.RelativePath(i));
    if java.io.File(char(item)).isAbsolute(),path=item;else,path=fullfile(runRoot,item);end
    assert(isfile(path));assert(localHash(path)==string(manifest.SHA256(i)));
end
ok=true;fprintf("PDCCH TDoc 10.5.2.1 artifact checks: PASS (%d files, %d PNG)\n",height(manifest),height(figures));
end

function value=localHash(path)
fid=fopen(path,"r");clean=onCleanup(@()fclose(fid)); %#ok<NASGU>
value=string(sixgr.util.sha256Hex(fread(fid,Inf,"*uint8")));
end
