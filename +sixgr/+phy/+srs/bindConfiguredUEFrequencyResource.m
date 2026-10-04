function [cfg,binding]=bindConfiguredUEFrequencyResource(cfg,ueIndex,rnti,servingCellID)
% Bind an explicitly configured UE SRS frequency/sequence resource.
% No RNTI-derived pilot, UE-ordinal shift or automatic orthogonality claim.
% Timing, bandwidth, port count and power remain the installed base config.
% An empty catalog preserves legacy shared-resource behavior, including
% intentional collisions. A nonempty catalog requires an exact owner match.
validateattributes([ueIndex rnti servingCellID],{'numeric'}, ...
    {'real','finite','integer','positive','numel',3});
internal=sixgr.util.structGet(cfg,'phy.srs.ueResourceBindings',[]);
scenario=sixgr.util.structGet(cfg, ...
    'lls6g.reference_signals.srs.ue_resource_bindings',[]);
assert(isempty(internal) || isempty(scenario) || isequaln(internal,scenario), ...
    'sixgr:srs:UEBindingConflict','Internal and scenario SRS resource bindings disagree.');
rows=internal; if isempty(rows), rows=scenario; end
binding=struct();
if isempty(rows), return; end
assert(isstruct(rows),'sixgr:srs:UEBindingSchema','SRS UE bindings must be a struct array.');
required={'ue_index','rnti','serving_cell_id','resource_id', ...
    'comb_offset','cyclic_shift','sequence_id'};
assert(all(isfield(rows,required)) && isempty(setdiff(fieldnames(rows),required)), ...
    'sixgr:srs:UEBindingSchema','SRS UE bindings require exactly: %s.',strjoin(required,', '));
owners=zeros(numel(rows),2); matches=false(numel(rows),1);
for k=1:numel(rows)
    row=rows(k);
    for f=required
        value=row.(f{1});
        assert(isnumeric(value) && isscalar(value) && isreal(value) && ...
            isfinite(value) && value==fix(value) && value>=0, ...
            'sixgr:srs:UEBindingSchema','SRS binding %s must be a nonnegative integer scalar.',f{1});
    end
    assert(row.ue_index>0 && row.serving_cell_id>0 && row.rnti>0 && row.rnti<=65535, ...
        'sixgr:srs:UEBindingSchema','SRS binding requires positive UE/cell and a 16-bit RNTI.');
    owners(k,:)=[row.ue_index row.serving_cell_id];
    matches(k)=row.ue_index==ueIndex && row.serving_cell_id==servingCellID;
end
assert(size(unique(owners,'rows'),1)==size(owners,1), ...
    'sixgr:srs:UEBindingDuplicate','Only one installed SRS frequency resource per UE/cell is supported.');
assert(nnz(matches)==1,'sixgr:srs:UEBindingMissing', ...
    'No configured SRS resource for UE %d serving cell %d.',ueIndex,servingCellID);
row=rows(matches);
assert(row.rnti==rnti,'sixgr:srs:UEBindingRNTI','SRS resource belongs to a different RNTI.');
% Resolve the base comb through the existing canonical builder; reject bad
% input before its historical integer rounding can hide malformed bindings.
base=sixgr.phy.srs.buildSRSConfigFromScenario(cfg);
comb=double(base.ToolboxSRS.KTC);
switch comb
    case 2, maxShift=8;
    case 4, maxShift=12;
    case 8, maxShift=6;
    otherwise, error('sixgr:srs:UEBindingComb','Unsupported SRS transmission comb.');
end
assert(row.comb_offset<comb && row.cyclic_shift<maxShift && row.sequence_id<=1023, ...
    'sixgr:srs:UEBindingRange','SRS comb offset, cyclic shift or sequence identity is out of range.');
cfg.phy.srs.KBarTC=row.comb_offset;
cfg.phy.srs.CyclicShift=row.cyclic_shift;
cfg.phy.srs.NSRSID=row.sequence_id;
cfg.phy.srs.resourceIds=row.resource_id;
cfg.phy.srs.bindingSource='configured_per_ue_frequency_resource';
binding=struct('UEIndex',double(ueIndex),'RNTI',double(rnti), ...
    'ServingCellID',double(servingCellID),'ResourceID',double(row.resource_id), ...
    'CombNumber',comb,'CombOffset',double(row.comb_offset), ...
    'CyclicShift',double(row.cyclic_shift),'SequenceID',double(row.sequence_id), ...
    'Source',"explicit_installed_srs_resource_configuration");
binding.SHA256=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(binding),'UTF-8'))));
cfg.phy.srs.UEFrequencyResourceBinding=binding;
end
