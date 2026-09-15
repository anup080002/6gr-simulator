function ok=testLLSStatusNoteIdempotency()
% Ordered diagnostic notes must converge without changing any verdict.
join=@sixgr.util.joinStatusNotes;
assert(join()=="" && join("",strings(0,1))=="");
assert(join("first",["second";"first"],"third")=="first | second | third");
assert(join("first | second","second | third")=="first | second | third");
assert(join("first|second","first|second")=="first|second");
assert(join([missing;"first"],"second")=="first | second");
expected="Original execution failed. | Required MIMO evidence missing. | Recovery remains failed.";
current=expected;
for pass=1:100
    current=join(current,"Required MIMO evidence missing.","Recovery remains failed.");
    assert(current==expected,'Repeated reductions must not accumulate duplicate notes.');
end
% Every producer on the normal/recovery fixed-point path uses the same join.
for name=["sixgr.lls6g.runners.runSingle","sixgr.truth.recoverLLSRunArtifacts", ...
        "sixgr.truth.applyPersistedMIMOConfiguredEffectiveStatus"]
    source=fileread(which(name));
    assert(contains(source,'sixgr.util.joinStatusNotes('));
end
ok=true;
end
