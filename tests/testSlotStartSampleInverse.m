function ok=testSlotStartSampleInverse()
% Compare exact slot identity with independently accumulated native CP lengths.
% The stale-reference policy is in slots, not average-duration fractions.
cases=[15 0;30 0;60 0;120 0;240 0;60 1];
nonuniformWitness=false;
for i=1:size(cases,1)
    cp='normal'; if cases(i,2), cp='extended'; end
    carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',cases(i,1),'CyclicPrefix',cp);
    info=nrOFDMInfo(carrier,'Nfft',512);
    fs=double(info.SampleRate); L=double(carrier.SymbolsPerSlot);
    slotLengths=sum(reshape(double(info.SymbolLengths),L,[]),1);
    starts=[0 cumsum(repmat(slotLengths,1,21))];
    for slot0=0:numel(starts)-1
        actual=sixgr.phy.frame.slotStartSample(carrier,slot0,fs);
        assert(actual==starts(slot0+1),'Exact slot clock disagrees with native CP lengths.');
        decoded=sixgr.phy.frame.slotIndexFromStartSample(carrier,actual,fs);
        assert(decoded==slot0,'Exact slot index must survive subframe/frame boundaries.');
    end
    meanSlot=fs*1e-3*15/cases(i,1);
    if ~cases(i,2) && cases(i,1)>=60
        % Existing mean-duration freshness incorrectly rejects this age-one pilot.
        assert(starts(2)/meanSlot>1);
        age=sixgr.phy.frame.slotIndexFromStartSample(carrier,starts(2),fs)- ...
            sixgr.phy.frame.slotIndexFromStartSample(carrier,starts(1),fs);
        assert(age==1); nonuniformWitness=true;
    end
    reject(@()sixgr.phy.frame.slotIndexFromStartSample(carrier,starts(2)+1,fs), ...
        'sixgr:phy:frame:NotSlotStartSample');
end
assert(nonuniformWitness);
reject(@()sixgr.phy.frame.slotIndexFromStartSample(carrier,0,1234567), ...
    'sixgr:phy:frame:SlotBoundaryOffSampleClock');
fprintf('SLOT_START_INVERSE_PASS native_CP_clock=1 mean_duration_false_stale_reproduced=1\n');
ok=true;
end
function reject(fn,id)
try, fn(); catch ME, assert(strcmp(ME.identifier,id),'Unexpected rejection: %s',ME.identifier); return; end
error('test:MissingRejection','Expected %s.',id);
end
