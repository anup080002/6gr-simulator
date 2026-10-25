function ok=testBroadcastRuntimeOrigin()
% Actual native broadcast generation/PBCH decode and shared enqueue binding.
% No RF/channel, shared receiver completion, access or data qualification.
setup6GRSimToolkit('Verbose',false);
savedRNG=rng; restore=onCleanup(@()rng(savedRNG)); %#ok<NASGU>
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_m10db.yaml');
folder=fullfile(pwd,'results','validation','broadcast_runtime_origin',char(java.util.UUID.randomUUID()));
mkdir(folder);
cfg=sixgr.lls6g.buildInternalConfig(scenario,folder); cfg.run.rootRunFolder=folder;
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,folder,multi,struct(),50);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
[state,owner]=sixgr.truth.CoupledWaveformStream.initialize(state,cfg,{cfg});
[dl,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'DL');
c=sixgr.phy.grid.makeCarrier(dl); slotsPerFrame=double(c.SlotsPerFrame);
original=dl; rows=struct('UnwrappedFrame',{},'RuntimeSlot0',{}, ...
    'BroadcastStartSample',{},'EncodedAndDecodedSFN',{},'LocalBufferSamples',{});
for frame=[0 2 1024]
    slot0=frame*slotsPerFrame;
    out=sixgr.link.runCellSearch_MIB_SIB1(dl,'PrepareOnly',true, ...
        'UseRuntimeChannel',true,'RuntimeSlot',slot0);
    assert(isfield(out,'PreparedBroadcast'),'%s',out.FailureReason);
    p=out.PreparedBroadcast;
    first=sixgr.phy.frame.slotStartSample(c,slot0,p.SampleRateHz);
    assert(isequaln(dl,original) && p.BroadcastStartAbsoluteSlot==slot0 && ...
        p.BroadcastStartSample==first && p.Tx.BroadcastStartAbsoluteSlot==slot0 && ...
        p.Tx.BroadcastStartSample==first && p.Config.phy.carrier.NFrame==frame && ...
        p.Config.phy.carrier.NSlot==0 && p.ReceiverConfig.phy.carrier.NFrame==frame && ...
        p.Config.lls6g.runtime.AbsoluteSlotIndex0==slot0);
    assert(p.NumSamples==size(p.TransmitSamples,1) && ...
        p.NumSamples<round(.1*p.SampleRateHz), ...
        'A later radio frame must not allocate a zero prefix from simulation origin.');
    for si=p.Tx.SIB1Transmissions
        assert(si.BroadcastStartAbsoluteSlot==slot0 && si.BroadcastStartSample==first && ...
            si.SIB1AbsoluteSlot>=slot0 && si.SIB1WaveformStartSample== ...
            sixgr.phy.frame.slotStartSample(c,si.SIB1AbsoluteSlot,p.SampleRateHz)-first);
    end
    assert(all(p.TxInfo.PortGridAbsoluteSymbolIndices>=slot0*c.SymbolsPerSlot) && ...
        p.TxInfo.WaveformStartAbsoluteSymbolIndex0==slot0*c.SymbolsPerSlot);
    % Decode the actual generated PBCH bits; metadata equality alone cannot
    % establish that the new radio frame reached the waveform generator.
    [grid,sync]=sixgr.phy.dl.SSB_Rx(p.TransmitSamples(:,1),p.ReceiverConfig, ...
        'SampleRate_Hz',p.SampleRateHz);
    [pbch,detail]=sixgr.phy.dl.PBCH_Recovery(grid,sync,p.ReceiverConfig);
    assert(pbch.Ok);
    mib=sixgr.phy.broadcast.decodeMIBTransportBlock(detail.Selected.trblk);
    receivedSFN=16*double(mib.SystemFrameNumberMSB6)+double(pbch.MIBSFN4LSBValue);
    assert(receivedSFN==mod(frame,1024) && pbch.HalfFrame==0);
    if frame==1024, localObservedRollover(p,receivedSFN,folder); end
    rows(end+1)=struct('UnwrappedFrame',frame,'RuntimeSlot0',slot0, ...
        'BroadcastStartSample',first,'EncodedAndDecodedSFN',receivedSFN, ...
        'LocalBufferSamples',p.NumSamples); %#ok<AGROW>
    if frame==2, later=p; end
end
% An absent RuntimeSlot preserves a genuinely authored frame; explicit zero
% remains a deliberate runtime origin, not a hidden default override.
authored=dl; authored.phy.carrier.NFrame=2; authored.phy.carrier.NSlot=0;
direct=sixgr.link.prepareCellSearchBroadcast(authored,true);
assert(direct.BroadcastStartAbsoluteSlot==later.BroadcastStartAbsoluteSlot && ...
    isequal(direct.TransmitSamples,later.TransmitSamples));

context=struct('Config',dl,'Slot',later.BroadcastStartAbsoluteSlot+1, ...
    'Frame',3,'UE',1,'ServingCell',1,'TrackingOnly',false);
random=rng; pending=owner.Pending; clock=owner.Events.NextSampleIndex;
bad=later; bad.BroadcastStartSample=bad.BroadcastStartSample+1;
reject(@()owner.queueDownlink('PBCH',1,bad,context),'sixgr:truth:SharedBroadcastOriginMismatch');
bad=later; bad.Tx.BroadcastStartAbsoluteSlot=0;
reject(@()owner.queueDownlink('PBCH',1,bad,context),'sixgr:truth:SharedBroadcastOriginMismatch');
bad=rmfield(later,'BroadcastStartAbsoluteSlot');
reject(@()owner.queueDownlink('PBCH',1,bad,context),'sixgr:truth:SharedBroadcastOriginMismatch');
wrongContext=context; wrongContext.Slot=wrongContext.Slot+slotsPerFrame;
reject(@()owner.queueDownlink('PBCH',1,later,wrongContext),'sixgr:truth:SharedBroadcastOriginMismatch');
assert(isequaln(owner.Pending,pending) && owner.Events.NextSampleIndex==clock && isequal(rng,random));
owner.queueDownlink('PBCH',1,later,context);
assert(numel(owner.Pending)==1 && owner.Events.NextSampleIndex==clock && ...
    owner.Pending.Context.Prepared.BroadcastStartSample==later.BroadcastStartSample);
% Reject a subframe/slot relocation before any native broadcast execution.
reject(@()sixgr.link.prepareCellSearchBroadcast(dl,true,'RuntimeSlot',1), ...
    'sixgr:link:BroadcastRuntimeFrameAlignment');
bad=authored; bad.phy.carrier.NSlot=1;
reject(@()sixgr.link.prepareCellSearchBroadcast(bad,true), ...
    'sixgr:link:BroadcastRuntimeFrameAlignment');
localPhysicalPowerOrigin(scenario,folder);
sixgr.util.csvWriteTable(fullfile(folder,'producer_clock_cases.csv'),struct2table(rows), ...
    'PreserveSchema',true,'RoundTripNumericText',true);
fprintf('BROADCAST_RUNTIME_ORIGIN_PASS frames=0,2,1024 native_PBCH=3 shared_enqueue=1 physical_channel_executions=0 folder=%s\n',folder);
ok=true;
end

function localObservedRollover(p,decodedSFN,folder)
% Reuse this exact generated/decoded TX, with no additional waveform or
% channel execution. The observation is a TX publication fixture, not RX.
before=sixgr.phy.waveform.WaveformHash.runtimeArray(p.TransmitSamples);
observation=sixgr.phy.waveform.WaveformObservationBuffer( ...
    p.BroadcastStartSample,p.BroadcastStartSample+p.NumSamples, ...
    p.SampleRateHz,size(p.TransmitSamples,2));
observation.append(sixgr.phy.waveform.WaveformChunk( ...
    p.TransmitSamples,p.BroadcastStartSample),p.SampleRateHz);
T=sixgr.truth.buildObservedBroadcastREAllocation(p,observation,1);
assert(~isempty(T) && all(T.sfn==decodedSFN) && decodedSFN==0 && ...
    all(T.absolute_slot>=p.BroadcastStartAbsoluteSlot) && ...
    all(T.slot_within_frame==mod(T.absolute_slot,p.Tx.Carrier.SlotsPerFrame)) && ...
    observation.sampleHash()==before && ...
    sixgr.phy.waveform.WaveformHash.runtimeArray(p.TransmitSamples)==before);
ssb=T(T.channel=="SSB",:); si=T(T.channel~="SSB",:);
assert(sum(ssb.re_count)==nnz(p.Tx.SSBWaveInfo.SSBComposite.TransmitPortResourceGrid));
expectedSI=0;
for part=p.Tx.SIB1Transmissions
    expectedSI=expectedSI+nnz(sixgr.link.broadcastSIB1WaveformPortGrid(part));
end
assert(sum(si.re_count)==expectedSI && ...
    all(ismember(si.absolute_slot,[p.Tx.SIB1Transmissions.SIB1AbsoluteSlot])));
layout=sixgr.report.resultLayout(fullfile(folder,'frame1024_original_tx'));
[written,native,ssbNative]=sixgr.truth.writeObservedREAllocationArtifacts(T,p.Config,layout);
assert(isempty(native) && isempty(ssbNative) && height(written)==height(T));
path=fullfile(layout.ComponentCSVDirs.frame_grid,'observed_re_allocation.csv');
saved=sixgr.util.csvReadTable(path,'TextType','string');
for name=["absolute_slot","sfn","slot_within_frame","symbol_index", ...
        "subcarrier_start","subcarrier_count","port_index","re_count"]
    assert(isequal(saved.(name),written.(name)), ...
        'Observed rollover CSV changed original %s coordinates.',name);
end
assert(sixgr.util.sha256File(path)==sixgr.util.sha256File( ...
    fullfile(layout.ReportCSVDir,'live_re_allocation_snapshot.csv')));
fprintf('OBSERVED_RE_SFN_WRAP_PASS original_frame=1024 sfn=0 rows=%d CSV=%s\n',height(T),path);
end

function localPhysicalPowerOrigin(scenario,folder)
% A separately authored absolute-power fixture exercises the fixed-EPRE
% join which normalized fixed-SNR preparation deliberately does not use.
% No physical channel, noise draw, RF stage or receiver is executed here.
d=scenario.toStruct();
for base=["integration","canonical_control.integration"]
    d=sixgr.util.structSet(d,base+".run_mode","GEOMETRY_NETWORK");
    d=sixgr.util.structSet(d,base+".subprofile","connected_network");
    d=sixgr.util.structSet(d,base+".configured_snr_is_link_authority",false);
    d=sixgr.util.structSet(d,base+".power_reference_mode","absolute_calibrated_sqrt_mw");
end
d.simulation.noise_operating_mode="receiver_noise_figure_thermal_noise";
cfg=sixgr.lls6g.buildInternalConfig(d,folder); cfg.run.rootRunFolder=folder;
c=sixgr.phy.grid.makeCarrier(cfg); origin=2*double(c.SlotsPerFrame);
p0=sixgr.link.prepareCellSearchBroadcast(cfg,true,'RuntimeSlot',0);
p2=sixgr.link.prepareCellSearchBroadcast(cfg,true,'RuntimeSlot',origin);
for p={p0,p2}
    p=p{1}; ctx=p.PowerContext;
    assert(~ctx.FixedSNRNormalizedReference && ctx.PhysicalDevicePowerClaim && ...
        string(ctx.WaveformAmplitudeUnit)=="sqrt_mW" && ctx.ScaleApplied && ...
        string(ctx.PowerNormalizationPolicy)=="fixed_epre_over_configured_bwp" && ...
        ~ctx.PAApplied && ...
        ctx.NormalizationWaveformStartAbsoluteSymbolIndex0== ...
            p.BroadcastStartAbsoluteSlot*c.SymbolsPerSlot && ...
        string(ctx.NormalizationGridSymbolIdentity)== ...
            "original_TX_absolute_grid_joined_to_buffer_local_active_symbols");
    assert(isequal(p.TransmitSamples, ...
        p.Tx.Waveform.*cast(ctx.AmplitudeScale,'like',p.Tx.Waveform)));
    [~,~,local]=sixgr.rf.measureActiveOFDMTotalPower(p.Tx.Waveform,p.TxInfo);
    absolute=local.ActiveSymbolIndices+p.TxInfo.WaveformStartAbsoluteSymbolIndex0;
    assert(all(ismember(absolute,p.TxInfo.PortGridAbsoluteSymbolIndices)) && ...
        numel(local.ActiveSymbolIndices)==ctx.NormalizationGridActiveSymbolCount);
end
% SFN bits may change, but the same allocation and unit-energy modulation
% do not change the full-BWP reference just because its epoch moved.
for name=["AmplitudeScale","ReferenceInputPower_mW","FullBWPActivityFactor", ...
        "NormalizationGridMeanEnergyPerRE","OutputTotalPower_mW"]
    a=double(p0.PowerContext.(name)); b=double(p2.PowerContext.(name));
    assert(isfinite(a) && isfinite(b) && a>0 && b>0 && ...
        abs(a-b)<=1e-10*max(a,b), ...
        'Epoch relocation changed physical reference %s.',name);
end
assert(p0.PowerContext.NormalizationGridActiveSymbolCount== ...
    p2.PowerContext.NormalizationGridActiveSymbolCount);
assert(isequal(p0.TxInfo.PortGridAbsoluteSymbolIndices, ...
    p2.TxInfo.PortGridAbsoluteSymbolIndices-origin*c.SymbolsPerSlot));
% Changing a current configuration timestamp is not authority to relabel
% original TX sample/grid operands; only the retained TX origin is used.
poison=p2.Config;
poison.lls6g.userContext.RuntimeSlotStartTime_s=123;
[same,ctx]=sixgr.rf.applyPowerContext(p2.Tx.Waveform,poison,'DL',p2.TxInfo,'ApplyPA',false);
assert(isequal(same,p2.TransmitSamples) && ctx.AmplitudeScale==p2.PowerContext.AmplitudeScale);
bad=rmfield(p2.TxInfo,'WaveformStartAbsoluteSymbolIndex0');
reject(@()sixgr.rf.applyPowerContext(p2.Tx.Waveform,p2.Config,'DL',bad,'ApplyPA',false), ...
    'sixgr:rf:InvalidPowerNormalizationGridSymbolOrigin');
for invalid={-1,NaN,Inf,.5,'0',single(0),[0 1],flintmax}
    bad=p2.TxInfo; bad.WaveformStartAbsoluteSymbolIndex0=invalid{1};
    reject(@()sixgr.rf.applyPowerContext(p2.Tx.Waveform,p2.Config,'DL',bad,'ApplyPA',false), ...
        'sixgr:rf:InvalidPowerNormalizationGridSymbolOrigin');
end
bad=p2.TxInfo; bad.WaveformStartAbsoluteSymbolIndex0=0;
reject(@()sixgr.rf.applyPowerContext(p2.Tx.Waveform,p2.Config,'DL',bad,'ApplyPA',false), ...
    'sixgr:rf:DLFullBWPActiveSymbolGridMismatch');
T=table([0;2],[p0.PowerContext.AmplitudeScale;p2.PowerContext.AmplitudeScale], ...
    [p0.PowerContext.ReferenceInputPower_mW;p2.PowerContext.ReferenceInputPower_mW], ...
    'VariableNames',{'UnwrappedFrame','AmplitudeScale','ReferenceInputPower_mW'});
sixgr.util.csvWriteTable(fullfile(folder,'physical_power_origin_cases.csv'),T, ...
    'PreserveSchema',true,'RoundTripNumericText',true);
fprintf('BROADCAST_PHYSICAL_POWER_ORIGIN_PASS frames=0,2 native_preparations=2 channel_RF_RX_executions=0\n');
end

function reject(f,id)
try, f(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s; got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('sixgr:test:ExpectedBroadcastOriginError','Expected %s.',id);
end
