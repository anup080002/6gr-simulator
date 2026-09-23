function ok=testKPICanonicalAttemptClock()
% Declared timing fixture: canonical absolute slots must not gain a second
% radio-frame offset in derived HARQ delivery/latency tables.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
for slotDuration=[1e-3 0.125e-3]
    slotsPerFrame=round(0.01/slotDuration);
    absoluteSlot0=[30;57];
    if slotsPerFrame==80, absoluteSlot0=[83;457]; end
    raw=struct();
    for direction=["DL","UL"]
        T=table(repmat(direction,2,1),ones(2,1),true(2,1),zeros(2,1), ...
            1000*ones(2,1),1000*ones(2,1),1000*ones(2,1), ...
            floor(absoluteSlot0/slotsPerFrame)+1,absoluteSlot0+1, ...
            direction+"_clock_tb_"+string((1:2).'),zeros(2,1),zeros(2,1), ...
            ones(2,1),repmat(slotDuration*1e3,2,1),(1:2).', ...
            'VariableNames',{'Direction','Goodput_Mbps','CRCPass','BitErrors', ...
            'BitsCompared','TBSize_bits','GoodBits','Frame','Slot','TransportBlockId', ...
            'HARQProcessId','RV','NDI','AirInterfaceTTI_ms','TrialId'});
        T.RuntimeAbsoluteSlotIndex0=absoluteSlot0;
        T.CarrierNSlot=mod(absoluteSlot0,slotsPerFrame);
        raw.(direction)=T;
    end
    out=sixgr.kpi.reconstructLLSKPISummaryFromRaw(raw,'MeasurementWindowSec', ...
        (max(absoluteSlot0)+1)*slotDuration);
    for direction=["DL","UL"]
        trace=out.("HARQDeliveryTrace"+direction);
        expected=absoluteSlot0*slotDuration;
        assert(all(abs(trace.AttemptStartTime_s-expected)<1e-12), ...
            'test:KPIDoubleCountedFrame','%s mu=%g canonical slot was offset by its radio frame again.', ...
            direction,log2(1e-3/slotDuration));
        assert(all(abs(trace.AttemptEndTime_s-(expected+slotDuration))<1e-12));
    end
    % Partial explicit timestamps retain priority row by row. A missing
    % row must not cause the fallback loop to overwrite a measured time.
    raw.DL.AttemptStartTime_s=[0.002;NaN];
    raw.DL.Time_s=[0.003;NaN];
    out=sixgr.kpi.reconstructLLSKPISummaryFromRaw(raw);
    assert(out.HARQDeliveryTraceDL.AttemptStartTime_s(1)==0.002 && ...
        abs(out.HARQDeliveryTraceDL.AttemptStartTime_s(2)-absoluteSlot0(2)*slotDuration)<1e-12, ...
        'test:KPIClockAuthorityOverwritten','Only absent timestamps may be filled from lower-priority clock evidence.');
end
fprintf('KPI_CANONICAL_ATTEMPT_CLOCK_PASS numerologies=0,3 directions=DL,UL\n');
ok=true;
end
