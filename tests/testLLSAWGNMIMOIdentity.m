function ok=testLLSAWGNMIMOIdentity()
% Explicit AWGN channel must preserve all MIMO connector dimensions.
[cfg,~]=sixgr.lls.loadConfig('configs/lls/pdsch_reference.yaml');
cfg.channel.model='AWGN'; cfg.channel.txAntennas=4; cfg.channel.rxAntennas=4;
cfg.antenna.enabled=false;
carrier=nrCarrierConfig;
carrier.NSizeGrid=cfg.carrier.nSizeGrid;
carrier.SubcarrierSpacing=cfg.carrier.subcarrierSpacingKHz;
x=complex(ones(128,4));
[y,h,info]=sixgr.lls.applyChannel(x,carrier,cfg,19);
assert(isequal(y,x) && isequal(size(h),[carrier.NSizeGrid*12 carrier.SymbolsPerSlot 4 4]));
assert(info.AntennaTxLogicalPorts==4 && info.AntennaRxPhysicalElements==4);
for tx=1:4
    for rx=1:4
        value=double(rx==tx);
        assert(all(h(:,:,rx,tx)==value,'all'));
    end
end
cfg.channel.rxAntennas=2;
localReject(@()sixgr.lls.applyChannel(x,carrier,cfg,19), ...
    'sixgr:lls:AWGNIdentityDimensions');
cfg.channel.rxAntennas=4; cfg.channel.txAntennas=2;
localReject(@()sixgr.lls.applyChannel(x,carrier,cfg,19), ...
    'sixgr:lls:AWGNIdentityDimensions');
ok=true; fprintf('LLS_AWGN_MIMO_IDENTITY_PASS\n');
end

function localReject(fn,id)
try
    fn();
catch ME
    assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s', ...
        id,ME.identifier,ME.message);
    return
end
error('test:MissingRejection','Expected %s.',id);
end
