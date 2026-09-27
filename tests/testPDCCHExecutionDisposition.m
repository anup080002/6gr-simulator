function ok = testPDCCHExecutionDisposition(retainedCSV)
% Current physical completion flags and legacy blocked-row classification.
if nargin < 1, retainedCSV = ""; end
T = table(["NA";"FAIL";"PASS";"PENDING";"FAIL"], ...
    [0;1;1;0;0],[0;1;1;0;1], ...
    ["control_blocked_no_nonoverlapping_pdcch_candidate";"crc_failed";"";"";"acquisition_failed"], ...
    'VariableNames',{'Status','DecodeAttempted','PDCCHReceiverTrialExecuted','FailureReason'});
T.ControlObservationAvailable = true(height(T),1); % Poison the old derived label.
T.PDCCHPreTransmissionFinalized = logical([1;0;0;0;0]);
T.PDCCHAdmissionSelected = logical([0;1;1;1;1]);
T.GrantControlState = ["control_blocked_no_nonoverlapping_pdcch_candidate";"control_failed";"control_ok";"pending";"control_failed"];
E = sixgr.link.pdcchTrialExecutionState(T);
assert(isequal(E.ObservationAvailable,logical([0;1;1;0;1])));
assert(isequal(E.BindingEligible,logical([0;1;1;0;0])));
assert(E.BindingFailureCode(1) == T.FailureReason(1));
assert(E.BindingFailureCode(2) == "" && E.BindingFailureCode(3) == "");
assert(E.BindingFailureCode(5) == "dci_decode_not_attempted");
canonical = sixgr.truth.CoupledTruthRuntime.canonicalizePersistedControlReferenceTable('PDCCH',T);
assert(~canonical.ControlObservationAvailable(1) && canonical.ControlObservationAvailable(2), ...
    'The actual MATLAB canonical exporter must preserve the execution distinction.');
assert(canonical.ValueStatus(1)=="NOT_AVAILABLE" && ...
    canonical.NAReason(1)=="control_blocked_no_nonoverlapping_pdcch_candidate" && ...
    canonical.TruthStatus(1)=="runtime_pretransmission_pdcch_admission_disposition", ...
    'A finalized admission block must be a typed pre-transmission non-trial.');
legacy = removevars(T,'PDCCHReceiverTrialExecuted');
E = sixgr.link.pdcchTrialExecutionState(legacy);
assert(~E.ObservationAvailable(1) && ~E.BindingEligible(1));
assert(E.BindingEligible(2),'A real failed CRC must still reach the CRC/binding checks.');
bad = T; bad.PDCCHReceiverTrialExecuted(1) = Inf;
localReject(@()sixgr.link.pdcchTrialExecutionState(bad));
bad = T; bad.DecodeAttempted(1) = 2;
localReject(@()sixgr.link.pdcchTrialExecutionState(bad));
if strlength(string(retainedCSV)) > 0
    retained = readtable(retainedCSV,'TextType','string');
    selected = startsWith(string(retained.FailureReason),'control_blocked_');
    assert(any(selected),'The supplied retained evidence has no blocked grants.');
    E = sixgr.link.pdcchTrialExecutionState(retained(selected,:));
    assert(~any(E.ObservationAvailable) && ~any(E.BindingEligible));
    assert(all(startsWith(E.BindingFailureCode,'control_blocked_')));
    fprintf('RETAINED_PDCCH_BLOCKED_ROWS_CORRECTED=%d\n',nnz(selected));
end
ok = true;
fprintf('PDCCH_EXECUTION_DISPOSITION_PASS: no receiver execution is not a CRC failure.\n');
end

function localReject(call)
try, call(); catch exception
    assert(strcmp(exception.identifier,'sixgr:link:InvalidPDCCHExecutionEvidence')); return;
end
error('testPDCCHExecutionDisposition:MissingRejection','Invalid execution evidence accepted.');
end
