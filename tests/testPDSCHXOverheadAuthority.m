function ok=testPDSCHXOverheadAuthority()
% TS 38.214 V18.7.0 5.1.3.2: higher-layer N_oh is not a collision count.
cfg.phy.pdsch.symbolAllocation=[0 14];
cfg.phy.ssb=struct('enable',true,'symbolLocations',0:3,'scs_kHz',30);
cfg.phy.csirs=struct('enable',true,'symbolLocations',[4 8]);
cfg.phy.carrier.SubcarrierSpacing=15;
assert(sixgr.phy.dl.resolvePDSCHXOverhead(cfg,[0 14])==0, ...
    'Absent xOverhead must be zero, not guessed from SSB/CSI-RS symbols.');
for value=[0 6 12 18]
    cfg.phy.pdsch.xOverhead=value;
    assert(sixgr.phy.dl.resolvePDSCHXOverhead(cfg,[0 14])==value);
    assert(sixgr.phy.dl.resolvePDSCHXOverhead(cfg,[7 4])==value);
end
cfg.phy.pdsch=rmfield(cfg.phy.pdsch,'xOverhead');
cfg.phy.pdsch.XOverhead=12;
assert(sixgr.phy.dl.resolvePDSCHXOverhead(cfg,[0 14])==12);
cfg.phy.pdsch.xOverhead=6;
reject(@()sixgr.phy.dl.resolvePDSCHXOverhead(cfg,[0 14]), ...
    'sixgr:phy:dl:ConflictingPDSCHXOverhead');
cfg.phy.pdsch=rmfield(cfg.phy.pdsch,'XOverhead');
for invalid={NaN,Inf,-1,1,6.1,[6 12],'6'}
    cfg.phy.pdsch.xOverhead=invalid{1};
    reject(@()sixgr.phy.dl.resolvePDSCHXOverhead(cfg,[0 14]), ...
        'sixgr:phy:dl:InvalidPDSCHXOverhead');
end
ok=true;
fprintf('PDSCH_XOVERHEAD_AUTHORITY_PASS absent_zero=1 configured_values=4 invalid_rejected=7\n');
end

function reject(fn,id)
try, fn(); catch cause, assert(strcmp(cause.identifier,id),cause.message); return; end
error('test:ExpectedRejection','Expected %s.',id);
end
