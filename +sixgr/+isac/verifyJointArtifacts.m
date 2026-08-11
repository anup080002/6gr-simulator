function report = verifyJointArtifacts(runFolder)
%VERIFYJOINTARTIFACTS Verify the complete table/PNG/hash contract.

arguments
    runFolder (1,1) string
end
contract = [sixgr.isac.figureContract();sixgr.isac.exampleFigureContract()];
item = strings(0,1); pass = false(0,1); details = strings(0,1);
for i=1:height(contract)
    path=fullfile(runFolder,"figures",contract.Folder(i),contract.FigureStem(i)+".png");
    item(end+1,1)=contract.FigureStem(i)+".png"; %#ok<AGROW>
    pass(end+1,1)=exist(path,"file")==2; %#ok<AGROW>
    if pass(end)
        info=imfinfo(path);
        details(end+1,1)=sprintf("%dx%d",info.Width,info.Height); %#ok<AGROW>
    else
        details(end+1,1)="missing"; %#ok<AGROW>
    end
end
for i=1:17
    files=dir(fullfile(runFolder,"tables",sprintf("Table%02d_*.csv",i)));
    mats=dir(fullfile(runFolder,"tables",sprintf("Table%02d_*.mat",i)));
    item(end+1,1)=sprintf("Table%02d csv+mat",i); %#ok<AGROW>
    pass(end+1,1)=numel(files)==1&&numel(mats)==1; %#ok<AGROW>
    details(end+1,1)=sprintf("csv=%d mat=%d",numel(files),numel(mats)); %#ok<AGROW>
end
svg=dir(fullfile(runFolder,"**","*.svg"));
item(end+1,1)="No SVG outputs"; pass(end+1,1)=isempty(svg); ...
    details(end+1,1)=sprintf("svg=%d",numel(svg));
lineagePath=fullfile(runFolder,"aggregate","figure_lineage.csv");
lineageOk=false;
if exist(lineagePath,"file")==2
    lineage=readtable(lineagePath,"TextType","string");
    lineageOk=height(lineage)==height(contract)&&all(lineage.Status=="pass")&& ...
        all(strlength(lineage.SourceCSV_SHA256)==64)&&all(strlength(lineage.ImageSHA256)==64);
end
item(end+1,1)="Figure SHA-256 lineage"; pass(end+1,1)=lineageOk; ...
    details(end+1,1)=sprintf("expected_rows=%d",height(contract));
report=table(item,pass,details,'VariableNames',{'Item','Pass','Details'});
writetable(report,fullfile(runFolder,"aggregate","artifact_verification.csv"));
if ~all(pass)
    error("sixgr:isac:JointArtifactVerificationFailed", ...
        "Joint ISAC artifact verifier failed %d of %d checks.",nnz(~pass),numel(pass));
end
end
