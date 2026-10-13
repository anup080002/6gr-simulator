function ok = testPDSCHDMRSReservationAuthority()
% Port identity, not rank alone, determines the required CDM reservation.
setup6GRSimToolkit('Verbose',false);
carrier=nrCarrierConfig('NSizeGrid',273,'SubcarrierSpacing',30);
% Type, ports, enhanced, groups, expected-valid. Nonconsecutive/high ports
% prevent replacing this check with a rank-only heuristic.
cases={1,0,false,1,true; 1,[0 1],false,1,true; ...
    1,2,false,1,false; 1,[0 2],false,1,false; ...
    1,0:3,false,1,false; 1,0:3,false,2,true; ...
    2,4,false,2,false; 2,[4 5],false,3,true; ...
    1,8,true,1,true; 1,10,true,1,false; 1,[0 10],true,2,true};
for k=1:size(cases,1)
    type=cases{k,1}; ports=cases{k,2}; enhanced=cases{k,3}; groups=cases{k,4};
    cfg=localConfig(type,ports,enhanced,groups);
    before=cfg;
    mode="basic"; if enhanced, mode="enhanced"; end
    validator=@()sixgr.pdsch.PDSCHDMRSValidator.resolvePortSet( ...
        type,1,mode,ports,'NumLayers',numel(ports),'NumCDMGroupsWithoutData',groups);
    factory=@()sixgr.phy.grid.pdschConfigFromConfig(carrier,cfg);
    if cases{k,5}
        actual=validator(); native=factory();
        assert(isequal([actual.CDMGroupLambda],native.DMRS.CDMGroups));
        assert(isequal(native.DMRS.DMRSPortSet,ports) && ...
            native.DMRS.NumCDMGroupsWithoutData==groups);
    else
        localReject(validator); localReject(factory);
    end
    assert(isequaln(cfg,before),'Validation must not repair explicit configuration silently.');
end
% Independently count occupied REs: 14 symbols, three type-1 DMRS symbols,
% six RE per reserved group per PRB. No other reference exclusions here.
for groups=1:2
    cfg=localConfig(1,0,false,groups);
    [indices,info,pdsch]=sixgr.phy.grid.allocREsPDSCH(carrier,cfg);
    expectedNRE=14*12-3*6*groups;
    assert(info.NREPerPRB==expectedNRE && info.G==273*expectedNRE*2);
    assert(size(indices,1)==273*expectedNRE);
    native=nrPDSCHConfig('PRBSet',0:272,'SymbolAllocation',[0 14],'Modulation','QPSK');
    native.DMRS.DMRSPortSet=0;
    native.DMRS.DMRSAdditionalPosition=2;
    native.DMRS.NumCDMGroupsWithoutData=groups;
    [nativeIndices,nativeInfo]=nrPDSCHIndices(carrier,native);
    assert(isequal(indices,nativeIndices) && info.G==nativeInfo.G);
    assert(nrTBS(pdsch.Modulation,1,273,info.NREPerPRB,0.5)== ...
        nrTBS('QPSK',1,273,expectedNRE,0.5));
end
fprintf('PDSCH_DMRS_RESERVATION_PASS configurations=%d exact_273PRB_allocations=2\n',size(cases,1));
ok=true;
end

function cfg=localConfig(type,ports,enhanced,groups)
cfg=struct();
cfg.phy.pdsch=struct('modulation','QPSK','numLayers',numel(ports), ...
    'prbSet',0:272,'symbolAllocation',[0 14],'mappingType','A','RNTI',1);
cfg.phy.pdsch.dmrs=struct('configurationType',type,'maxLength',1, ...
    'additionalPositions',2,'scheduledPortSet',ports,'enhancedR18',enhanced, ...
    'numCDMGroupsWithoutData',groups);
end

function localReject(fn)
try
    fn();
catch ME
    assert(strcmp(ME.identifier,'sixgr:pdsch:DMRSPortOutsideReservedCDMGroups'), ...
        'Unexpected rejection %s: %s',ME.identifier,ME.message);
    return;
end
error('sixgr:test:MissingRejection','Unreserved scheduled DMRS group was accepted.');
end
