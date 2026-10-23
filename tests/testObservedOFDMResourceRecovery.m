function ok=testObservedOFDMResourceRecovery()
% Exact accounting fixture, not waveform or device-power qualification.
setup6GRSimToolkit('Verbose',false);
folder=tempname; mkdir(folder); cleanup=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
carrier=nrCarrierConfig('NSizeGrid',3,'SubcarrierSpacing',30);
n=5;
T=table([0;0;0;0;1],[2;2;2;3;2],[0;0;12;24;0],12*ones(n,1), ...
    repmat("DL",n,1),repmat("CSI-RS",n,1),ones(n,1),ones(n,1), ...
    repmat("allocation,with_delimiter",n,1),repmat("carrier_cp_ofdm",n,1), ...
    repmat("runtime_observed_tx_occupancy",n,1),ones(n,1), ...
    repmat("executed_tx_toolbox_config_and_indices",n,1),repmat(string(repmat('a',1,64)),n,1), ...
    'VariableNames',{'absolute_slot','symbol_index','subcarrier_start','subcarrier_count', ...
    'direction','channel','cell_id','ue_id','allocation_id','grid_domain', ...
    'evidence_scope','active_flag','authority','ConfigHash'});
path=fullfile(folder,'actual.csv'); writetable(T,path);
digest=sixgr.util.sha256File(path);
[one,a]=sixgr.truth.readObservedOFDMResourceIntervals(path,digest,carrier,1);
[many,b]=sixgr.truth.readObservedOFDMResourceIntervals(path,digest,carrier,17);
snapshot=fullfile(folder,'immutable.bin'); copyfile(path,snapshot);
[archived,~]=sixgr.truth.readObservedOFDMResourceIntervals(snapshot,digest,carrier,2);
assert(isequaln(one,archived),'test:ArchiveExtensionMismatch', ...
    'Content-addressed checkpoint .bin snapshots must be read without copying/renaming the evidence.');
assert(isequaln(one,many) && height(one)==3 && a.SourceRows==5 && ...
    a.MaxChunkRows==1 && b.SourceRows==5 && ~a.ReceiverActivityInferred && ~a.OriginalFilesChanged);
first=one(one.AbsoluteSlotIndex0==0 & one.SymbolIndex0==2,:);
assert(first.SourceRowCount==3 && isequal(jsondecode(first.PRBSet0BasedJSON),[0;1]) && ...
    first.AllocationID=="allocation,with_delimiter");
scope=jsondecode(first.PopulationScopeJSON);
assert(string(scope.ConfigHash)==T.ConfigHash(1));
extended=nrCarrierConfig('NSizeGrid',3,'SubcarrierSpacing',60,'CyclicPrefix','extended');
[ext,~]=sixgr.truth.readObservedOFDMResourceIntervals(path,digest,extended,2);
assert(all(ext.ResourceSymbolsPerSlot==12));
localReject(@()sixgr.truth.readObservedOFDMResourceIntervals(path,string(repmat('0',1,64)),carrier), ...
    'sixgr:truth:ObservedResourceHashMismatch');
bad=T; bad.subcarrier_start(1)=36; writetable(bad,path);
localReject(@()sixgr.truth.readObservedOFDMResourceIntervals(path,sixgr.util.sha256File(path),carrier), ...
    'sixgr:truth:InvalidObservedResourceCoordinates');
bad=T; bad.evidence_scope(1)="planned"; writetable(bad,path);
localReject(@()sixgr.truth.readObservedOFDMResourceIntervals(path,sixgr.util.sha256File(path),carrier), ...
    'sixgr:truth:NonExecutedOFDMResourceEvidence');
bad=T; bad.symbol_index(1)=12; writetable(bad,path);
localReject(@()sixgr.truth.readObservedOFDMResourceIntervals(path,sixgr.util.sha256File(path),extended), ...
    'sixgr:truth:InvalidObservedResourceCoordinates');
fprintf('OBSERVED_OFDM_RESOURCE_RECOVERY_PASS exact_chunk_invariant=1\n');
ok=true;
end

function localReject(fn,id)
try
    fn(); error('test:MissingRejection','Invalid source accepted.');
catch ex
    assert(strcmp(ex.identifier,id),'test:WrongRejection', ...
        'Expected %s; got %s: %s',id,ex.identifier,ex.message);
end
end
