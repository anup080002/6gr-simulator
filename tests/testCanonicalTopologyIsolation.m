function ok=testCanonicalTopologyIsolation()
% Unrelated canonical controls must not change the network population.
% Explicit topology fields may change their own domain, not erase the rest.
cfg=struct();
cfg.frequency.duplex_mode='TDD';
cfg.users=struct('enabled',true,'n_users',4,'rnti_start',201);
cfg.deployment_topology=struct('num_sites',2,'num_sectors_per_site',3, ...
    'num_cells',6,'num_trps',6,'num_ues',4, ...
    'sector_azimuth_offsets_deg',[0 120 240],'sector_azimuths_deg',[0 120 240]);
cfg.scenario.layout=struct('nSites',2,'nSectorsPerSite',3,'nCells',6);
cfg.scenario.ue.nUE=4;
cfg.scenario.sectorization.azimOffsets_deg=[0 120 240];
baseline=sixgr.lls6g.config.normalizeScenarioAliases(cfg);
controls={struct('integration',struct('enabled',true,'run_mode','FIXED_SNR_SWEEP')), ...
    struct('logging',struct('level','DEBUG')), ...
    struct('output',struct('save_csv',true)), ...
    struct('topology',struct()), ...
    struct('topology',struct('site_layout','hexagonal'))};
paths=["users.n_users","users.rnti_start","deployment_topology.num_sites", ...
    "deployment_topology.num_sectors_per_site","deployment_topology.num_cells", ...
    "deployment_topology.num_trps","deployment_topology.num_ues", ...
    "deployment_topology.sector_azimuth_offsets_deg","scenario.layout.nSites", ...
    "scenario.layout.nSectorsPerSite","scenario.layout.nCells", ...
    "scenario.ue.nUE","scenario.sectorization.azimOffsets_deg"];
for k=1:numel(controls)
    changed=cfg; changed.canonical_control=controls{k};
    actual=sixgr.lls6g.config.normalizeScenarioAliases(changed);
    for path=paths
        assert(isequaln(sixgr.util.structGet(actual,path,[]), ...
            sixgr.util.structGet(baseline,path,[])), ...
            'test:CanonicalTopologyMutation','Canonical control %d changed unrelated %s.',k,path);
    end
    repeated=sixgr.lls6g.config.normalizeScenarioAliases(actual);
    localAssertUnchanged(actual,repeated,paths,'second normalization');
end
changed=cfg; changed.canonical_control.topology.num_ues=7;
actual=sixgr.lls6g.config.normalizeScenarioAliases(changed);
assert(actual.users.n_users==7 && actual.deployment_topology.num_ues==7 && ...
    actual.scenario.ue.nUE==7);
localAssertUnchanged(baseline,actual,setdiff(paths, ...
    ["users.n_users","deployment_topology.num_ues","scenario.ue.nUE"]),'UE-only override');

% A TRP count or sector orientation is not authority to replace UE/site counts.
changed=cfg; changed.canonical_control.topology.num_trps=12;
actual=sixgr.lls6g.config.normalizeScenarioAliases(changed);
assert(actual.deployment_topology.num_trps==12);
localAssertUnchanged(baseline,actual,setdiff(paths,"deployment_topology.num_trps"), ...
    'TRP-only override');
changed=cfg; changed.canonical_control.topology.sector_azimuth_offsets_deg=[15 135 255];
actual=sixgr.lls6g.config.normalizeScenarioAliases(changed);
azimuthPaths=["deployment_topology.sector_azimuth_offsets_deg", ...
    "deployment_topology.sector_azimuths_deg","scenario.sectorization.azimOffsets_deg"];
for path=azimuthPaths
    assert(isequal(double(sixgr.util.structGet(actual,path,[])),[15 135 255]));
end
localAssertUnchanged(baseline,actual,setdiff(paths,azimuthPaths),'azimuth-only override');

% Network count overrides derive the network only, preserving other domains.
changed=cfg; changed.canonical_control.topology.num_sites=3;
actual=sixgr.lls6g.config.normalizeScenarioAliases(changed);
assert(actual.deployment_topology.num_sites==3 && ...
    actual.deployment_topology.num_sectors_per_site==3 && actual.deployment_topology.num_cells==9);
localAssertUnchanged(baseline,actual, ...
    ["users.n_users","users.rnti_start","deployment_topology.num_trps", ...
    "deployment_topology.sector_azimuth_offsets_deg"],'site-only override');
for field=["num_sites","num_sectors_per_site","num_cells","num_trps","num_ues"]
    for raw={0,-1,1.5,NaN,Inf,[],[1 2],"2",true}
        changed=cfg; changed.canonical_control.topology.(field)=raw{1};
        localReject(@()sixgr.lls6g.config.normalizeScenarioAliases(changed), ...
            'sixgr:lls6g:config:InvalidCanonicalTopology');
    end
end
changed=cfg; changed.frequency.duplex_mode=["TDD","FDD"];
localReject(@()sixgr.lls6g.config.normalizeScenarioAliases(changed), ...
    'sixgr:lls6g:config:InvalidDuplexMode');

% Full canonical authoring must still project each explicitly selected domain.
changed=cfg;
changed.canonical_control.topology=struct('num_sites',3,'num_sectors_per_site',2, ...
    'num_cells',6,'num_trps',9,'num_ues',8,'sector_azimuth_offsets_deg',[30 210], ...
    'rnti_start',401);
actual=sixgr.lls6g.config.normalizeScenarioAliases(changed);
assert(actual.deployment_topology.num_sites==3 && actual.scenario.layout.nSites==3);
assert(actual.deployment_topology.num_sectors_per_site==2 && ...
    actual.scenario.layout.nSectorsPerSite==2);
assert(actual.deployment_topology.num_cells==6 && actual.scenario.layout.nCells==6);
assert(actual.deployment_topology.num_trps==9 && actual.users.n_users==8 && ...
    actual.deployment_topology.num_ues==8 && actual.scenario.ue.nUE==8);
assert(actual.users.rnti_start==401 && ...
    isequal(actual.scenario.sectorization.azimOffsets_deg,[30 210]));

% Reproduce the actual load/build boundary, not only a small struct fixture.
% The integration-only parent introduced the one-UE collapse in the retained
% bidirectional run. This preflight must fail before expensive PHY execution.
fixture=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/validation/lls_bidirectional_disjoint_ul.yaml');
twoUE=fixture.toStruct();
twoUE.users.n_users=2;
twoUE.users.rnti_start=201;
twoUE.deployment_topology.num_ues=2;
twoUE.scenario.ue.nUE=2;
twoUE=sixgr.lls6g.config.normalizeScenarioAliases(twoUE);
runtime=sixgr.lls6g.buildInternalConfig(twoUE,tempname);
assert(runtime.scenario.nUE==2 && runtime.scenario.ue.nUE==2, ...
    'test:CanonicalRuntimePopulation','The real bidirectional fixture lost a requested UE.');
sixgr.truth.validateCoupledNoisePowerAuthority(runtime);
assert(sixgr.rf.isNormalizedFixedSNRPowerReference(runtime), ...
    'Topology repair must preserve the fixed-SNR integration authority.');
fprintf(['CANONICAL_TOPOLOGY_ISOLATION_PASS unrelated_controls=5 ' ...
    'partial_overrides=3 full_override=1 two_ue_runtime_preflight=1\n']);
ok=true;
end

function localAssertUnchanged(expected,actual,paths,label)
for path=reshape(paths,1,[])
    assert(isequaln(sixgr.util.structGet(actual,path,[]), ...
        sixgr.util.structGet(expected,path,[])), ...
        'test:CanonicalTopologyMutation','%s changed unrelated %s.',label,path);
end
end

function localReject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s.',id);
end
