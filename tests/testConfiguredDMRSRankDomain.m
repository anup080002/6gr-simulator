function ok=testConfiguredDMRSRankDomain()
% Declared configuration/native-allocation checks, not waveform reception.
setup6GRSimToolkit('Verbose',false);
fixture='simulator/configs/scenarios/lls_tdd_four_port_received_rank_transition_fixture.yaml';
scenario=sixgr.lls6g.config.loadScenarioConfig(fixture);
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempname);
before=cfg;
e=sixgr.phy.grant.validatePDSCHDMRSRankDomain(cfg);
assert(isequal(e.Ranks,1:4) && all(e.NumCDMGroupsWithoutData==2));
assert(isequal(e.PortSets{4},0:3) && isequal(e.CDMGroups{4},[0 0 1 1]));
assert(isequaln(cfg,before),'Preflight must not rewrite installed configuration.');

% Reproduce the v54 inheritance defect through the actual build boundary:
% bootstrap rank one is legal, but later admitted rank three/four is not.
bad=scenario.toStruct();
bad.reference_signals.pdsch_dmrs_num_cdm_groups_without_data=1;
localReject(@()sixgr.lls6g.buildInternalConfig(bad,tempname), ...
    'sixgr:pdsch:DMRSPortOutsideReservedCDMGroups');

% One group is valid for the actual type-1 ports 0 and 1; a dormant
% capability ceiling must not force reservations for disallowed ranks.
one=cfg;
one.phy.pdsch.dmrs.numCDMGroupsWithoutData=1;
one.phy.csi.rankDomain=[1 2];
one.phy.csi.reportConfiguration.AllowedRanks=[1 2];
oneBefore=one;
e=sixgr.phy.grant.validatePDSCHDMRSRankDomain(one);
assert(isequal(e.Ranks,[1 2]) && all(e.NumCDMGroupsWithoutData==1));
assert(isequaln(one,oneBefore));
restricted=one; restricted.phy.csi.rankDomain=1:4;
e=sixgr.phy.grant.validatePDSCHDMRSRankDomain(restricted);
assert(isequal(e.Ranks,[1 2]),'Installed AllowedRanks must restrict the raw search domain.');
restricted=one; restricted.phy.csi.reportConfiguration.AllowedRanks=1:4;
e=sixgr.phy.grant.validatePDSCHDMRSRankDomain(restricted);
assert(isequal(e.Ranks,[1 2]),'The raw search domain also restricts installed AllowedRanks.');
disjoint=one; disjoint.phy.csi.reportConfiguration.AllowedRanks=[3 4];
localRejectID(@()sixgr.phy.grant.validatePDSCHDMRSRankDomain(disjoint), ...
    'sixgr:phy:csi:EmptyRankDomain');
% Fixed rank validates only its installed bootstrap, not adaptive reports.
fixed=one;
fixed.phy.csi.rankDomain=1:4;
fixed.runtime.link_adaptation.RankPolicy='fixed';
e=sixgr.phy.grant.validatePDSCHDMRSRankDomain(fixed);
assert(isequal(e.Ranks,1));
% The scheduler's actual ceiling also bounds an advertised report domain.
capped=one; capped.phy.csi.rankDomain=1:4; capped.phy.pdsch.maxLayers=2;
e=sixgr.phy.grant.validatePDSCHDMRSRankDomain(capped);
assert(isequal(e.Ranks,[1 2]));
% No explicit report domain means all adaptive ranks up to the installed
% ceiling, not bootstrap-only validation.
missing=one;
missing.phy.csi=rmfield(missing.phy.csi,'rankDomain');
missing.phy.csi.reportConfiguration=rmfield(missing.phy.csi.reportConfiguration,'AllowedRanks');
localReject(@()sixgr.phy.grant.validatePDSCHDMRSRankDomain(missing), ...
    'sixgr:pdsch:DMRSPortOutsideReservedCDMGroups');
% Port identity matters: rank one on port 2 is outside group zero.
nonconsecutive=one;
nonconsecutive.phy.pdsch.dmrs.availablePortSet=[2 3 0 1];
localReject(@()sixgr.phy.grant.validatePDSCHDMRSRankDomain(nonconsecutive), ...
    'sixgr:pdsch:DMRSPortOutsideReservedCDMGroups');
% Explicit scheduled/frozen ports remain exact authority, never cleared
% or expanded by a capability preflight to make another rank legal.
explicit=one; explicit.phy.pdsch.dmrs.scheduledPortSet=0;
explicitBefore=explicit;
localReject(@()sixgr.phy.grant.validatePDSCHDMRSRankDomain(explicit), ...
    'sixgr:pdsch:InvalidDMRSPortSet');
assert(isequaln(explicit,explicitBefore));

% Legal two-codeword DM-RS must not be rejected because the bootstrap's
% scalar modulation is materialized per codeword only when a grant exists.
high=cfg;
high.phy.pdsch.maxLayers=8;
high.phy.pdsch.dmrs.availablePortSet=0:7;
high.phy.pdsch.dmrs.maxLength=2;
high.phy.pdsch.dmrs.additionalPositions=0;
high.phy.csi.maxRank=8;
high.phy.csi.rankDomain=[1 2 4 8];
high.phy.csi.reportConfiguration.AllowedRanks=[1 2 4 8];
high.phy.csi.reportConfiguration.MaxRank=8;
high.phy.csi.reportConfiguration.Ports=8;
highBefore=high;
e=sixgr.phy.grant.validatePDSCHDMRSRankDomain(high);
assert(isequal(e.Ranks,[1 2 4 8]) && isequal(e.PortSets{end},0:7));
assert(isequaln(high,highBefore));

% Existing UL four-port fragment already reserves both groups. This
% declared allocation probe does not invent an accepted SRS/DCI tuple.
carrier=sixgr.phy.grid.makeCarrier(cfg);
for rank=[1 2 4]
    [~,info,pusch]=sixgr.phy.grid.allocREsPUSCH(carrier,cfg, ...
        'NumLayers',rank,'TPMI',0);
    assert(pusch.NumLayers==rank && isequal(pusch.DMRS.DMRSPortSet,0:rank-1) && ...
        pusch.DMRS.NumCDMGroupsWithoutData==2 && ...
        all(pusch.DMRS.CDMGroups<2) && info.G>0);
end
% Both the original one-group two-port fixture and selected n40 installed
% domain remain valid; n40's two-group reservation is not changed here.
legacy=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_received_csi_application_coexistence_fixture.yaml');
legacyCfg=sixgr.lls6g.buildInternalConfig(legacy,tempname);
e=sixgr.phy.grant.validatePDSCHDMRSRankDomain(legacyCfg);
assert(all(e.Ranks<=2) && all(e.NumCDMGroupsWithoutData==1));
n40=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
n40Cfg=sixgr.lls6g.buildInternalConfig(n40,tempname);
e=sixgr.phy.grant.validatePDSCHDMRSRankDomain(n40Cfg);
assert(all(ismember([1 2 4],e.Ranks)) && all(e.NumCDMGroupsWithoutData==2));
fprintf('CONFIGURED_DMRS_RANK_DOMAIN_PASS native_configuration_only=1 waveform_executed=0\n');
ok=true;
end

function localReject(fn,causeID)
try
    fn();
catch failure
    assert(strcmp(failure.identifier,'sixgr:lls6g:config:PDSCHDMRSRankDomainInvalid'), ...
        'Unexpected rejection %s: %s',failure.identifier,failure.message);
    assert(any(cellfun(@(cause)strcmp(cause.identifier,causeID),failure.cause)), ...
        'Original native/port identity rejection was not preserved.');
    return;
end
error('sixgr:test:MissingRejection','Incompatible configured DM-RS domain was accepted.');
end

function localRejectID(fn,id)
try
    fn();
catch failure
    assert(strcmp(failure.identifier,id),'Unexpected rejection %s: %s', ...
        failure.identifier,failure.message);
    return;
end
error('sixgr:test:MissingRejection','Incompatible configured rank restriction was accepted.');
end
