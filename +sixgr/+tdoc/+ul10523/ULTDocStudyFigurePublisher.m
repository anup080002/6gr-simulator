classdef ULTDocStudyFigurePublisher
    %FIGUREPUBLISHER Regenerate TDoc conceptual/analytical PNGs from CSV.

    methods (Static)
        function manifest = publish(runFolder, contract, deterministic, context)
            rows = contract(startsWith(string(contract.FigureId),"TFIG-"),:);
            manifestRows = repmat(localManifestRow(),height(rows),1);
            sourceRows = repmat(localSourceRow(),height(rows),1);
            sourceRoot = fullfile(runFolder,"tables","figure_sources");
            figureRoot = fullfile(runFolder,"figures","tdoc");
            if ~isfolder(sourceRoot), mkdir(sourceRoot); end
            if ~isfolder(figureRoot), mkdir(figureRoot); end

            for idx = 1:height(rows)
                figureId = string(rows.FigureId(idx));
                key = replace(figureId,"-","_");
                if ~isfield(deterministic.Sources,key)
                    error("sixgr:tdoc:ul10523:MissingFigureSource", ...
                        "No deterministic source is defined for %s.", figureId);
                end
                source = deterministic.Sources.(key);
                sourceNames = strip(split(string(rows.SourceCsv(idx)),";"));
                sourcePaths = strings(numel(sourceNames),1);
                sourceHashes = strings(numel(sourceNames),1);
                for sourceIdx = 1:numel(sourceNames)
                    sourcePath = fullfile(sourceRoot,sourceNames(sourceIdx));
                    if sourceIdx == 1
                        sourceTable = source;
                    else
                        nodeLabels = string(source.Label);
                        sourceTable = table(nodeLabels(1:end-1),nodeLabels(2:end), ...
                            (1:numel(nodeLabels)-1).', ...
                            'VariableNames',{'FromNode','ToNode','Sequence'});
                    end
                    sixgr.tdoc.ul10523.ULTDocStudyResultWriter.write(sourcePath,sourceTable,context);
                    sourcePaths(sourceIdx) = replace(string(fullfile("tables","figure_sources",sourceNames(sourceIdx))),"\","/");
                    sourceHashes(sourceIdx) = sixgr.csi.studyFileSHA256(sourcePath);
                end

                pngRel = string(rows.PNGPath(idx));
                pngPath = fullfile(runFolder,replace(pngRel,"/",filesep));
                localDraw(source,string(rows.EvidenceClass(idx)),string(rows.Title(idx)),pngPath);
                info = imfinfo(pngPath); pixels = double(imread(pngPath));
                nonBlank = std(pixels,0,"all") > 0;
                pass = info.Width >= 1200 && info.Height >= 675 && nonBlank;
                manifestRows(idx)=struct("FigureId",figureId, ...
                    "TDocFigureNumber",double(rows.TDocFigureNumber(idx)), ...
                    "Title",string(rows.Title(idx)), ...
                    "EvidenceClass",string(rows.EvidenceClass(idx)), ...
                    "CampaignIds",string(rows.CampaignIds(idx)), ...
                    "SourceCsvRelativePaths",strjoin(sourcePaths,";"), ...
                    "SourceSHA256",strjoin(sourceHashes,";"), ...
                    "PNGPath",pngRel,"VectorPath","", ...
                    "PNG_SHA256",sixgr.csi.studyFileSHA256(pngPath), ...
                    "WidthPx",double(info.Width),"HeightPx",double(info.Height), ...
                    "NonBlank",nonBlank,"TDocReady",false, ...
                    "Status",localStatus(pass), ...
                    "Notes","Raster-only by user instruction; controlling DOCX unavailable, so exact visual equivalence is not claimed.");
                sourceRows(idx)=struct("FigureId",figureId, ...
                    "SourceCsvRelativePaths",strjoin(sourcePaths,";"), ...
                    "SourceSHA256",strjoin(sourceHashes,";"), ...
                    "EvidenceClass",string(rows.EvidenceClass(idx)), ...
                    "DerivationAuthority",localAuthority(figureId), ...
                    "Status",localStatus(pass));
            end
            manifest=struct2table(manifestRows,"AsArray",true);
            sixgr.tdoc.ul10523.ULTDocStudyResultWriter.write(fullfile(runFolder,"manifests", ...
                "figure_manifest.csv"),manifest,context);
            sixgr.tdoc.ul10523.ULTDocStudyResultWriter.write(fullfile(runFolder,"manifests", ...
                "tdoc_figure_source_manifest.csv"), ...
                struct2table(sourceRows,"AsArray",true),context);
        end
    end
end

function localDraw(source,evidence,titleText,path)
fig=figure("Visible","off","Color","w","Position",[50 50 1280 720]);
cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
if evidence=="CONCEPTUAL_DIAGRAM"
    ax=axes(fig,"Position",[0.04 0.08 0.92 0.78]); axis(ax,[0 1 0 1]); axis(ax,"off"); hold(ax,"on");
    n=height(source); x=linspace(0.12,0.88,n);
    for k=1:n
        rectangle(ax,"Position",[x(k)-0.09 0.40 0.18 0.16], ...
            "Curvature",0.12,"FaceColor",localColor(k,n),"EdgeColor",[0.05 0.20 0.27],"LineWidth",1.5);
        text(ax,x(k),0.48,string(source.Label(k)),"HorizontalAlignment","center", ...
            "VerticalAlignment","middle","FontSize",11,"FontWeight","bold", ...
            "Interpreter","none");
        if k<n
            quiver(ax,x(k)+0.095,0.48,x(k+1)-x(k)-0.19,0,0, ...
                "Color",[0.15 0.42 0.55],"LineWidth",2,"MaxHeadSize",0.8);
        end
    end
    text(ax,0.5,0.27,"Conceptual relationship — no measured performance claim", ...
        "HorizontalAlignment","center","Color",[0.35 0.40 0.43],"FontSize",11);
else
    ax=axes(fig,"Position",[0.11 0.14 0.82 0.70]);
    vars=string(source.Properties.VariableNames);
    numeric=false(1,width(source));
    for k=1:width(source),numeric(k)=isnumeric(source.(vars(k)));end
    use=find(numeric);
    if numel(use)<2,error("sixgr:tdoc:ul10523:BadAnalyticalSource","Analytical figure source needs two numeric columns.");end
    plot(ax,double(source.(vars(use(1)))),double(source.(vars(use(2)))),"-o", ...
        "LineWidth",2,"MarkerSize",6,"Color",[0.02 0.50 0.43],"MarkerFaceColor",[0.20 0.72 0.63]);
    grid(ax,"on"); box(ax,"on"); xlabel(ax,replace(vars(use(1)),"_"," ")); ylabel(ax,replace(vars(use(2)),"_"," "));
    subtitle(ax,"Evidence class: "+evidence+" — not calibrated link performance","Interpreter","none");
end
sgtitle(fig,titleText,"Interpreter","none","FontSize",15,"FontWeight","bold");
exportgraphics(fig,path,"Resolution",150,"BackgroundColor","white");
end

function c=localColor(k,n)
t=(k-1)/max(n-1,1); c=(1-t)*[0.82 0.96 0.93]+t*[0.70 0.84 0.96];
end
function v=localStatus(tf),if tf,v="PASS";else,v="FAIL";end,end
function v=localAuthority(id)
if any(id==["TFIG-05","TFIG-06"]),v="declared_quick_sanity_equation";
elseif any(id==["TFIG-09","TFIG-12","TFIG-19"]),v="exact_analytical_identity";
else,v="csv_defined_conceptual_topology";end
end
function r=localManifestRow()
r=struct("FigureId","","TDocFigureNumber",NaN,"Title","", ...
    "EvidenceClass","","CampaignIds","","SourceCsvRelativePaths","", ...
    "SourceSHA256","","PNGPath","","VectorPath","","PNG_SHA256","", ...
    "WidthPx",0,"HeightPx",0,"NonBlank",false,"TDocReady",false, ...
    "Status","FAIL","Notes","");
end
function r=localSourceRow()
r=struct("FigureId","","SourceCsvRelativePaths","","SourceSHA256","", ...
    "EvidenceClass","","DerivationAuthority","","Status","FAIL");
end
