function out=buildObservedRETimeFrequencyUnion(T)
% Exact occupied time/frequency support from retained executed RE runs.
% Ports are deliberately collapsed: existing producers include logical and
% physical port domains. Reservations, silent/unexecuted REs and native
% PRACH/mixed-numerology grids are not inferred from this carrier table.
out=table();
if istable(T)&&isempty(T), return; end
id='sixgr:truth:InvalidObservedREUnion';
required={'absolute_slot','symbol_index','cell_id','direction','channel', ...
    'component','subcarrier_start','subcarrier_count','port_index', ...
    'allocation_id','grid_domain','coordinate_precision','evidence_scope','active_flag'};
assert(istable(T)&&all(ismember(required,T.Properties.VariableNames)),id, ...
    'Require original exact executed carrier RE rows.');
numericNames={'absolute_slot','symbol_index','cell_id','subcarrier_start', ...
    'subcarrier_count','port_index'};
v=T{:,numericNames};
assert(isnumeric(v)&&isreal(v)&&all(isfinite(v)&v==fix(v)&v>=0,'all')&& ...
    all(T.subcarrier_count>0)&&all(T.subcarrier_start+T.subcarrier_count<=flintmax), ...
    id,'Exact coordinates must be finite nonnegative integers with positive run lengths.');
assert(all(string(T.grid_domain)=="carrier_cp_ofdm")&& ...
    all(string(T.coordinate_precision)=="exact_contiguous_re_run")&& ...
    all(string(T.evidence_scope)=="runtime_observed_tx_occupancy")&& ...
    all(T.active_flag==1)&&all(ismember(string(T.direction),["DL","UL"])),id, ...
    'Only original active carrier occupancy is eligible; native/planned/reserved rows are separate.');
for name=["channel","component","allocation_id"]
    text=string(T.(name));
    assert(size(text,2)==1&&all(~ismissing(text)&strlength(strtrim(text))>0), ...
        id,'Every original run needs channel/component/allocation ownership.');
end
assert(~any(contains(lower(string(T.component)),["reserved","unavailable"]),'all'), ...
    id,'Reserved or unavailable support is not occupied RE evidence.');

% Only the independent execution binder owns a reusable local-clock ID.
% A shared receiver/channel ObservationID must not split one physical slot.
if ismember('ObservationID',T.Properties.VariableNames)
    observation=string(T.ObservationID); observation(ismissing(observation))="";
    independent=false(height(T),1);
    scope=strings(height(T),1);
    if ismember('ExecutionScope',T.Properties.VariableNames)
        scope=string(T.ExecutionScope); scope(ismissing(scope))="";
        independent=scope=="independent_link_execution";
    end
    assert(all(strlength(observation)==0|strlength(scope)>0)&& ...
        all(~independent|strlength(observation)>0),id, ...
        'Observation IDs require explicit shared/independent execution-clock scope.');
    if any(independent)
        T.IndependentObservationID=strings(height(T),1);
        T.IndependentObservationID(independent)=observation(independent);
    end
end
keys={'grid_domain','cell_id','direction','absolute_slot','symbol_index'};
for name={'ScenarioID','ConfigHash','RunID','RunTag','ExecutionID','IndependentObservationID', ...
        'CarrierFrequencyHz','CarrierFrequency_Hz','carrier_frequency_hz', ...
        'CarrierContextCenterFrequencyHz','grid_subcarrier_spacing_hz', ...
        'SubcarrierSpacingHz','SubcarrierSpacing_kHz','CarrierContextSubcarrierSpacingHz', ...
        'CarrierNStartGrid','GridStartPRB','CarrierContextGridStartPRB','PointA_Hz'}
    if ismember(name{1},T.Properties.VariableNames), keys{end+1}=name{1}; end %#ok<AGROW>
end
keyText=strings(height(T),numel(keys));
for k=1:numel(keys)
    values=T.(keys{k});
    if isnumeric(values)||islogical(values), values=compose('%.17g',double(values));
    else, values=string(values); values(ismissing(values))=""; end
    assert(size(values,2)==1,id,'Each original clock/context field must be scalar per row.');
    keyText(:,k)=values;
end
[~,first,group]=unique(keyText,'rows','sorted');
out=T(first,keys);
count=height(out); unions=strings(count,1); families=unions;
occupied=zeros(count,1); componentSum=occupied; allocations=occupied;
sourceRows=occupied; distinctPortLabels=occupied;
% Group row indices once. Do not expand per-port REs or build a dense grid.
[sortedGroup,order]=sort(group);
cuts=[1;find(diff(sortedGroup)~=0)+1;numel(group)+1];
for g=1:count
    ids=order(cuts(g):cuts(g+1)-1);
    runs=double(T{ids,{'subcarrier_start','subcarrier_count'}});
    [merged,occupied(g)]=localUnion(runs);
    % Preserve an array of [start,count] tuples even for one run. A bare
    % 1-by-2 numeric matrix serializes as a vector and changes JSON shape.
    unions(g)=string(jsonencode(num2cell(merged,2)));
    labels=[string(T.channel(ids)),string(T.component(ids))];
    [labelNames,~,labelGroup]=unique(labels,'rows','sorted');
    components=repmat(struct('Channel',"",'Component',"", ...
        'OccupiedREUnionCount',0,'AllocationCount',0,'SourceRowCount',0),size(labelNames,1),1);
    for c=1:numel(components)
        selected=labelGroup==c;
        [~,n]=localUnion(runs(selected,:));
        components(c)=struct('Channel',labelNames(c,1),'Component',labelNames(c,2), ...
            'OccupiedREUnionCount',n, ...
            'AllocationCount',numel(unique(string(T.allocation_id(ids(selected))))), ...
            'SourceRowCount',nnz(selected));
    end
    families(g)=string(jsonencode(components));
    componentSum(g)=sum([components.OccupiedREUnionCount]);
    allocations(g)=numel(unique(string(T.allocation_id(ids))));
    sourceRows(g)=numel(ids);
    distinctPortLabels(g)=numel(unique(double(T.port_index(ids))));
end
out.OccupiedSubcarrierRuns0BasedJSON=unions;
out.OccupiedREUnionCount=occupied;
out.FamilyComponentCountsJSON=families;
out.FamilyComponentUnionSumCount=componentSum;
out.CrossComponentOverlapExcessCount=componentSum-occupied;
out.SourceAllocationCount=allocations;
out.SourceRowCount=sourceRows;
out.SourceDistinctPortLabelCount=distinctPortLabels;
out.PortScope=repmat("ports_collapsed_mixed_producer_domains_not_physical_port_count",count,1);
out.SupportScope=repmat("observed_occupied_carrier_REs_only_reserved_and_unobserved_support_excluded",count,1);
out.OverlapDefinition=repmat("sum_family_component_unions_minus_joint_union_not_pairwise_collision_count",count,1);
out.Source=repmat("original_executed_RE_runs_exact_interval_union_no_power_inference",count,1);
out.ContextScope=repmat("original_available_identity_and_carrier_fields_only_missing_context_not_inferred",count,1);
end

function [runs,n]=localUnion(runs)
% Half-open integer intervals; touching runs can be represented as one run.
runs=sortrows(unique(runs,'rows'),[1 2]);
merged=zeros(size(runs)); used=0;
for k=1:size(runs,1)
    left=runs(k,1); right=left+runs(k,2);
    if used==0||left>merged(used,1)+merged(used,2)
        used=used+1; merged(used,:)=[left right-left];
    else
        merged(used,2)=max(merged(used,1)+merged(used,2),right)-merged(used,1);
    end
end
runs=merged(1:used,:); n=sum(runs(:,2));
end
