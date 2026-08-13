function ok=testBWOPAI10513Artifacts()
%TESTBWOPAI10513ARTIFACTS Run the short full-contract artifact gate.
setup6GRSimToolkit("Verbose",false,"RunToolboxChecks",false);
root=string(tempname);mkdir(root);cleanup=onCleanup(@()localCleanup(root)); %#ok<NASGU>
result=runBWOPAI10513Campaign( ...
    "simulator/configs/bwop_ai10513/master_campaign.yaml", ...
    "OutputRoot",root,"RunID","artifact_unit","Mode","smoke");
assert(result.Passed);
assert(height(result.Figures)==34);
assert(nnz(result.Figures.Kind=="conceptual") == 9);
assert(nnz(result.Figures.Kind=="result") == 25);
assert(all(result.Figures.Status=="PASS"|result.Figures.Status=="BLOCKED"));
assert(isfile(fullfile(result.RunFolder,"metadata","manifest.json")));
assert(isfile(fullfile(result.RunFolder,"metadata","file_inventory.csv")));
assert(isfile(result.Reports.Markdown)&&isfile(result.Reports.HTML));
assert(isempty(dir(fullfile(result.RunFolder,"**","*.svg"))));
manifest=jsondecode(fileread(fullfile(result.RunFolder,"metadata","manifest.json")));
inventory=readtable(fullfile(result.RunFolder,"metadata","file_inventory.csv"), ...
    "TextType","string","VariableNamingRule","preserve");
files=dir(fullfile(result.RunFolder,"**","*"));files=files(~[files.isdir]);
assert(manifest.file_count==numel(files)&&manifest.inventoried_file_count==height(inventory));
assert(numel(files)==height(inventory)+2);
assert(all(~startsWith(inventory.RelativePath,"/")&~contains(inventory.RelativePath,"..")));
png=result.Figures.ImagePath(result.Figures.Status=="PASS");
for i=1:numel(png)
    info=imfinfo(fullfile(result.RunFolder,png(i)));
    assert(info.Width>=3000&&info.Height>=1000&&info.BitDepth>=24);
end
ok=true;
fprintf("testBWOPAI10513Artifacts: PASS (34 figure contracts)\n");
end

function localCleanup(path)
if isfolder(path),rmdir(path,"s");end
end
