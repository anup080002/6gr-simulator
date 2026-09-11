function ok = testDUTReferenceUnavailableIdentity()
% Metadata-only missing-evidence fixture, never a measured PHY result.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
ctx = llsImplementationHarnessFixture("label_only");
out = sixgr.validation.LLSValidationHarness(ctx.RunFolder, ...
    ctx.ScenarioConfig,ctx.InternalConfig,'WriteArtifacts',true);
T = out.DUTReferenceComparison;
assert(~isempty(T),'Enabled blocks must retain explicit unavailable-reference diagnostics.');
assert(isstring(T.BlockId) && all(strlength(T.BlockId)>0), ...
    'Appending unavailable rows must preserve string block identity.');
assert(isstring(T.RunId) && all(T.RunId==out.Context.RunId));
assert(all(~T.Pass & ~T.ReferenceAvailable));
assert(all(T.FailureReason=="reference_path_unavailable"));
S = out.ReferenceComparisonSummary;
assert(height(S)==height(T) && all(S.ComparisonCount==1));
assert(all(S.FailCount==1 & S.PassCount==0 & ~S.DUTReferencePass));
assert(all(strlength(S.BlockId)>0));
persisted = readtable(out.ReportArtifacts.DUTReferenceComparisonCSV, ...
    'TextType','string','VariableNamingRule','preserve');
assert(isequal(persisted.BlockId,T.BlockId));
assert(isequal(persisted.FailureReason,T.FailureReason));
ok = true;
fprintf('DUT_REFERENCE_UNAVAILABLE_IDENTITY_PASS: missing evidence remains identifiable and failed.\n');
end
