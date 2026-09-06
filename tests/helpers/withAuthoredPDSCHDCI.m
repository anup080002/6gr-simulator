function grant = withAuthoredPDSCHDCI(cfg, grant)
%WITHAUTHOREDPDSCHDCI Actual packed DCI for a TX-only unit fixture.
% No PDCCH reception is claimed. The fixture supplies HARQ and K0; this
% helper binds its explicit timing and calls the production DCI packer.
carrier = sixgr.phy.grid.makeCarrier(cfg);
slot = double(carrier.NFrame)*double(carrier.SlotsPerFrame) + double(carrier.NSlot);
timing = sixgr.pdsch.resolveSchedulerPDSCHTiming(grant, slot);
if ~isfield(grant, 'TimingDecision')
    grant.TimingDecision = struct('Valid',true,'IndexConvention',"zero_based", ...
        'ControlAbsoluteSlot',timing.PDCCHAbsoluteSlot,'DataAbsoluteSlot',slot, ...
        'K0',timing.K0);
end
if ~isfield(grant, 'K1')
    % Codec-only fixture. No feedback waveform or processing time is claimed.
    grant.K1 = 4;
end
assert(isfield(grant,'HARQ'),'TX fixture must declare its HARQ process/NDI/RV.');
sch = sixgr.l2.mac.SchedulerPF(cfg, 'Direction','DL');
grant.DCI = sch.buildDCIBitfield(grant);
grant.ControlDecodeOk = false;
grant.PDCCHGrantBindingOk = false;
end
