function ok=testULHARQReceiverState()
% Declared receiver-state contracts, not a physical missed-DCI campaign.
setup6GRSimToolkit('Verbose',false);
a=struct('ScopeKey',"process-a",'ReceiverKey',"gNB-UL-TB-declared-a", ...
    'NDIEpoch',1,'DataAbsoluteSlot',4,'ObservationID',"rx-1", ...
    'GrantContextID',"grant-1",'CommandObservationID',"command-1", ...
    'StartSample',400,'EndSampleExclusive',500,'SampleRateHz',1000,'AvailableAtSample',500);
[empty,prior,token]=sixgr.truth.resolveULHARQReceiverState({},a);
assert(isempty(empty) && isempty(prior));
soft=struct('LLRSum',ones(4,1),'ObservationWeight',ones(4,1), ...
    'HARQKey',a.ReceiverKey,'CodewordIndex',1,'CodingLayoutHash',"declared-layout");
d=struct('ReceiverAttempt',token,'DecodeAttempted',true,'CRCPass',false,'SoftBuffer',soft);
[failed,~,~]=sixgr.truth.resolveULHARQReceiverState({},a,d);
assert(isequaln(failed{1}.SoftBuffer,soft));
reject(@()sixgr.truth.resolveULHARQReceiverState(failed,a), ...
    'sixgr:truth:StaleULHARQReceiveAttempt');
b=next(a,2);
[unchanged,prior,token2]=sixgr.truth.resolveULHARQReceiverState(failed,b);
assert(isequaln(unchanged,failed) && isequaln(prior,soft));
% An unattempted receiver erasure advances the clock, preserving only the
% previously received soft bits, without requiring or recording a UE TX.
erasure=struct('ReceiverAttempt',token2,'DecodeAttempted',false,'CRCPass',false,'SoftBuffer',[]);
silent=sixgr.truth.resolveULHARQReceiverState(failed,b,erasure);
assert(isequaln(silent{1}.SoftBuffer,soft) && ~silent{1}.DecodeAttempted);
c=next(b,3); [~,prior,token3]=sixgr.truth.resolveULHARQReceiverState(silent,c);
assert(isequaln(prior,soft));
passed=struct('ReceiverAttempt',token3,'DecodeAttempted',true,'CRCPass',true,'SoftBuffer',soft);
cleared=sixgr.truth.resolveULHARQReceiverState(silent,c,passed);
assert(cleared{1}.CRCPass && isempty(cleared{1}.SoftBuffer));
poison=passed; poison.ExpectedBits=ones(999,1); poison.ReferenceContentMatch=false;
assert(isequaln(cleared,sixgr.truth.resolveULHARQReceiverState(silent,c,poison)));
% Same process/NDI bit in a new epoch cannot reuse an older soft buffer.
new=next(b,4); new.NDIEpoch=2; new.ReceiverKey="gNB-UL-TB-declared-new-epoch";
[~,prior,newToken]=sixgr.truth.resolveULHARQReceiverState(silent,new);
assert(isempty(prior));
e=erasure; e.ReceiverAttempt=newToken;
fresh=sixgr.truth.resolveULHARQReceiverState(silent,new,e);
assert(isempty(fresh{1}.SoftBuffer));
bad=next(new,5); bad.NDIEpoch=1; bad.ReceiverKey=a.ReceiverKey;
reject(@()sixgr.truth.resolveULHARQReceiverState(fresh,bad),'sixgr:truth:StaleULHARQReceiverEpoch');
bad=next(b,5); bad.ReceiverKey="gNB-UL-TB-contradictory";
reject(@()sixgr.truth.resolveULHARQReceiverState(silent,bad),'sixgr:truth:StaleULHARQReceiverEpoch');
bad=passed; bad.ReceiverAttempt=token2;
reject(@()sixgr.truth.resolveULHARQReceiverState(silent,c,bad),'sixgr:truth:ChangedULHARQReceiverState');
tampered=silent; tampered{1}.SoftBuffer.LLRSum(1)=99;
reject(@()sixgr.truth.resolveULHARQReceiverState(tampered,c,passed),'sixgr:truth:ChangedULHARQReceiverState');
infinite=silent; infinite{1}.SoftBuffer.LLRSum(1)=Inf;
[~,~,positive]=sixgr.truth.resolveULHARQReceiverState(infinite,c);
infinite{1}.SoftBuffer.LLRSum(1)=-Inf;
[~,~,negative]=sixgr.truth.resolveULHARQReceiverState(infinite,c);
assert(positive.PriorStateDigest~=negative.PriorStateDigest);
bad=erasure; bad.CRCPass=true;
reject(@()sixgr.truth.resolveULHARQReceiverState(failed,b,bad),'sixgr:truth:InvalidULHARQReceiverDecision');
bad=erasure; bad.SoftBuffer=soft;
reject(@()sixgr.truth.resolveULHARQReceiverState(failed,b,bad),'sixgr:truth:UnattemptedULHARQSoftEvidence');
bad=passed; bad.SoftBuffer.HARQKey="gNB-UL-TB-foreign";
reject(@()sixgr.truth.resolveULHARQReceiverState(silent,c,bad),'sixgr:link:ULHARQSoftBufferIdentityMismatch');
bad=passed; bad.SoftBuffer.CodingLayoutHash="another-layout";
reject(@()sixgr.truth.resolveULHARQReceiverState(silent,c,bad),'sixgr:truth:ULHARQReceiverCodingDomainChanged');
bad=passed; bad.SoftBuffer.LLRSum(1)=NaN;
reject(@()sixgr.truth.resolveULHARQReceiverState(silent,c,bad),'sixgr:truth:InvalidULHARQReceiverSoftEvidence');
bad=passed; bad.SoftBuffer.ObservationWeight(1)=-1;
reject(@()sixgr.truth.resolveULHARQReceiverState(silent,c,bad),'sixgr:truth:InvalidULHARQReceiverSoftEvidence');
bad=passed; bad.SoftBuffer.LLRSum=ones(5,1); bad.SoftBuffer.ObservationWeight=ones(5,1);
reject(@()sixgr.truth.resolveULHARQReceiverState(silent,c,bad),'sixgr:truth:ULHARQReceiverCodingDomainChanged');
assert(~any(isfield(silent{1},{'TransportBlockBits','TxCount','GoodBits','TBSBytes'})));
fprintf('UL_HARQ_RECEIVER_STATE_PASS declared_normal_erasure_retx_epoch_contracts=1 RF=0\n');
ok=true;
end

function b=next(a,n)
b=a; b.DataAbsoluteSlot=a.DataAbsoluteSlot+5;
b.StartSample=a.EndSampleExclusive+400; b.EndSampleExclusive=b.StartSample+100;
b.AvailableAtSample=b.EndSampleExclusive;
b.ObservationID="rx-"+n; b.GrantContextID="grant-"+n; b.CommandObservationID="command-"+n;
end

function reject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
