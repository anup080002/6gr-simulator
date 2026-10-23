function ok=testSharedSRSReferenceHandoff()
% Source-bound callback contract and actual assertion formatting only.
% No receiver, waveform, scoring reference, or accepted spatial decision is
% manufactured or executed here. The actual shared UL retry is a separate gate.
root=fileparts(fileparts(mfilename('fullpath')));
harness=fileread(fullfile(root,'tests','testSharedPUSCHChannelArtifacts.m'));
runner=fileread(fullfile(root,'+sixgr','+truth','runWaveformLinkBundle.m'));
branch=regexp(harness, ...
    '(?s)elseif item.Kind=="SRS"\s*(.*?)elseif item.Kind=="TRS"', ...
    'tokens');
assert(isscalar(branch),'Retain one original shared SRS callback.');
body=branch{1}{1};
compact=regexprep(body,'\s|\.\.\.','');
production=regexprep(runner,'\s|\.\.\.','');
producer='[desiredReference,referenceEvidence,refs]=sixgr.truth.sharedLinkScoringObservation(item.Planes,p,c.DesiredReferencePlane);';
assert(contains(compact,producer), ...
    'Preserve the original desired-link buffer and evidence from their owner.');
assert(contains(production, ...
    '[desiredReference,referenceEvidence]=sixgr.truth.sharedLinkScoringObservation(item.Planes,p,c.DesiredReferencePlane);'), ...
    'The harness contract must follow the canonical production SRS handoff.');
required={'input.DesiredReferenceObservation=desiredReference;', ...
    'input.DesiredReferenceEvidence=referenceEvidence;'};
call='[state,out]=sixgr.truth.receiveSharedSRSMeasurement(state,item,input);';
callAt=strfind(compact,call);
assert(isscalar(callAt),'Receive the actual SRS exactly once.');
producerAt=strfind(compact,producer);
assert(isscalar(producerAt));
for k=1:numel(required)
    at=strfind(compact,required{k});
    assert(isscalar(at) && producerAt<at && at<callAt && ...
        contains(production,required{k}), ...
        'Both original reference operands must precede the canonical receiver call.');
end
assert(contains(compact, ...
    "'Prepared',p,'Observation',receiver,'PhysicalMeasurementObservation',pre"), ...
    'Practical receiver input and pre-RF measurement remain separate original planes.');
assert(contains(compact,'assert(referenceEvidence.ChannelReferenceCoverageComplete);'));
assert(~contains(compact,'input.Observation=desiredReference') && ...
    ~contains(compact,'input.PhysicalMeasurementObservation=desiredReference'), ...
    'The clean reference must not become a practical receiver operand.');

% Execute the exact callback assertion, not a duplicated formatter. These
% are declared error-message fixtures, never synthetic receiver evidence.
assertion=regexp(body, ...
    '(?s)(assert\(out\.Ok,''test:SharedSRSFailed'',.*?)\s*state\.TestSRS=', ...
    'tokens');
assert(isscalar(assertion),'Keep the strict out.Ok gate and its original error ID.');
statement=assertion{1}{1};
assert(contains(statement,'fillmissing(string(out.FailureReason),"constant","[missing]")') && ...
    contains(statement,'fillmissing(string(out.Notes),"constant","[missing]")'));
saveAt=strfind(compact,"save(fullfile(state.TestRoot,'srs_receiver_failure.mat')");
assertAt=strfind(compact,"assert(out.Ok,'test:SharedSRSFailed'");
assert(isscalar(saveAt) && isscalar(assertAt) && saveAt<assertAt, ...
    'Retain the original failure result before any assertion-formatting error.');
before=rng;
localCheckAssertion(statement,false,"srs_channel_nmse_reference_unavailable",string(missing), ...
    'srs_channel_nmse_reference_unavailable; [missing]');
localCheckAssertion(statement,false,string(missing),"retained diagnostic", ...
    '[missing]; retained diagnostic');
localCheckAssertion(statement,false,"",string(missing),'; [missing]');
out=struct('Ok',true,'FailureReason',string(missing),'Notes',string(missing)); %#ok<NASGU>
eval(statement);
assert(isequal(before,rng),'The handoff regression must not run another physical realization.');
ok=true;
fprintf('SHARED_SRS_REFERENCE_HANDOFF_PASS scope=source_contract_and_strict_error_format waveform_executions=0\n');
end

function localCheckAssertion(statement,pass,reason,notes,expected)
out=struct('Ok',pass,'FailureReason',reason,'Notes',notes); %#ok<NASGU>
try
    eval(statement);
catch cause
    assert(strcmp(cause.identifier,'test:SharedSRSFailed'), ...
        'Strict receiver rejection was obscured by %s: %s',cause.identifier,cause.message);
    assert(contains(cause.message,expected));
    return;
end
error('test:MissingRejection','The original strict out.Ok assertion did not reject.');
end
