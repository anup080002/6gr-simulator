function ok=testSRSConfiguredUEFrequencyResource()
% Exercise production binding/native pilots, not the multi-UE test allocator.
cfg=sixgr.config.defaultConfig();
cfg.phy.carrier=struct('NSizeGrid',6,'NStartGrid',0,'SubcarrierSpacing',30,'NCellID',1);
cfg.phy.numerology.scs_kHz=30; cfg.phy.duplex.mode='FDD';
cfg.phy.srs=struct('enable',true,'nPorts',2,'period_slots',5,'period_offset',0, ...
    'slotNumbers',0,'CSRS',0,'BSRS',0,'BHop',0,'bandwidthRB',4,'expectedNumRB',4, ...
    'SymbolStart',13,'NumSRSSymbols',1,'KTC',2,'KBarTC',0,'CyclicShift',0, ...
    'NSRSID',1,'resourceSetUsage','codebook');
[legacy,empty]=sixgr.phy.srs.bindConfiguredUEFrequencyResource(cfg,2,4661,1);
assert(isequaln(legacy,cfg) && isempty(fieldnames(empty)));
fragment=sixgr.lls6g.config.readConfigFile('simulator/configs/validation/srs_two_ue_frequency_bindings.yaml');
cfg=sixgr.util.mergeStruct(cfg,fragment);
[a,ba]=sixgr.phy.srs.bindConfiguredUEFrequencyResource(cfg,1,4660,1);
[b,bb]=sixgr.phy.srs.bindConfiguredUEFrequencyResource(cfg,2,4661,1);
sa=sixgr.phy.srs.buildSRSConfigFromScenario(a);
sb=sixgr.phy.srs.buildSRSConfigFromScenario(b);
ga=gridFor(sa); gb=gridFor(sb);
assert(sa.ResourceId==0 && sb.ResourceId==1 && ba.SHA256~=bb.SHA256);
assert(~any(any(ga~=0,3) & any(gb~=0,3),'all'), ...
    'Configured two-port comb offsets must have disjoint physical REs.');
assert(abs(sum(abs(ga).^2,'all')-sum(abs(gb).^2,'all'))<1e-12, ...
    'Resource separation must not inject pilot energy.');
assert(a.phy.srs.nPorts==cfg.phy.srs.nPorts && b.phy.srs.period_slots==cfg.phy.srs.period_slots);
[occupied,exclusions]=sixgr.phy.srs.configuredNullREExclusions(a,sa.ToolboxCarrier);
assert(isequal(occupied,any(ga~=0,3)|any(gb~=0,3)) && ...
    exclusions.ResourcesDue==2 && ~exclusions.ActualTransmissionsInferred);
late=sa.ToolboxCarrier; late.NSlot=1;
[idle,idleEvidence]=sixgr.phy.srs.configuredNullREExclusions(a,late);
assert(~any(idle,'all') && idleEvidence.ResourcesDue==0);
foreign=cfg; foreign.phy.srs.ueResourceBindings(2).serving_cell_id=2;
foreign=sixgr.phy.srs.bindConfiguredUEFrequencyResource(foreign,1,4660,1);
[sameCell,sameCellEvidence]=sixgr.phy.srs.configuredNullREExclusions(foreign,sa.ToolboxCarrier);
assert(isequal(sameCell,any(ga~=0,3)) && sameCellEvidence.ConfiguredResourcesExamined==1);
poisoned=a; poisoned.phy.srs.UEFrequencyResourceBinding.CombOffset=1;
reject(@()sixgr.phy.srs.configuredNullREExclusions(poisoned,sa.ToolboxCarrier), ...
    'sixgr:srs:NullREReceiverIdentity');
% Explicit collisions remain physical inputs, not silently orthogonalized.
collision=cfg; collision.phy.srs.ueResourceBindings(2).comb_offset=0;
c=sixgr.phy.srs.bindConfiguredUEFrequencyResource(collision,2,4661,1);
gc=gridFor(sixgr.phy.srs.buildSRSConfigFromScenario(c));
assert(isequal(ga,gc));
modern=rmfield(cfg.phy.srs,'ueResourceBindings'); scenario=cfg;
scenario.phy.srs=modern;
scenario.lls6g.reference_signals.srs.ue_resource_bindings=cfg.phy.srs.ueResourceBindings;
[~,same]=sixgr.phy.srs.bindConfiguredUEFrequencyResource(scenario,2,4661,1);
assert(same.SHA256==bb.SHA256);
% Nonzero resource identity does not increase the DCI SRI field width.
nonzero=sb; nonzero.ResourceId=37; nonzero.ResourceIds=37;
assert(sixgr.system.abstraction.singleSRSResourceIndicator(nonzero)==0);
data=struct('ULReferenceSignaling',struct('srs_resource_count',1, ...
    'dmrs_configuration_type',1,'dmrs_max_length',1, ...
    'dmrs_type_enhanced',false,'multipanel_sdm',false), ...
    'ULPrecoding',struct('transmission_scheme','codebook'),'TransformPrecodingEnabled',false);
fields=sixgr.phy.pdcch.ULReferenceSignaling.bindSRI(struct('srs_resource_indicator',0),data,0);
assert(~isfield(fields,'srs_resource_indicator'));
reject(@()sixgr.phy.pdcch.ULReferenceSignaling.bindSRI(struct(),data,37), ...
    'sixgr:phy:pdcch:InvalidSRSResourceIndicator');
multiple=nonzero; multiple.ResourceIds=[37 42]; multiple.NumResources=2;
reject(@()sixgr.system.abstraction.singleSRSResourceIndicator(multiple), ...
    'sixgr:abstraction:SRSMultipleResourcesUnsupported');
reject(@()sixgr.phy.srs.bindConfiguredUEFrequencyResource(cfg,2,4660,1),'sixgr:srs:UEBindingRNTI');
reject(@()sixgr.phy.srs.bindConfiguredUEFrequencyResource(cfg,3,4662,1),'sixgr:srs:UEBindingMissing');
bad=cfg; bad.phy.srs.ueResourceBindings(2)=bad.phy.srs.ueResourceBindings(1);
reject(@()sixgr.phy.srs.bindConfiguredUEFrequencyResource(bad,1,4660,1),'sixgr:srs:UEBindingDuplicate');
bad=cfg; bad.phy.srs.ueResourceBindings(2).comb_offset=2;
reject(@()sixgr.phy.srs.bindConfiguredUEFrequencyResource(bad,2,4661,1),'sixgr:srs:UEBindingRange');
bad=cfg; bad.phy.srs.ueResourceBindings(2).cyclic_shift=0.5;
reject(@()sixgr.phy.srs.bindConfiguredUEFrequencyResource(bad,2,4661,1),'sixgr:srs:UEBindingSchema');
ok=true;
end
function g=gridFor(s)
g=nrResourceGrid(s.ToolboxCarrier,s.NumSRSPorts);
g(nrSRSIndices(s.ToolboxCarrier,s.ToolboxSRS))=nrSRS(s.ToolboxCarrier,s.ToolboxSRS);
end
function reject(f,id)
try, f(); catch ex, assert(strcmp(ex.identifier,id),'Expected %s, got %s.',id,ex.identifier); return; end
error('test:ExpectedRejection','Expected %s.',id);
end
