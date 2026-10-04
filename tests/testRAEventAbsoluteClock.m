function ok=testRAEventAbsoluteClock()
events=table([0;1;2;2],[4;9;2;4],'VariableNames',{'Frame','Slot'});
assert(isequal(sixgr.truth.resolveRAEventAbsoluteSlots(events,0.001),[4;19;22;24]));
assert(isequal(sixgr.truth.resolveRAEventAbsoluteSlots(events,0.0005),[4;29;42;44]));
for invalid=[NaN,-1,10,0.5]
    bad=events; bad.Slot(1)=invalid;
    try
        sixgr.truth.resolveRAEventAbsoluteSlots(bad,0.001);
    catch ex
        assert(string(ex.identifier)=="sixgr:truth:InvalidRAEventClock");
        continue;
    end
    error('Invalid event clock was accepted.');
end
ok=true;
end
