function report=diagnoseN40RetainedSRSEVM(originalFolder,diagnosticFolder)
% Original persisted pairs only; no waveform, RF or checkpoint execution.
assert(~isfolder(diagnosticFolder),'test:DiagnosticExists','Preserve previous diagnostics.');
mkdir(diagnosticFolder);
source=fullfile(originalFolder,'air_interface','csv','srs_trials.csv');
T=sixgr.util.csvReadTable(source,'TextType','string');
paths=string(source);
for k=1:height(T)
    if strlength(string(T.ControlEVMSamplesMATFile(k)))>0
        paths(end+1,1)=fullfile(originalFolder,string(T.ControlEVMSamplesMATFile(k))); %#ok<AGROW>
    end
end
paths=unique(paths,'stable'); before=strings(size(paths));
for k=1:numel(paths), before(k)=sixgr.util.sha256File(paths(k)); end
report=struct('Ok',false,'Scope',"original_retained_SRS_pairs_export_only_no_RF_no_checkpoint", ...
    'PrimaryStudyEligible',false,'OriginalFolder',string(originalFolder), ...
    'DiagnosticFolder',string(diagnosticFolder),'OriginalsUnchanged',false);
try
    replay=T; count=0;
    for k=1:height(T)
        pairs=sixgr.report.readControlEVMPairs(T(k,:),source);
        for p=reshape(pairs,1,[])
            assert(string(p.ReferenceSource)=="same_executed_isolated_emitted_SRS_received_pilot_grid"&& ...
                isfield(p,'IsolatedComponentProved')&&islogical(p.IsolatedComponentProved)&& ...
                isscalar(p.IsolatedComponentProved)&&p.IsolatedComponentProved, ...
                'test:OriginalSRSProofMissing','Never invent an original isolation marker.');
        end
        row=sixgr.report.retainControlEVMPairs(diagnosticFolder,T(k,:),pairs);
        for field=string(row.Properties.VariableNames)
            replay.(field)(k,:)=row.(field);
        end
        count=count+sum(arrayfun(@(p)numel(p.SampleIndex),pairs));
    end
    outputTrial=fullfile(diagnosticFolder,'air_interface','csv','srs_trials.csv');
    sixgr.util.csvWriteTable(outputTrial,replay,'PreserveSchema',true);
    output=sixgr.report.exportControlEVMSamples(outputTrial,replay);
    P=sixgr.util.csvReadTable(output,'TextType','string');
    assert(height(P)==count&&all(P.IsolatedComponentProved)&& ...
        all(strlength(string(P.OriginalPairRecordSHA256))==64));
    report.PairCount=count; report.TrialCount=height(T); report.OutputCSV=string(output);
    report.OutputSHA256=sixgr.util.sha256File(output);
    report.Ok=true;
catch cause
    report.ErrorIdentifier=string(cause.identifier); report.Error=string(cause.message);
end
after=strings(size(paths));
for k=1:numel(paths), after(k)=sixgr.util.sha256File(paths(k)); end
report.OriginalsUnchanged=isequal(before,after); report.Ok=report.Ok&&report.OriginalsUnchanged;
report.OriginalFiles=table2struct(table(paths,before,after,'VariableNames',{'Path','BeforeSHA256','AfterSHA256'}));
report.Path=string(fullfile(diagnosticFolder,'receipt.json'));
fid=fopen(report.Path,'w'); assert(fid>=0); cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
fprintf(fid,'%s',jsonencode(sixgr.util.jsonSafeValue(report),'PrettyPrint',true));
end
