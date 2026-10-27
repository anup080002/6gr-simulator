function ok=testObservedRETimeFrequencyUnion()
% Declared exact-run arithmetic fixtures, not newly executed RF samples.
T=localFixture(); before=T;
U=sixgr.truth.buildObservedRETimeFrequencyUnion(T);
assert(isequaln(T,before)&&height(U)==1&&U.OccupiedREUnionCount==8);
assert(isequal(jsondecode(U.OccupiedSubcarrierRuns0BasedJSON),[0 6;10 2]));
assert(U.FamilyComponentUnionSumCount==10&&U.CrossComponentOverlapExcessCount==2);
assert(U.SourceAllocationCount==3&&U.SourceDistinctPortLabelCount==2&&U.SourceRowCount==4);
parts=jsondecode(U.FamilyComponentCountsJSON);
assert(numel(parts)==2&&sum([parts.OccupiedREUnionCount])==10);
single=sixgr.truth.buildObservedRETimeFrequencyUnion(T(1,:));
assert(single.OccupiedSubcarrierRuns0BasedJSON=="[[0,4]]"&& ...
    isequal(jsondecode(single.OccupiedSubcarrierRuns0BasedJSON),[0 4]), ...
    'A single exact run keeps the same array-of-tuples JSON shape.');
% Repeated ports, repeated publication and input order cannot increase REs.
repeated=[T;T]; repeated.port_index(5:end)=63;
V=sixgr.truth.buildObservedRETimeFrequencyUnion(repeated(end:-1:1,:));
assert(V.OccupiedREUnionCount==8&&V.FamilyComponentUnionSumCount==10&& ...
    V.SourceRowCount==8&&V.SourceDistinctPortLabelCount==3);
% Same local slot in independent observations must not become simultaneous.
a=T; a.ObservationID=repmat("original_trial_A",height(a),1);
a.ExecutionScope=repmat("independent_link_execution",height(a),1);
b=a; b.ObservationID(:)="original_trial_B"; b.subcarrier_start=b.subcarrier_start+100;
V=sixgr.truth.buildObservedRETimeFrequencyUnion([a;b]);
assert(height(V)==2&&all(V.OccupiedREUnionCount==8));
% Distinct shared channel observations still use one original physical clock.
a.ExecutionScope(:)="shared_physical_stream"; b=a; b.ObservationID(:)="other_channel_capture";
V=sixgr.truth.buildObservedRETimeFrequencyUnion([a;b]);
assert(height(V)==1&&V.OccupiedREUnionCount==8);
localReject(@()sixgr.truth.buildObservedRETimeFrequencyUnion(removevars(a,'ExecutionScope')));
for field=["RunID","ExecutionID","CarrierFrequencyHz","grid_subcarrier_spacing_hz"]
    a=T; b=T;
    if endsWith(field,"ID"), a.(field)=repmat("original_A",height(a),1); b.(field)=repmat("original_B",height(b),1);
    else, a.(field)=repmat(30000,height(a),1); b.(field)=repmat(15000,height(b),1); end
    V=sixgr.truth.buildObservedRETimeFrequencyUnion([a;b]);
    assert(height(V)==2&&all(V.OccupiedREUnionCount==8));
end
b=T; b.symbol_index(:)=3;
V=sixgr.truth.buildObservedRETimeFrequencyUnion([T;b]);
assert(height(V)==2&&all(V.OccupiedREUnionCount==8));
b=T; b.direction(:)="UL";
assert(height(sixgr.truth.buildObservedRETimeFrequencyUnion([T;b]))==2);
b=T; b.cell_id(:)=2;
assert(height(sixgr.truth.buildObservedRETimeFrequencyUnion([T;b]))==2);
assert(isempty(sixgr.truth.buildObservedRETimeFrequencyUnion(table())));
for mutation=1:7
    bad=T;
    switch mutation
        case 1, bad.subcarrier_count(1)=0;
        case 2, bad.subcarrier_start(1)=.5;
        case 3, bad.active_flag(1)=false;
        case 4, bad.evidence_scope(1)="planned_not_executed";
        case 5, bad.grid_domain(1)="prach_native_ofdm";
        case 6, bad.component(1)="RESERVED";
        case 7, bad.allocation_id(1)="";
    end
    localReject(@()sixgr.truth.buildObservedRETimeFrequencyUnion(bad));
end
% Real production publication preserves source rows and mirrored CSV bytes.
root=tempname; layout=sixgr.report.resultLayout(root);
cfg=struct('run',struct('scenarioID','declared_RE_union_fixture'), ...
    'meta',struct('configHash','declared_fixture_not_a_real_run_hash'));
sixgr.truth.writeObservedREAllocationArtifacts(T,cfg,layout);
p=fullfile(layout.ComponentCSVDirs.frame_grid,'observed_re_time_frequency_union.csv');
q=fullfile(layout.ReportCSVDir,'live_re_time_frequency_union.csv');
assert(sixgr.util.sha256File(p)==sixgr.util.sha256File(q));
published=sixgr.util.csvReadTable(p);
assert(height(published)==1&&published.OccupiedREUnionCount==8&& ...
    published.FamilyComponentUnionSumCount==10&& ...
    string(published.ConfigHash)==string(cfg.meta.configHash));
sixgr.truth.writeObservedREAllocationArtifacts(table(),struct(),layout);
assert(~isfile(p)&&~isfile(q));
ok=true; fprintf('OBSERVED_RE_TIME_FREQUENCY_UNION_PASS overlap=1 disjoint=1 duplicate_ports=1 original_scope=1 publication=1 RF=0\n');
end

function T=localFixture()
T=table(zeros(4,1),ones(4,1),ones(4,1),repmat("DL",4,1), ...
    repmat("PDSCH",4,1),["DATA";"DATA";"DM-RS";"DATA"], ...
    [0;0;2;10],[4;4;4;2],[0;1;0;0],["a";"a";"b";"c"], ...
    repmat("carrier_cp_ofdm",4,1),repmat("exact_contiguous_re_run",4,1), ...
    repmat("runtime_observed_tx_occupancy",4,1),true(4,1), ...
    'VariableNames',{'absolute_slot','symbol_index','cell_id','direction','channel', ...
    'component','subcarrier_start','subcarrier_count','port_index','allocation_id', ...
    'grid_domain','coordinate_precision','evidence_scope','active_flag'});
end

function localReject(f)
try, f(); catch cause
    assert(strcmp(cause.identifier,'sixgr:truth:InvalidObservedREUnion')); return;
end
error('test:InvalidREUnionAccepted','Invalid source occupancy was accepted.');
end
