function state=commitSharedDataTransmission(state,item)
% Commit an actual started transmission before any later decoder result.
% The private physical-owner ledger proves execution; a caller-created
% preparation or event alone cannot reserve bytes or count a HARQ attempt.
assert(isfield(state,'SharedWaveformStream') && item.Kind=="DataTX", ...
    'sixgr:truth:SharedDataTXOwnerRequired','An actual shared-owner TX event is required.');
owner=state.SharedWaveformStream;
prepared=item.Context.Prepared;
identity=sixgr.truth.preparedDataTransmissionIdentity(prepared,item.UE);
assert(isequaln(identity,item.Context.TransmissionIdentity), ...
    'sixgr:truth:SharedDataTXIdentityMismatch','TX event identity must match the retained coded contribution.');
records=owner.DataTransmissions;
hit=arrayfun(@(r)r.Identity.TransmissionID==identity.TransmissionID,records);
assert(nnz(hit)==1 && isequaln(records(hit).Identity,identity) && ...
    records(hit).CommittedAtSample<=owner.Events.NextSampleIndex && ...
    records(hit).FirstActiveSample==item.Context.FirstActiveSample, ...
    'sixgr:truth:SharedDataTXNotExecuted','No matching active sample has physically executed.');
ledger=sixgr.util.structGet(state,'SharedDataTXLedger',{});
assert(~any(cellfun(@(r)r.Identity.TransmissionID==identity.TransmissionID,ledger)), ...
    'sixgr:truth:DuplicateSharedDataTXCommit','A physical attempt must affect queue and HARQ state exactly once.');
grant=prepared.RequestBinding.Grant;
bits=prepared.Tx.TransportBlock;
assert(isnumeric(bits) && isvector(bits) && ~isempty(bits) && ...
    all(bits(:)==0 | bits(:)==1) && mod(numel(bits),8)==0, ...
    'sixgr:truth:InvalidSharedDataTXPayload','Retain actual byte-aligned encoded transport-block bits.');
assert(double(grant.TBSBits)==numel(bits), ...
    'sixgr:truth:SharedDataTXTBSMismatch','Frozen grant and actual encoded payload size must agree.');
pid=double(sixgr.util.structGet(grant,'HARQ.HarqID',NaN));
validateattributes(pid,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
entity=state.DLHarq;
if prepared.Direction=="UL", entity=state.ULHarq; end
ue=find(entity.UEList==identity.RNTI);
assert(isscalar(ue) && pid<entity.NumProcesses, ...
    'sixgr:truth:SharedDataTXUnallocatedHARQ','The real scheduler must allocate the HARQ process before transmission.');
process=entity.UEProcs{ue}(pid+1);
assert(process.Active && process.NDI==grant.HARQ.NDI && process.RV==grant.HARQ.RV, ...
    'sixgr:truth:SharedDataTXHARQMismatch','TX must retain the allocated NDI/RV/process state.');
% Validate a real coding context before onTx mutates a shared handle.
grant.HARQTBContext=sixgr.harq.createTBContext(struct('Grant',grant, ...
    'PHYGrant',prepared.RequestBinding.PHYGrant,'Direction',prepared.Direction, ...
    'CodingLayout',prepared.Tx.CodingLayout,'TBSBits',numel(bits), ...
    'PreviousContext',process.TBContext));
slot0=prepared.ReceiverConfig.lls6g.runtime.AbsoluteSlotIndex0;
validateattributes(slot0,{'numeric'},{'scalar','real','finite','integer','nonnegative'});
grant.Slot=double(slot0)+1;
grant.Frame=floor(double(slot0)/double(prepared.Tx.Carrier.SlotsPerFrame))+1;
% Queue/packet ledgers are value state: validate their update before the
% shared HARQ handle mutates, then publish both updates together.
nextState=sixgr.truth.CoupledTruthRuntime.commitGrantExecution(state,item.UE,prepared.Direction,grant);
entity.onTx(identity.RNTI,pid,uint8(bits(:)),grant,grant.Slot);
state=nextState;
ledger{end+1,1}=struct('Identity',identity,'Grant',grant,'TransportBlockBits',int8(bits(:)), ...
    'FirstActiveSample',records(hit).FirstActiveSample, ...
    'CommittedAtSample',records(hit).CommittedAtSample, ...
    'Source',"actual_shared_physical_transmission_started_not_receiver_outcome");
state.SharedDataTXLedger=ledger;
end
