function T=buildObservedSSBNativeAllocation(p,observation,cellID)
% Exact emitted SS/PBCH REs on their own OFDM clock and frequency lattice.
% Never project a native RE into multiple carrier REs and count those as
% transmitted symbols. Carrier PRB intersections belong to a separate load
% model; these rows retain original beam/port/component ownership.
tx=p.Tx; common=tx.Carrier; fs=double(p.SampleRateHz);
assert(isa(observation,'sixgr.phy.waveform.WaveformObservationBuffer') && ...
    isscalar(observation) && observation.isComplete() && ...
    observation.SampleRateHz==fs && ...
    observation.EndSampleExclusive-observation.StartSample==p.NumSamples && ...
    observation.NumReceiveAntennas==size(p.TransmitSamples,2), ...
    'sixgr:truth:BroadcastGridObservationMismatch', ...
    'Native SS/PBCH evidence requires its complete original committed observation.');
assert(all(isfield(p,{'BroadcastStartAbsoluteSlot','BroadcastStartSample'})) && ...
    all(isfield(tx,{'BroadcastStartAbsoluteSlot','BroadcastStartSample'})) && ...
    isequal(p.BroadcastStartAbsoluteSlot,tx.BroadcastStartAbsoluteSlot) && ...
    isequal(p.BroadcastStartSample,tx.BroadcastStartSample) && ...
    isequal(p.BroadcastStartSample,observation.StartSample) && ...
    isequal(p.BroadcastStartSample,sixgr.phy.frame.slotStartSample( ...
        common,p.BroadcastStartAbsoluteSlot,fs)), ...
    'sixgr:truth:BroadcastGridOriginMismatch', ...
    'Native SS/PBCH rows cannot transplant original IQ into another radio frame.');
scs=double(tx.SSBInfo.SSBTiming.SSBSubcarrierSpacingKHz);
grid=tx.SSBWaveInfo.SSBComposite.TransmitPortResourceGrid;
logicalGrid=tx.SSBWaveInfo.ResourceGridSSBurst.ResourceGrid;
assert(size(grid,1)==240 && size(logicalGrid,3)==1 && ...
    size(grid,2)==size(logicalGrid,2) && size(grid,3)==size(p.TransmitSamples,2) && ...
    all(isfinite(grid),'all') && isequal(any(grid~=0,3),logicalGrid~=0), ...
    'sixgr:truth:BroadcastGridPortMismatch','Native SSB logical and waveform-port support must agree.');
native=nrCarrierConfig('NSizeGrid',20,'SubcarrierSpacing',scs, ...
    'NCellID',common.NCellID,'CyclicPrefix','normal');
clock=sixgr.truth.ssbEmittedSymbolClock(grid,size(tx.SSBWaveform,1),scs,fs);
starts=clock.CPStartSample0; cp=clock.CyclicPrefixLengths;
nSymbols=size(grid,2);
origin=double(observation.StartSample);
nativeBase=origin/(fs/(1000*native.SlotsPerSubframe));
commonBase=origin/(fs/(1000*common.SlotsPerSubframe));
assert(all(isfinite([nativeBase commonBase])) && all([nativeBase commonBase]>=0) && ...
    all([nativeBase commonBase]==fix([nativeBase commonBase])), ...
    'sixgr:truth:BroadcastGridOriginMismatch','Broadcast origin must align to both actual OFDM slot clocks.');
ownership=tx.SSBInfo.SSBResourceOwnership.Rows;
assert(tx.SSBInfo.SSBResourceOwnership.NCellID==common.NCellID, ...
    'sixgr:truth:BroadcastGridPCIMismatch','SS/PBCH ownership must use the transmitted PCI.');
v=tx.SSBInfo.SSBGridValidation;
low=double(v.SSBLowOffsetFromPointAHz-v.CarrierLowOffsetFromPointAHz);
bandwidth=12*double(common.NSizeGrid)*double(common.SubcarrierSpacing)*1000;
assert(isfinite(low) && low>=0 && low+240*scs*1000<=bandwidth, ...
    'sixgr:truth:BroadcastGridFrequencyMismatch','Native SS/PBCH must lie inside the common carrier.');
plan=tx.SSBBurstPlan;
period=double(plan.PeriodicityMs)*double(native.SlotsPerSubframe)*14;
assert(period>0 && period==fix(period),'sixgr:truth:BroadcastGridPeriod','Invalid native SSB period.');
used=false(size(logicalGrid)); T=table();
fields=["PSSIndices","SSSIndices","PBCHIndices","DMRSIndices"];
labels=["PSS","SSS","PBCH","PBCH_DMRS"];
hash=string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(grid));
for cycle=0:period:nSymbols-1
    for index=reshape(plan.ActiveSSBIndices0Based,1,[])
        first=cycle+plan.AbsoluteCandidateSymbols0Based(index+1);
        if first+4>nSymbols, continue; end
        block=logicalGrid(:,first+(1:4));
        if ~any(block~=0,'all'), continue; end
        expected=reshape(ownership.Owner~="ZERO",240,4);
        assert(isequal(block~=0,expected),'sixgr:truth:BroadcastGridOwnershipMismatch', ...
            'Generated native SSB support disagrees with retained signal ownership.');
        used(:,first+(1:4))=expected;
        mapped=struct('Carrier',native,'Grid',grid);
        for k=1:numel(fields)
            rows=ownership(ownership.Owner==labels(k),:); parts=cell(size(grid,3),1);
            for port=1:size(grid,3)
                ids=sub2ind([size(grid,1) size(grid,2) size(grid,3)],rows.Subcarrier0+1,first+rows.Symbol0+1, ...
                    repmat(port,height(rows),1));
                parts{port}=ids(grid(ids)~=0);
            end
            mapped.(fields(k))=vertcat(parts{:});
        end
        id="ssb_cell_"+cellID+"_burst_"+commonBase+"_index_"+index+"_cycle_"+cycle;
        part=sixgr.truth.buildObservedREAllocation(mapped,'Channel','SSB','Direction','DL', ...
            'AbsoluteSlot',nativeBase,'CellID',cellID,'AllocationID',id);
        symbol=(part.absolute_slot-nativeBase)*14+part.symbol_index+1;
        n=height(part);
        part.grid_domain(:)="ssb_native_cp_ofdm";
        part.coordinate_precision(:)="exact_native_ssb_grid_run";
        part.grid_subcarrier_spacing_hz=repmat(scs*1000,n,1);
        part.grid_subcarrier_count=repmat(240,n,1);
        part.grid_symbol_count=repmat(nSymbols,n,1);
        part.emitted_symbol_count=repmat(nnz(clock.EmittedSymbolMask),n,1);
        part.native_symbol_index_from_burst=symbol-1;
        part.carrier_origin_slot0=repmat(commonBase,n,1);
        part.ssb_index0=repmat(index,n,1); part.associated_ssb_index0=part.ssb_index0;
        part.rnti=NaN(n,1);
        part.waveform_port_domain=repmat(string(tx.SSBInfo.WaveformDomain),n,1);
        part.transmit_grid_sha256=repmat(hash,n,1);
        part.broadcast_start_sample=repmat(origin,n,1);
        part.broadcast_end_sample_exclusive=repmat(double(observation.EndSampleExclusive),n,1);
        part.observation_sample_rate_hz=repmat(fs,n,1);
        part.cp_start_sample=origin+starts(symbol);
        part.useful_start_sample=part.cp_start_sample+cp(symbol);
        part.useful_end_sample_exclusive=part.useful_start_sample+clock.Nfft;
        part.frequency_first_hz=low-bandwidth/2+part.subcarrier_start*scs*1000;
        part.frequency_last_hz=part.frequency_first_hz+(part.subcarrier_count-1)*scs*1000;
        part.frequency_axis_source=repmat("native_bin_centers_relative_to_common_carrier_center",n,1);
        part.authority(:)="executed_broadcast_tx_grid_and_committed_waveform_interval";
        T=[T;part]; %#ok<AGROW>
    end
end
assert(isequal(used,logicalGrid~=0),'sixgr:truth:UnclassifiedBroadcastGrid', ...
    'Every emitted native SS/PBCH RE must have exact component ownership.');
end
