function ok=testPUSCHDMRSAliasAuthority()
% Authored policy, inheritance and native allocation, not received DCI or RF.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
work=tempname; mkdir(work);
cleanup=onCleanup(@()rmdir(work,'s')); %#ok<NASGU> % This unique test folder only.
base=string(fullfile(pwd,'simulator','configs','scenarios','dl_4ghz_baseline.yaml'));
checks={@()inheritance(base,work),@()conflicts(base,work), ...
    @()overrides(base),@()nativeAllocation(base),@()roundTrip(base,work)};
names=["authored_inheritance","conflicts_and_types","sweep_runtime_overrides", ...
    "native_configured_DMRS","resolved_reload"];
passed=false(size(checks));
for k=1:numel(checks)
    try
        checks{k}(); passed(k)=true;
        fprintf('PUSCH_DMRS_ALIAS_PASS %s\n',names(k));
    catch cause
        fprintf(2,'PUSCH_DMRS_ALIAS_FAIL %s %s\n',names(k),getReport(cause,'extended','hyperlinks','off'));
    end
end
assert(all(passed),'test:PUSCHDMRSAliasAuthority','Passed %d/%d groups.',nnz(passed),numel(passed));
ok=true;
end

function inheritance(base,work)
left="reference_signals.pusch_dmrs_additional_positions";
right="pusch.dmrs_additional_position";
parent=write(work,'parent',base,setValue(struct(),left,2));
child=write(work,'child',parent,setValue(struct(),right,1));
grandchild=write(work,'grandchild',child,struct('meta',struct('description','unrelated child')));
s=load(grandchild); equal(s,left,right,1);
back=write(work,'back_to_reference_alias',grandchild,setValue(struct(),left,2));
s=load(back); equal(s,left,right,2);
% A later sibling author wins only this pair, not every PUSCH property.
first=write(work,'first',strings(0,1),setValue(struct(),left,3));
second=write(work,'second',strings(0,1),setValue(struct(),right,0));
composed=write(work,'composed',[base first second],struct());
s=load(composed); equal(s,left,right,0);
reverse=write(work,'reverse',[base second first],struct());
s=load(reverse); equal(s,left,right,3);
pool=write(work,'ordered_pool',base,setValue(struct(),'pusch.dmrs_port_set',[1 0]));
s=load(pool);
equal(s,"reference_signals.pusch_dmrs.port_set","pusch.dmrs_port_set",[1 0]);
end

function conflicts(base,work)
[left,right]=paths();
one={1,1,0,2,1,[0 1]}; two={2,2,1,3,2,[1 0]};
original=load(base);
for k=1:numel(left)
    authored=setValue(setValue(struct(),left(k),one{k}),right(k),two{k});
    path=write(work,"conflict_"+k,base,authored);
    reject(@()load(path),'sixgr:lls6g:config:ConflictingPUSCHDMRSAliases');
    % Direct builder calls cannot assert unknown last-writer precedence.
    raw=sixgr.util.mergeStruct(original,authored);
    reject(@()sixgr.lls6g.buildInternalConfig(raw,tempname), ...
        'sixgr:lls6g:config:ConflictingPUSCHDMRSAliases');
end
for value={NaN,[],true,'1',[1 2],1+1i}
    authored=setValue(struct(),right(1),value{1});
    reject(@()sixgr.lls6g.config.PUSCHDMRSAuthority.merge(struct(),authored), ...
        'sixgr:lls6g:config:InvalidPUSCHDMRSValue');
end
for value={[0 0],[0 12],['0' '1'],[true false]}
    authored=setValue(struct(),right(6),value{1});
    reject(@()sixgr.lls6g.config.PUSCHDMRSAuthority.merge(struct(),authored), ...
        'sixgr:lls6g:config:InvalidPUSCHDMRSValue');
end
end

function overrides(base)
left="reference_signals.pusch_dmrs_additional_positions";
right="pusch.dmrs_additional_position";
original=load(base);
authored=setValue(struct(),right,1);
% This is the exact runSingle generic-sweep normalization interface.
merged=sixgr.util.mergeStruct(original,authored);
s=sixgr.lls6g.config.normalizeScenarioAliases(merged,'Authority',authored);
equal(s,left,right,1);
assert(isequaln(s,sixgr.lls6g.config.normalizeScenarioAliases(s)));
s.canonical_control.runtime_overrides=struct( ...
    'path',{char(right),char(right)},'value',{2,0});
s=sixgr.lls6g.config.normalizeScenarioAliases(s);
equal(s,left,right,0);
assert(isequaln(s,sixgr.lls6g.config.normalizeScenarioAliases(s)));
s.canonical_control.runtime_overrides=struct( ...
    'path',{char(left),char(right)},'value',{2,1});
reject(@()sixgr.lls6g.config.normalizeScenarioAliases(s), ...
    'sixgr:lls6g:config:ConflictingPUSCHDMRSAliases');
end

function nativeAllocation(base)
original=load(base); [left,right]=paths();
% Configured standalone DMRS duration, not a new connected DCI maxLength
% capability/dynamic-duration implementation. No control context is invented.
values={2,2,1,3,3,[1 0]}; authored=struct();
for k=1:numel(right), authored=setValue(authored,right(k),values{k}); end
authored.pusch.num_layers=1;
s=sixgr.lls6g.config.normalizeScenarioAliases( ...
    sixgr.util.mergeStruct(original,authored),'Authority',authored);
for k=1:numel(left), equal(s,left(k),right(k),values{k}); end
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
d=cfg.phy.pusch.dmrs;
assert(d.configType==2&&d.configurationType==2&&d.maxLength==2&&d.length==2&& ...
    d.typeApos==3&&d.typeAPosition==3&&d.additionalPositions==1&&d.numCDMGroupsWithoutData==3);
assert(isequal(d.availablePortSet,[1 0])&&isequal(d.portSet,1)&&isequal(d.DMRSPortSet,1));
carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30);
[actual,~,pusch]=sixgr.phy.grid.allocREsPUSCH(carrier,cfg,'PRBSet',0:7, ...
    'SymbolAllocation',[0 14],'MappingType','A','NumLayers',1, ...
    'TransformPrecoding',false,'TransmissionScheme','nonCodebook');
assert(pusch.DMRS.DMRSConfigurationType==2&&pusch.DMRS.DMRSLength==2&& ...
    pusch.DMRS.DMRSTypeAPosition==3&&pusch.DMRS.DMRSAdditionalPosition==1&& ...
    pusch.DMRS.NumCDMGroupsWithoutData==3&&isequal(pusch.DMRS.DMRSPortSet,1));
native=nrPUSCHIndices(carrier,pusch,'IndexBase','1based');
assert(isequal(actual,native)&&~isempty(nrPUSCHDMRSIndices(carrier,pusch)));
% A multi-port capability pool is not the active rank-one DMRS set.
s=load(fullfile(pwd,'simulator','configs','scenarios', ...
    'lls_tdd_four_port_received_rank_transition_fixture.yaml'));
s.pusch.num_layers=1;
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(isequal(cfg.phy.pusch.dmrs.availablePortSet,0:3)&& ...
    isequal(cfg.phy.pusch.dmrs.portSet,0)&&isequal(cfg.phy.pusch.dmrs.DMRSPortSet,0));
[ports,source]=sixgr.phy.grant.resolveScheduledDMRSPortSet(cfg,'UL',1);
assert(isequal(ports,0)&&string(source)=="configured_active_dmrs_port_pool");
end

function roundTrip(base,work)
s=load(base); [left,right]=paths();
for extension=["json","yaml"]
    path=fullfile(work,"resolved_dmrs."+extension);
    if extension=="json", sixgr.util.jsonWrite(path,s);
    else, sixgr.lls6g.config.writeYAML(path,s); end
    before=fileread(path); restored=load(path);
    for k=1:numel(left)
        expected=sixgr.util.structGet(s,left(k),[]);
        if ~isempty(expected), equal(restored,left(k),right(k),expected); end
    end
    assert(strcmp(before,fileread(path)));
    a=sixgr.lls6g.buildInternalConfig(s,tempname);
    b=sixgr.lls6g.buildInternalConfig(restored,tempname);
    assert(isequaln(a.phy.pusch.dmrs,b.phy.pusch.dmrs));
end
end

function [left,right]=paths()
left=["reference_signals.pusch_dmrs_config_type","reference_signals.pusch_dmrs_max_length", ...
    "reference_signals.pusch_dmrs_additional_positions","reference_signals.pusch_dmrs_type_a_position", ...
    "reference_signals.pusch_dmrs_num_cdm_groups_without_data","reference_signals.pusch_dmrs.port_set"];
right=["pusch.dmrs_configuration_type","pusch.dmrs_length","pusch.dmrs_additional_position", ...
    "pusch.dmrs_type_a_position","pusch.dmrs_num_cdm_groups_without_data","pusch.dmrs_port_set"];
end
function equal(s,left,right,value)
assert(isequal(sixgr.util.structGet(s,left,[]),value)&&isequal(sixgr.util.structGet(s,right,[]),value), ...
    'Configured alias values %s / %s were not retained exactly.',left,right);
end
function s=load(path)
loaded=sixgr.lls6g.config.loadScenarioConfig(path); s=loaded.toStruct();
end
function path=write(work,name,parents,s)
path=string(fullfile(work,name+".json"));
if ~isempty(parents), s.inherits=string(parents); end
sixgr.util.jsonWrite(path,s);
end
function s=setValue(s,path,value), s=sixgr.util.structSet(s,path,value); end
function reject(action,id)
try, action(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:MissingPUSCHDMRSAliasGuard','Expected %s.',id);
end
