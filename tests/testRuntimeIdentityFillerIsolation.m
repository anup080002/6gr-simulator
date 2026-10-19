function ok = testRuntimeIdentityFillerIsolation()
%TESTRUNTIMEIDENTITYFILLERISOLATION Identity blanks are never decorated.

T = table([""; "run-2"], [""; "scenario-2"], [""; "abc123"], ...
    [""; "runtime"], [""; "available"], ...
    'VariableNames', {'RunID', 'ScenarioID', 'ConfigHash', 'MetricSource', 'ValueStatus'});
filled = sixgr.truth.fillBlankCategoricalColumns(T, "pdcch_measurement");
assert(filled.RunID(1) == "" && filled.ScenarioID(1) == "" && ...
    filled.ConfigHash(1) == "", ...
    "Immutable identity blanks must remain visible to fail-closed validation.");
assert(contains(filled.MetricSource(1), "not_emitted_by_active_pdcch_measurement_runtime"));
assert(contains(filled.ValueStatus(1), "not_emitted_by_active_pdcch_measurement_runtime"));
assert(filled.RunID(2) == "run-2" && filled.ScenarioID(2) == "scenario-2");
assert(sixgr.truth.isImmutableIdentityField("SourceArtifactSHA256"));
assert(~sixgr.truth.isImmutableIdentityField("MetricSource"));
uuid=table(["";"execution-uuid"],'VariableNames',{'RunUUID'});
assert(sixgr.truth.isImmutableIdentityField("RunUUID") && ...
    isequaln(uuid,sixgr.truth.fillBlankCategoricalColumns(uuid,"pbch")), ...
    'An absent RunUUID must not become a channel-specific identity token.');

% Message and context hashes are producer evidence, including the absence
% of a receiver-decoded message after a failed CRC. Exercise both export
% passes and the actual CSV serialization (not only the name predicate).
identityFields=["MessageSHA256","RRCSetupCompletePayloadSHA256", ...
    "RRCSetupCompleteTransmittedPayloadSHA256","DCIPayloadHashRx", ...
    "PayloadHash","DCIContextDigest"];
evidence=table([false;true],'VariableNames',{'CRCPass'});
actualHash=string(sixgr.util.sha256Hex(uint8([1 2 3 4])));
for field=identityFields
    assert(sixgr.truth.isImmutableIdentityField(field));
    evidence.(field)=["";actualHash];
end
for scope=["prach_trials","pdcch_trials","ul_pusch_trials"]
    retained=sixgr.truth.fillBlankCategoricalColumns(evidence,scope);
    retained=sixgr.truth.canonicalizeLLSLiveSignalChainTable(scope,retained);
    assert(isequaln(retained,evidence), ...
        'Export must preserve actual message/context identities and legitimate blanks.');
end
csvPath=string(tempname)+".csv";
cleanup=onCleanup(@() delete(csvPath)); %#ok<NASGU>
writetable(retained,csvPath);
opts=detectImportOptions(csvPath,'TextType','string');
opts=setvartype(opts,cellstr(identityFields),'string');
roundTrip=readtable(csvPath,opts);
for field=identityFields
    values=fillmissing(roundTrip.(field),'constant',"");
    assert(isequal(values,evidence.(field)), ...
        'CSV round trip must not manufacture or alter a message identity.');
end

% Structured evidence is not categorical text. In normalized SSB runs the
% absolute-power object is deliberately absent; decorating it makes the
% downstream parser enter the wrong physical reference plane.
structured=table(["";"{""ReferencePlane"":""physical""}"], ...
    ["{""ReferencePlane"":""normalized""}";""], ...
    'VariableNames',{'SSBWindowPowerMeasurementJSON','SSBWindowRelativePowerMeasurementJSON'});
preserved=sixgr.truth.fillBlankCategoricalColumns(structured,'pbch');
assert(isequaln(preserved,structured), ...
    'Structured JSON evidence and legitimate empty objects must not be decorated.');

% A strongest-only detector has no complete received-preamble set. Neither
% that absent set nor a measured empty set may become a display token. The
% token previously made failed-run PRACH publication reject valid evidence.
prach=table([0;0;0],[0;NaN;1],[1;0;1],["";"";"1|0"], ...
    [false;true;true], 'VariableNames',{'PreambleIndexTx', ...
    'PreambleIndexDetected','PreambleDetected','DetectedPreambleSet', ...
    'DetectedPreambleSetAvailable'});
preserved=sixgr.truth.fillBlankCategoricalColumns(prach,'prach');
assert(isequaln(preserved,prach), ...
    'Do not fabricate preamble identities for absent or measured-empty sets.');
[missed,wrong,scope]=sixgr.report.prachTargetDetectionEvidence(preserved);
assert(isequal(missed,[0;1;0]) && isequaln(wrong,[0;NaN;0]) && ...
    scope(1)=="legacy_single_candidate" && ...
    all(scope(2:3)=="per_target_shared_occasion_not_independent_trials"));
bad=prach; bad.DetectedPreambleSet(1)="0";
try
    sixgr.report.prachTargetDetectionEvidence(bad);
    error('test:MissingRejection','An unavailable set with identities must be rejected.');
catch failure
    assert(strcmp(failure.identifier,'sixgr:report:InvalidPRACHDetectionSet'));
end

reasons = table(["";"receiver_not_executed"], ["";"frame_not_complete"], ...
    'VariableNames',{'MeasuredTrialSINRNAReason','NAReason'});
retained = sixgr.truth.fillBlankCategoricalColumns(reasons,"pbch");
assert(isequaln(retained,reasons), ...
    'Reason fields must retain the producer evidence, including legitimate blanks.');

% A successful control receiver emits no failure code. Replacing that
% blank with a categorical token causes the downstream strict binding
% gate to invent a failure despite a matching CRC and grant identity.
for field=["GrantBindingFailureCode","PDCCHGrantBindingFailureCode", ...
        "FailureCode","FailureReason","CSIComputationErrorIdentifier", ...
        "CSIComputationErrorMessage"]
    control=table([true;false],["bound";"failed"], ...
        ["";"decoded_dci_crc_failed"], ...
        'VariableNames',{'GrantBindingOk','GrantBindingStatus',char(field)});
    preserved=sixgr.truth.fillBlankCategoricalColumns(control,'pdcch');
    assert(isequaln(preserved,control), ...
        'Do not fabricate or erase producer failure evidence in %s.',field);
end

canonical = sixgr.truth.canonicalizeLLSLiveSignalChainTable( ...
    "ul_pusch_trials", T);
assert(canonical.RunID(1) == "" && canonical.ScenarioID(1) == "" && ...
    canonical.ConfigHash(1) == "", ...
    "Signal-chain canonicalization must not fabricate immutable identity.");

ok = true;
fprintf("PASS testRuntimeIdentityFillerIsolation: identity provenance is no longer fabricated.\n");
end
