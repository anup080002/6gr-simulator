function ok=testLLSBootstrapEvidenceCSV()
% CSV import types must not turn missing CSI into adaptation evidence.
setup6GRSimToolkit('Verbose',false);
logsRoot=fullfile(pwd,'logs');
if ~isfolder(logsRoot), mkdir(logsRoot); end
folder=tempname(logsRoot); mkdir(folder);
air=fullfile(folder,'air_interface','csv'); mkdir(air);
for scope=["dl_pdsch_trials","ul_pusch_trials"]
    original=table((1:5).',[true;true;true;true;false], ...
        [NaN;12;NaN;NaN;NaN],nan(5,1),[NaN;NaN;9;NaN;NaN], ...
        [NaN;NaN;NaN;7;11], ...
        'VariableNames',{'Slot','LinkAdaptationApplied', ...
        'LinkAdaptationAppliedFeedbackSourceSlot','FeedbackSourceSlot', ...
        'CQIFeedbackSourceSlot','AppliedLinkAdaptationResolvedCQI'});
    expected=[false;true;true;true;false];
    for representation=1:4
        t=original;
        for name=string(t.Properties.VariableNames(3:end))
            values=t.(name);
            if representation==2, t.(name)=num2cell(values);
            elseif representation>=3
                tokens=string(values); tokens(isnan(values))="";
                if representation==4, tokens=cellstr(tokens); end
                t.(name)=tokens;
            end
        end
        if representation>=3
            t.LinkAdaptationApplied=["true";"true";"true";"true";"false"];
            if representation==4, t.LinkAdaptationApplied=cellstr(t.LinkAdaptationApplied); end
        end
        before=t;
        fixed=sixgr.truth.canonicalizeLLSLiveSignalChainTable(scope,t);
        assert(isequal(fixed.LinkAdaptationApplied,expected));
        assert(isequaln(fixed(:,[1 3:width(t)]),before(:,[1 3:width(t)])), ...
            'Only the unsupported applied claim may change; preserve source evidence.');
        assert(isequaln(fixed,sixgr.truth.canonicalizeLLSLiveSignalChainTable(scope,fixed)));
    end
    % Exact failure shape: primary trial flags plus entirely blank CSI cells.
    blank=original(1:3,:); blank.LinkAdaptationApplied(:)=false;
    for name=string(blank.Properties.VariableNames(3:end)), blank.(name)=repmat({''},3,1); end
    fixed=sixgr.truth.canonicalizeLLSLiveSignalChainTable(scope,blank);
    assert(~any(fixed.LinkAdaptationApplied) && height(fixed)==3 && width(fixed)==width(blank));
    path=fullfile(air,scope+".csv");
    sixgr.util.csvWriteTable(path,blank,'PreserveSchema',true);
    sixgr.truth.sanitizeLLSArtifactCSVs(folder);
    once=fileread(path);
    sixgr.truth.sanitizeLLSArtifactCSVs(folder);
    assert(strcmp(once,fileread(path)),'Repeated primary CSV sanitization must be byte-idempotent.');
    imported=sixgr.util.csvReadTable(path);
    assert(height(imported)==3 && width(imported)==width(blank) && ...
        all(sixgr.truth.numericMeasurementColumn(imported.LinkAdaptationApplied)==0));
    for name=string(original.Properties.VariableNames(3:end))
        bad=blank; bad.(name){2}='invented_feedback';
        reject(@()sixgr.truth.canonicalizeLLSLiveSignalChainTable(scope,bad), ...
            'sixgr:truth:InvalidNumericMeasurementColumn');
    end
    bad=blank; bad.LinkAdaptationApplied=[0;NaN;1];
    reject(@()sixgr.truth.canonicalizeLLSLiveSignalChainTable(scope,bad), ...
        'sixgr:truth:InvalidLinkAdaptationAppliedEvidence');
    bad=blank; bad.LinkAdaptationApplied=[0;.5;1];
    reject(@()sixgr.truth.canonicalizeLLSLiveSignalChainTable(scope,bad), ...
        'sixgr:truth:InvalidLinkAdaptationAppliedEvidence');
end
fprintf('BOOTSTRAP_CSV_EVIDENCE_PASS scopes=DL,UL representations=4 missing_CSI_not_promoted=1 folder=%s\n',folder);
ok=true;
end
function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s.',id,cause.identifier); return;
end
error('test:MissingRejection','Expected %s.',id);
end
