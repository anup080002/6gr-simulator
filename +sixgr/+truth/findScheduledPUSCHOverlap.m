function [overlapping,evidence]=findScheduledPUSCHOverlap(state,cfg,ue,targetSlot,symbolAllocation)
% gNB control-TX authority, independent of whether the UE accepted that DCI.
% This inventories actual scheduled overlap, not UE detection or UCI reception.
validateattributes(symbolAllocation,{'numeric'},{'vector','numel',2,'real','finite','integer','nonnegative'});
carrier=sixgr.phy.grid.makeCarrier(cfg);
assert(symbolAllocation(2)>0 && sum(symbolAllocation)<=carrier.SymbolsPerSlot, ...
    'sixgr:truth:InvalidPUCCHOverlapSymbols','Use a nonempty in-slot PUCCH symbol interval.');
owner=state.SharedWaveformStream;
controls=owner.readTransmittedULControls(ue,targetSlot);
identity=cfg.phy.frame.DefaultIdentity;
ids=strings(0,1); overlapping=cell(0,1);
for k=1:numel(controls)
    r=controls{k}; g=r.Binding.Grant; t=g.TimingDecision;
    assert(g.UEIndex==ue && g.RNTI==cfg.phy.pusch.RNTI && ...
        string(t.ScheduledCCID)==string(identity.ScheduledCCID) && ...
        string(t.TargetBWPID)==string(identity.ULBWPID), ...
        'sixgr:truth:UnresolvedCrossCarrierUCIOverlap','Cross-carrier/BWP transport ownership needs explicit resolution.');
    symbols=g.SymbolAllocation;
    overlap=symbols(1)<sum(symbolAllocation) && symbolAllocation(1)<sum(symbols);
    if overlap
        overlapping{end+1,1}=r; %#ok<AGROW>
    else
        ids(end+1,1)=r.ObservationID; %#ok<AGROW>
    end
end
evidence=struct('UEIndex',ue,'TargetSlot',targetSlot,'PUCCHSymbolAllocation',double(symbolAllocation), ...
    'NonoverlappingULControlObservationIDs',ids,'OverlappingPUSCHCount',numel(overlapping), ...
    'CheckedAtSample',owner.Events.NextSampleIndex, ...
    'Source',"physical_gNB_control_TX_ledger_not_UE_command_acceptance");
end
