function evidence=assertNoScheduledPUSCHOverlap(state,cfg,ue,targetSlot,symbolAllocation)
% gNB control-TX authority, independent of whether the UE accepted that DCI.
% This proves only absence of an overlapping scheduled PUSCH, not a UCI RX.
validateattributes(symbolAllocation,{'numeric'},{'vector','numel',2,'real','finite','integer','nonnegative'});
carrier=sixgr.phy.grid.makeCarrier(cfg);
assert(symbolAllocation(2)>0 && sum(symbolAllocation)<=carrier.SymbolsPerSlot, ...
    'sixgr:truth:InvalidPUCCHOverlapSymbols','Use a nonempty in-slot PUCCH symbol interval.');
owner=state.SharedWaveformStream;
controls=owner.readTransmittedULControls(ue,targetSlot);
identity=cfg.phy.frame.DefaultIdentity;
ids=strings(numel(controls),1);
for k=1:numel(controls)
    r=controls{k}; g=r.Binding.Grant; t=g.TimingDecision;
    assert(g.UEIndex==ue && g.RNTI==cfg.phy.pusch.RNTI && ...
        string(t.ScheduledCCID)==string(identity.ScheduledCCID) && ...
        string(t.TargetBWPID)==string(identity.ULBWPID), ...
        'sixgr:truth:UnresolvedCrossCarrierUCIOverlap','Cross-carrier/BWP transport ownership needs explicit resolution.');
    symbols=g.SymbolAllocation;
    overlap=symbols(1)<sum(symbolAllocation) && symbolAllocation(1)<sum(symbols);
    assert(~overlap,'sixgr:truth:UnresolvedScheduledPUSCHReceiveHypothesis', ...
        'A physically transmitted UL command schedules overlapping PUSCH; resolve independent PUCCH/PUSCH reception before committing HARQ.');
    ids(k)=r.ObservationID;
end
evidence=struct('UEIndex',ue,'TargetSlot',targetSlot,'PUCCHSymbolAllocation',double(symbolAllocation), ...
    'NonoverlappingULControlObservationIDs',ids,'OverlappingPUSCHCount',0, ...
    'CheckedAtSample',owner.Events.NextSampleIndex, ...
    'Source',"physical_gNB_control_TX_ledger_not_UE_command_acceptance");
end
