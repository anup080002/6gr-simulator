function ok=testSIB1RetainedMIBReception()
% Original native PBCH acquisition -> later native SI-only waveform decode.
% Declared unit-link/CFO component fixture, not shared scheduling, RF,
% acquisition-state installation, mobility, or statistical qualification.
setup6GRSimToolkit('Verbose',false);
savedRNG=rng; restoreRNG=onCleanup(@()rng(savedRNG)); %#ok<NASGU>
folder=fullfile(pwd,'results','validation','sib1_retained_mib',char(java.util.UUID.randomUUID()));
mkdir(folder); fprintf('SIB1_RETAINED_MIB_EVIDENCE %s\n',folder);
ownedLedger=~sixgr.runtime.RuntimeCallLedger.isConfigured();
if ownedLedger, sixgr.runtime.RuntimeCallLedger.configure(folder,struct('RunId',"retained_mib")); end
restoreLedger=onCleanup(@()localReleaseLedger(ownedLedger)); %#ok<NASGU>
cfg=localConfig(); cfg.phy.carrier.NFrame=1022;
tx=sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg,'SNRdB',Inf);
fs=tx.SampleRateHz; origin=tx.BroadcastStartSample;
cfo=137; % independent deterministic impairment; never a receiver hypothesis
samples=tx.Waveform.*exp(1j*2*pi*cfo*(0:size(tx.Waveform,1)-1).'/fs);
original=localObservation(samples,origin,fs);
originalHash=original.sampleHash();
[combined,context]=sixgr.phy.broadcast.recoverSIB1FromWaveform(original,cfg);
save(fullfile(folder,'original_acquisition.mat'),'cfg','tx','samples','combined','context','cfo','-v7.3');
assert(combined.StrictOk && combined.BCHCrcPass && combined.MIBDecoded && ...
    combined.CandidateIdentityConsistent && combined.DCICrcPass && combined.DLSCHCrcPass, ...
    'test:RetainedMIBAcquisition','Original acquisition failed: %s / %s',combined.Status,combined.FailureReason);
assert(isa(context,'sixgr.phy.broadcast.ReceivedMIBContext') && ...
    context.Data.AbsoluteFrameNumber==1022 && context.Data.ReceivedSFN==1022 && ...
    context.Data.CaptureSampleSHA256==originalHash && context.Data.AvailableAtSample==original.EndSampleExclusive && ...
    context.Data.CFOPhaseOriginSample==origin && abs(context.Data.FrequencyOffsetHz-cfo)<1, ...
    'The prior context must retain measured BCH/clock/CFO operands, not TX frame hints.');
before=sixgr.runtime.RuntimeCallLedger.snapshot();
[mibOnly,mibContext]=sixgr.phy.broadcast.recoverSIB1FromWaveform(original,cfg,'RecoveryScope','SSB_MIB');
after=sixgr.runtime.RuntimeCallLedger.snapshot(); added=after(height(before)+1:end,:);
assert(mibOnly.SSBMIBComplete && ~mibOnly.SIB1ReceptionAttempted && ...
    context.SHA256==mibContext.SHA256 && ...
    ~any(ismember(added.FunctionName,["sixgr.phy.dl.PDCCH_Rx","sixgr.phy.dl.PDSCH_Rx"])), ...
    'MIB-only reception must return its actual reusable context without attempting SI.');
same=sixgr.phy.broadcast.recoverSIB1UsingReceivedMIB(original,cfg,context);
for name=["DCIPayloadHex","PDSCHControlEvent","SIB1TransportBlockBits", ...
        "SIB1PayloadBits","SIB1RxTreeHash","SIB1AbsoluteSlot", ...
        "SIB1PDSCHEqualizedSymbols","SIB1ObservationStartSample","SIB1ObservationEndSampleExclusive"]
    assert(isequaln(same.(name),combined.(name)),'Combined/shared SI decoder changed %s.',name);
end

% A genuinely new SI-only waveform at frame 1024: do not move old IQ or
% decode another SS/PBCH burst to obtain a convenient new frame label.
laterCfg=cfg; laterCfg.phy.carrier.NFrame=1024;
laterTX=sixgr.phy.broadcast.generateSIB1Transmission(laterCfg,tx.SIB1Transmissions(1).SSBInfo);
start=laterTX.WaveformStartAbsoluteSample;
assert(start>=context.Data.AvailableAtSample && ~laterTX.SSBEmissionIncluded);
laterSamples=laterTX.Waveform.*exp(1j*2*pi*cfo*(start-origin+(0:size(laterTX.Waveform,1)-1)).'/fs);
later=localObservation(laterSamples,start,fs); laterHash=later.sampleHash();
rxCfg=cfg; rxCfg.phy.carrier.NFrame=7; % deliberately unrelated configuration clock
before=sixgr.runtime.RuntimeCallLedger.snapshot(); randomBefore=rng;
status=profile('status'); assert(strcmp(status.ProfilerStatus,'off'));
profile clear; stopProfile=onCleanup(@()profile('off')); profile on;
received=sixgr.phy.broadcast.recoverSIB1UsingReceivedMIB(later,rxCfg,context, ...
    'AbsoluteMonitoringSlot',laterTX.SIB1AbsoluteSlot);
profile off; calls=profile('info'); clear stopProfile;
after=sixgr.runtime.RuntimeCallLedger.snapshot(); added=after(height(before)+1:end,:);
save(fullfile(folder,'original_later_si.mat'),'laterCfg','laterTX','laterSamples','received','added','calls','context','-v7.3');
assert(received.StrictOk && received.DCICrcPass && received.DLSCHCrcPass && received.SIB1ASN1DecodeOk, ...
    'test:RetainedMIBSI','Later actual SI failed: %s / %s',received.Status,received.FailureReason);
assert(isequal(rng,randomBefore) && original.sampleHash()==originalHash && later.sampleHash()==laterHash);
assert(received.PriorBCHContextSHA256==context.SHA256 && ~received.NewBCHReceptionAttempted && ...
    ~any(isfield(received,{'BCHCrcPass','BCHCRCValid','MIBDecoded','SS_RSRP_dBm','ReceivedDLTimingReference'})) && ...
    received.SIB1AbsoluteSlot==laterTX.SIB1AbsoluteSlot && floor(received.SIB1AbsoluteSlot/20)==1024 && ...
    received.SIB1ObservationStartSample==0 && received.SIB1CFOPhaseOriginSample==origin && ...
    received.SIB1CFOPhaseStartSample==start-origin);
corrected=laterSamples.*cast(exp(-1j*2*pi*context.Data.FrequencyOffsetHz* ...
    ((start-origin+(0:size(laterSamples,1)-1)).'/fs)),'like',laterSamples);
assert(received.SIB1InputSampleSHA256==laterHash && ...
    received.SIB1CFOCorrectedSampleSHA256==sixgr.phy.waveform.WaveformHash.runtimeArray(corrected));
for name=["sixgr.phy.dl.PDCCH_Rx","sixgr.phy.dl.PDSCH_Rx"]
    assert(sum(added.FunctionName==name)==1,'Exactly one actual %s execution is required.',name);
end
names=string({calls.FunctionTable.FunctionName});
assert(~any(contains(names,'SSB_Rx')|contains(names,'PBCH_Recovery')|contains(names,'generateSSB_MIB_SIB1_Waveform')));
[equalTree,~]=sixgr.rrc.asn1.compareSIB1Trees(laterTX.TxTree,received.SIB1RxTree);
assert(equalTree && received.SIB1PayloadHashRx==string(laterTX.SIB1PayloadHash));
localNegatives(cfg,original,later,context,laterTX.SIB1AbsoluteSlot);
localKSSBWaveforms(cfg,context,folder);

% Original measured decoder fields survive all actual exporter aliases.
paths=sixgr.phy.broadcast.exportSIB1EvidenceArtifacts(fullfile(folder,'original_export'),tx,combined);
localAssertKSSBExport(paths,combined);
legacy=rmfield(combined,localKSSBFields());
legacyPaths=sixgr.phy.broadcast.exportSIB1EvidenceArtifacts(fullfile(folder,'legacy_absent_export'),tx,legacy);
localAssertLegacy(legacyPaths);
rejected=combined; rejected.CandidateIdentityConsistent=false; rejected.MIBDecoded=false;
rejectPaths=sixgr.phy.broadcast.exportSIB1EvidenceArtifacts(fullfile(folder,'declared_identity_negative'),tx,rejected);
localAssertStage(rejectPaths,false);
trial=sixgr.util.csvReadTable(rejectPaths.RecoveryTrialsCSV,'TextType','string');
assert(all(trial.BCHCrcPass==1) && all(trial.BCHCRCValid==1));
T=table(context.SHA256,context.Data.ReceivedSFN,context.Data.AbsoluteFrameNumber, ...
    context.Data.AvailableAtSample,received.SIB1AbsoluteSlot,start, ...
    received.DCICrcPass,received.DLSCHCrcPass,string(laterHash), ...
    'VariableNames',{'PriorMIBSHA256','PriorSFN','PriorAbsoluteFrame','PriorAvailableAtSample', ...
    'SIB1AbsoluteSlot','SIStartSample','DCICRC','SIB1CRC','OriginalSISampleSHA256'});
sixgr.util.csvWriteTable(fullfile(folder,'retained_mib_si_trial.csv'),T,'PreserveSchema',true,'RoundTripNumericText',true);
fprintf('SIB1_RETAINED_MIB_PASS acquisition_frame=1022 SI_frame=1024 later_PBCH_calls=0 actual_control_data_decodes=1 kSSB_native_cases=2 folder=%s\n',folder);
ok=true;
end

function localNegatives(cfg,original,later,context,slot)
before=sixgr.runtime.RuntimeCallLedger.snapshot(); randomBefore=rng;
reject(@()sixgr.phy.broadcast.recoverSIB1UsingReceivedMIB(later,cfg,context.Data), ...
    'sixgr:phy:broadcast:InvalidReceivedMIBContext');
bad=cfg; bad.phy.carrier.NCellID=mod(context.Data.NCellID+1,1008);
reject(@()sixgr.phy.broadcast.recoverSIB1UsingReceivedMIB(later,bad,context),'sixgr:phy:broadcast:ReceivedMIBCellMismatch');
bad=cfg; bad.initial_access.configuration_epoch=context.Data.ReceiverGeometry.ConfigurationEpoch+1;
reject(@()sixgr.phy.broadcast.recoverSIB1UsingReceivedMIB(later,bad,context),'sixgr:phy:broadcast:ReceivedMIBGeometryChanged');
changed=original.readComplete(); changed(1)=changed(1)+1;
changed=localObservation(changed,original.StartSample,original.SampleRateHz);
reject(@()sixgr.phy.broadcast.recoverSIB1UsingReceivedMIB(changed,cfg,context),'sixgr:phy:broadcast:ReceivedMIBCaptureMismatch');
early=localObservation(later.readComplete(),original.StartSample+1,later.SampleRateHz);
reject(@()sixgr.phy.broadcast.recoverSIB1UsingReceivedMIB(early,cfg,context),'sixgr:phy:broadcast:ReceivedMIBNotYetAvailable');
wrongRate=localObservation(later.readComplete(),later.StartSample,later.SampleRateHz*2);
reject(@()sixgr.phy.broadcast.recoverSIB1UsingReceivedMIB(wrongRate,cfg,context),'sixgr:phy:broadcast:ReceivedMIBSampleRateMismatch');
incomplete=sixgr.phy.waveform.WaveformObservationBuffer(later.StartSample,later.EndSampleExclusive,later.SampleRateHz,later.NumReceiveAntennas);
reject(@()sixgr.phy.broadcast.recoverSIB1UsingReceivedMIB(incomplete,cfg,context),'WAVEFORM:IncompleteObservation');
after=sixgr.runtime.RuntimeCallLedger.snapshot();
assert(height(after)==height(before) && isequal(rng,randomBefore),'Invalid original context/capture must fail before receiver entry.');
x=later.readComplete(); short=localObservation(x(1:end-1,:),later.StartSample,later.SampleRateHz);
missing=sixgr.phy.broadcast.recoverSIB1UsingReceivedMIB(short,cfg,context,'AbsoluteMonitoringSlot',slot);
assert(~missing.StrictOk && ~missing.SIB1ReceptionAttempted && ~missing.DCICrcPass && ...
    missing.PDCCHCandidatesAttempted==0 && missing.Status=="INCOMPLETE_OBSERVATION");
badSlot=sixgr.phy.broadcast.recoverSIB1UsingReceivedMIB(later,cfg,context,'AbsoluteMonitoringSlot',slot+3);
assert(~badSlot.SIB1ReceptionAttempted && ...
    badSlot.FailureIdentifier=="sixgr:phy:broadcast:InvalidReceivedSIMonitoringSlot");
after=sixgr.runtime.RuntimeCallLedger.snapshot(); added=after(height(before)+1:end,:);
assert(~any(ismember(added.FunctionName,["sixgr.phy.dl.PDCCH_Rx","sixgr.phy.dl.PDSCH_Rx"])));
end

function localKSSBWaveforms(cfg,originalContext,folder)
% The encoded PBCH indication is independent of the valid physical grid
% placement. This is original native TX coding, not edited receiver output.
c=sixgr.phy.grid.makeCarrier(cfg); t=sixgr.phy.frame.SSBTimingResolver.resolveFromConfig(cfg);
sampling=sixgr.phy.frame.OFDMSamplingResolver.resolve(c); fs=sampling.SampleRateHz;
assert(t.SSBSubcarrierSpacingKHz==c.SubcarrierSpacing && any(t.Lmax==[4 8]));
firstSC=t.GridRelationship.SSBLowOffsetFromPointAHz/(c.SubcarrierSpacing*1000)-12*c.NStartGrid;
assert(firstSC==fix(firstSC) && firstSC>=0 && firstSC+240<=12*c.NSizeGrid);
for k=[16 24]
    bits=originalContext.Data.TransportBlockBits;
    bits(9:12)=int8(bitget(uint8(mod(k,16)),4:-1:1)).';
    plane=complex(zeros(240,4));
    plane(nrPSSIndices)=nrPSS(c.NCellID); plane(nrSSSIndices)=nrSSS(c.NCellID);
    plane(nrPBCHDMRSIndices(c.NCellID))=nrPBCHDMRS(c.NCellID,0);
    coded=nrBCH(bits,originalContext.Data.ReceivedSFN,0,t.Lmax,k,c.NCellID);
    plane(nrPBCHIndices(c.NCellID))=nrPBCH(coded,c.NCellID,0);
    grid=nrResourceGrid(c,1);
    grid(firstSC+(1:240),t.SelectedStartSymbol+(1:4))=plane;
    wave=nrOFDMModulate(c,grid,'SampleRate',fs,'Nfft',sampling.Nfft,'Windowing',0);
    observation=localObservation(wave,originalContext.Data.CaptureStartSample,fs);
    before=sixgr.runtime.RuntimeCallLedger.snapshot();
    [rx,ctx]=sixgr.phy.broadcast.recoverSIB1FromWaveform(observation,cfg);
    after=sixgr.runtime.RuntimeCallLedger.snapshot(); added=after(height(before)+1:end,:);
    save(fullfile(folder,sprintf('original_kssb_%d.mat',k)),'bits','coded','grid','wave','rx','ctx','added');
    assert(rx.BCHCrcPass && rx.MIBDecoded && rx.SSBIdentityVerified && rx.DecodedKSSB==k && ...
        rx.MIBKSSBLow4==mod(k,16) && rx.PBCHKSSBHighContribution==16 && ...
        ctx.Data.MIB.SSBSubcarrierOffset==k && ctx.Data.OriginalDecodedMIBState.SSBSubcarrierOffset==mod(k,16), ...
        'Native kSSB=%d reception failed: %s / %s',k,rx.Status,rx.FailureReason);
    if k==24
        assert(rx.Status=="NO_ASSOCIATED_TYPE0_FOR_RECEIVED_SSB" && ~rx.StrictOk && ...
            ~rx.SIB1ReceptionAttempted && ~rx.CORESET0Present && rx.PDCCHCandidatesAttempted==0 && ...
            ~any(ismember(added.FunctionName,["sixgr.phy.dl.PDCCH_Rx","sixgr.phy.dl.PDSCH_Rx"])));
    end
end
end

function cfg=localConfig()
cfg=sixgr.config.defaultConfig(); cfg.run.strictMode=true;
cfg.phy.sib1.enable=true; cfg.phy.carrier.NCellID=17;
cfg.phy.carrier.NFrame=0; cfg.phy.carrier.NSlot=0;
cfg.phy.carrier.SubcarrierSpacing=30; cfg.phy.carrier.SubcarrierSpacing_kHz=30;
cfg.phy.carrier.NSizeGrid=51; cfg.phy.channelBandwidth_MHz=20;
cfg.frequency.bandwidth_hz=20e6; cfg.channel.bandwidth_Hz=20e6;
cfg.phy.ssb.NCRBSSB=30; cfg.phy.ssb.KSSB=0;
cfg.phy.ssb.periodicity_ms=10; cfg.phy.ssb.period_ms=10;
cfg.phy.ssb.activeBitmap=logical([1 0 0 0 0 0 0 0]);
cfg.phy.ssb.runtimeSSBIndex=0; cfg.phy.sib1.transmissionScope="selected_ssb_occasion";
cfg.initial_access.type0=struct('monitoring_occasion_ordinal',1);
cfg.initial_access.sib1.pdsch=struct('prb_start',0,'num_prb',24, ...
    'symbol_start',2,'num_symbols',12,'mcs',0,'rv',0);
cfg.phy.sib1.coreset0Index=0; cfg.phy.sib1.searchSpaceZero=4;
cfg.phy.mib.pdcchConfigSIB1=4; cfg.phy.mib.dmrsTypeAPosition=2;
cfg.phy.sync.fineCFOEnabled=true;
end

function observation=localObservation(samples,start,fs)
observation=sixgr.phy.waveform.WaveformObservationBuffer(start,start+size(samples,1),fs,size(samples,2));
observation.append(sixgr.phy.waveform.WaveformChunk(samples,start),fs);
end

function fields=localKSSBFields()
fields={'KSSBContractVersion','Lmax','MIBKSSBLow4','PBCHKSSBMSB', ...
    'PBCHKSSBHighContribution','KSSBHighBitApplicable','DecodedKSSB','k_SSB', ...
    'BCHCRCValid','CandidateIdentityConsistent'};
end

function localAssertKSSBExport(paths,result)
fields=localKSSBFields();
for path=["RecoveryTrialsCSV","PBCHRecoveryTrialsCSV","MIBFieldEvidenceCSV","AirInterfaceCSV"]
    T=sixgr.util.csvReadTable(paths.(path),'TextType','string');
    assert(~isempty(T) && all(string(T.KSSBContractVersion)==result.KSSBContractVersion));
    for name=string(fields(2:end))
        assert(isequaln(double(T.(name)),repmat(double(result.(name)),height(T),1)), ...
            'Original %s was changed in %s.',name,path);
    end
    if path=="PBCHRecoveryTrialsCSV", assert(all(T.MIBKSSBSubcarrierOffset==result.MIBKSSBSubcarrierOffset)); end
    if path=="MIBFieldEvidenceCSV"
        row=T(T.MIBEvidenceField=="kSSBSubcarrierOffset",:);
        assert(height(row)==1 && row.NumericValue==result.MIBKSSBSubcarrierOffset);
    end
end
localAssertStage(paths,true);
end

function localAssertLegacy(paths)
fields=localKSSBFields();
for path=["RecoveryTrialsCSV","PBCHRecoveryTrialsCSV","MIBFieldEvidenceCSV","AirInterfaceCSV"]
    T=sixgr.util.csvReadTable(paths.(path),'TextType','string');
    assert(~isempty(T),'Original legacy rows must remain present in %s.',path);
    % csvWriteTable deliberately prunes all-blank/all-NaN columns unless
    % PreserveSchema is requested. Missing historical operands may thus be
    % absent or explicitly unavailable, but must never acquire a v2 value.
    names=string(T.Properties.VariableNames);
    if ismember("KSSBContractVersion",names)
        versions=string(T.KSSBContractVersion);
        assert(all(ismissing(versions)|strlength(versions)==0|versions=="NaN"));
    end
    for name=string(fields(2:end))
        if ismember(name,names), assert(all(isnan(double(T.(name))))); end
    end
end
localAssertStage(paths,false);
end

function localAssertStage(paths,expected)
T=sixgr.util.csvReadTable(paths.WaveformDecodeTraceCSV,'TextType','string');
row=T(T.StageName=="PBCH_BCH_MIB_RECOVERY",:);
assert(height(row)==1 && logical(row.StagePass)==expected);
end

function reject(f,id)
try, f(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message); return;
end
error('test:RetainedMIBExpectedError','Expected %s.',id);
end

function localReleaseLedger(owned)
if owned, sixgr.runtime.RuntimeCallLedger.reset(); end
end
