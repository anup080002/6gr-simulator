function T=buildObservedBroadcastREAllocation(prepared,txObservation,cellID)
%BUILDOBSERVEDBROADCASTREALLOCATION Committed SS/PBCH and SI-RNTI TX resources.
% Receiver success is deliberately not an input. Decode failure cannot erase
% a transmission. Ownership is checked against retained Toolbox samples/grids;
% no resource is published solely because the scenario planned it.
tx=prepared.Tx; carrier=tx.Carrier; fs=prepared.SampleRateHz;
assert(txObservation.isComplete() && txObservation.SampleRateHz==fs && ...
    txObservation.EndSampleExclusive-txObservation.StartSample==prepared.NumSamples && ...
    txObservation.NumReceiveAntennas==size(prepared.TransmitSamples,2), ...
    'sixgr:truth:BroadcastGridObservationMismatch','Complete committed broadcast TX observation is required.');
base=txObservation.StartSample/(fs/(1000*carrier.SlotsPerSubframe));
assert(isfinite(base) && base>=0 && base==fix(base), ...
    'sixgr:truth:BroadcastGridOriginMismatch','Broadcast starts on a canonical carrier slot boundary.');
assert(tx.SSBInfo.SSBTiming.SSBSubcarrierSpacingKHz==carrier.SubcarrierSpacing, ...
    'sixgr:truth:BroadcastGridNumerologyMismatch','Do not invent an equal-numerology grid for mixed numerology.');
logicalGrid=tx.SSBWaveInfo.ResourceGridSSBurst.ResourceGrid;
portGrid=tx.SSBWaveInfo.SSBComposite.TransmitPortResourceGrid;
assert(size(logicalGrid,1)==240 && size(logicalGrid,3)==1 && ...
    size(portGrid,1)==240 && size(portGrid,2)==size(logicalGrid,2) && ...
    size(portGrid,3)==size(prepared.TransmitSamples,2) && ...
    all(isfinite(portGrid),'all') && isequal(any(portGrid~=0,3),logicalGrid~=0), ...
    'sixgr:truth:BroadcastGridPortMismatch','Actual SSB logical and mapped waveform-port support must agree.');
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
mapping=tx.SIB1SpatialMapping;
assert(tx.SIB1WaveformStartSample==sixgr.phy.frame.slotStartSample(carrier,tx.SIB1AbsoluteSlot,fs) && ...
    tx.SIB1WaveformStartSample+size(tx.SIB1Waveform,1)<=prepared.NumSamples, ...
    'sixgr:truth:SIB1GridTimingMismatch','SIB1 slot must match its committed waveform offset.');
for channel=["PDCCH","PDSCH"]
    original=tx.(channel+"Tx"); mapped=original;
    if channel=="PDCCH"
        original.PDCCHIndices=original.PDCCHInd;
        original.DMRSIndices=original.DMRSInd;
    end
    if mapping.MatrixAppliedHere
        assert(size(original.Grid,3)==1 && numel(mapping.PrecoderMatrix)==size(prepared.TransmitSamples,2), ...
            'sixgr:truth:SIB1GridPortMismatch','SIB1 must use its actual associated-SSB mapping.');
        mapped.Grid=reshape(original.Grid(:)*mapping.PrecoderMatrix, ...
            size(original.Grid,1),size(original.Grid,2),numel(mapping.PrecoderMatrix));
    end
    % Materialize channel components from the retained executed logical TX,
    % then project their exact RE indices onto the actual waveform ports.
    source=sixgr.truth.buildObservedREAllocation(original,'Channel',channel,'Direction','DL', ...
        'AbsoluteSlot',base+tx.SIB1AbsoluteSlot,'CellID',cellID, ...
        'AllocationID',"sib1_"+lower(channel)+"_cell_"+cellID+"_burst_"+base);
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
    T=[T;vertcat(parts{:})]; %#ok<AGROW>
end
T=sixgr.truth.deduplicateObservedREAllocation(T);
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
end
