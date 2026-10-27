function [windows,unavailable]=planCellPRACHReceiveWindows(calendar,first,stop)
% Arm by receive-window START, including lookahead before the native RO.
% A startup window whose prefix predates sample0 is retained as unavailable;
% its missing samples are never padded or passed to the detector.
assert(calendar.ContractVersion=="cell_PRACH_receive_calendar/v1" && ...
    calendar.SHA256==string(sixgr.util.sha256Hex(jsonencode( ...
        sixgr.util.jsonSafeValue(rmfield(calendar,'SHA256'))))), ...
    'sixgr:truth:CellPRACHCalendarChanged','Retain the original installed calendar.');
validateattributes(first,{'numeric'},{'scalar','real','integer','nonnegative','finite'});
validateattributes(stop,{'numeric'},{'scalar','real','integer','>',first,'finite'});
n=calendar.Native; r=calendar.Receiver; T=n.Occasions;
tc=double(sixgr.phy.frame.AbsoluteTime.TicksPerSecond)/r.SampleRateHz;
assert(tc==fix(tc),'sixgr:truth:CellPRACHClockMismatch','No rounded receive clocks.');
offset=sixgr.phy.frame.resolveULTimingAdvanceOffsetValue(r.TimingAdvanceOffsetPresent,r.TimingAdvanceOffset,n.FrequencyRange);
advance=double(offset.NTAOffset_Tc)/tc+r.SearchGuardSamples;
period=n.PeriodFrames*r.SampleRateHz/100;
assert(period==fix(period) && advance==fix(advance),'sixgr:truth:CellPRACHClockMismatch','Exact sample boundaries required.');
windows=cell(0,1); unavailable=struct('OccasionOrdinal1',{},'Reason',{},'ReceiveStartSample',{});
for p=max(0,floor((first+advance)/period)-1):floor((stop+advance)/period)
    for row=1:height(T)
        if ~calendar.Validity.RepeatedValidity(row,1), continue; end
        a=double(T.PRACHWaveformStartTicks(row))/tc+p*period-advance;
        ordinal=p*height(T)+row;
        if a<0
            if first==0
                unavailable(end+1)=struct('OccasionOrdinal1',ordinal, ...
                    'Reason',"receiver_prefix_precedes_physical_origin",'ReceiveStartSample',a); %#ok<AGROW>
            end
            continue;
        end
        if a<first || a>=stop, continue; end
        w=sixgr.phy.ra.planPRACHReceiveWindow(n,ordinal,r);
        w.CellCalendarSHA256=calendar.SHA256;
        w.ROValiditySHA256=string(sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(calendar.Validity))));
        w.Scope="configured_valid_cell_receive_window_not_detection";
        windows{end+1,1}=w; %#ok<AGROW>
    end
end
if ~isempty(windows)
    starts=cellfun(@(w)w.ReceiveStartSample,windows); [~,order]=sort(starts);
    windows=windows(order);
end
end
