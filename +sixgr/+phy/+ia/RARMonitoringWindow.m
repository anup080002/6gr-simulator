classdef RARMonitoringWindow
    % Type1 CSS occasions on the 38.211 Tc clock (38.213 clause 8.2).
    % This is a receive-opportunity plan, never evidence of a decoder attempt.
    methods (Static)
        function window=resolve(frame,control,prachEndTicks,windowSlots,clockOffsetTicks)
            if nargin<5, clockOffsetTicks=int64(0); end
            validateattributes(clockOffsetTicks,{'int64'},{'scalar'});
            validateattributes(windowSlots,{'numeric'},{'scalar','integer','positive','finite'});
            finish=sixgr.phy.frame.AbsoluteTime.fromTicks(prachEndTicks-clockOffsetTicks);
            spec=sixgr.phy.frame.AbsoluteTime.resolveNumerology(frame.Numerology);
            period=control.SlotPeriodAndOffset;
            validateattributes(period,{'numeric'},{'vector','numel',2,'integer','nonnegative','finite'});
            validateattributes(control.MonitoringDurationSlots,{'numeric'}, ...
                {'scalar','integer','positive','<=',period(1)});
            if period(1)<1 || period(2)>=period(1)
                error('sixgr:phy:ia:InvalidRARMonitoringPeriod','Invalid Type1 period/offset.');
            end
            startSymbol=control.StartSymbol; duration=control.DurationSymbols;
            validateattributes(startSymbol,{'numeric'},{'scalar','integer','nonnegative','finite'});
            validateattributes(duration,{'numeric'},{'scalar','integer','positive','finite'});
            if startSymbol+duration>spec.SymbolsPerSlot
                error('sixgr:phy:ia:InvalidRARMonitoringSymbols','CORESET extends outside its slot.');
            end
            [f,s,~,~]=finish.toNumerology(spec);
            first=double(f)*spec.SlotsPerFrame+double(s);
            duplexPeriod=1;
            if frame.DuplexMode=="TDD", duplexPeriod=size(frame.SlotState.ResolvedDirection,1); end
            cycle=lcm(period(1),duplexPeriod);
            found=false;
            % One joint repetition plus one slot is sufficient after the
            % PRACH end; the extra slot permits the mandatory symbol gap.
            for slot=first:(first+cycle+1)
                if ~localOccasion(frame,control,slot), continue; end
                t=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(slot,startSymbol,spec);
                if slot==0 && startSymbol==0, continue; end
                prior=t.plusSymbols(-1,spec);
                if prior.Ticks>=finish.Ticks
                    found=true; break;
                end
            end
            if ~found
                error('sixgr:phy:ia:NoRARMonitoringOccasion', ...
                    'The Type1 CSS and duplex map provide no receive occasion after PRACH.');
            end
            expiry=t.plusSlots(windowSlots,spec);
            slots=zeros(0,1); ticks=zeros(0,1,'int64');
            for candidate=slot:(slot+windowSlots)
                if ~localOccasion(frame,control,candidate), continue; end
                start=sixgr.phy.frame.AbsoluteTime.fromAbsoluteSlotSymbol(candidate,startSymbol,spec);
                if start.Ticks>=expiry.Ticks, break; end
                slots(end+1,1)=candidate; ticks(end+1,1)=start.Ticks; %#ok<AGROW>
            end
            last=expiry.plusTicks(-1);
            [lf,ls,~,~]=last.toNumerology(spec);
            window=struct('ContractVersion',"sixgr_rar_type1_window/v1", ...
                'Source',"38.213_8.2_actual_prach_end_and_type1_css", ...
                'ControlSource',string(control.Source),'Numerology',spec, ...
                'PRACHActiveEndTicksExclusive',finish.Ticks, ...
                'StartTicks',t.Ticks,'ExpiryTicksExclusive',expiry.Ticks, ...
                'StartSlot',slot,'StartSymbol',startSymbol, ...
                'LastSlot',double(lf)*spec.SlotsPerFrame+double(ls), ...
                'DurationSlots',double(windowSlots),'MonitoringSlots',slots, ...
                'MonitoringStartTicks',ticks,'CORESETDurationSymbols',duration, ...
                'SearchSpaceID',control.SearchSpaceID,'CORESETID',control.CORESETID, ...
                'ReceiverExecutionQualified',false,'ProxyUsed',false,'FallbackUsed',false);
            % Slot/symbol coordinates remain in the UE's received radio
            % frame. Physical event timestamps include its measured phase.
            window.ClockOffsetTicks=clockOffsetTicks;
            for field=["PRACHActiveEndTicksExclusive","StartTicks","ExpiryTicksExclusive","MonitoringStartTicks"]
                window.(field)=window.(field)+clockOffsetTicks;
            end
        end
    end
end

function tf=localOccasion(frame,control,slot)
p=control.SlotPeriodAndOffset;
tf=mod(slot-p(2),p(1))<control.MonitoringDurationSlots && ...
    frame.IsDLAllocation(slot,[control.StartSymbol control.DurationSymbols]);
end
