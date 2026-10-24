classdef PHYDiagnosticClockContract
    % Bounded, read-only qualification of diagnostic radio-clock claims.
    % This checks exported source contracts, not waveform authenticity or
    % standards conformance. Unknown historical clocks are never repaired.
    % State grows with distinct (Direction,SnapshotID), not coefficient rows.
    methods (Static)
        function names=inputColumns()
            names=["Direction","SnapshotID","SFN","CarrierNFrame", ...
                "CarrierNSlot","SCS_kHz","SlotsPerFrame","AbsoluteSlot", ...
                "RuntimeAbsoluteSlotIndex0","Slot","SFNSource", ...
                "SlotConvention","AbsoluteSlotConvention","AbsoluteSlotSource"];
        end

        function state=initialize()
            state=struct('ContractVersion',"sixgr.diagnostic.radio_clock/v1", ...
                'RowsChecked',0,'MaxChunkRows',0,'MissingSnapshotIDRows',0, ...
                'MissingDirectionRows',0,'InvalidDirectionRows',0, ...
                'RepeatedIdentityRows',0,'ConflictingIdentityRows',0, ...
                'Groups',repmat(localGroup("",""),0,1));
        end

        function state=observe(state,T)
            assert(isstruct(state)&&isscalar(state)&& ...
                state.ContractVersion=="sixgr.diagnostic.radio_clock/v1" && istable(T), ...
                'sixgr:truth:DiagnosticClockContractInput','Use initialized state and a table chunk.');
            n=height(T); if n==0, return; end
            offset=state.RowsChecked;
            numericNames=["SFN","CarrierNFrame","CarrierNSlot","SCS_kHz", ...
                "SlotsPerFrame","AbsoluteSlot","RuntimeAbsoluteSlotIndex0","Slot"];
            textNames=["SFNSource","SlotConvention","AbsoluteSlotConvention","AbsoluteSlotSource"];
            numbers=nan(n,numel(numericNames)); texts=strings(n,numel(textNames));
            invalid=false(n,1); conflict=false(n,1); reasons=strings(n,1);
            for k=1:numel(numericNames)
                [numbers(:,k),bad]=localNumber(T,numericNames(k));
                invalid=invalid|bad; reasons=localReason(reasons,bad,"malformed_"+numericNames(k));
            end
            for k=1:numel(textNames)
                [texts(:,k),bad]=localText(T,textNames(k));
                invalid=invalid|bad; reasons=localReason(reasons,bad,"malformed_"+textNames(k));
            end
            [direction,bad]=localText(T,"Direction");
            invalid=invalid|bad; reasons=localReason(reasons,bad,"malformed_Direction");
            direction=upper(direction);
            [snapshot,bad]=localText(T,"SnapshotID");
            invalid=invalid|bad; reasons=localReason(reasons,bad,"malformed_SnapshotID");
            missingID=strlength(snapshot)==0; missingDirection=strlength(direction)==0;
            badDirection=~missingDirection & ~ismember(direction,["DL","UL"]);
            invalid=invalid|badDirection;
            reasons=localReason(reasons,badDirection,"unsupported_Direction");
            reasons=localReason(reasons,missingID,"missing_SnapshotID");
            reasons=localReason(reasons,missingDirection,"missing_Direction");
            state.MissingSnapshotIDRows=state.MissingSnapshotIDRows+sum(missingID);
            state.MissingDirectionRows=state.MissingDirectionRows+sum(missingDirection);
            state.InvalidDirectionRows=state.InvalidDirectionRows+sum(badDirection);
            sfn=numbers(:,1); frame=numbers(:,2); slot=numbers(:,3);
            scs=numbers(:,4); perFrame=numbers(:,5); absolute=numbers(:,6);
            runtime=numbers(:,7); reportSlot=numbers(:,8);
            bad=isfinite(sfn)&sfn>=1024;
            invalid=invalid|bad; reasons=localReason(reasons,bad,"SFN_out_of_range");
            bad=isfinite(perFrame)&perFrame==0;
            invalid=invalid|bad; reasons=localReason(reasons,bad,"SlotsPerFrame_must_be_positive");
            % NR clock arithmetic only. This does not validate a band's
            % legal SCS or call an experimental numerology NR compliant.
            supportedSCS=ismember(scs,[15 30 60 120 240 480 960]);
            unsupported=isfinite(scs)&~supportedSCS;
            reasons=localReason(reasons,unsupported,"unsupported_NR_clock_numerology");
            bad=supportedSCS&isfinite(perFrame)&perFrame~=10.*scs./15;
            conflict=conflict|bad; reasons=localReason(reasons,bad,"SCS_SlotsPerFrame_conflict");
            % An absent export is not backfilled. Mathematical consistency
            % can still be checked against an explicitly declared NR SCS.
            arithmeticPerFrame=perFrame;
            derive=~isfinite(perFrame)&supportedSCS;
            arithmeticPerFrame(derive)=10.*scs(derive)./15;
            bad=isfinite(sfn)&isfinite(frame)&sfn~=mod(frame,1024);
            conflict=conflict|bad; reasons=localReason(reasons,bad,"SFN_CarrierNFrame_conflict");
            bad=isfinite(absolute)&isfinite(runtime)&absolute~=runtime;
            conflict=conflict|bad; reasons=localReason(reasons,bad,"absolute_runtime_conflict");
            % Validate every declared epoch, even if another mandatory
            % operand/source is absent. No NaN can mask a finite conflict.
            for epoch=[6 7]
                value=numbers(:,epoch); ready=isfinite(value)&isfinite(arithmeticPerFrame)&arithmeticPerFrame>0;
                bad=ready&isfinite(slot)&mod(value,arithmeticPerFrame)~=mod(slot,arithmeticPerFrame);
                conflict=conflict|bad; reasons=localReason(reasons,bad,numericNames(epoch)+"_CarrierNSlot_conflict");
                bad=ready&isfinite(sfn)&mod(floor(value./arithmeticPerFrame),1024)~=sfn;
                conflict=conflict|bad; reasons=localReason(reasons,bad,numericNames(epoch)+"_SFN_conflict");
                bad=ready&isfinite(frame)&mod(floor(value./arithmeticPerFrame),1024)~=mod(frame,1024);
                conflict=conflict|bad; reasons=localReason(reasons,bad,numericNames(epoch)+"_CarrierNFrame_conflict");
            end
            absoluteConvention=texts(:,3); slotConvention=texts(:,2);
            bad=strlength(absoluteConvention)>0 & absoluteConvention~="zero_based_absolute_slot";
            invalid=invalid|bad; reasons=localReason(reasons,bad,"unsupported_absolute_slot_convention");
            allowed=["","one_based_absolute_slot","zero_based_absolute_slot", ...
                "one_based_slot_within_frame","zero_based_slot_within_frame","independent_trial_index"];
            bad=~ismember(slotConvention,allowed);
            invalid=invalid|bad; reasons=localReason(reasons,bad,"unsupported_report_slot_convention");
            bad=isfinite(reportSlot)&reportSlot==0 & ...
                ismember(slotConvention,["one_based_absolute_slot","one_based_slot_within_frame"]);
            invalid=invalid|bad; reasons=localReason(reasons,bad,"one_based_report_slot_zero");
            bad=isfinite(reportSlot)&isfinite(perFrame)&perFrame>0 & ...
                ((slotConvention=="one_based_slot_within_frame"&reportSlot>perFrame) | ...
                (slotConvention=="zero_based_slot_within_frame"&reportSlot>=perFrame));
            invalid=invalid|bad; reasons=localReason(reasons,bad,"report_slot_outside_frame");
            for epoch=[6 7]
                value=numbers(:,epoch); ready=isfinite(reportSlot)&isfinite(value);
                bad=ready & ((slotConvention=="one_based_absolute_slot" & reportSlot~=value+1) | ...
                    (slotConvention=="zero_based_absolute_slot" & reportSlot~=value));
                conflict=conflict|bad; reasons=localReason(reasons,bad,"report_slot_absolute_origin_conflict");
                ready=ready&isfinite(perFrame)&perFrame>0;
                bad=ready & ((slotConvention=="one_based_slot_within_frame" & reportSlot~=mod(value,perFrame)+1) | ...
                    (slotConvention=="zero_based_slot_within_frame" & reportSlot~=mod(value,perFrame)));
                conflict=conflict|bad; reasons=localReason(reasons,bad,"report_slot_frame_origin_conflict");
            end
            carrierReady=all(isfinite(numbers(:,1:5)),2)&supportedSCS & ...
                texts(:,1)=="executed_nrCarrierConfig_NFrame_mod1024";
            declaredRadioSlot=ismember(slotConvention,allowed(2:5));
            radioSlotReady=~declaredRadioSlot|isfinite(reportSlot);
            knownAbsoluteSource=ismember(texts(:,4), ...
                ["executed_runtime_absolute_slot_index0","bound_runtime_AbsoluteSlotIndex0"]);
            absoluteReady=carrierReady&isfinite(absolute)&radioSlotReady& ...
                absoluteConvention=="zero_based_absolute_slot"&knownAbsoluteSource;
            reasons=localReason(reasons,~carrierReady,"missing_or_unrecognized_carrier_clock_provenance");
            reasons=localReason(reasons,~radioSlotReady,"missing_declared_radio_slot");
            reasons=localReason(reasons,~absoluteReady,"missing_absolute_clock_provenance");
            keys=unique([direction snapshot],'rows','stable');
            for k=1:size(keys,1)
                mask=direction==keys(k,1)&snapshot==keys(k,2);
                rows=find(mask);
                hit=find(string({state.Groups.Direction})==keys(k,1)& ...
                    string({state.Groups.SnapshotID})==keys(k,2),1);
                if isempty(hit)
                    state.Groups(end+1,1)=localGroup(keys(k,1),keys(k,2));
                    hit=numel(state.Groups);
                end
                g=state.Groups(hit);
                hasIdentity=strlength(keys(k,1))>0&&strlength(keys(k,2))>0&& ...
                    ismember(keys(k,1),["DL","UL"]);
                repeated=(numel(rows)-double(g.RowsChecked==0))*double(hasIdentity);
                state.RepeatedIdentityRows=state.RepeatedIdentityRows+repeated;
                % Keep one first-declared tuple; repeated coefficient/panel
                % rows are expected, not new independent observations.
                clash=false(numel(rows),1);
                if hasIdentity
                for j=1:size(numbers,2)
                    values=numbers(rows,j); finite=isfinite(values);
                    if j==8
                        % Only a declared radio-slot convention makes the
                        % report Slot part of this clock tuple. Frame stays
                        % independent and is never read by this validator.
                        finite=finite&ismember(slotConvention(rows),allowed(2:5));
                    end
                    if isnan(g.FirstNumeric(j)) && any(finite)
                        g.FirstNumeric(j)=values(find(finite,1));
                    end
                    clash=clash|(finite&values~=g.FirstNumeric(j));
                end
                for j=1:size(texts,2)
                    values=texts(rows,j); present=strlength(values)>0;
                    if strlength(g.FirstText(j))==0 && any(present)
                        g.FirstText(j)=values(find(present,1));
                    end
                    clash=clash|(present&values~=g.FirstText(j));
                end
                % Complementary partial rows can contradict across fields
                % even when no individual row contains the whole tuple.
                % This checks claims only; it never qualifies missing rows.
                if localTupleConflict(g.FirstNumeric,g.FirstText)
                    clash(:)=true;
                end
                end
                conflict(rows)=conflict(rows)|clash;
                reasons(rows)=localReason(reasons(rows),clash,"snapshot_clock_tuple_conflict");
                state.ConflictingIdentityRows=state.ConflictingIdentityRows+sum(clash);
                good=~invalid(rows)&~conflict(rows)&~missingID(rows)&~missingDirection(rows);
                consistent=good&absoluteReady(rows);
                g.RowsChecked=g.RowsChecked+numel(rows);
                g.InvalidRows=g.InvalidRows+sum(invalid(rows));
                g.ConflictRows=g.ConflictRows+sum(conflict(rows)&~invalid(rows));
                g.ConsistentRows=g.ConsistentRows+sum(consistent);
                g.UnavailableRows=g.UnavailableRows+sum(good&~absoluteReady(rows) | ...
                    (~invalid(rows)&~conflict(rows)&(missingID(rows)|missingDirection(rows))));
                g.CarrierClockConsistentRows=g.CarrierClockConsistentRows+sum(good&carrierReady(rows));
                issue=find(~consistent,1);
                if isnan(g.FirstIssueRow)&&~isempty(issue), g.FirstIssueRow=offset+rows(issue); end
                g.Reasons=unique([g.Reasons;reasons(rows(strlength(reasons(rows))>0))],'stable');
                state.Groups(hit)=g;
            end
            state.RowsChecked=state.RowsChecked+n;
            state.MaxChunkRows=max(state.MaxChunkRows,n);
        end

        function summary=summarize(state)
            summary=state;
            for k=1:numel(summary.Groups)
                g=summary.Groups(k);
                if g.InvalidRows>0, status="invalid";
                elseif g.ConflictRows>0, status="conflict";
                elseif g.UnavailableRows>0||g.RowsChecked==0, status="unavailable";
                else, status="consistent";
                end
                summary.Groups(k).Status=status;
                summary.Groups(k).RadioClockSourceContractConsistent=status=="consistent";
            end
            summary.RadioClockSourceContractConsistent=state.RowsChecked>0 && ...
                all([summary.Groups.RadioClockSourceContractConsistent]);
            summary.QualificationScope="exported_clock_contract_only_not_PHY_or_standards_conformance";
        end
    end
end

function g=localGroup(direction,snapshot)
g=struct('Direction',string(direction),'SnapshotID',string(snapshot), ...
    'RowsChecked',0,'ConsistentRows',0,'UnavailableRows',0,'InvalidRows',0, ...
    'ConflictRows',0,'CarrierClockConsistentRows',0,'FirstIssueRow',NaN, ...
    'FirstNumeric',nan(1,8),'FirstText',strings(1,4),'Reasons',strings(0,1), ...
    'Status',"unavailable",'RadioClockSourceContractConsistent',false);
end

function [values,bad]=localNumber(T,name)
n=height(T); values=nan(n,1); bad=false(n,1);
if ~ismember(name,string(T.Properties.VariableNames)), return; end
raw=T.(name);
if isnumeric(raw) && isequal(size(raw),[n 1])
    values=double(raw); missing=isnan(real(values))&imag(values)==0;
elseif (isstring(raw)||iscellstr(raw)||ischar(raw)) %#ok<ISCLSTR>
    [text,bad]=localText(T,name);
    missing=ismember(lower(text),["","nan","missing","<missing>"]);
    values=str2double(text);
else
    bad(:)=true; return;
end
bad=bad|(~missing & (~isfinite(values)|imag(values)~=0|real(values)<0| ...
    real(values)~=fix(real(values))|real(values)>flintmax-1));
% The safe exported integer domain is [0,2^53-1]. Rejecting the boundary
% 2^53 also catches uint64/decimal integers rounded onto it during parsing.
values=real(values); values(missing|bad)=NaN;
end

function conflict=localTupleConflict(v,t)
conflict=false;
sfn=v(1); frame=v(2); slot=v(3); scs=v(4); perFrame=v(5);
supported=ismember(scs,[15 30 60 120 240 480 960]);
if supported&&isfinite(perFrame)&&perFrame~=10*scs/15, conflict=true; end
if ~isfinite(perFrame)&&supported, perFrame=10*scs/15; end
if all(isfinite([sfn frame]))&&sfn~=mod(frame,1024), conflict=true; end
if all(isfinite(v(6:7)))&&v(6)~=v(7), conflict=true; end
for epoch=v(6:7)
    if ~isfinite(epoch), continue; end
    if isfinite(v(8))
        if t(2)=="one_based_absolute_slot"&&v(8)~=epoch+1, conflict=true; end
        if t(2)=="zero_based_absolute_slot"&&v(8)~=epoch, conflict=true; end
    end
    if ~isfinite(perFrame)||perFrame<=0, continue; end
    if isfinite(slot)&&mod(epoch,perFrame)~=mod(slot,perFrame), conflict=true; end
    if isfinite(sfn)&&mod(floor(epoch/perFrame),1024)~=sfn, conflict=true; end
    if isfinite(frame)&&mod(floor(epoch/perFrame),1024)~=mod(frame,1024), conflict=true; end
    if isfinite(v(8))
        if t(2)=="one_based_slot_within_frame"&&v(8)~=mod(epoch,perFrame)+1, conflict=true; end
        if t(2)=="zero_based_slot_within_frame"&&v(8)~=mod(epoch,perFrame), conflict=true; end
    end
end
end

function [values,bad]=localText(T,name)
n=height(T); values=strings(n,1); bad=false(n,1);
if ~ismember(name,string(T.Properties.VariableNames)), return; end
raw=T.(name);
if ~(isstring(raw)||iscellstr(raw)||ischar(raw)) %#ok<ISCLSTR>
    bad(:)=true; return;
end
text=string(raw);
if ~isequal(size(text),[n 1]), bad(:)=true; return; end
text(ismissing(text))=""; values=strtrim(text);
end

function reasons=localReason(reasons,mask,value)
% One diagnostic per row, no raw row retention. Status/counters preserve
% other failure classes even when the first reason was already selected.
mask=mask&strlength(reasons)==0; reasons(mask)=value;
end
