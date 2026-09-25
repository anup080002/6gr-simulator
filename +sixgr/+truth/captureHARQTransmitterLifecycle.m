function T=captureHARQTransmitterLifecycle(state)
% Snapshot actual TX-side HARQ events without inventing receiver outcomes.
% Archived points are immutable: the caller captures before replacing the
% HARQ entities at an independent sweep boundary. Reading is non-mutating.
T=sixgr.util.structGet(state,'HARQTransmitterLifecycleArchive',table());
assert(istable(T),'sixgr:truth:InvalidHARQLifecycleArchive');
for field=["DLHarq","ULHarq"]
    entity=sixgr.util.structGet(state,field,[]);
    if isempty(entity), continue; end
    assert(isa(entity,'sixgr.l2.mac.HARQEntity'), ...
        'sixgr:truth:InvalidHARQLifecycleOwner');
    current=entity.getTransmitterLifecycle();
    if isempty(current), continue; end
    point=double(sixgr.util.structGet(state,'CurrentSweepPointIndex',NaN));
    snr=double(sixgr.util.structGet(state,'CurrentSNR_dB',NaN));
    assert(isscalar(point) && isfinite(point) && point>=1 && point==fix(point), ...
        'sixgr:truth:HARQLifecycleSweepIdentityMissing');
    current.SweepPointIndex=repmat(point,height(current),1);
    current.ConfiguredSNR_dB=repmat(snr,height(current),1);
    if isempty(T), T=current; else, T=[T;current]; end %#ok<AGROW>
end
end
