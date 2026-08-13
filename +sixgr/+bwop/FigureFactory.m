classdef FigureFactory
    %FIGUREFACTORY Source-bound raster/editable/vector BWOP publication.

    methods (Static)
        function row=publish(runFolder,figureID,source,evidenceClass,configHash,options)
            arguments
                runFolder (1,1) string
                figureID (1,1) string
                source table
                evidenceClass (1,1) string
                configHash (1,1) string
                options.Kind (1,1) string = "result"
                options.Render (1,1) string = "line"
                options.XField (1,1) string = ""
                options.YField (1,1) string = ""
                options.GroupField (1,1) string = ""
                options.XTickLabelField (1,1) string = ""
                options.Title (1,1) string = ""
                options.XLabel (1,1) string = ""
                options.YLabel (1,1) string = ""
                options.Caption (1,1) string = ""
                options.ScenarioID (1,1) string = ""
                options.StatisticsQualified (1,1) logical = false
                options.DPI (1,1) double = 300
            end
            if isempty(source)
                error("sixgr:bwop:EmptyFigureSource", ...
                    "Figure %s cannot be published from an empty source table.",figureID);
            end
            evidenceClass=sixgr.bwop.EvidenceClassifier.require(evidenceClass);
            sixgr.bwop.EvidenceClassifier.assertNotProxy(source);
            sourceDir=fullfile(runFolder,"tables","csv");matDir=fullfile(runFolder,"tables","mat");
            if options.Kind=="conceptual"
                figureDir=fullfile(runFolder,"figures","conceptual");
            else
                figureDir=fullfile(runFolder,"figures",localEvidenceFolder(evidenceClass));
            end
            sixgr.util.ensureFolder(sourceDir);sixgr.util.ensureFolder(matDir);sixgr.util.ensureFolder(figureDir);
            csvPath=fullfile(sourceDir,figureID+".csv");matPath=fullfile(matDir,figureID+".mat");
            sixgr.util.csvWriteTable(csvPath,source);sourceTable=source; %#ok<NASGU>
            save(matPath,"sourceTable","-v7");
            fig=figure("Visible","off","Color","w","Position",[100 100 1600 960]);
            cleanup=onCleanup(@()localClose(fig)); %#ok<NASGU>
            localRender(fig,source,options);
            pngPath=fullfile(figureDir,figureID+".png");
            sixgr.visual.exportRasterAtomic(fig,string(pngPath),options.DPI);
            figPath=fullfile(figureDir,figureID+".fig");pdfPath=fullfile(figureDir,figureID+".pdf");
            localSaveEditableAndPDF(fig,figPath,pdfPath);
            close(fig);clear cleanup;
            captionPath=fullfile(figureDir,figureID+"_caption.txt");
            caption=options.Caption;
            if strlength(caption)==0
                caption="["+evidenceClass+"] "+options.Title+" Scenario="+ ...
                    options.ScenarioID+", config="+configHash+".";
            end
            sixgr.util.writeTextFile(captionPath,caption);
            meta=struct("figure_id",figureID,"scenario_ids",options.ScenarioID, ...
                "evidence_class",evidenceClass,"config_hash",configHash, ...
                "source_csv",localRelative(csvPath,runFolder), ...
                "source_mat",localRelative(matPath,runFolder), ...
                "source_csv_sha256",localHash(csvPath),"png",localRelative(pngPath,runFolder), ...
                "png_sha256",localHash(pngPath),"fig",localRelative(figPath,runFolder), ...
                "pdf",localRelative(pdfPath,runFolder),"caption",localRelative(captionPath,runFolder), ...
                "statistics_qualified",options.StatisticsQualified,"status","PASS", ...
                "tdoc_ready",sixgr.bwop.EvidenceClassifier.mayEnterTDocReady( ...
                evidenceClass,"PASS",options.StatisticsQualified));
            metaPath=fullfile(figureDir,figureID+".json");sixgr.util.jsonWrite(metaPath,meta);
            row=table(figureID,options.ScenarioID,options.Kind,evidenceClass,"PASS", ...
                string(localRelative(pngPath,runFolder)),string(localRelative(csvPath,runFolder)), ...
                string(localRelative(matPath,runFolder)),string(localRelative(metaPath,runFolder)), ...
                string(localRelative(captionPath,runFolder)),localHash(pngPath),localHash(csvPath), ...
                logical(meta.tdoc_ready),"", ...
                'VariableNames',{'FigureID','ScenarioID','Kind','EvidenceClass','Status', ...
                'ImagePath','SourceCSV','SourceMAT','MetadataPath','CaptionPath', ...
                'ImageSHA256','SourceSHA256','TDocReady','BlockerReason'});
        end

        function row=block(runFolder,figureID,scenarioID,evidenceClass,reason,configHash)
            evidenceClass=sixgr.bwop.EvidenceClassifier.require(evidenceClass);
            folder=fullfile(runFolder,"reports","blockers");sixgr.util.ensureFolder(folder);
            data=struct("figure_id",figureID,"scenario_id",scenarioID, ...
                "evidence_class",evidenceClass,"status","BLOCKED", ...
                "reason",reason,"config_hash",configHash, ...
                "placeholder_curve_generated",false,"tdoc_ready",false);
            jsonPath=fullfile(folder,figureID+"_blocker.json");sixgr.util.jsonWrite(jsonPath,data);
            mdPath=fullfile(folder,figureID+"_blocker.md");
            sixgr.util.writeTextFile(mdPath,"# "+figureID+" — BLOCKED"+newline+newline+ ...
                "- Scenario: `"+scenarioID+"`"+newline+"- Required evidence: `"+evidenceClass+"`"+newline+ ...
                "- Reason: "+reason+newline+"- No placeholder curve was generated."+newline);
            row=table(figureID,scenarioID,"result",evidenceClass,"BLOCKED","","","", ...
                string(localRelative(jsonPath,runFolder)),string(localRelative(mdPath,runFolder)), ...
                "","",false,reason,'VariableNames',{'FigureID','ScenarioID','Kind', ...
                'EvidenceClass','Status','ImagePath','SourceCSV','SourceMAT','MetadataPath', ...
                'CaptionPath','ImageSHA256','SourceSHA256','TDocReady','BlockerReason'});
        end
    end
end

function localRender(fig,T,opt)
ax=axes(fig);hold(ax,"on");
ink=[.08 .12 .18];set(ax,"Color","w","XColor",ink,"YColor",ink, ...
    "GridColor",[.70 .74 .80],"MinorGridColor",[.82 .84 .88],"FontSize",11);
switch lower(opt.Render)
    case "flow"
        x=double(T.X);y=double(T.Y);plot(ax,x,y,"-","LineWidth",2,"Color",[.1 .35 .65]);
        scatter(ax,x,y,150,[.05 .55 .45],"filled");
        for i=1:height(T),text(ax,x(i),y(i)+.08,string(T.Label(i)), ...
                "HorizontalAlignment","center","Interpreter","none","FontSize",10, ...
                "Color",ink,"FontWeight","bold");end
        axis(ax,"off");xlim(ax,[min(x)-.5 max(x)+.5]);ylim(ax,[min(y)-.3 max(y)+.35]);
    case "region"
        y=1:height(T);
        for i=1:height(T)
            rectangle(ax,"Position",[double(T.StartRB(i)),y(i)-.35,double(T.SizeRB(i)),.7], ...
                "FaceColor",[.2 .6 .82 .45],"EdgeColor",[.05 .25 .45]);
        end
        yticks(ax,y);yticklabels(ax,string(T.Label));xlabel(ax,"CRB / RB index");grid(ax,"on");
    case "bar"
        x=double(T.(opt.XField));y=double(T.(opt.YField));bar(ax,x,y,"FaceColor",[.12 .55 .78]);
        if strlength(opt.XTickLabelField)>0
            xticks(ax,x);xticklabels(ax,string(T.(opt.XTickLabelField)));xtickangle(ax,20);
        end
        xlabel(ax,opt.XLabel);ylabel(ax,opt.YLabel);grid(ax,"on");
    case "scatter"
        x=double(T.(opt.XField));y=double(T.(opt.YField));
        if strlength(opt.GroupField)>0
            groups=string(T.(opt.GroupField));uniqueGroups=unique(groups,"stable");
            for g=uniqueGroups(:).'
                mask=groups==g;scatter(ax,x(mask),y(mask),45,"filled","DisplayName",g);
            end
            lgd=legend(ax,"Location","bestoutside","Interpreter","none");
            set(lgd,"Color","w","TextColor",ink,"EdgeColor",[.65 .68 .72]);
        else
            scatter(ax,x,y,45,[.1 .45 .8],"filled");
        end
        xlabel(ax,opt.XLabel);ylabel(ax,opt.YLabel);grid(ax,"on");
    otherwise
        x=double(T.(opt.XField));y=double(T.(opt.YField));
        if strlength(opt.GroupField)>0
            groups=string(T.(opt.GroupField));uniqueGroups=unique(groups,"stable");
            for g=uniqueGroups(:).'
                mask=groups==g;[sx,order]=sort(x(mask));sy=y(mask);sy=sy(order);
                plot(ax,sx,sy,"-o","LineWidth",1.6,"DisplayName",g);
            end
            lgd=legend(ax,"Location","best","Interpreter","none");
            set(lgd,"Color","w","TextColor",ink,"EdgeColor",[.65 .68 .72]);
        else
            [x,order]=sort(x);y=y(order);plot(ax,x,y,"-o","LineWidth",1.8,"MarkerFaceColor",[.1 .45 .8]);
        end
        xlabel(ax,opt.XLabel);ylabel(ax,opt.YLabel);grid(ax,"on");
end
title(ax,opt.Title,"Interpreter","none","Color",ink,"FontWeight","bold");
xlabelHandle=get(ax,"XLabel");ylabelHandle=get(ax,"YLabel");
set([xlabelHandle ylabelHandle],"Color",ink);
end

function folder=localEvidenceFolder(value)
switch value
    case "ANALYTICAL_EXACT",folder="analytical_screening";
    case "ANALYTICAL_SCREENING",folder="analytical_screening";
    case "SOURCE_REPRODUCTION",folder="source_reproduction";
    case "CALIBRATED_LLS",folder="calibrated_lls";
    case "PROCEDURE_SLS",folder="procedure_sls";
    otherwise,folder="assumption_only";
end
end

function localSaveEditableAndPDF(fig,figPath,pdfPath)
token=string(char(java.util.UUID.randomUUID()));tmpFig=fullfile(tempdir,"bwop-"+token+".fig");tmpPdf=fullfile(tempdir,"bwop-"+token+".pdf");
cleanup=onCleanup(@()localDelete([tmpFig tmpPdf])); %#ok<NASGU>
savefig(fig,tmpFig);print(fig,tmpPdf,"-dpdf","-painters","-bestfit");
copyfile(tmpFig,figPath,"f");copyfile(tmpPdf,pdfPath,"f");
end

function localClose(fig)
if isgraphics(fig),close(fig);end
end

function localDelete(paths)
for path=string(paths(:)).',if isfile(path),delete(path);end,end
end

function hash=localHash(path)
fid=fopen(path,"r");if fid<0,error("sixgr:bwop:HashReadFailed","Cannot read %s.",path);end
clean=onCleanup(@()fclose(fid));bytes=fread(fid,Inf,"*uint8");hash=sixgr.util.sha256Hex(bytes);
end

function out=localRelative(path,root)
path=string(path);root=string(root);prefix=root+filesep;
if startsWith(path,prefix,"IgnoreCase",ispc),out=extractAfter(path,strlength(prefix));else,out=path;end
out=replace(out,"\","/");
end
