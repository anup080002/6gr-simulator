function report=verify1083Artifacts(runFolder)
%VERIFY1083ARTIFACTS Verify the exact WFig17-WFig36 evidence contract.
arguments
    runFolder (1,1) string
end
contract=sixgr.isac.validationFigureContract();
formats=[".mat",".csv",".fig",".png",".pdf"];
rows=cell(height(contract)*numel(formats),1); index=0;
for figureIndex=1:height(contract)
    stem=contract.FigureStem(figureIndex);
    for formatIndex=1:numel(formats)
        extension=formats(formatIndex);
        path=string(fullfile(runFolder,"figures",stem+extension));
        exists=exist(path,"file")==2; bytes=0; hash=""; width=NaN; heightPx=NaN;
        details="missing";
        if exists
            info=dir(path); bytes=info.bytes; hash=localHash(path); details="present";
            if extension==".png"
                imageInfo=imfinfo(path); width=imageInfo.Width; heightPx=imageInfo.Height;
                details=sprintf("%dx%d",width,heightPx);
            elseif extension==".csv"
                source=readtable(path,"TextType","string");
                details=sprintf("rows=%d columns=%d",size(source,1),size(source,2));
            end
        end
        index=index+1;
        rows{index}=table(stem,extension,path,exists,bytes,hash,width,heightPx,details, ...
            'VariableNames',{'FigureStem','Format','Path','Pass','Bytes','SHA256', ...
            'ImageWidthPixels','ImageHeightPixels','Details'});
    end
end
report=vertcat(rows{1:index});
aggregate=fullfile(runFolder,"aggregate");
if exist(aggregate,"dir")~=7, mkdir(aggregate); end
writetable(report,fullfile(aggregate,"validation_figure_lineage.csv"));
if ~all(report.Pass)
    missing=report.Path(~report.Pass);
    error("sixgr:isac:Missing1083Artifact", ...
        "10.8.3 artifact verification failed: %d required files are missing. First: %s", ...
        numel(missing),missing(1));
end
end

function hash=localHash(path)
fid=fopen(path,"rb");
if fid<0, error("sixgr:isac:ArtifactReadFailed","Cannot read %s.",path); end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
hash=string(sixgr.util.sha256Hex(fread(fid,Inf,"*uint8")));
end
