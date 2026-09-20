function [eligible, evidence] = resolveCSIReceiveReferenceEvidence(state,cfg,ue,servingCell,calendar,targetSlot)
%RESOLVECSIRECEIVEREFERENCEEVIDENCE Bind configured CSI occasions to RX evidence.
% A periodic calendar row is only a receive obligation when a causal,
% completed CSI-RS receiver observation exists in the active sweep.  This
% function intentionally does not inspect pending CSI reports or UE payload
% bits; those are producer state and would be a receiver oracle.

validateattributes(ue,{'numeric'},{'scalar','real','finite','integer','positive'});
validateattributes(servingCell,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
validateattributes(targetSlot,{'numeric'},{'scalar','real','finite','integer','positive'});
assert(istable(calendar),'sixgr:truth:InvalidCSIReceiveCalendar', ...
    'The installed CSI receive calendar must be a table.');

eligible=false(height(calendar),1);
evidence=table();
if isempty(calendar)
    return;
end
assert(ismember('CSIReferenceSlot',calendar.Properties.VariableNames), ...
    'sixgr:truth:InvalidCSIReceiveCalendar', ...
    'The installed CSI calendar must identify its CSI reference slot.');

retained=sixgr.util.structGet(state,'ControlTrials.CSIRS',table());
if ~istable(retained) || isempty(retained)
    return;
end
required={'UEIndex','ServingCell','Slot'};
assert(all(ismember(required,retained.Properties.VariableNames)), ...
    'sixgr:truth:CSIRSProducerSchemaIncomplete', ...
    'CSI receive evidence must identify UE, serving cell and source slot.');
first=sixgr.util.structGet(state,'SweepPointStartSlot',1);
validateattributes(first,{'numeric'},{'scalar','real','finite','integer','positive'});
shared=isa(sixgr.util.structGet(state,'SharedWaveformStream',[]), ...
    'sixgr.truth.CoupledWaveformStream');

selectedRows=zeros(0,1);
for ci=1:height(calendar)
    reference=double(calendar.CSIReferenceSlot(ci));
    if ~(isfinite(reference) && reference==fix(reference) && ...
            reference>=first && reference<=targetSlot)
        continue;
    end
    candidates=find(double(retained.UEIndex)==double(ue) & ...
        double(retained.ServingCell)==double(servingCell) & ...
        double(retained.Slot)>=double(first) & double(retained.Slot)<=reference);
    best=0;
    bestSlot=-Inf;
    for ri=reshape(candidates,1,[])
        candidate=retained(ri,:);
        [availableSlot,usable,clocked]=sixgr.truth.csirsMeasurementAvailability(candidate,shared);
        usable=usable && availableSlot<=targetSlot && ...
            ~sixgr.truth.isCSIReportingMeasurementGap(cfg,double(candidate.Slot));
        if shared
            usable=usable && clocked;
        end
        if usable && double(candidate.Slot)>=bestSlot
            best=ri;
            bestSlot=double(candidate.Slot);
        end
    end
    if best>0
        eligible(ci)=true;
        selectedRows(end+1,1)=best; %#ok<AGROW>
    end
end
if ~isempty(selectedRows)
    evidence=retained(selectedRows,:);
end
end
