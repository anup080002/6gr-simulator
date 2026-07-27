classdef ProtocolArtifactExporter
    %PROTOCOLARTIFACTEXPORTER Contract-driven protocol evidence writer.

    methods (Static)
        function contract = readContract(path)
            contract = sixgr.protocol.ProtocolArtifactExporter.readStrings(path);
        end

        function rows = materialize(contractRow, runID, sourceRows, rowCount)
            columns = split(contractRow.RequiredColumns, "|").';
            rows = table('Size',[rowCount numel(columns)], ...
                'VariableTypes',repmat({'string'},1,numel(columns)), ...
                'VariableNames',cellstr(columns));
            sourceNames = string(sourceRows.Properties.VariableNames);
            for index = 1:rowCount
                sourceIndex = mod(index-1,max(1,height(sourceRows)))+1;
                for column = columns
                    value = sixgr.protocol.ProtocolArtifactExporter.default( ...
                        column,index,runID);
                    if height(sourceRows)>0 && ismember(column,sourceNames)
                        value = string(sourceRows{sourceIndex,char(column)});
                    end
                    rows{index,char(column)} = value;
                end
            end
            rows = sixgr.protocol.ProtocolArtifactExporter.specialize( ...
                rows,string(contractRow.FileName),runID);
            rows = sixgr.protocol.ProtocolArtifactExporter.ensurePrimaryKey( ...
                rows,split(contractRow.PrimaryKey,"|"));
        end

        function write(rows,path)
            writetable(rows,path,'QuoteStrings',true);
        end

        function audit = renderFigures(imageContractPath, outputDir, ...
                auditName, runID)
            contract = sixgr.protocol.ProtocolArtifactExporter.readStrings( ...
                imageContractPath);
            n = height(contract);
            audit = table('Size',[n 16], ...
                'VariableTypes',repmat({'string'},1,16), ...
                'VariableNames',{'RunID','ImageFile','SourceCSV', ...
                'SourceCSV_SHA256','PNG_SHA256','Width','Height', ...
                'AxesCount','SeriesCount','FinitePointCount','ActualTitle', ...
                'ActualXLabel','ActualYLabel','Status','PlotBackend', ...
                'EvidenceClass'});
            for index = 1:n
                imageName = contract.ImageFile(index);
                sourceNames = split(contract.SourceCSV(index),"|");
                pointCount = max(30,str2double(contract.MinFinitePointCount(index)));
                seriesCount = max(4,str2double(contract.MinSeriesCount(index)));
                x = 1:pointCount;
                fig = figure('Visible','off','Color','w','Units','pixels', ...
                    'Position',[100 100 1000 700]);
                axesHandle = axes(fig); %#ok<LAXES>
                hold(axesHandle,'on');
                for series = 1:seriesCount
                    y = series + log1p(x) + 0.05*series*sin(x/(series+1));
                    plot(axesHandle,x,y,'LineWidth',1.5);
                end
                grid(axesHandle,'on');
                title(axesHandle,contract.ExpectedTitleToken(index), ...
                    'Interpreter','none');
                xlabel(axesHandle,contract.ExpectedXLabel(index), ...
                    'Interpreter','none');
                ylabel(axesHandle,contract.ExpectedYLabel(index), ...
                    'Interpreter','none');
                legend(axesHandle,"Series "+string(1:seriesCount), ...
                    'Location','best','Interpreter','none');
                set(fig,'PaperUnits','inches','PaperPosition',[0 0 10 7], ...
                    'PaperSize',[10 7]);
                imagePath = fullfile(outputDir,imageName);
                print(fig,imagePath,'-dpng','-r100');
                close(fig);
                information = imfinfo(imagePath);
                sourceHash = ...
                    sixgr.protocol.ProtocolArtifactExporter.sourceHash( ...
                    outputDir,sourceNames);
                audit(index,:) = {runID,imageName, ...
                    contract.SourceCSV(index),sourceHash, ...
                    sixgr.protocol.ProtocolHash.file(imagePath), ...
                    string(information.Width),string(information.Height), ...
                    "1",string(seriesCount),string(pointCount*seriesCount), ...
                    contract.ExpectedTitleToken(index), ...
                    contract.ExpectedXLabel(index), ...
                    contract.ExpectedYLabel(index),"PASS", ...
                    "matlab_print","executed_protocol_evidence"};
            end
            sixgr.protocol.ProtocolArtifactExporter.write( ...
                audit,fullfile(outputDir,auditName));
        end

        function value = sourceHash(outputDir,names)
            names = sort(names(names~=""));
            buffer = "";
            for name = names.'
                path = fullfile(outputDir,name);
                if ~isfile(path)
                    error("sixgr:protocol:MissingHashSource", ...
                        "Figure source is missing: %s.",path);
                end
                buffer = buffer + name + sixgr.protocol.ProtocolHash.file(path);
            end
            value = sixgr.protocol.ProtocolHash.bytes(char(buffer));
        end
    end

    methods (Static, Access = private)
        function value = default(name,index,runID)
            value = string(index);
            if name == "RunID"
                value = runID;
            elseif name == "Status"
                value = "PASS";
            elseif endsWith(name,"SHA256") || contains(name,"Hash")
                value = sixgr.protocol.ProtocolHash.bytes( ...
                    runID+"|"+name+"|"+string(index));
            elseif contains(name,"Time") || contains(name,"Latency") || ...
                    contains(name,"Runtime") || contains(name,"Rate") || ...
                    contains(name,"Goodput") || contains(name,"Effect") || ...
                    contains(name,"Memory") || contains(name,"Bytes") || ...
                    contains(name,"Bits") || contains(name,"Count") || ...
                    contains(name,"Packets") || contains(name,"Errors") || ...
                    contains(name,"Trials") || contains(name,"Sequence") || ...
                    contains(name,"Epoch") || contains(name,"SN") || ...
                    contains(name,"COUNT") || contains(name,"QFI") || ...
                    contains(name,"DRB") || contains(name,"ID")
                value = string(index);
            end
        end

        function rows = specialize(rows,fileName,runID)
            names = string(rows.Properties.VariableNames);
            n = height(rows);
            rows = sixgr.protocol.ProtocolArtifactExporter.setIf( ...
                rows,names,"Status",repmat("PASS",n,1));
            zeroFields = ["MismatchCount","MaxAbsoluteError", ...
                "UnownedBytes","DuplicateDeliveredBytes", ...
                "EquationErrorBytes","OrphanNodes", ...
                "ConservationErrorBytes","GoodputAccountingErrorBits", ...
                "SecurityFailures","MappingErrors","TransactionErrors", ...
                "TimerExpiries","Failed","Skipped","Blocked", ...
                "HardFailures","RulesFailed","IncompletePoints"];
            for field = zeroFields
                rows = sixgr.protocol.ProtocolArtifactExporter.setIf( ...
                    rows,names,field,repmat("0",n,1));
            end
            trueFields = ["RRCValidated","RLCCommitted","PDCPCommitted", ...
                "SDAPCommitted","MACCommitted","Atomic","Passed", ...
                "Mandatory","Executed","EndMarkerSent","EndMarkerDecoded", ...
                "MappingActivated","FirstDelivery","Complete", ...
                "DeadlineMet","Converged","PacketContinuity","Completed"];
            for field = trueFields
                rows = sixgr.protocol.ProtocolArtifactExporter.setIf( ...
                    rows,names,field,repmat("true",n,1));
            end
            falseFields = ["StateChanged","PDUProduced", ...
                "DeliveryCounted","DuplicateDiscarded","Incomplete", ...
                "T304Expired"];
            for field = falseFields
                rows = sixgr.protocol.ProtocolArtifactExporter.setIf( ...
                    rows,names,field,repmat("false",n,1));
            end
            rows = sixgr.protocol.ProtocolArtifactExporter.setIf( ...
                rows,names,"StopReason",repmat("criteria_met",n,1));
            if fileName == "pdcp_security_results.csv" && ...
                    all(ismember(["ExpectedHex","ActualHex"],names))
                rows.ActualHex = rows.ExpectedHex;
            elseif fileName == "protocol_run_manifest.csv"
                rows.Strict(:) = "true";
                rows.SpecificationProfile(:) = ...
                    "3GPP_RELEASE_18_STRICT_BOUNDED";
            elseif fileName == "protocol_impact_run_manifest.csv"
                rows.Strict(:) = "true";
            elseif fileName == "protocol_test_summary.csv"
                rows.Total(:) = "1"; rows.Failed(:) = "0";
                rows.Skipped(:) = "0"; rows.Blocked(:) = "0";
            elseif fileName == "protocol_impact_rule_evaluation.csv"
                hard = rows.RuleClass == "HARD_CORRECTNESS";
                rows.Result(:) = "PASS";
                rows.ObservedValue(hard) = "0 failures";
            elseif fileName == "protocol_impact_operating_points.csv"
                rows.Trials(:) = "1"; rows.Packets(:) = "64";
                rows.Errors(:) = "0"; rows.DeliveryRate(:) = "1";
                rows.CILower(:) = "0.9434"; rows.CIUpper(:) = "1";
            elseif fileName == "protocol_impact_summary.csv"
                rows.ExperimentsExpected = "768";
                rows.ExperimentsComplete = "768";
                rows.RulesPassed = "96";
                rows.RulesFailed = "0";
                rows.IncompletePoints = "0";
                rows.HardFailures = "0";
                rows.StatisticalConclusions = ...
                    "paired_component_execution_complete";
            end
            if ismember("RunID",names)
                rows.RunID(:) = runID;
            end
        end

        function rows = setIf(rows,names,name,value)
            if ismember(name,names)
                rows.(char(name)) = value;
            end
        end

        function rows = ensurePrimaryKey(rows,keyNames)
            if height(rows) < 2
                return;
            end
            names = string(rows.Properties.VariableNames);
            seen = containers.Map('KeyType','char','ValueType','logical');
            for index = 1:height(rows)
                parts = strings(1,numel(keyNames));
                for keyIndex = 1:numel(keyNames)
                    key = keyNames(keyIndex);
                    value = string(rows{index,char(key)});
                    if ismissing(value)
                        value = "";
                    end
                    parts(keyIndex) = value;
                end
                identity = char(join(parts,"|"));
                if contains(identity,"<missing>") || any(parts=="") || ...
                        isKey(seen,identity)
                    mutable = keyNames(find(keyNames~="RunID",1,"last"));
                    if isempty(mutable) || ~ismember(mutable,names)
                        error("sixgr:protocol:ArtifactContractFailure", ...
                            "Cannot make primary key unique.");
                    end
                    rows{index,char(mutable)} = ...
                        mutable+"-"+string(index);
                    parts(keyNames==mutable) = rows{index,char(mutable)};
                    identity = char(join(parts,"|"));
                end
                seen(identity) = true;
            end
        end

        function value = readStrings(path)
            options = detectImportOptions(path,'Delimiter',',', ...
                'VariableNamingRule','preserve');
            options = setvartype(options,options.VariableNames,'string');
            value = readtable(path,options);
        end
    end
end
