function ok=testPUCCHReceiverDisposition(outputRoot)
% Reuse real prior receiver decisions for a projection-only regression.
% This is not new PHY execution and never modifies the captured primary CSVs.
setup6GRSimToolkit('Verbose',false);
if nargin<1, outputRoot=tempname; end
assert(~isfolder(outputRoot),'test:EvidenceExists','Choose a new evidence directory.');
mkdir(outputRoot);
root='docs/lls/evidence_20260913';
rows={};
for capture=["pucch_baseline_signal_02","pucch_baseline_signal_03"]
    file=fullfile(root,capture,'received_pucch_trials.csv');
    actual=readtable(file,'TextType','string','VariableNamingRule','preserve');
    assert(height(actual)==1);
    observed=struct('DTXFlag',logical(actual.DTXFlag), ...
        'DecodeOk',logical(actual.ReceiverUsable));
    projected=sixgr.truth.pucchReceiverDisposition(observed);
    assert(projected.DTXFlag==logical(actual.DTXFlag));
    if actual.DTXFlag
        assert(projected.DTXReason=="receiver_reported_dtx");
    else
        assert(projected.DTXReason=="");
    end
    rows{end+1}=struct('Capture',capture,'SourceCSV',string(file), ...
        'ReceiverDTX',logical(actual.DTXFlag),'ProjectedDTX',projected.DTXFlag, ...
        'ProjectedReason',projected.DTXReason, ...
        'EvidenceScope',"projection_of_retained_actual_receiver_decision_not_new_phy"); %#ok<AGROW>
end
% Logical feedback DTX does not prove physical receiver DTX.
observed=struct('DTXFlag',false,'DecodeOk',true,'DecodedBits',int8(1));
missing=sixgr.truth.resolveReceivedHARQBit(observed,2,true);
assert(missing.FeedbackOutcome=="DTX");
projected=sixgr.truth.pucchReceiverDisposition(missing);
assert(~projected.DTXFlag && projected.DTXReason=="");
for bad={struct(),struct('DTXFlag',NaN),struct('DTXFlag',[0 1]),struct('DTXFlag',2)}
    rejected=false;
    try
        sixgr.truth.pucchReceiverDisposition(bad{1});
    catch cause
        rejected=any(string(cause.identifier)==["sixgr:truth:MissingPUCCHReceiverDisposition", ...
            "sixgr:truth:InvalidPUCCHReceiverDisposition"]);
    end
    assert(rejected,'Missing/invalid receiver decisions must not become false non-DTX.');
end
results=struct2table(vertcat(rows{:}));
writetable(results,fullfile(outputRoot,'receiver_disposition_projection.csv'));
disp(results);
ok=true; disp('PUCCH_RECEIVER_DISPOSITION_PASS');
end
