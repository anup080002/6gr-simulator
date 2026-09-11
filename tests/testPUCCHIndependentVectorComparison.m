function ok=testPUCCHIndependentVectorComparison()
setup6GRSimToolkit('Verbose',false);
root=fullfile(fileparts(fileparts(mfilename('fullpath'))),'tests','vectors','pucch');
[summary,details]=sixgr.phy.pucch.PUCCHIndependentVectorComparison.build(root,'focused_pucch_comparison');
assert(height(summary)==12 && ~isempty(details));
assert(all(~summary.TruthQualified));
assert(sum(summary.MismatchCount)==nnz(details.Status=="FAIL"));
assert(sum(summary.UnverifiedFieldCount)==nnz(details.Status=="NOT_EXECUTED"));
% A format validator must not fabricate a waveform outcome; a collision
% decision must not masquerade as an actually multiplexed UCI transmission.
assert(all(details.Status(details.Field=="WaveformExpected")=="NOT_EXECUTED"));
assert(all(details.Status(details.Field=="ExpectedPUSCHUCIMultiplexed")=="NOT_EXECUTED"));
input=sixgr.phy.pucch.PUCCHUtil.readAllStrings(fullfile(root,'pucch_uci_report_test_vectors.csv'));
expected=sixgr.phy.pucch.PUCCHUtil.readAllStrings(fullfile(root,'expected_pucch_uci_serialization.csv'));
baseline=sixgr.phy.pucch.PUCCHIndependentVectorComparison.compare('uci_report',input,expected);
assert(~any(baseline.Status=="FAIL"));
reordered=sixgr.phy.pucch.PUCCHIndependentVectorComparison.compare('uci_report',input,flipud(expected));
assert(isequaln(baseline,reordered),'Comparisons must join by CaseID, not file row order.');
% Preserve leading zeros and detect length errors as exact bit-string errors.
changed=expected(2,:); changed.Sequence1Bits="1"+changed.Sequence1Bits;
negative=sixgr.phy.pucch.PUCCHIndependentVectorComparison.compare('uci_report',input(2,:),changed);
assert(nnz(negative.Status=="FAIL")==1);
assert(negative.Status(negative.Field=="Sequence1Bits")=="FAIL");
assert(negative.ObservedValue(negative.Field=="Sequence1Bits")==expected.Sequence1Bits(2));
assertError(@()sixgr.phy.pucch.PUCCHIndependentVectorComparison.compare( ...
    'uci_report',input,expected(1:end-1,:)),'sixgr:phy:pucch:VectorIdentityMismatch');
duplicate=expected; duplicate.CaseID(2)=duplicate.CaseID(1);
assertError(@()sixgr.phy.pucch.PUCCHIndependentVectorComparison.compare( ...
    'uci_report',input,duplicate),'sixgr:phy:pucch:VectorIdentityMismatch');
% Record actual audit findings; this safety test does not assert phase PASS.
disp(summary(:,{'VectorFamily','VectorCount','MismatchCount','UnverifiedFieldCount','Status'}));
fprintf('PUCCH_EXECUTED_COMPARISONS=%d MISMATCHES=%d UNVERIFIED=%d\n', ...
    sum(summary.ExecutedComparisonCount),sum(summary.MismatchCount),sum(summary.UnverifiedFieldCount));
ok=true;
end

function assertError(fcn,id)
observed="";
try, fcn(); catch exception, observed=string(exception.identifier); end
assert(observed==string(id),'Expected %s, observed %s.',id,observed);
end
