classdef RunAuditor
    %RUNAUDITOR Fail-closed semantic and artifact audit before finalization.

    methods (Static)
        function audit = run(runFolder,campaign,figures,scenarioStatus,tables)
            arguments
                runFolder (1,1) string
                campaign (1,1) struct
                figures table
                scenarioStatus table
                tables (1,1) struct
            end
            imageAudit=localImageAudit(runFolder);
            csvAudit=localCSVAudit(runFolder);
            checks=localSemanticChecks(runFolder,campaign,figures,scenarioStatus,tables, ...
                imageAudit,csvAudit);
            sixgr.util.csvWriteTable(fullfile(runFolder,"metadata", ...
                "png_image_audit.csv"),imageAudit);
            sixgr.util.csvWriteTable(fullfile(runFolder,"metadata", ...
                "csv_schema_audit.csv"),csvAudit);
            sixgr.util.csvWriteTable(fullfile(runFolder,"metadata", ...
                "final_semantic_audit.csv"),checks);
            if any(~checks.Pass)
                error("sixgr:bwop:FinalSemanticAuditFailed", ...
                    "BWOP final audit failed: %s.",strjoin(checks.Check(~checks.Pass),", "));
            end
            audit=struct("Checks",checks,"Images",imageAudit,"CSVs",csvAudit);
        end
    end
end

function T=localImageAudit(root)
files=dir(fullfile(root,"**","*.png"));
n=numel(files);path=strings(n,1);bytes=zeros(n,1);width=zeros(n,1);height=zeros(n,1);
bitDepth=zeros(n,1);hash=strings(n,1);readable=false(n,1);
for ii=1:n
    absolute=fullfile(files(ii).folder,files(ii).name);
    path(ii)=localRelative(absolute,root);bytes(ii)=files(ii).bytes;
    try
        info=imfinfo(absolute);width(ii)=info.Width;height(ii)=info.Height;
        bitDepth(ii)=info.BitDepth;hash(ii)=localHash(absolute);readable(ii)=true;
    catch
        readable(ii)=false;
    end
end
T=table(path,bytes,width,height,bitDepth,hash,readable, ...
    'VariableNames',{'RelativePath','Bytes','Width','Height','BitDepth','SHA256','Readable'});
end

function T=localCSVAudit(root)
files=dir(fullfile(root,"**","*.csv"));
n=numel(files);path=strings(n,1);bytes=zeros(n,1);rows=zeros(n,1);columns=zeros(n,1);
uniqueHeaders=false(n,1);readable=false(n,1);hash=strings(n,1);
for ii=1:n
    absolute=fullfile(files(ii).folder,files(ii).name);
    path(ii)=localRelative(absolute,root);bytes(ii)=files(ii).bytes;hash(ii)=localHash(absolute);
    try
        opt=detectImportOptions(absolute,"FileType","text");
        tableValue=readtable(absolute,opt);
        rows(ii)=height(tableValue);columns(ii)=width(tableValue);
        uniqueHeaders(ii)=numel(unique(string(tableValue.Properties.VariableNames)))==columns(ii);
        readable(ii)=true;
    catch
        readable(ii)=false;
    end
end
T=table(path,bytes,rows,columns,uniqueHeaders,readable,hash, ...
    'VariableNames',{'RelativePath','Bytes','Rows','Columns','UniqueHeaders','Readable','SHA256'});
end

function T=localSemanticChecks(runFolder,campaign,figures,status,t,imageAudit,csvAudit)
checks=strings(0,1);pass=false(0,1);detail=strings(0,1);
calibrated=~isempty(t.LLSSummary);
scenarioOk=height(status)==34&&all(ismember(status.Status,["PASS","WARN","BLOCKED"]));
if calibrated,scenarioOk=scenarioOk&&~any(status.Status=="BLOCKED");end
add("scenario_contract",scenarioOk, ...
    "rows="+height(status)+", blocked="+nnz(status.Status=="BLOCKED"));
figureOk=height(figures)==34&&all(ismember(figures.Status,["PASS","BLOCKED"]));
if calibrated
    figureOk=figureOk&&nnz(figures.Status=="PASS")==33&& ...
        nnz(figures.Status=="BLOCKED")==1&& ...
        all(figures.FigureID(figures.Status=="BLOCKED")=="R04");
end
add("figure_contract",figureOk, ...
    "pass="+nnz(figures.Status=="PASS")+", blocked="+strjoin(figures.FigureID(figures.Status=="BLOCKED"),"|"));
if calibrated
    add("waveform_quality_gate",all(t.LLSQuality.Pass), ...
        "passed="+nnz(t.LLSQuality.Pass)+"/"+height(t.LLSQuality));
    add("waveform_trial_count",height(t.LLSTrials)==36, ...
        "observed="+height(t.LLSTrials)+", configured=36");
    add("waveform_summary_count",height(t.LLSSummary)==18, ...
        "observed="+height(t.LLSSummary)+", configured=18");
    snrError=max(abs(double(t.LLSTrials.MeasuredSNRdB)-double(t.LLSTrials.TargetSNRdB)));
    add("measured_snr_calibration",snrError<=double( ...
        campaign.Config.calibrated_waveform.maximum_measured_snr_error_db), ...
        "max_abs_error_db="+snrError);
    blerClosure=max(abs(double(t.LLSSummary.BLER)- ...
        double(t.LLSSummary.NumBlockErrors)./double(t.LLSSummary.NumTB)));
    add("bler_arithmetic",blerClosure<=eps(1)*8,"max_abs_residual="+blerClosure);
    ciOk=all(t.LLSSummary.BLER>=t.LLSSummary.BLERLowerCI& ...
        t.LLSSummary.BLER<=t.LLSSummary.BLERUpperCI);
    add("confidence_interval_contains_estimate",ciOk,"summary_rows="+height(t.LLSSummary));
    offsetExpected=10*log10(32/216);
    offsetObserved=unique(t.LLSSummary.SNROffsetDb(t.LLSSummary.CaseID=="cal_total_216"));
    add("fixed_total_power_offset",isscalar(offsetObserved)&& ...
        abs(offsetObserved-offsetExpected)<1e-6, ...
        "observed_db="+string(offsetObserved)+", expected_db="+offsetExpected);
    jointExpected=1-double(t.JointSIB1.PDCCHSuccessProbability).* ...
        double(t.JointSIB1.ConditionalPDSCHSuccessProbability);
    jointResidual=max(abs(jointExpected-double(t.JointSIB1.JointAcquisitionBLER)));
    add("joint_sib1_arithmetic",jointResidual<=eps(1)*8,"max_abs_residual="+jointResidual);
    add("waveform_truth_labels",all(t.LLSSummary.ExecutionBackend=="waveform_truth")&& ...
        all(t.LLSSummary.ApproximationMode=="none")&& ...
        all(t.LLSSummary.EvidenceClass=="CALIBRATED_LLS"), ...
        "summary_rows="+height(t.LLSSummary));
else
    add("waveform_campaign_selection",true,"calibrated waveform execution not selected in this mode");
end
add("png_files_readable",~isempty(imageAudit)&&all(imageAudit.Readable)& ...
    all(imageAudit.Bytes>0)&all(imageAudit.Width>=1200)& ...
    all(imageAudit.Height>=720)&all(imageAudit.BitDepth>=24), ...
    "count="+height(imageAudit)+", minimum="+min(imageAudit.Width)+"x"+min(imageAudit.Height));
add("png_hashes_unique",numel(unique(imageAudit.SHA256))==height(imageAudit), ...
    "unique="+numel(unique(imageAudit.SHA256))+"/"+height(imageAudit));
add("csv_files_readable",~isempty(csvAudit)&&all(csvAudit.Readable)& ...
    all(csvAudit.Bytes>0)&all(csvAudit.Columns>0)&all(csvAudit.UniqueHeaders), ...
    "count="+height(csvAudit)+", empty_rows="+nnz(csvAudit.Rows==0));
add("no_svg",isempty(dir(fullfile(runFolder,"**","*.svg"))), ...
    "raster PNG plus editable FIG/vector PDF only");
T=table(checks,pass,detail,'VariableNames',{'Check','Pass','Detail'});

    function add(name,value,message)
        checks(end+1,1)=string(name);pass(end+1,1)=logical(value);detail(end+1,1)=string(message);
    end
end

function out=localRelative(path,root)
canonicalRoot=string(char(java.io.File(char(root)).getCanonicalPath()));
canonicalPath=string(char(java.io.File(char(path)).getCanonicalPath()));
prefix=canonicalRoot+filesep;
if ~startsWith(canonicalPath,prefix)
    error("sixgr:bwop:AuditPathEscape","Audit path escaped the run root: %s.",canonicalPath);
end
out=replace(extractAfter(canonicalPath,strlength(prefix)),"\","/");
end

function hash=localHash(path)
fid=fopen(path,"r");
if fid<0,error("sixgr:bwop:AuditReadFailed","Cannot read %s.",path);end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
hash=sixgr.util.sha256Hex(fread(fid,Inf,"*uint8"));
end
