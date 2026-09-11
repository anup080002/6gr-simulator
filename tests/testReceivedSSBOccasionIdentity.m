function ok = testReceivedSSBOccasionIdentity()
sync = struct('SSBTiming',struct('CandidateIndices',0:3, ...
    'CandidateStartSymbolsWithinHalfFrame',[2 8 16 22]), ...
    'SelectedCandidateStartSymbol',16);
pbch = struct('SSBIndex',3,'Ok',false,'ErrFlag',1);
id = sixgr.phy.sync.receivedSSBOccasionIdentity(sync,pbch);
assert(id.ObservedSSBOccasionIndex==2 && id.PBCHHypothesisSSBIndex==3 && ...
    ~id.SSBIdentityVerified && id.SSBIndexSource=="received_pss_candidate_window");
pbch.Ok=true; pbch.ErrFlag=0;
id = sixgr.phy.sync.receivedSSBOccasionIdentity(sync,pbch);
assert(~id.SSBIdentityVerified,'CRC alone must not validate another received occasion.');
pbch.SSBIndex=2;
id = sixgr.phy.sync.receivedSSBOccasionIdentity(sync,pbch);
assert(id.SSBIdentityVerified);
hashes = [string(repmat('a',1,64)),string(repmat('b',1,64))];
e = struct('ActiveSSBIndices0Based',[1 3],'PrecoderMatrixSHA256',hashes);
assert(sixgr.truth.resolveSSBPrecoderHash(e,1)==hashes(1));
assert(sixgr.truth.resolveSSBPrecoderHash(e,3)==hashes(2));
bad=sync; bad.SelectedCandidateStartSymbol=9;
localReject(@() sixgr.phy.sync.receivedSSBOccasionIdentity(bad,pbch));
localReject(@() sixgr.truth.resolveSSBPrecoderHash(e,2));
e.ActiveSSBIndices0Based=[3 3];
localReject(@() sixgr.truth.resolveSSBPrecoderHash(e,3));
ok=true;
end

function localReject(f)
try
    f();
catch ME
    assert(startsWith(string(ME.identifier),'sixgr:'));
    return;
end
error('test:ExpectedError','Invalid received/precoder identity was accepted.');
end
