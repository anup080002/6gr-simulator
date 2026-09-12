function ok=testExecutedHARQClock()
setup6GRSimToolkit('Verbose',false);
for slot1=[1 2 20 21 20481]
    carrier=nrCarrierConfig('SubcarrierSpacing',30,'NSizeGrid',11, ...
        'NFrame',mod(floor((slot1-1)/20),1024),'NSlot',mod(slot1-1,20));
    before=struct('Slot',NaN,'Frame',NaN,'ScheduledAbsoluteSlot',slot1-1);
    after=sixgr.link.bindExecutedHARQClock(before,carrier,slot1);
    assert(after.Slot==slot1 && after.Frame==floor((slot1-1)/20)+1 && ...
        after.ScheduledAbsoluteSlot==slot1-1 && ...
        string(after.HARQClockSource)=="executed_nr_carrier_and_absolute_slot");
    assert(isequal(after,sixgr.link.bindExecutedHARQClock(after,carrier,slot1)));
    for name=["Slot","Frame","ScheduledAbsoluteSlot"]
        bad=after; bad.(name)=bad.(name)+1;
        reject(@()sixgr.link.bindExecutedHARQClock(bad,carrier,slot1));
    end
    reject(@()sixgr.link.bindExecutedHARQClock(before,carrier,slot1+1));
end
fprintf('EXECUTED_HARQ_CLOCK_PASS slots=5 guards=20 includes_sfn_wrap\n');
ok=true;
end

function reject(fn)
try, fn(); catch ME, assert(strcmp(ME.identifier,'sixgr:link:HARQExecutedClockMismatch')); return; end
error('test:MissingRejection','Expected executed-clock rejection.');
end
