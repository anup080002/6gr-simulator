function ok=testULHARQSoftBufferIdentity()
% Declared ownership contracts only; no received waveform or combining claim.
key="gNB-UL-TB-declared_process_epoch_a";
check=@(prior)sixgr.link.validateULHARQSoftBufferIdentity(prior,key);
check([]); check(struct());
prior=struct('LLRSum',zeros(4,1),'ObservationWeight',ones(4,1), ...
    'HARQKey',char(key),'CodewordIndex',1);
check(prior);
for foreign=["gNB-UL-TB-declared_process_epoch_b","","other_contract"]
    bad=prior; bad.HARQKey=foreign;
    localReject(@()check(bad),'sixgr:link:ULHARQSoftBufferIdentityMismatch');
end
for codeword=[0 2 NaN Inf]
    bad=prior; bad.CodewordIndex=codeword;
    localReject(@()check(bad),'sixgr:link:ULHARQSoftBufferIdentityMismatch');
end
for name=["LLRSum","ObservationWeight","HARQKey","CodewordIndex"]
    bad=rmfield(prior,name);
    localReject(@()check(bad),'sixgr:link:ULHARQUnboundPriorBuffer');
end
localReject(@()check(ones(4,1)),'sixgr:link:ULHARQUnboundPriorBuffer');
localReject(@()check({prior}),'sixgr:link:ULHARQUnboundPriorBuffer');
bad=prior; bad.HARQKey=[key key];
localReject(@()check(bad),'sixgr:link:ULHARQSoftBufferIdentityMismatch');
localReject(@()sixgr.link.validateULHARQSoftBufferIdentity([],""), ...
    'sixgr:link:ULHARQReceiverKeyRequired');
ok=true;
fprintf('UL_HARQ_SOFT_BUFFER_IDENTITY_PASS declared_contract=1 RF=0\n');
end

function localReject(action,id)
try
    action();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s.',id,cause.identifier); return;
end
error('test:MissingRejection','Expected %s.',id);
end
