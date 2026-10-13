function ok=testSIB1CORESETFrequencyAuthority()
% Independent bit vectors and actual RE coordinates; not a BLER campaign.
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig('NSizeGrid',273,'NStartGrid',0,'SubcarrierSpacing',30);
cfg=struct('phy',struct('mib',struct('dmrsTypeAPosition',2), ...
    'sib1',struct('resolvedCORESET0',struct('RBStart',126,'NumRB',24))));
[tx,pdsch]=sixgr.phy.broadcast.buildSIB1DCI10(carrier,cfg, ...
    'PRBStart',0,'PRBCount',24,'SymbolStart',2,'NumSymbols',7,'MCSIndex',2);
% TS 38.214 type-1 RIV at full allocation N=L=24 gives RIV=47.
expected=[dec2bin(47,9) dec2bin(3,4) '0' dec2bin(2,5) '00' '0' repmat('0',1,15)];
assert(numel(tx.Bits)==37 && isequal(tx.Bits,int8(expected(:)-'0')));
assert(tx.RIV==47 && tx.PRBStartBWPRelative==0 && tx.PRBStart==126);
assert(isequal(pdsch.PRBSet,126:149));
indices=double(nrPDSCHIndices(carrier,pdsch));
prbs=floor(mod(indices-1,12*273)/12);
assert(isequal(unique(prbs(:)).',126:149));
poisoned=cfg;
poisoned.initial_access.sib1.pdsch=struct('prb_start',0,'num_prb',273,'mcs',9);
[rx,recovered]=sixgr.phy.broadcast.buildSIB1DCI10(carrier,poisoned,'Bits',tx.Bits);
assert(rx.RIV==47 && isequal(recovered.PRBSet,pdsch.PRBSet));
carrier.NStartGrid=7;
[~,shifted]=sixgr.phy.broadcast.buildSIB1DCI10(carrier,cfg,'Bits',tx.Bits);
assert(isequal(shifted.PRBSet,119:142));
localReject(@()sixgr.phy.broadcast.buildSIB1DCI10(carrier,cfg,'Bits',[tx.Bits;zeros(7,1)]), ...
    'sixgr:phy:pdcch:payload_length_mismatch');
localReject(@()sixgr.phy.broadcast.buildSIB1DCI10(carrier,cfg,'PRBStart',1,'PRBCount',24), ...
    'sixgr:phy:broadcast:SIB1AllocationOutsideBWP');
cfg.phy.sib1=rmfield(cfg.phy.sib1,'resolvedCORESET0');
localReject(@()sixgr.phy.broadcast.buildSIB1DCI10(carrier,cfg), ...
    'sixgr:phy:broadcast:MissingSIB1CORESET0');
ok=true;
fprintf('SIB1_CORESET_FREQUENCY_AUTHORITY_PASS\n');
end
function localReject(action,identifier)
try, action(); catch cause
    assert(strcmp(cause.identifier,identifier),'Expected %s; received %s.',identifier,cause.identifier);
    return;
end
error('test:SIB1MissingRejection','Expected %s.',identifier);
end
