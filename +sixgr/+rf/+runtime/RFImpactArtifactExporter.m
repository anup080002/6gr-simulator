classdef RFImpactArtifactExporter
%RFIMPACTARTIFACTEXPORTER Publish original component operands and explicit axes.
    methods(Static)
        function summary=export(evidence,vectorRoot,outputDir)
            arguments
                evidence (1,1) struct
                vectorRoot (1,1) string
                outputDir (1,1) string
            end
            localValidateOperands(evidence);
            contract=localReadContract(fullfile(vectorRoot,'desired_rf_impact_csv_contract.csv'),"csv");
            imageContract=localReadContract(fullfile(vectorRoot,'desired_rf_impact_image_contract.csv'),"image");
            assert(all(ismember(imageContract.SourceCSV,contract.FileName)), ...
                'RF:ImpactContractSchema','Every image must name an explicitly requested CSV source.');
            if ~isfolder(outputDir), mkdir(outputDir); end
            for k=1:height(contract)
                assert(~isfile(fullfile(outputDir,contract.FileName(k))), ...
                    'RF:ImpactArtifactExists','Use a new output directory; never overwrite earlier evidence.');
            end
            archiveName="rf_impact_observation_operands.mat"; archivePath=fullfile(outputDir,archiveName);
            assert(~isfile(archivePath),'RF:ImpactArtifactExists','Do not overwrite original operands.');
            sixgr.util.matSave(archivePath,struct('Contract',"rf_impact_original_kernel_operands/v1", ...
                'Observations',{evidence.ObservationOperands},'Metadata',evidence.Metadata),'UseArtifactStore',false);
            archiveHash=localFileHash(archivePath);
            rowCounts=struct(); hashes=struct();
            for k=1:height(contract)
                name=contract.FileName(k);
                if name=="rf_impact_image_semantic_audit.csv", continue; end
                field=erase(name,'.csv');
                assert(isfield(evidence,field)&&istable(evidence.(field)), ...
                    'RF:ImpactContract','A requested table must exist, including honest typed-empty tables.');
                value=evidence.(field);
                if ismember('ExperimentID',value.Properties.VariableNames)&& ...
                        ismember('MeasurementReceiptSHA256',value.Properties.VariableNames)
                    value.SourceOperandsMAT=repmat(archiveName,height(value),1);
                    value.SourceOperandsMATSHA256=repmat(archiveHash,height(value),1);
                end
                localValidateTable(value,contract(k,:),evidence);
                path=fullfile(outputDir,name);
                sixgr.util.csvWriteTable(path,value,'PreserveSchema',true,'RoundTripNumericText',true);
                rowCounts.(field)=height(value); hashes.(field)=localFileHash(path);
            end
            audit=localImages(evidence,outputDir,imageContract);
            auditPath=fullfile(outputDir,'rf_impact_image_semantic_audit.csv');
            sixgr.util.csvWriteTable(auditPath,audit,'PreserveSchema',true,'RoundTripNumericText',true);
            rowCounts.rf_impact_image_semantic_audit=height(audit);
            hashes.rf_impact_image_semantic_audit=localFileHash(auditPath);
            rules=evidence.rf_impact_rule_evaluation;
            mandatory=rules.Mandatory;
            criteriaPassed=any(mandatory)&&all(rules.Evaluated(mandatory)&rules.Passed(mandatory)==1);
            summary=struct('Passed',criteriaPassed,'PublicationPassed',true, ...
                'AcceptanceCriteriaPassed',criteriaPassed,'OutputDir',outputDir,'RowCounts',rowCounts, ...
                'CSVHashes',hashes,'MissingTables',strings(0,1),'ContractFailures',strings(0,1), ...
                'UnavailableMandatoryRules',rules.RuleID(mandatory&~rules.Evaluated), ...
                'ImageAudit',audit,'OperandArchive',archiveName,'OperandArchiveSHA256',archiveHash, ...
                'ClaimRestriction',"COMPONENT_OBSERVATIONS_NOT_RECEIVER_LINK_OR_DEVICE_QUALIFICATION");
        end
    end
end

function localValidateOperands(e)
assert(isfield(e,'ObservationOperands')&&iscell(e.ObservationOperands), ...
    'RF:ImpactOperandClosure','Original operand receipts are mandatory.');
raw=e.rf_impact_raw_trials;
assert(height(raw)==numel(e.ObservationOperands)&&numel(unique(raw.ExperimentID))==height(raw)&& ...
    e.Metadata.RequestedExecutionCount==height(raw),'RF:ImpactOperandClosure','Exactly one row per original execution.');
for k=1:height(raw)
    r=raw(k,:); o=e.ObservationOperands{k};
    assert(o.ExperimentID==r.ExperimentID&&o.MeasurementReceiptJSON==r.MeasurementReceiptJSON&& ...
        o.MeasurementReceiptSHA256==r.MeasurementReceiptSHA256&&localSHA(r.MeasurementReceiptJSON)==r.MeasurementReceiptSHA256, ...
        'RF:ImpactOperandClosure','Original source identity/token/hash changed.');
    values=removevars(r,{'MeasurementReceiptJSON','MeasurementReceiptSHA256'});
    assert(string(jsonencode(sixgr.util.jsonSafeValue(table2struct(values))))==r.MeasurementReceiptJSON, ...
        'RF:ImpactOperandClosure','The exact row must match its original measurement receipt.');
    assert(string(jsonencode(sixgr.util.jsonSafeValue(o.Configuration)))==r.KernelConfigJSON&& ...
        localSHA(r.KernelConfigJSON)==r.KernelConfigSHA256,'RF:ImpactOperandClosure','Original executed configuration changed.');
    for field=string(fieldnames(o.Receipt)).'
        assert(ismember(field,r.Properties.VariableNames)&&isequaln(o.Receipt.(field),r.(field)), ...
            'RF:ImpactOperandClosure','Original returned receipt field %s changed.',field);
    end
    assert(all(isfinite(o.Input),'all')&&all(isfinite(o.Output),'all')&& ...
        isnan(r.BLER)&&~r.BLERAvailable,'RF:ImpactOperandClosure','No decoder was run by this component driver.');
    if isempty(o.Output)
        assert(r.SampleCount==0&&strlength(r.InputSHA256)==0&&strlength(r.OutputSHA256)==0, ...
            'RF:ImpactOperandClosure','Analytical results are not waveform observations.');
        if r.Kernel=="NoisePowerLedger.cascade"
            metric="ModeledNoiseFigure_dB"; expected=o.ReturnedEvidence.CascadeNF_dB;
        elseif r.Kernel=="DeclaredAdditivePowerBudgetEquation"
            cfg=o.Configuration;
            requested=cfg.P0_dBm+10*log10(2^cfg.Mu*cfg.MRB)+cfg.Alpha*cfg.AssumedPathloss_dB+cfg.DeltaTF_dB+cfg.AssumedTPCOffset_dB;
            expected=min(cfg.PCMAX_dBm,requested); metric="AppliedPowerTarget_dBm";
            assert(isequaln(requested,r.RequestedPower_dBm)&& ...
                isequaln(expected,o.ReturnedEvidence.ClampedPowerTarget_dBm)&& ...
                ~o.ReturnedEvidence.ReceiverMeasurementUsed&&~o.ReturnedEvidence.DecodedControlUsed&& ...
                ~o.ReturnedEvidence.WaveformPowerApplied, ...
                'RF:ImpactOperandClosure','An assumed-input equation is not measured RS or applied power.');
        else
            error('RF:ImpactOperandClosure','Unsupported analytical metric owner.');
        end
        localMetricValue(r,metric,expected);
        continue;
    end
    x=double(o.Input); y=double(o.Output);
    assert(isequal(size(x),size(y))&&numel(x)==r.SampleCount&& ...
        string(sixgr.phy.waveform.WaveformHash.runtimeArray(o.Input))==r.InputSHA256&& ...
        string(sixgr.phy.waveform.WaveformHash.runtimeArray(o.Output))==r.OutputSHA256, ...
        'RF:ImpactOperandClosure','Retained original waveform bytes differ.');
    reference=sum(abs(x(:)).^2); errorEnergy=sum(abs(y(:)-x(:)).^2);
    assert(isequaln(reference,r.ReferenceEnergy)&&isequaln(errorEnergy,r.ErrorEnergy)&& ...
        isequaln(100*sqrt(errorEnergy/reference),r.WaveformRelativeRMSError_pct)&& ...
        isequaln(sum(abs(y(:)).^2)/numel(y),r.OutputMeanPower), ...
        'RF:ImpactOperandClosure','The source waveform operands must reproduce reported measurements.');
    metric="WaveformRelativeRMSError_pct"; expected=100*sqrt(errorEnergy/reference);
    if r.FamilyID=="F50"
        n=numel(y); f=(-n/2:n/2-1)'*r.SampleRate_Hz/n;
        spectrum=abs(fftshift(fft(y(:),n))).^2/n^2;
        assigned=sum(spectrum(f>=r.AssignedBandLow_Hz&f<=r.AssignedBandHigh_Hz));
        adjacent=sum(spectrum(abs(f)>=r.AdjacentAbsBandLow_Hz&abs(f)<=r.AdjacentAbsBandHigh_Hz));
        assert(isequaln(assigned,r.AssignedBandPower)&&isequaln(adjacent,r.AdjacentBandPower), ...
            'RF:ImpactOperandClosure','The named spectral-band metric must retain its actual powers.');
        metric="MeasuredBandPowerRatio_dB"; expected=10*log10(assigned/adjacent);
    end
    localMetricValue(r,metric,expected);
    if r.ADCResultAvailable
        q=o.ReturnedEvidence;
        assert(isequaln(q.Output,o.Output)&&q.Bits==r.Bits&&q.FullScale==r.FullScale&& ...
            isequaln(q.ClippingRatio,r.ClippingRatio)&&isequaln(q.ErrorVariance,r.ADCErrorVariance)&& ...
            q.Bits==o.Configuration.Bits&&q.FullScale==o.Configuration.FullScale, ...
            'RF:ImpactOperandClosure','ADC metrics must be the actual returned result/configuration.');
    end
end
end

function localMetricValue(row,metric,value)
assert(row.Metric==metric&&isequaln(row.Value,value)&&isequaln(row.(metric),value)&& ...
    row.MetricAvailable==~isnan(value),'RF:ImpactOperandClosure', ...
    'Pair effects must consume the exact named operand-backed value, not a copied unrelated scalar.');
end

function localValidateTable(value,contract,e)
required=split(contract.RequiredColumns,';');
assert(all(ismember(required,string(value.Properties.VariableNames))), ...
    'RF:ImpactContract','Missing required columns in %s.',contract.FileName);
raw=e.rf_impact_raw_trials;
switch contract.CountPolicy
    case "executions", expected=height(raw);
    case "pairs", expected=numel(unique(raw.PairID));
    case "families", expected=numel(unique(raw.FamilyID));
    case "rules", expected=height(e.rf_impact_rule_evaluation);
    case "availability", expected=height(e.rf_impact_metric_availability);
    case "empty_unexecuted", expected=0;
    case "category"
        families=split(contract.SourceFamilies,';'); source=raw(ismember(raw.FamilyID,families),:);
        expected=height(source);
        assert(isequal(value.ExperimentID,source.ExperimentID), ...
            'RF:ImpactContract','Category source identities/order must survive exactly.');
        original=value(:,raw.Properties.VariableNames);
        assert(isequaln(original,source),'RF:ImpactContract','Category values cannot be manufactured from generic metrics.');
    otherwise, error('RF:ImpactContract','Unknown exact-count policy.');
end
assert(height(value)==expected,'RF:ImpactContract','No padding, dropped executions or fabricated row-count gate.');
if ismember('MeasurementReceiptSHA256',value.Properties.VariableNames)
    assert(numel(unique(value.ExperimentID))==height(value),'RF:ImpactContract','Duplicate primary observations.');
end
end

function audit=localImages(e,outputDir,contract)
rows=cell(height(contract),1);
for k=1:height(contract)
    c=contract(k,:); sourcePath=fullfile(outputDir,c.SourceCSV); field=erase(c.SourceCSV,'.csv');
    assert(isfield(e,field)&&istable(e.(field)),'RF:ImpactPlotContract','Unknown declared source table.');
    source=e.(field); names=string(source.Properties.VariableNames);
    count=height(source); available=false(count,1); finite=false(count,1);
    status="unavailable_declared_metric_not_executed"; points=table(); seriesCount=0;
    imageHash=""; pointsHash=""; pointsFile=""; width=NaN; heightPixels=NaN;
    if all(ismember([c.XColumn,c.YColumn,c.AvailabilityColumn],names))
        av=source.(c.AvailabilityColumn);
        assert(islogical(av)||isnumeric(av),'RF:ImpactPlotContract','Availability must be explicit boolean/numeric.');
        available=isfinite(double(av))&double(av)==1;
        x=source.(c.XColumn); y=source.(c.YColumn);
        assert(isnumeric(x)&&isnumeric(y),'RF:ImpactPlotContract','Axes must name actual numeric source columns.');
        finite=isfinite(x)&isfinite(y);
        selected=available&finite; points=source(selected,:);
        if any(selected)
            points.PlotX=x(selected); points.PlotY=y(selected);
            groupNames=split(c.SeriesColumns,';');
            assert(all(ismember(groupNames,names)),'RF:ImpactPlotContract','Missing explicit series identity.');
            keys=strings(height(points),1);
            for j=1:height(points), keys(j)=string(jsonencode(table2struct(points(j,cellstr(groupNames))))); end
            points.PlotSeriesIdentityJSON=keys; groups=unique(keys,'stable'); seriesCount=numel(groups);
            assert(~ismissing(c.ExpectedTitle)&&strlength(c.ExpectedTitle)>0,'RF:ImpactPlotContract','Missing plot scope.');
            pointsFile=erase(c.ImageFile,'.png')+"_points.csv"; pointsPath=fullfile(outputDir,pointsFile);
            sixgr.util.csvWriteTable(pointsPath,points,'PreserveSchema',true,'RoundTripNumericText',true);
            pointsHash=localFileHash(pointsPath);
            fig=figure('Visible','off','Color','w','Position',[100 100 1150 760]);
            cleanup=onCleanup(@()close(fig)); ax=axes(fig); hold(ax,'on');
            for g=1:numel(groups)
                sel=keys==groups(g); h=scatter(ax,points.PlotX(sel),points.PlotY(sel),24,'filled','DisplayName',groups(g));
                assert(isequaln(double(h.XData(:)),double(points.PlotX(sel)))&& ...
                    isequaln(double(h.YData(:)),double(points.PlotY(sel))), ...
                    'RF:ImpactPlotContract','The rendered axes must contain the exact declared source points.');
            end
            grid(ax,'on'); title(ax,c.ExpectedTitle,'Interpreter','none');
            xlabel(ax,c.ExpectedXLabel,'Interpreter','none'); ylabel(ax,c.ExpectedYLabel,'Interpreter','none');
            legend(ax,'show','Interpreter','none','Location','eastoutside');
            imagePath=fullfile(outputDir,c.ImageFile); exportgraphics(fig,imagePath,'Resolution',120);
            info=imfinfo(imagePath); imageHash=localFileHash(imagePath); width=double(info.Width); heightPixels=double(info.Height);
            status="rendered_exact_original_finite_points"; clear cleanup
        elseif any(available)
            status="unavailable_no_finite_points_undefined_or_infinite_value_preserved_in_source";
        end
    end
    rows{k}=table(c.ImageFile,c.SourceCSV,localFileHash(sourcePath),imageHash,width,heightPixels, ...
        c.ExpectedTitle,c.ExpectedXLabel,c.ExpectedYLabel,c.XColumn,c.YColumn,c.SeriesColumns, ...
        count,nnz(available),nnz(available&finite),nnz(available&~finite),seriesCount, ...
        pointsFile,pointsHash,status, ...
        'VariableNames',{'ImageFile','SourceCSV','SourceCSVSHA256','PNGSHA256','Width','Height','Title','XLabel','YLabel', ...
        'XColumn','YColumn','SeriesColumns','SourceRowCount','AvailableRowCount','PlottedRowCount', ...
        'UndefinedOrInfiniteRowCount','SeriesCount','PointsCSV','PointsCSVSHA256','Status'});
end
audit=vertcat(rows{:});
end

function contract=localReadContract(path,kind)
% Contract CSVs have a declared comma/header/data boundary. Inference from
% short files must never interpret semicolon-separated list VALUES as the
% column delimiter, nor skip a textual prefix in favor of numerical rows.
if kind=="csv"
    expected=["FileName","CountPolicy","SourceFamilies","RequiredColumns"];
    key="FileName"; optional="SourceFamilies";
else
    expected=["ImageFile","ExpectedTitle","ExpectedXLabel","ExpectedYLabel", ...
        "SourceCSV","XColumn","YColumn","AvailabilityColumn","SeriesColumns"];
    key="ImageFile"; optional=strings(0,1);
end
fid=fopen(path,'r','n','UTF-8');
assert(fid>=0,'RF:ImpactContractSchema','Cannot open original contract %s.',path);
cleanup=onCleanup(@()fclose(fid));
first=fgetl(fid); clear cleanup
assert(ischar(first),'RF:ImpactContractSchema','A contract needs its original header.');
if ~isempty(first)&&double(first(1))==65279, first=first(2:end); end
header=split(string(first),',');
for k=1:numel(header)
    name=header(k);
    if startsWith(name,'"')&&endsWith(name,'"')&&strlength(name)>=2
        if strlength(name)==2, name="";
        else, name=extractBetween(name,2,strlength(name)-1); end
    end
    header(k)=name;
end
assert(isequal(header(:),expected(:))&&numel(unique(header))==numel(header), ...
    'RF:ImpactContractSchema','Original %s contract headers must match the exact declared schema.',kind);
try
    options=detectImportOptions(path,'FileType','text','Delimiter',',', ...
        'NumHeaderLines',0,'VariableNamingRule','preserve');
    options.VariableNamesLine=1; options.DataLines=[2 Inf];
    assert(isequal(string(options.VariableNames(:)),expected(:)), ...
        'RF:ImpactContractSchema','Original header cardinality or names changed during parsing.');
    options=setvartype(options,options.VariableNames,'string');
    options=setvaropts(options,options.VariableNames,'WhitespaceRule','preserve','EmptyFieldRule','missing');
    options.ExtraColumnsRule='error'; options.ImportErrorRule='error';
    contract=readtable(path,options);
catch cause
    wrapped=MException('RF:ImpactContractSchema','Cannot parse exact comma contract %s.',path);
    throw(addCause(wrapped,cause));
end
assert(width(contract)==numel(expected)&&height(contract)>0&& ...
    isequal(string(contract.Properties.VariableNames(:)),expected(:)), ...
    'RF:ImpactContractSchema','Preserve the exact header and every requested contract row.');
required=setdiff(expected,optional,'stable');
for name=required
    value=contract.(name);
    assert(isstring(value)&&all(~ismissing(value)&strlength(strtrim(value))>0), ...
        'RF:ImpactContractSchema','A contract row has a missing required %s field.',name);
end
assert(numel(unique(contract.(key)))==height(contract), ...
    'RF:ImpactContractSchema','Duplicate artifact names are not distinct requested populations.');
if kind=="csv"
    assert(all(ismember(contract.CountPolicy,["executions","pairs","families","category", ...
        "rules","availability","empty_unexecuted","images"])), ...
        'RF:ImpactContractSchema','Unknown exact-count policy.');
    contract.SourceFamilies(ismissing(contract.SourceFamilies))=""; % Explicitly optional metadata only.
    lists="RequiredColumns";
    assert(all(strlength(contract.SourceFamilies(contract.CountPolicy=="category"))>0), ...
        'RF:ImpactContractSchema','A category requires its exact source family list.');
    paths="FileName";
else
    lists="SeriesColumns"; paths=["ImageFile","SourceCSV"];
end
for name=lists
    for k=1:height(contract)
        values=split(contract.(name)(k),';');
        assert(all(strlength(values)>0)&&numel(unique(values))==numel(values)&& ...
            all(cellfun(@isvarname,cellstr(values))), ...
            'RF:ImpactContractSchema','Explicit column lists must be nonempty unique source field names.');
    end
end
for name=paths
    extension='csv'; if name=="ImageFile", extension='png'; end
    for value=contract.(name).'
        assert(~isempty(regexp(char(value),['^[A-Za-z0-9_]+\.' extension '$'],'once')), ...
            'RF:ImpactContractSchema','Contract artifacts must be simple relative filenames.');
    end
end
end

function hash=localFileHash(path)
hash=string(sixgr.util.sha256File(path));
end
function hash=localSHA(token)
hash=string(sixgr.util.sha256Hex(uint8(unicode2native(char(token),'UTF-8'))));
end
