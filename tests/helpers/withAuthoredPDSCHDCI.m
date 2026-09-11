function grant = withAuthoredPDSCHDCI(cfg, grant)
%WITHAUTHOREDPDSCHDCI Actual packed DCI for a TX-only unit fixture.
% No PDCCH reception is claimed. The fixture supplies HARQ and K0; this
% helper binds its explicit timing and calls the production DCI packer.
carrier = sixgr.phy.grid.makeCarrier(cfg);
slot = double(carrier.NFrame)*double(carrier.SlotsPerFrame) + double(carrier.NSlot);
timing = sixgr.pdsch.resolveSchedulerPDSCHTiming(grant, slot);
assert(isfield(grant,'HARQ'),'TX fixture must declare its HARQ process/NDI/RV.');
sch = sixgr.l2.mac.SchedulerPF(cfg, 'Direction','DL');
grant.ControlAbsoluteSlot=timing.PDCCHAbsoluteSlot;
grant=sch.attachCanonicalTimingDecision(grant);
assert(grant.ScheduledAbsoluteSlot==slot, ...
    'The authored fixture must retain its explicitly selected data occasion.');
grant.DCI = sch.buildDCIBitfield(grant);
grant.ControlDecodeOk = false;
grant.PDCCHGrantBindingOk = false;
end
