function ok=testSharedPUSCHCommitReceipt()
% Declared receipt-validation contracts, NOT a PHY or HARQ commit fixture.
% The actual common-commit method must obtain its receipt from RF completion.
r=struct('ObservationID',"declared_observation",'GrantContextID',"declared_grant", ...
    'ReceiverContextDigest',"declared_context",'HARQMappingDigest',"declared_mapping", ...
    'AvailableAtSample',100);
r.Digest=sixgr.phy.pucch.PUCCHUtil.hash(r);
state=struct('SharedPUSCHHARQFeedbackReceipts',{{r}});
h=struct('GrantSnapshot',struct('PHYGrant',struct('GrantContextId',r.GrantContextID)), ...
    'UCIReceiveContextDigest',r.ReceiverContextDigest,'SharedPUSCHHARQFeedbackReceipt',r, ...
    'ExpectedHARQACKBits',ones(99,1,'int8'));
consume=@sixgr.truth.CoupledTruthRuntime.applyDecodedPUSCHHARQACKRuntime;
before=state;
first=consume(state,h); second=consume(first,h);
assert(isequaln(first,before) && isequaln(second,before));
% No HARQ handle exists in this contract test: a second onFeedback call or
% a TX-sized legacy fallback would fail, rather than masquerade as success.
localReject(@()consume(struct(),h));
bad=h; bad=rmfield(bad,'SharedPUSCHHARQFeedbackReceipt');
localReject(@()consume(state,bad));
bad=h; bad.SharedPUSCHHARQFeedbackReceipt=true;
localReject(@()consume(state,bad));
bad=h; bad.SharedPUSCHHARQFeedbackReceipt.AvailableAtSample=101;
localReject(@()consume(state,bad));
bad=h; bad.UCIReceiveContextDigest="wrong_context";
localReject(@()consume(state,bad));
bad=h; bad.GrantSnapshot.PHYGrant.GrantContextId="wrong_grant";
localReject(@()consume(state,bad));
duplicate=state; duplicate.SharedPUSCHHARQFeedbackReceipts={r,r};
localReject(@()consume(duplicate,h));
% A recomputed hash is not ownership; the retained receipt must also match.
bad=h; changed=r; changed.ObservationID="other_observation";
changed.Digest=sixgr.phy.pucch.PUCCHUtil.hash(rmfield(changed,'Digest'));
bad.SharedPUSCHHARQFeedbackReceipt=changed;
localReject(@()consume(state,bad));
assert(isequaln(state,before));
fprintf('SHARED_PUSCH_COMMIT_RECEIPT_GUARD_PASS no_second_legacy_update no_RF_claim\n');
ok=true;
end

function localReject(fn)
id='sixgr:truth:MissingIndependentPUSCHHARQCommit';
try, fn(); catch err
    assert(strcmp(err.identifier,id),'Expected %s; got %s: %s',id,err.identifier,err.message);
    return;
end
error('test:ExpectedRejection','Expected %s',id);
end
