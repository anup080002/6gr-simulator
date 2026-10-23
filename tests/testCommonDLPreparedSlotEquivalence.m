function ok=testCommonDLPreparedSlotEquivalence()
setup6GRSimToolkit('Verbose',false);
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_4ghz_20mhz_64txru_4rx_cdlc100_impaired.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
reference=sixgr.phy.frame.CommonDLResourcePlan(cfg);
before=rng;
for slot0=[0 1 2 3 5 8 11 20]
    prepared=reference.prepareSlot(slot0);
    assert(isequal(prepared.controlReservations(slot0),reference.controlReservations(slot0)));
    % Off-slot calls must NOT reuse an earlier reservation snapshot.
    assert(isequal(prepared.controlReservations(slot0+1),reference.controlReservations(slot0+1)));
    for prb=[0 32 33 72 73 105]
        request=struct('PRBStart',prb,'NumPRB',1,'SymbolStart',0,'NumSymbols',14);
        [a,b]=reference.checkPDSCH(request,slot0);
        [c,d]=prepared.checkPDSCH(request,slot0);
        assert(isequaln(a,c) && isequaln(b,d));
    end
end
assert(isequal(before,rng));
assert(isnan(reference.PreparedSlot0),'Preparing a value snapshot must not mutate its source.');
ok=true; disp('COMMON_DL_PREPARED_SLOT_EQUIVALENCE_PASS');
end
