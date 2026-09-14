function ok=testPUCCHFeedbackDirection(resolveFn)
% Declared metadata/unit fixtures only; no waveform or HARQ disposition claim.
if nargin<1, resolveFn=@sixgr.truth.resolvePUCCHFeedbackDirection; end
rows=table(["UL";"UL"],["DL";"DL"],["harq_ack";"csi_part1_part2"], ...
    'VariableNames',{'Direction','FeedbackForDirection','UCIType'});
before=rows;
assert(resolveFn(rows)=="DL" && isequaln(rows,before));
assert(resolveFn(table2struct(rows))=="DL");
assert(resolveFn(table("DL",'VariableNames',{'Direction'}))=="DL");
% The resolver preserves explicit source identity. Other NR procedure guards
% validate whether a given source/transport combination is supported.
explicit=rows(1,:); explicit.FeedbackForDirection="UL";
assert(resolveFn(explicit)=="UL");
bad=rows; bad.FeedbackForDirection(2)="UL";
localReject(@()resolveFn(bad),'MixedPUCCHFeedbackDirections');
for value=["","sideways",string(missing)]
    bad=rows; bad.FeedbackForDirection(1)=value;
    localReject(@()resolveFn(bad),'InvalidPUCCHFeedbackDirection');
end
bad=removevars(rows,'FeedbackForDirection');
localReject(@()resolveFn(bad),'MissingPUCCHFeedbackDirection');
localReject(@()resolveFn(table()),'MissingPUCCHFeedbackDirection');
localReject(@()resolveFn(table(1,'VariableNames',{'Other'})),'MissingPUCCHFeedbackDirection');
fprintf('PUCCH_FEEDBACK_DIRECTION_UNIT_PASS: explicit source, legacy DL, mixed/missing rejection; no RF.\n');
ok=true;
end

function localReject(action,suffix)
try, action(); catch cause
    assert(string(cause.identifier)=="sixgr:truth:"+suffix,'Unexpected failure: %s',cause.message);
    return;
end
error('test:MissingRejection','Expected %s.',suffix);
end
