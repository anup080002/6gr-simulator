function T=buildObservedBroadcastREAllocation(prepared,txObservation,cellID)
%BUILDOBSERVEDBROADCASTREALLOCATION Committed SS/PBCH and SI-RNTI TX resources.
% Receiver success is deliberately not an input. Decode failure cannot erase
% a transmission. Ownership is checked against retained Toolbox samples/grids;
% no resource is published solely because the scenario planned it.
tx=prepared.Tx; carrier=tx.Carrier; fs=prepared.SampleRateHz;
ssbOnly=localSSBOnly(prepared,tx);
assert(txObservation.isComplete() && txObservation.SampleRateHz==fs && ...
    txObservation.EndSampleExclusive-txObservation.StartSample==prepared.NumSamples && ...
    txObservation.NumReceiveAntennas==size(prepared.TransmitSamples,2), ...
    'sixgr:truth:BroadcastGridObservationMismatch','Complete committed broadcast TX observation is required.');
base=txObservation.StartSample/(fs/(1000*carrier.SlotsPerSubframe));
assert(isfinite(base) && base>=0 && base==fix(base), ...
    'sixgr:truth:BroadcastGridOriginMismatch','Broadcast starts on a canonical carrier slot boundary.');
siOnly=isfield(tx,'SSBEmissionIncluded') && isequal(tx.SSBEmissionIncluded,false) && ...
    string(tx.WaveformContent)=="si_rnti_pdcch_pdsch_only";
if siOnly
assert(prepared.TransmitStartSample==txObservation.StartSample && ...
    tx.WaveformStartAbsoluteSample==txObservation.StartSample && ...
    tx.SIB1AbsoluteSlot==base, ...
    'sixgr:truth:SIB1GridTimingMismatch','SI-only TX must retain its own original radio origin.');
T=table();
else
assert(all(isfield(prepared,{'BroadcastStartAbsoluteSlot','BroadcastStartSample'})) && ...
    all(isfield(tx,{'BroadcastStartAbsoluteSlot','BroadcastStartSample'})) && ...
    isequal(prepared.BroadcastStartAbsoluteSlot,base) && ...
    isequal(tx.BroadcastStartAbsoluteSlot,base) && ...
    isequal(prepared.BroadcastStartSample,txObservation.StartSample) && ...
    isequal(tx.BroadcastStartSample,txObservation.StartSample), ...
    'sixgr:truth:BroadcastGridOriginMismatch', ...
    'Committed samples must retain their original encoded broadcast radio-frame origin.');
if tx.SSBInfo.SSBTiming.SSBSubcarrierSpacingKHz~=carrier.SubcarrierSpacing
    T=sixgr.truth.buildObservedSSBNativeAllocation(prepared,txObservation,cellID);
else
logicalGrid=tx.SSBWaveInfo.ResourceGridSSBurst.ResourceGrid;
portGrid=tx.SSBWaveInfo.SSBComposite.TransmitPortResourceGrid;
assert(size(logicalGrid,1)==240 && size(logicalGrid,3)==1 && ...
    size(portGrid,1)==240 && size(portGrid,2)==size(logicalGrid,2) && ...
    size(portGrid,3)==size(prepared.TransmitSamples,2) && ...
    all(isfinite(portGrid),'all') && isequal(any(portGrid~=0,3),logicalGrid~=0), ...
    'sixgr:truth:BroadcastGridPortMismatch','Actual SSB logical and mapped waveform-port support must agree.');
sixgr.truth.ssbEmittedSymbolClock(portGrid,size(tx.SSBWaveform,1), ...
    tx.SSBInfo.SSBTiming.SSBSubcarrierSpacingKHz,fs);
v=tx.SSBInfo.SSBGridValidation;
low=(v.SSBLowOffsetFromPointAHz-v.CarrierLowOffsetFromPointAHz)/(1000*carrier.SubcarrierSpacing);
assert(isfinite(low) && low>=0 && low==fix(low) && low+240<=12*carrier.NSizeGrid, ...
    'sixgr:truth:BroadcastGridFrequencyMismatch','Retained SSB placement must fit the actual carrier subcarriers.');
grid=zeros(12*carrier.NSizeGrid,size(portGrid,2),size(portGrid,3),'like',portGrid);
grid(low+(1:240),:,:)=portGrid;
ownership=tx.SSBInfo.SSBResourceOwnership.Rows;
assert(tx.SSBInfo.SSBResourceOwnership.NCellID==carrier.NCellID, ...
    'sixgr:truth:BroadcastGridPCIMismatch','SS/PBCH ownership must use the transmitted PCI.');
plan=tx.SSBBurstPlan; used=false(size(logicalGrid)); T=table();
period=plan.PeriodicityMs*carrier.SlotsPerSubframe*carrier.SymbolsPerSlot;
assert(period>0 && period==fix(period),'sixgr:truth:BroadcastGridPeriod','Invalid retained SSB period.');
fields=["PSSIndices","SSSIndices","PBCHIndices","DMRSIndices"];
labels=["PSS","SSS","PBCH","PBCH_DMRS"];
for cycle=0:period:size(logicalGrid,2)-1
    for index=reshape(plan.ActiveSSBIndices0Based,1,[])
        first=cycle+plan.AbsoluteCandidateSymbols0Based(index+1);
        if first+4>size(logicalGrid,2), continue; end
        block=logicalGrid(:,first+(1:4));
        if ~any(block~=0,'all'), continue; end
        expected=reshape(ownership.Owner~="ZERO",240,4);
        assert(isequal(block~=0,expected),'sixgr:truth:BroadcastGridOwnershipMismatch', ...
            'Generated SSB support disagrees with retained PSS/SSS/PBCH/DMRS ownership.');
        used(:,first+(1:4))=expected;
        mapped=struct('Carrier',carrier,'Grid',grid);
        for k=1:numel(fields)
            rows=ownership(ownership.Owner==labels(k),:);
            indices=[];
            for port=1:size(grid,3)
                ids=sub2ind([size(grid,1) size(grid,2) size(grid,3)],low+rows.Subcarrier0+1,first+rows.Symbol0+1, ...
                    repmat(port,height(rows),1));
                indices=[indices;ids(grid(ids)~=0)]; %#ok<AGROW>
            end
            mapped.(fields(k))=indices;
        end
        id="ssb_cell_"+cellID+"_burst_"+base+"_index_"+index+"_cycle_"+cycle;
        part=sixgr.truth.buildObservedREAllocation(mapped,'Channel','SSB','Direction','DL', ...
            'AbsoluteSlot',base,'CellID',cellID,'AllocationID',id);
        part=localMetadata(part,prepared,txObservation,index,index,NaN,grid);
        T=[T;part]; %#ok<AGROW>
    end
end
assert(isequal(used,logicalGrid~=0),'sixgr:truth:UnclassifiedBroadcastGrid', ...
    'Every transmitted SS/PBCH RE must have exact signal ownership.');
end
end
if ssbOnly
    transmissions=tx.SIB1Transmissions;
    T.authority(:)="executed_ssb_mib_only_tx_grid_and_committed_waveform_interval";
else
    transmissions=sixgr.phy.broadcast.retainedSIB1Transmissions(tx);
end
for occasion=1:numel(transmissions)
si=transmissions(occasion);
mapping=si.SIB1SpatialMapping;
if siOnly
assert(si.SIB1AbsoluteSlot==base && si.SIB1WaveformAbsoluteStartSample==txObservation.StartSample && ...
    size(si.SIB1Waveform,1)==prepared.NumSamples, ...
    'sixgr:truth:SIB1GridTimingMismatch','Independent SI resources must belong to the actual transmitted slot.');
else
assert(si.BroadcastStartAbsoluteSlot==base && si.BroadcastStartSample==txObservation.StartSample && ...
    si.SIB1WaveformStartSample==sixgr.phy.frame.slotStartSample(carrier,si.SIB1AbsoluteSlot,fs)-txObservation.StartSample && ...
    si.SIB1WaveformStartSample>=0 && ...
    si.SIB1WaveformStartSample+size(si.SIB1Waveform,1)<=prepared.NumSamples, ...
    'sixgr:truth:SIB1GridTimingMismatch','SIB1 slot must match its committed waveform offset.');
end
for channel=["PDCCH","PDSCH"]
    original=si.(channel+"Tx"); mapped=original;
    if channel=="PDCCH"
        original.PDCCHIndices=original.PDCCHInd;
        original.DMRSIndices=original.DMRSInd;
    end
    mapped.Grid=sixgr.link.broadcastSIB1WaveformPortGrid(si,original.Grid);
    % Materialize channel components from the retained executed logical TX,
    % then project their exact RE indices onto the actual waveform ports.
    source=sixgr.truth.buildObservedREAllocation(original,'Channel',channel,'Direction','DL', ...
        'AbsoluteSlot',si.SIB1AbsoluteSlot,'CellID',cellID, ...
        'AllocationID',"sib1_"+lower(channel)+"_cell_"+cellID+"_burst_"+base+"_ssb_"+mapping.SSBIndex);
    parts=cell(size(mapped.Grid,3),1);
    for port=1:size(mapped.Grid,3)
        keep=true(height(source),1);
        for r=1:height(source)
            sc=source.subcarrier_start(r)+(1:source.subcarrier_count(r));
            values=mapped.Grid(sc,source.symbol_index(r)+1,port);
            assert(all(values~=0) || all(values==0),'sixgr:truth:SIB1PartialSpatialMap', ...
                'A wideband SIB1 port map cannot partially erase a contiguous RE run.');
            keep(r)=any(values~=0);
        end
        part=source(keep,:); part.port_index(:)=port-1;
        parts{port}=localMetadata(part,prepared,txObservation,NaN,mapping.SSBIndex,65535,mapped.Grid);
    end
    T=localAppendDomains(T,vertcat(parts{:}));
end
end
T=sixgr.truth.deduplicateObservedREAllocation(T);
end

function yes=localSSBOnly(p,tx)
% An empty SI collection is legal only under the frozen producer contract.
yes=localTextIs(tx,'Content',"SSB_MIB") || ...
    localTextIs(tx,'WaveformContent',"ssb_mib_only") || ...
    localTextIs(p,'Content',"SSB_MIB") || localTextIs(p,'WaveformContent',"ssb_mib_only");
if ~yes, return; end
assert(localTextIs(tx,'Content',"SSB_MIB") && localTextIs(p,'Content',"SSB_MIB") && ...
    localTextIs(tx,'WaveformContent',"ssb_mib_only") && localTextIs(p,'WaveformContent',"ssb_mib_only") && ...
    isfield(tx,'SSBEmissionIncluded') && isequal(tx.SSBEmissionIncluded,true) && ...
    isfield(tx,'SIB1EmissionIncluded') && isequal(tx.SIB1EmissionIncluded,false) && ...
    isfield(tx,'SIB1Transmissions') && isstruct(tx.SIB1Transmissions) && isempty(tx.SIB1Transmissions) && ...
    isfield(tx,'SIB1TransmitSSBIndices0Based') && isnumeric(tx.SIB1TransmitSSBIndices0Based) && ...
    isempty(tx.SIB1TransmitSSBIndices0Based) && ...
    ~any(isfield(tx,{'SIB1Grid','PDCCHTx','PDSCHTx','SIB1Waveform'})), ...
    'sixgr:truth:BroadcastContentMismatch','SSB-only resources require the exact original content contract and no SI payload aliases.');
end

function yes=localTextIs(s,name,expected)
yes=false;
if ~isfield(s,name), return; end
x=s.(name);
if (isstring(x) && isscalar(x) && ~ismissing(x)) || (ischar(x) && isrow(x))
    yes=string(x)==expected;
end
end

function T=localAppendDomains(T,S)
% Different native clocks require different metadata, never invented values.
names=union(T.Properties.VariableNames,S.Properties.VariableNames,'stable');
for name=string(names)
    if ~ismember(name,T.Properties.VariableNames)
        T.(name)=localMissingLike(S.(name),height(T));
    elseif ~ismember(name,S.Properties.VariableNames)
        S.(name)=localMissingLike(T.(name),height(S));
    end
end
T=[T(:,names);S(:,names)];
end

function values=localMissingLike(example,n)
if isstring(example)
    values=strings(n,1);
elseif isnumeric(example)
    values=NaN(n,1);
elseif islogical(example)
    values=false(n,1);
else
    error('sixgr:truth:UnsupportedBroadcastMetadata','Unsupported native-grid metadata type %s.',class(example));
end
end

function T=localMetadata(T,p,observation,ssb,associated,rnti,grid)
n=height(T);
T.ssb_index0=repmat(double(ssb),n,1);
T.associated_ssb_index0=repmat(double(associated),n,1);
T.rnti=repmat(double(rnti),n,1);
T.waveform_port_domain=repmat(string(p.Tx.SSBInfo.WaveformDomain),n,1);
T.transmit_grid_sha256=repmat(string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(grid)),n,1);
T.broadcast_start_sample=repmat(double(observation.StartSample),n,1);
T.broadcast_end_sample_exclusive=repmat(double(observation.EndSampleExclusive),n,1);
T.observation_sample_rate_hz=repmat(double(observation.SampleRateHz),n,1);
T.authority(:)="executed_broadcast_tx_grid_and_committed_waveform_interval";
if isfield(p.Tx,'SSBEmissionIncluded') && isequal(p.Tx.SSBEmissionIncluded,false)
    T.authority(:)="executed_si_only_tx_grid_and_committed_waveform_interval";
end
end
