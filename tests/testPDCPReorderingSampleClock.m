function ok=testPDCPReorderingSampleClock()
for fs=[1000 7680000 30720000]
    r=sixgr.l2.pdcp18.PDCPReorderingState(18,0,.002,fs,4);
    assert(isequal(r.receive(0,.024),0));
    assert(isempty(r.receive(2,.025)));
    deadline=round(.027*fs);
    assert(r.TimerExpirySample==deadline&&r.ClockEpoch==4);
    assert(isempty(r.advance((deadline-1)/fs)));
    assert(isequal(r.advance(deadline/fs),2)&&r.RX_DELIV==3);
    assert(isempty(r.advance(deadline/fs)));
    clone=r.copy();assert(isequaln(clone.snapshot(),r.snapshot()));
    expectError(@()r.advance((deadline+.25)/fs),'sixgr:pdcp:ReorderingClockViolation');
end
expectError(@()sixgr.l2.pdcp18.PDCPReorderingState(18,0,.002,7680000,NaN), ...
    'sixgr:pdcp:ReorderingClockViolation');
fprintf('PDCP_REORDERING_SAMPLE_CLOCK_PASS exact_boundary=1 previous_sample_pending=1 original_clock=1\n');
ok=true;
end
function expectError(f,id)
try,f();catch ex,assert(string(ex.identifier)==id,ex.message);return;end
error('sixgr:test:MissingReorderingClockGuard','Expected %s.',id);
end
