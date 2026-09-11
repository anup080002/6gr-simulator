classdef PUCCHArtifactExporter
    %PUCCHARTIFACTEXPORTER Hash-bound CSV and CSV-sourced figure writer.

    methods (Static)
        function writeTable(outputDir,fileName,value)
            if ~istable(value) || height(value)==0
                error("sixgr:phy:pucch:EmptyEvidence", ...
                    "Evidence table %s has no executed rows.",fileName);
            end
            if ismember("Status",string(value.Properties.VariableNames)) && ...
                    any(upper(string(value.Status))~="PASS")
                failed = find(upper(string(value.Status))~="PASS");
                labels = string(failed(1:min(8,numel(failed))));
                if ismember("CaseID",string(value.Properties.VariableNames))
                    labels = string(value.CaseID(failed(1:min(8,numel(failed)))));
                end
                error("sixgr:phy:pucch:FailedEvidence", ...
                    "Evidence table %s contains %d non-PASS rows: %s.", ...
                    fileName,numel(failed),join(labels,", "));
            end
            if ~isfolder(outputDir), mkdir(outputDir); end
            path = fullfile(outputDir,fileName);
            writetable(value,path);
            reopened = readtable(path,"VariableNamingRule","preserve");
            if height(reopened)~=height(value)
                error("sixgr:phy:pucch:ArtifactIntegrity", ...
                    "CSV %s changed row count after write.",fileName);
            end
        end

        function audit = writeSemanticFigure(outputDir,contractRow)
            % Never infer semantics from column order or fabricate coverage.
            if string(contractRow.ImageFile)~="pucch_power_control_convergence.png" || ...
                    string(contractRow.SourceCSV)~="pucch_power_control.csv"
                error("sixgr:phy:pucch:UnverifiedFigureBinding", ...
                    "No verified source/axis binding exists for %s.",contractRow.ImageFile);
            end
            sources = split(string(contractRow.SourceCSV),"|");
            path = fullfile(outputDir,sources(1));
            if exist(path,"file")~=2
                error("sixgr:phy:pucch:MissingEvidenceSource", ...
                    "Figure source is absent: %s.",path);
            end
            data = sixgr.util.csvReadTable(path,"TextType","string");
            labels = ["RequestedPowerdBm","AppliedPowerdBm","MeasuredWaveformPowerdBm"];
            required = [labels,"CaseID","EvidenceScope","MeasurementReferenceDomain", ...
                "MeasurementReferencePlane","WaveformSHA256"];
            if ~all(ismember(required,string(data.Properties.VariableNames)))
                error("sixgr:phy:pucch:IncompleteFigureSemantics", ...
                    "Power figure requires named measured power and provenance columns.");
            end
            y = zeros(height(data),numel(labels));
            for index = 1:numel(labels)
                y(:,index) = localNumeric(data.(labels(index)));
            end
            if height(data)<2 || any(~isfinite(y),"all") || ...
                    numel(unique(string(data.CaseID)))~=height(data) || ...
                    any(ismissing(string(data.CaseID)) | strlength(string(data.CaseID))==0) || ...
                    any(string(data.EvidenceScope)~="component_power_control_calibration_not_main_run") || ...
                    any(string(data.MeasurementReferenceDomain)~="specified_active_ofdm_symbols_excluding_cp") || ...
                    any(string(data.MeasurementReferencePlane)~="post_ifft_cp_pre_node_rf") || ...
                    any(cellfun(@isempty,regexp(cellstr(string(data.WaveformSHA256)),"^[0-9a-fA-F]{64}$","once"))) || ...
                    double(contractRow.MinSeriesCount)>numel(labels) || ...
                    double(contractRow.MinFinitePointCount)>numel(y) || ...
                    double(contractRow.MinAxesCount)>1
                error("sixgr:phy:pucch:IncompleteFigureSemantics", ...
                    "Insufficient actual power samples or incompatible evidence provenance.");
            end
            actualTitle = "PUCCH power control — independent vector waveforms";
            actualXLabel = "Independent power-vector case";
            actualYLabel = "Power (dBm)";
            if ~contains(actualTitle,string(contractRow.ExpectedTitleToken)) || ...
                    string(contractRow.ExpectedXLabel)~=actualXLabel || ...
                    string(contractRow.ExpectedYLabel)~=actualYLabel
                error("sixgr:phy:pucch:UnverifiedFigureBinding", ...
                    "Contract must describe the actual independent-case power axes.");
            end
            sourceHash = sixgr.phy.pucch.PUCCHArtifactExporter.sourceSHA256(outputDir,sources);
            widthPixels = max(1200,double(contractRow.MinWidth));
            heightPixels = max(760,double(contractRow.MinHeight));
            fig = figure("Visible","off","Color","white","Units","pixels", ...
                "Position",[50 50 widthPixels heightPixels]);
            cleanup = onCleanup(@() close(fig));
            ax = axes(fig,"Color","white","XColor","black","YColor","black", ...
                "GridColor",[.65 .65 .65]);
            hold(ax,"on"); colors = lines(numel(labels));
            x = (1:height(data)).';
            for index = 1:numel(labels)
                % Independent cases are points, not a convergence trajectory.
                plot(ax,x,y(:,index),"LineStyle","none","Marker",localMarker(index), ...
                    "LineWidth",1.2,"Color",colors(index,:), ...
                    "DisplayName",labels(index));
            end
            tickRows = unique(round(linspace(1,height(data),min(12,height(data)))));
            xticks(ax,tickRows); xticklabels(ax,string(data.CaseID(tickRows)));
            xtickangle(ax,35);
            grid(ax,"on"); box(ax,"on");
            title(ax,actualTitle,"Interpreter","none","Color","black");
            xlabel(ax,actualXLabel,"Interpreter","none","Color","black");
            ylabel(ax,actualYLabel,"Interpreter","none","Color","black");
            legend(ax,"Location","best","Interpreter","none", ...
                "Color","white","TextColor","black","EdgeColor",[.5 .5 .5]);
            path = fullfile(outputDir,string(contractRow.ImageFile));
            fig.PaperUnits="inches";
            fig.PaperPosition=[0 0 widthPixels/100 heightPixels/100];
            fig.PaperSize=[widthPixels/100 heightPixels/100];
            print(fig,path,"-dpng","-r100");
            imageInfo = imfinfo(path);
            audit = struct( ...
                "ImageFile",string(contractRow.ImageFile), ...
                "SourceCSV",string(contractRow.SourceCSV), ...
                "SourceCSV_SHA256",sourceHash, ...
                "PNG_SHA256",sixgr.phy.pucch.PUCCHArtifactExporter.fileSHA256(path), ...
                "Width",imageInfo.Width,"Height",imageInfo.Height, ...
                "AxesCount",numel(findobj(fig,"Type","axes")), ...
                "SeriesCount",numel(findobj(ax,"Type","line")), ...
                "FinitePointCount",numel(y), ...
                "SourceRowCount",height(data), ...
                "BoundYColumns",join(labels,"|"), ...
                "BoundXColumn","CaseID (CSV row order)", ...
                "EvidenceScope","component_power_control_calibration_not_main_run", ...
                "ActualTitle",actualTitle, ...
                "ActualXLabel",actualXLabel, ...
                "ActualYLabel",actualYLabel, ...
                "Status","PASS");
        end

        function value = sourceSHA256(outputDir,names)
            names = sort(string(names(:)));
            bytes = zeros(0,1,"uint8");
            for index = 1:numel(names)
                nameBytes = uint8(unicode2native(char(names(index)),"UTF-8"));
                hashBytes = uint8(char( ...
                    sixgr.phy.pucch.PUCCHArtifactExporter.fileSHA256( ...
                    fullfile(outputDir,names(index)))));
                bytes = [bytes;nameBytes(:);hashBytes(:)]; %#ok<AGROW>
            end
            value = string(sixgr.rrc.asn1.asn1SHA256Hex(bytes));
        end

        function value = fileSHA256(path)
            fid = fopen(path,"rb");
            if fid<0
                error("sixgr:phy:pucch:MissingEvidenceSource", ...
                    "Cannot open %s.",path);
            end
            cleanup = onCleanup(@() fclose(fid));
            value = string(sixgr.rrc.asn1.asn1SHA256Hex( ...
                fread(fid,inf,"*uint8")));
        end
    end
end

function value = localNumeric(input)
if isnumeric(input) || islogical(input)
    value = double(input(:));
else
    value = str2double(string(input(:)));
end
end

function value = localMarker(index)
markers = ["o","+","x"];
value = markers(index);
end
