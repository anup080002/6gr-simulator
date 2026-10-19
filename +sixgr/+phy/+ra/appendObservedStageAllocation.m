function result=appendObservedStageAllocation(result,tx,stage)
% Exact TX-grid occupancy after physical stage execution, irrespective of CRC.
% Call only after the runtime has completed this stage's sample interval.
assert(isstruct(stage) && isscalar(stage) && stage.TxSampleCount>0 && ...
    stage.RxSampleCount>0 && isstruct(tx) && isfield(tx,'Waveform') && ...
    size(tx.Waveform,1)==stage.TxSampleCount, ...
    'sixgr:ra:UnexecutedAllocation','A prepared or silent stage is not observed TX occupancy.');
executed=sixgr.util.structGet(result,'RuntimeStageRows',table());
assert(~isempty(executed) && any(executed.StageName==stage.StageName & ...
    executed.StageSlot==stage.StageSlot & executed.TxSampleCount==stage.TxSampleCount), ...
    'sixgr:ra:UnexecutedAllocation','RA allocation must have its actual completed stage row.');
name=string(stage.StageName);
if name=="Msg1"
    channels="PRACH"; objects={tx};
elseif any(name==["Msg2","Msg4"])
    channels=["PDCCH","PDSCH"]; objects={tx.PDCCH,tx.PDSCH};
    % These are exact aliases of retained one-based producer indices.
    objects{1}.PDCCHIndices=objects{1}.PDCCHInd;
    objects{1}.DMRSIndices=objects{1}.DMRSInd;
elseif any(name==["Msg3","RRCSetupComplete"])
    channels="PUSCH"; objects={tx};
else
    error('sixgr:ra:UnknownObservedStage','Unsupported executed RA stage %s.',name);
end
identity=string(result.RunId)+"_cell"+string(result.CellId)+"_ue"+string(result.UEId)+ ...
    "_attempt"+string(result.AttemptId)+"_"+name+"_slot"+string(stage.StageSlot);
all=sixgr.util.structGet(result,'ObservedREAllocationTable',table());
for k=1:numel(channels)
    part=sixgr.truth.buildObservedREAllocation(objects{k}, ...
        'Direction',stage.Direction,'Channel',channels(k),'AbsoluteSlot',stage.StageSlot, ...
        'CellID',result.CellId,'UEID',result.UEId,'AllocationID',identity+"_"+channels(k));
    part.ra_stage=repmat(name,height(part),1);
    part.ra_attempt_id=repmat(double(result.AttemptId),height(part),1);
    part.stage_waveform_port_count=repmat(double(stage.TxPortCount),height(part),1);
    part.observation_start_sample=repmat(double(stage.ObservationStartSample),height(part),1);
    part.observation_end_sample_exclusive=repmat(double(stage.ObservationEndSampleExclusive),height(part),1);
    if channels(k)~="PRACH"
        % An allocation's producer grid is not necessarily the final shared
        % antenna grid. Do not label logical/control ports as 64 TXRUs.
        part.port_domain=repmat("executed_tx_object_grid_before_shared_spatial_mapping",height(part),1);
        part.grid_port_count=repmat(size(objects{k}.Grid,3),height(part),1);
    end
    all=localAppend(all,part);
end
result.ObservedREAllocationTable=sixgr.truth.deduplicateObservedREAllocation(all);
end

function output=localAppend(a,b)
if isempty(a), output=b; return; end
names=union(string(a.Properties.VariableNames),string(b.Properties.VariableNames),'stable');
for name=names
    if ~ismember(name,string(a.Properties.VariableNames)), a=localMissing(a,b,name); end
    if ~ismember(name,string(b.Properties.VariableNames)), b=localMissing(b,a,name); end
end
output=[a(:,cellstr(names));b(:,cellstr(names))];
end

function target=localMissing(target,source,name)
value=source.(name);
if isstring(value)
    target.(name)=strings(height(target),1);
elseif islogical(value)
    target.(name)=false(height(target),1);
elseif isnumeric(value)
    target.(name)=nan(height(target),1);
else
    error('sixgr:ra:ObservedAllocationSchema','Unsupported exact-allocation field %s.',name);
end
end
