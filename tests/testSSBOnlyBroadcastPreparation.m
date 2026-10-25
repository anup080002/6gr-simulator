function ok=testSSBOnlyBroadcastPreparation()
% Actual native SS/PBCH preparation and unit-link BCH reception.
% No shared RF/channel, independently scheduled SI or UE installation claim.
setup6GRSimToolkit('Verbose',false);
saved=rng; restore=onCleanup(@()rng(saved)); %#ok<NASGU>
folder=fullfile(pwd,'results','validation','ssb_only_broadcast',char(java.util.UUID.randomUUID()));
mkdir(folder); fprintf('SSB_ONLY_BROADCAST_EVIDENCE %s\n',folder);
owned=~sixgr.runtime.RuntimeCallLedger.isConfigured();
if owned, sixgr.runtime.RuntimeCallLedger.configure(folder,struct('RunId',"ssb_only")); end
cleanup=onCleanup(@()releaseLedger(owned)); %#ok<NASGU>
files=[string(mfilename('fullpath'))+".m", ...
    string(which('sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform')), ...
    string(which('sixgr.link.prepareCellSearchBroadcast')), ...
    string(which('sixgr.link.completeCellSearchBroadcast')), ...
    string(which('sixgr.link.runCellSearch_MIB_SIB1'))];
hashes=arrayfun(@(f)string(sixgr.util.sha256File(f)),files);
sixgr.util.csvWriteTable(fullfile(folder,'source_hashes.csv'), ...
    table(files(:),hashes(:),'VariableNames',{'Path','SHA256'}),'PreserveSchema',true);
ledger=sixgr.runtime.RuntimeCallLedger.snapshot();
status=profile('status'); assert(strcmp(status.ProfilerStatus,'off'));
profile clear; cleanupProfile=onCleanup(@()profile('off')); profile on;
for scs=[15 30]
    cfg=configuration(scs,folder); original=cfg;
    carrier=sixgr.phy.grid.makeCarrier(cfg);
    for frame=[0 2]
        slot=frame*double(carrier.SlotsPerFrame);
        p=sixgr.link.prepareCellSearchBroadcast(cfg,true,'Content','SSB_MIB','RuntimeSlot',slot);
        assertContent(p,cfg);
        assert(p.Config.phy.carrier.NFrame==frame && p.Config.phy.carrier.NSlot==0 && ...
            p.BroadcastStartAbsoluteSlot==slot && ...
            p.BroadcastStartSample==sixgr.phy.frame.slotStartSample(carrier,slot,p.SampleRateHz) && ...
            p.Tx.WaveformStartAbsoluteSample==p.BroadcastStartSample && ...
            p.Tx.WaveformStartAbsoluteSymbolIndex0==slot*carrier.SymbolsPerSlot && ...
            p.NumSamples==size(p.Tx.SSBWaveform,1) && ...
            p.NumSamples==round(.005*p.SampleRateHz));
        assert(isequal(p.TransmitSamples,p.Tx.SSBWaveform) && ...
            p.PowerContext.FixedSNRNormalizedReference && ~p.PowerContext.PhysicalDevicePowerClaim && ...
            p.RFExecutionDeferred && p.RuntimeChannelDeferred && ~p.PowerContext.PAApplied);
        assertOriginalGrid(p);
        capture=observation(p.TransmitSamples,p.BroadcastStartSample,p.SampleRateHz);
        [rx,mib]=sixgr.phy.broadcast.recoverSIB1FromWaveform(capture,p.ReceiverConfig, ...
            'RecoveryScope','SSB_MIB','CandidateSSBIndex',0);
        save(fullfile(folder,sprintf('original_ssb_%gk_frame%d.mat',scs,frame)), ...
            'original','p','rx','mib','-v7.3');
        assert(rx.SSBMIBComplete && rx.BCHCrcPass && rx.MIBDecoded && ...
            rx.PBCHStrictReceiverEvidenceOk && rx.MIBSystemFrameNumber==frame && ...
            rx.MIBSSBIndex==0 && rx.MIBHalfFrameBit==0 && ...
            rx.Status=="SSB_MIB_COMPLETE_SIB1_NOT_ATTEMPTED" && ...
            ~rx.StrictOk && ~rx.DCICrcPass && ~rx.DLSCHCrcPass && ~rx.SIB1ASN1DecodeOk && ...
            isa(mib,'sixgr.phy.broadcast.ReceivedMIBContext'), ...
            'test:SSBOnlyBCHDecode','Original BCH failed: %s / %s',rx.Status,rx.FailureReason);
    end
    assert(isequaln(cfg,original));
end

% Corrupt copies of the original preparation must fail before a receiver
% consumes the retained complete capture. Missing SI never declares scope.
beforeGuard=sixgr.runtime.RuntimeCallLedger.snapshot(); guardRNG=rng;
for mutation=1:6
    bad=p;
    switch mutation
        case 1, bad.Tx.Content="SSB_MIB_SIB1";
        case 2, bad=rmfield(bad,'WaveformContent');
        case 3, bad.Tx.SIB1EmissionIncluded=true;
        case 4, bad.Tx.SIB1Transmissions=struct('MalformedTestOperand',true);
        case 5, bad.Content="SSB_MIB_SIB1";
        case 6, bad.Tx.WaveformContent="ssb_mib_sib1_composite";
    end
    started=tic;
    reject(@()sixgr.link.completeCellSearchBroadcast(bad,capture,struct(), ...
        struct('UseRuntimeChannel',true),started),'sixgr:link:BroadcastContentMismatch');
end
assert(isequaln(beforeGuard,sixgr.runtime.RuntimeCallLedger.snapshot()) && isequal(guardRNG,rng));
fprintf('SSB_ONLY_COMPLETION_SCOPE_GUARDS_PASS mutations=6 receiver_calls=0\n');

% Use the real public link adapter as well as the direct receiver. This is
% the declared noiseless unit link, not a shared channel or SI reception.
cfg=configuration(30,folder); original=cfg;
linked=sixgr.link.runCellSearch_MIB_SIB1(cfg,'Content','SSB_MIB', ...
    'UseRuntimeChannel',false,'SSBIndex',0,'WriteArtifacts',false);
save(fullfile(folder,'original_link_adapter.mat'),'cfg','linked');
assert(linked.Ok && ~linked.Crash && linked.PBCH.Ok && ...
    linked.PBCHStrictReceiverEvidenceOk && linked.RecoveryScope=="SSB_MIB" && ...
    linked.BLER==0 && ...
    ~linked.SIB1PDSCHStrictReceiverEvidenceOk, ...
    'test:SSBOnlyLinkAdapter','SSB-only link completion failed: %s',linked.FailureReason);
assert(isequaln(cfg,original));
assertBCHOutcome(linked,true,0);

% Invalid original preparation fails before any BCH call and must not
% manufacture a block failure from the outer exception handler.
beforeInvalid=sixgr.runtime.RuntimeCallLedger.snapshot();
invalid=sixgr.link.runCellSearch_MIB_SIB1(cfg,'Content','SSB_MIB', ...
    'RuntimeSlot',1,'UseRuntimeChannel',false,'WriteArtifacts',false);
afterInvalid=sixgr.runtime.RuntimeCallLedger.snapshot();
addedInvalid=afterInvalid(height(beforeInvalid)+1:end,:);
assert(invalid.Crash && ~invalid.Ok && ...
    invalid.FailureIdentifier=="sixgr:link:BroadcastRuntimeFrameAlignment" && ...
    ~any(contains(addedInvalid.FunctionName,'PBCH_Recovery')));
assertBCHOutcome(invalid,false,NaN);

% Explicit SSB/MIB requests do not depend on an enabled SI procedure.
% Exercise public preparation and actual candidate reception, retaining the
% disabled setting rather than temporarily enabling SIB1 behind the caller.
disabled=cfg; disabled.phy.sib1.enable=false; originalDisabled=disabled;
only=sixgr.link.runCellSearch_MIB_SIB1(disabled,'Content','SSB_MIB', ...
    'PrepareOnly',true,'UseRuntimeChannel',true,'RuntimeSlot',0, ...
    'CandidateSSBIndices',0,'WriteArtifacts',false);
assert(~only.Crash && only.Status=="prepared_not_received" && ...
    ~only.DecodeAttempted && isfield(only,'PreparedBroadcast'), ...
    'test:DisabledSIExplicitPreparation','Explicit SSB/MIB preparation failed: %s',only.FailureReason);
assertBCHOutcome(only,false,NaN);
preparedOnly=only.PreparedBroadcast;
assert(preparedOnly.Content=="SSB_MIB" && preparedOnly.WaveformContent=="ssb_mib_only" && ...
    preparedOnly.Tx.Content=="SSB_MIB" && ~preparedOnly.Tx.SIB1EmissionIncluded && ...
    isstruct(preparedOnly.Tx.SIB1Transmissions) && isempty(preparedOnly.Tx.SIB1Transmissions));
for c={preparedOnly.Config,preparedOnly.ReceiverConfig,preparedOnly.Tx.Config}
    assert(isequaln(c{1}.phy.sib1,disabled.phy.sib1) && ~c{1}.phy.sib1.enable);
end
disabledRX=sixgr.link.runCellSearch_MIB_SIB1(disabled,'Content','SSB_MIB', ...
    'UseRuntimeChannel',false,'CandidateSSBIndices',0,'WriteArtifacts',false);
save(fullfile(folder,'original_disabled_SI_adapter.mat'), ...
    'disabled','only','disabledRX','-v7.3');
assert(disabledRX.Ok && ~disabledRX.Crash && disabledRX.PBCH.Ok && ...
    disabledRX.PBCHStrictReceiverEvidenceOk && disabledRX.RecoveryScope=="SSB_MIB" && ...
    disabledRX.BLER==0 && ~disabledRX.SIB1PDSCHStrictReceiverEvidenceOk && ...
    isequal(disabledRX.CandidateSSBIndices,0) && numel(disabledRX.CandidateResults)==1 && ...
    ~disabledRX.CandidateResults{1}.SIB1.SIB1ReceptionAttempted, ...
    'test:DisabledSIExplicitReception','Explicit SSB/MIB reception failed: %s',disabledRX.FailureReason);
assertBCHOutcome(disabledRX,true,0);
% The original non-SIB1 public branch also reports a completed BCH block,
% not a combined accepted-cell or SI-procedure verdict.
plain=sixgr.link.runCellSearch_MIB_SIB1(disabled,'UseRuntimeChannel',false, ...
    'NumSubframes',5,'SSBIndex',0,'WriteArtifacts',false);
assert(~plain.Crash && plain.DecodeAttempted && plain.PBCH.BCHCRCValid, ...
    'test:PlainBCHAdapter','Original plain BCH completion failed: %s',plain.FailureReason);
assertBCHOutcome(plain,true,double(~plain.PBCH.BCHCRCValid));
save(fullfile(folder,'original_plain_BCH_adapter.mat'),'disabled','plain');
reject(@()sixgr.link.runCellSearch_MIB_SIB1(disabled, ...
    'PrepareOnly',true,'UseRuntimeChannel',true), ...
    'sixgr:link:InvalidBroadcastPreparationRequest');
assert(isequaln(disabled,originalDisabled));
fprintf('SSB_ONLY_DISABLED_SI_ADAPTER_PASS original_BCH=1 SI_calls=0\n');

% Absolute-power preparation still binds the exact original SSB port grid
% and local-to-absolute symbol origin, never an SI grid or waveform mean.
absolute=cfg; absolute.integration.run_mode="GEOMETRY_NETWORK";
absolute.integration.configured_snr_is_link_authority=false;
absolute.integration.power_reference_mode="absolute_calibrated_sqrt_mw";
absolute.powerAndRF.downlinkPowerNormalizationPolicy="fixed_epre_over_configured_bwp";
powers=cell(1,2);
absoluteCarrier=sixgr.phy.grid.makeCarrier(absolute);
for k=1:2
    slot=(k-1)*2*double(absoluteCarrier.SlotsPerFrame);
    p=sixgr.link.prepareCellSearchBroadcast(absolute,true,'Content','SSB_MIB','RuntimeSlot',slot);
    assertContent(p,absolute); assertOriginalGrid(p);
    power=p.PowerContext;
    assert(power.ScaleApplied && ~power.FixedSNRNormalizedReference && ...
        power.PhysicalDevicePowerClaim && string(power.WaveformAmplitudeUnit)=="sqrt_mW" && ...
        ~power.PAApplied && power.NormalizationWaveformStartAbsoluteSymbolIndex0== ...
        p.Tx.WaveformStartAbsoluteSymbolIndex0 && ...
        isequal(p.TransmitSamples,p.Tx.Waveform.*cast(power.AmplitudeScale,'like',p.Tx.Waveform)));
    [~,~,activity]=sixgr.rf.measureActiveOFDMTotalPower(p.Tx.Waveform,p.TxInfo);
    assert(all(ismember(activity.ActiveSymbolIndices+p.TxInfo.WaveformStartAbsoluteSymbolIndex0, ...
        p.TxInfo.PortGridAbsoluteSymbolIndices)) && ...
        numel(activity.ActiveSymbolIndices)==power.NormalizationGridActiveSymbolCount);
    save(fullfile(folder,sprintf('original_absolute_preparation_%d.mat',k)),'p','-v7.3');
    powers{k}=power;
end
for name=["AmplitudeScale","ReferenceInputPower_mW","FullBWPActivityFactor", ...
        "NormalizationGridMeanEnergyPerRE","OutputTotalPower_mW"]
    a=double(powers{1}.(name)); b=double(powers{2}.(name));
    assert(isfinite(a)&&isfinite(b)&&a>0&&b>0&&abs(a-b)<=1e-10*max(a,b), ...
        'Moving original SFN must not change SSB allocation power term %s.',name);
end
profile off; calls=profile('info'); clear cleanupProfile;
names=string({calls.FunctionTable.FunctionName});
assert(~any(contains(names,'generateSIB1Transmission') | contains(names,'PDCCH_Tx') | ...
    contains(names,'PDSCH_Tx') | contains(names,'PDCCH_Rx') | contains(names,'PDSCH_Rx')));
after=sixgr.runtime.RuntimeCallLedger.snapshot(); ssbCalls=after(height(ledger)+1:end,:);
assert(~any(contains(string(ssbCalls.FunctionName), ...
    ["generateSIB1Transmission","PDCCH_Tx","PDSCH_Tx","PDCCH_Rx","PDSCH_Rx"])));
save(fullfile(folder,'original_ssb_only_call_evidence.mat'),'calls','ssbCalls');
fprintf('SSB_ONLY_NATIVE_PASS received_BCH=7 original_SI_TX_RX=0 shared_RF_claim=0\n');

% Defaults still encode real SI. Compare exact native outputs rather than
% altering the existing composite acceptance conditions.
legacy=sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg,'Seed',cfg.run.seed);
explicit=sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg, ...
    'Content','SSB_MIB_SIB1','Seed',cfg.run.seed);
assert(legacy.Content=="SSB_MIB_SIB1" && legacy.WaveformContent=="ssb_mib_sib1_composite" && ...
    legacy.SSBEmissionIncluded && legacy.SIB1EmissionIncluded && ...
    isequal(legacy.Waveform,explicit.Waveform) && ...
    isequaln(legacy.SIB1Transmissions,explicit.SIB1Transmissions));
transmissions=sixgr.phy.broadcast.retainedSIB1Transmissions(legacy);
assert(~isempty(transmissions) && all([transmissions.SIB1TransportBlockSize]>0));
save(fullfile(folder,'original_legacy_composite.mat'),'legacy','explicit','-v7.3');
before=rng;
for value={"", "sib1_only",true,7,["SSB_MIB","SSB_MIB_SIB1"]}
    reject(@()sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg,'Content',value{1}), ...
        'sixgr:phy:broadcast:InvalidBroadcastContent');
    reject(@()sixgr.link.prepareCellSearchBroadcast(cfg,true,'Content',value{1}), ...
        'sixgr:phy:broadcast:InvalidBroadcastContent');
end
assert(isequal(before,rng) && isequal(hashes,arrayfun(@(f)string(sixgr.util.sha256File(f)),files)));
fprintf('SSB_ONLY_BROADCAST_PREPARATION_PASS legacy_default_unchanged=1 folder=%s\n',folder);
ok=true;
end

function cfg=configuration(scs,folder)
if scs==15
    scenario=sixgr.lls6g.config.loadScenarioConfig( ...
        'simulator/configs/scenarios/lls_causal_access_to_data_wiring.yaml');
    cfg=sixgr.lls6g.buildInternalConfig(scenario,folder);
    coreset=1;
else
    cfg=sixgr.config.defaultConfig(); cfg.run.strictMode=true;
    cfg.phy.carrier.NSizeGrid=51; cfg.phy.carrier.NCellID=17;
    cfg.phy.carrier.SubcarrierSpacing=30; cfg.phy.carrier.SubcarrierSpacing_kHz=30;
    cfg.phy.channelBandwidth_MHz=20; cfg.frequency.bandwidth_hz=20e6;
    coreset=0;
end
cfg.phy.carrier.NFrame=0; cfg.phy.carrier.NSlot=0;
cfg.phy.sib1.enable=true; cfg.phy.pdcch.enable=true;
cfg.phy.csirs.enable=false; cfg.phy.trs.enable=false;
cfg.initial_access.type0.monitoring_occasion_ordinal=3;
cfg.initial_access.sib1.pdsch=struct('prb_start',0,'num_prb',24, ...
    'symbol_start',2,'num_symbols',12,'mcs',0,'rv',0,'ptrs_enabled',false);
cfg.phy.sib1.coreset0Index=coreset; cfg.phy.sib1.searchSpaceZero=2;
cfg.phy.mib.pdcchConfigSIB1=16*coreset+2; cfg.phy.mib.dmrsTypeAPosition=2;
cfg.phy.ssb.periodicity_ms=20; cfg.phy.ssb.period_ms=20;
cfg.phy.ssb.runtimeSSBIndex=0; cfg.phy.ssb.pbchObservationSubframes=5;
cfg.phy.sib1.ssbObservationSubframes=5;
t=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(cfg);
cfg.phy.ssb.activeBitmap=false(1,t.Lmax); cfg.phy.ssb.activeBitmap(1)=true;
cfg.phy.ssb.activeCandidateIndices0Based=0;
cfg.phy.sib1.transmissionScope="selected_ssb_occasion";
cfg.integration.run_mode="FIXED_SNR_SWEEP";
cfg.integration.configured_snr_is_link_authority=true;
cfg.integration.power_reference_mode="normalized_unit_es";
cfg.run.noiseOperatingMode='standalone_awgn_snr_argument';
cfg.channel.snr_dB=Inf; cfg.rf.pa.enable=false;
end

function assertContent(p,cfg)
assert(isscalar(p.Tx) && p.Content=="SSB_MIB" && p.Tx.Content==p.Content && ...
    p.WaveformContent=="ssb_mib_only" && p.Tx.WaveformContent==p.WaveformContent && ...
    p.Tx.SSBEmissionIncluded && ~p.Tx.SIB1EmissionIncluded && ...
    isstruct(p.Tx.SIB1Transmissions) && isempty(p.Tx.SIB1Transmissions) && ...
    isempty(p.Tx.SIB1TransmitSSBIndices0Based));
assert(~any(isfield(p.Tx,{'PDCCHTx','PDSCHTx','SIB1Grid','TxTree', ...
    'SIB1Bits','SIB1AbsoluteSlot','SIB1PayloadHash'})));
assert(isequaln(p.Config.phy.sib1,cfg.phy.sib1) && ...
    isequaln(p.ReceiverConfig.phy.sib1,cfg.phy.sib1) && cfg.phy.sib1.enable && ...
    isequaln(p.Config.phy.pdsch,cfg.phy.pdsch) && ...
    isequaln(p.Tx.Config.phy.sib1,cfg.phy.sib1));
end

function assertOriginalGrid(p)
native=p.Tx.SSBWaveInfo.SSBComposite.TransmitPortResourceGrid;
active=find(reshape(any(any(native~=0,1),3),[],1));
g=p.Tx.SSBInfo.SSBGridValidation; carrier=p.Tx.Carrier;
first=(g.SSBLowOffsetFromPointAHz-g.CarrierLowOffsetFromPointAHz)/(1000*carrier.SubcarrierSpacing);
expected=zeros(12*carrier.NSizeGrid,numel(active),size(native,3),'like',native);
expected(first+(1:240),:,:)=native(:,active,:);
assert(isequal(p.TxInfo.PortGrid,expected) && ...
    isequal(p.TxInfo.PortGridAbsoluteSymbolIndices, ...
    p.Tx.WaveformStartAbsoluteSymbolIndex0+double(active-1)) && ...
    p.TxInfo.PowerNormalizationGridSource=="exact_producer_ssb_pbch_active_port_grid" && ...
    p.TxInfo.WaveformStartAbsoluteSymbolIndex0==p.Tx.WaveformStartAbsoluteSymbolIndex0);
end

function out=observation(samples,first,fs)
out=sixgr.phy.waveform.WaveformObservationBuffer(first,first+size(samples,1),fs,size(samples,2));
out.append(sixgr.phy.waveform.WaveformChunk(samples,first),fs);
end

function assertBCHOutcome(out,eligible,errorCount)
assert(out.BLERScope=="BCH_original_completed_block" && ...
    out.BLEREligibleTrialCount==double(eligible) && ...
    isequaln(out.BLER,errorCount) && isequaln(out.BLERErrorCount,errorCount));
if eligible
    assert(out.BLERSource=="original_completed_BCH_decode_raw_CRC" && ...
        out.BLERStatus=="one_original_BCH_block_not_combined_SI_procedure");
else
    assert(out.BLERSource=="unavailable" && strlength(out.BLERStatus)>0);
end
end

function reject(f,id)
try, f(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:SSBOnlyMissingGuard','Expected %s.',id);
end

function releaseLedger(owned)
if owned, sixgr.runtime.RuntimeCallLedger.reset(); end
end
