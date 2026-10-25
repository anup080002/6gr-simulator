function ok=testSIB1TransmissionExtraction()
% Exact SI producer extraction; native coded unit-link/AWGN reception.
% This is not independent SI scheduling, SI-only RX, RF or access evidence.
setup6GRSimToolkit('Verbose',false);
savedRNG=rng; restoreRNG=onCleanup(@()rng(savedRNG)); %#ok<NASGU>
status=profile('status');
assert(strcmp(status.ProfilerStatus,'off'), ...
    'test:SIB1ProfilerOwner','This focused test needs an idle MATLAB profiler.');
folder=fullfile(pwd,'results','validation','sib1_transmission_extraction', ...
    char(java.util.UUID.randomUUID()));
mkdir(folder);
fprintf('SIB1_TRANSMISSION_EXTRACTION_EVIDENCE %s\n',folder);
ownedLedger=~sixgr.runtime.RuntimeCallLedger.isConfigured();
if ownedLedger
    sixgr.runtime.RuntimeCallLedger.configure(folder,struct('RunId',"si_extraction"));
end
restoreLedger=onCleanup(@()localReleaseLedger(ownedLedger)); %#ok<NASGU>
files=[string(mfilename('fullpath'))+".m", ...
    string(which('sixgr.phy.broadcast.generateSIB1Transmission')), ...
    string(which('sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform')), ...
    string(which('sixgr.phy.broadcast.recoverSIB1FromWaveform'))];
hashes=arrayfun(@(p)string(sixgr.util.sha256File(p)),files);
sourceTable=table(files(:),hashes(:),'VariableNames',{'Path','SHA256'});
sixgr.util.csvWriteTable(fullfile(folder,'source_hashes.csv'),sourceTable,'PreserveSchema',true);
rows=struct([]);
for ordinal=1:2
    cfg=localConfiguration(ordinal,folder);
    original=cfg;
    % This wrapper owns the one actual SS/PBCH burst and all composition.
    broadcast=sixgr.phy.broadcast.generateSSB_MIB_SIB1_Waveform(cfg,'SNRdB',Inf);
    assert(isequaln(cfg,original) && numel(broadcast.SIB1Transmissions)==1);
    retained=broadcast.SIB1Transmissions(1);
    association=retained.SSBInfo; originalAssociation=association;
    ledgerBefore=sixgr.runtime.RuntimeCallLedger.snapshot(); randomBefore=rng;
    profile clear;
    stopProfile=onCleanup(@()profile('off'));
    profile on;
    direct=sixgr.phy.broadcast.generateSIB1Transmission(cfg,association);
    profile off;
    calls=profile('info');
    clear stopProfile;
    assert(isequal(rng,randomBefore) && isequaln(cfg,original) && ...
        isequaln(association,originalAssociation), ...
        'The SI-only encoder must not mutate the original association, configuration or RNG.');
    ledgerAfter=sixgr.runtime.RuntimeCallLedger.snapshot();
    added=ledgerAfter(height(ledgerBefore)+1:end,:);
    for name=["sixgr.phy.broadcast.generateSIB1Transmission", ...
            "sixgr.phy.dl.PDCCH_Tx","sixgr.phy.dl.PDSCH_Tx"]
        assert(sum(added.FunctionName==name)==1, ...
            'test:SIB1ProducerCalls','Expected exactly one actual %s call.',name);
    end
    % SSB_Tx is not ledger-instrumented. Use actual profiler call evidence,
    % not absence of a nonexistent ledger entry, to prove no extra burst.
    callNames=string({calls.FunctionTable.FunctionName});
    assert(any(contains(callNames,'generateSIB1Transmission')) && ...
        any(contains(callNames,'PDCCH_Tx')) && any(contains(callNames,'PDSCH_Tx')) && ...
        ~any(contains(callNames,'SSB_Tx')) && ~any(contains(callNames,'nrWaveformGenerator')) && ...
        ~any(contains(callNames,'generateSSB_MIB_SIB1_Waveform')), ...
        'test:SIB1ExtraBroadcast','Direct SI must encode no additional SS/PBCH waveform.');
    localExact(retained,direct);
    assert(~direct.SSBEmissionIncluded && broadcast.SSBEmissionIncluded && ...
        direct.WaveformContent=="si_rnti_pdcch_pdsch_only" && ...
        ~any(isfield(direct,{'SSBWaveform','SSBWaveInfo','SSBComposite', ...
        'BroadcastStartSample','BroadcastStartAbsoluteSlot','SIB1WaveformStartSample'})));
    first=sixgr.phy.frame.slotStartSample(direct.Carrier,direct.SIB1AbsoluteSlot,direct.SampleRateHz);
    last=sixgr.phy.frame.slotStartSample(direct.Carrier,direct.SIB1AbsoluteSlot+1,direct.SampleRateHz);
    assert(direct.WaveformStartAbsoluteSample==first && ...
        direct.SIB1WaveformAbsoluteStartSample==first && ...
        direct.WaveformStartAbsoluteSymbolIndex0==direct.SIB1AbsoluteSlot*direct.Carrier.SymbolsPerSlot && ...
        size(direct.Waveform,1)==last-first && ...
        retained.SIB1WaveformStartSample==first-broadcast.BroadcastStartSample, ...
        'The SI samples contain one native slot, without an absolute-time zero prefix.');
    mapped=sixgr.link.broadcastSIB1WaveformPortGrid(direct);
    assert(isequaln(mapped,sixgr.link.broadcastSIB1WaveformPortGrid(retained)));
    composer=sixgr.phy.waveform.WaveformStreamComposer( ...
        direct.SampleRateHz,size(broadcast.SSBWaveform,2),0);
    composer.enqueue('original-SSB', ...
        sixgr.phy.waveform.WaveformChunk(broadcast.SSBWaveform,0),direct.SampleRateHz);
    composer.enqueue('direct-SI',sixgr.phy.waveform.WaveformChunk( ...
        direct.Waveform,first-broadcast.BroadcastStartSample),direct.SampleRateHz);
    composed=composer.readThrough(size(broadcast.Waveform,1));
    assert(isequaln(composed.Samples,broadcast.Waveform), ...
        'Extracted SI must recreate the original noiseless composite sample-for-sample.');
    seed=9200+ordinal; rng(seed,'twister');
    [receivedSamples,noise]=sixgr.phy.waveform.addOccupiedREAWGN( ...
        composed.Samples,direct.Carrier,35,'SignalEnergyPerOccupiedRE',1);
    observation=sixgr.phy.waveform.WaveformObservationBuffer( ...
        broadcast.BroadcastStartSample, ...
        broadcast.BroadcastStartSample+size(receivedSamples,1), ...
        direct.SampleRateHz,size(receivedSamples,2));
    observation.append(sixgr.phy.waveform.WaveformChunk( ...
        receivedSamples,broadcast.BroadcastStartSample),direct.SampleRateHz);
    receiverCandidate=[];
    if ordinal==2
        % The retained YAML emits SSB0..3, while this component deliberately
        % emits SI only for SSB0. Declare a search hypothesis, not decoded
        % identity: the actual BCH must independently confirm SSB0 below.
        receiverCandidate=0;
    end
    receiver=sixgr.phy.broadcast.recoverSIB1FromWaveform(observation,cfg, ...
        'CandidateSSBIndex',receiverCandidate);
    scope="native_coded_unit_link_AWGN_composite_RX_not_independent_SI_scheduler";
    save(fullfile(folder,sprintf('original_case_%d.mat',ordinal)), ...
        'cfg','direct','retained','receivedSamples','noise','receiver','receiverCandidate', ...
        'added','calls','seed','scope','-v7.3');
    assert(receiver.StrictOk && receiver.BCHCrcPass && receiver.DCICrcPass && ...
        receiver.DLSCHCrcPass && receiver.SIB1ASN1DecodeOk && ...
        receiver.SIB1AbsoluteSlot==direct.SIB1AbsoluteSlot && isempty(receiver.UsedOracleFields) && ...
        (ordinal~=2 || (receiver.SSBIndex==0 && receiver.MIBSSBIndex==0)), ...
        'test:SIB1ExtractionDecode','Actual case %d decode failed: %s',ordinal,receiver.FailureReason);
    [equalTree,treeHash]=sixgr.rrc.asn1.compareSIB1Trees(direct.TxTree,receiver.SIB1RxTree);
    assert(equalTree && string(treeHash.TxTreeHash)==string(treeHash.RxTreeHash) && ...
        receiver.SIB1PayloadHashRx==string(direct.SIB1PayloadHash));
    localNegatives(cfg,association);
    row=struct('Case',ordinal,'NSizeGrid',double(direct.Carrier.NSizeGrid), ...
        'SCS_kHz',double(direct.Carrier.SubcarrierSpacing), ...
        'BroadcastStartSample',broadcast.BroadcastStartSample, ...
        'SIB1AbsoluteSlot',direct.SIB1AbsoluteSlot,'SIStartSample',first, ...
        'NativeSISamples',size(direct.Waveform,1),'DirectExtraSSBCalls',0, ...
        'SIEncoderCalls',1,'PDCCHEncoderCalls',1,'PDSCHEncoderCalls',1, ...
        'BCHCRC',receiver.BCHCrcPass,'DCICRC',receiver.DCICrcPass, ...
        'DLSCHCRC',receiver.DLSCHCrcPass,'Scope',scope);
    if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
    sixgr.util.csvWriteTable(fullfile(folder,'actual_cases.csv'),struct2table(rows), ...
        'PreserveSchema',true,'RoundTripNumericText',true);
    fprintf('SIB1_TRANSMISSION_EXTRACTION_CASE_PASS case=%d RB=%d SCS=%g SI_slot=%d\n', ...
        ordinal,row.NSizeGrid,row.SCS_kHz,row.SIB1AbsoluteSlot);
end
assert(rows(1).NSizeGrid~=rows(2).NSizeGrid && rows(1).SCS_kHz~=rows(2).SCS_kHz && ...
    rows(1).BroadcastStartSample==0 && rows(2).BroadcastStartSample>0);
assert(isequal(hashes,arrayfun(@(p)string(sixgr.util.sha256File(p)),files)));
fprintf('SIB1_TRANSMISSION_EXTRACTION_PASS actual_composite_decodes=2 independent_SI_receiver=0 folder=%s\n',folder);
ok=true;
end

function localExact(original,direct)
for name=["SIB1Waveform","SIB1Grid","SIB1SpatialMapping","SIB1Bits", ...
        "SIB1PaddedBits","SIB1PayloadHash","SIB1TransportBlockSize", ...
        "DCI","DCIPayloadHex","Type0MonitoringOccasion","SIB1AbsoluteSlot", ...
        "SSBPowerReferenceContract","SIB1WaveformAbsoluteStartSample"]
    assert(isequaln(original.(name),direct.(name)), ...
        'test:SIB1ExtractionIdentity','Original %s changed in direct SI encoding.',name);
end
for name=["Grid","PDCCHInd","DMRSInd"]
    assert(isequaln(original.PDCCHTx.(name),direct.PDCCHTx.(name)));
end
for name=["Grid","TransportBlock","PDSCHIndicesZeroBased", ...
        "DMRSIndicesPerPortZeroBased","PTRSIndicesPerPortZeroBased","GPerCodeword"]
    assert(isequaln(original.PDSCHTx.(name),direct.PDSCHTx.(name)));
end
end

function localNegatives(cfg,association)
before=rng; ledger=sixgr.runtime.RuntimeCallLedger.snapshot();
bad=association; bad.NCellID=mod(bad.NCellID+1,1008);
reject(@()sixgr.phy.broadcast.generateSIB1Transmission(cfg,bad),'sixgr:phy:broadcast:SIB1AssociationMismatch');
bad=association; bad.NCellID=char(bad.NCellID);
reject(@()sixgr.phy.broadcast.generateSIB1Transmission(cfg,bad),'sixgr:phy:broadcast:SIB1AssociationMismatch');
bad=association; bad.NSizeGrid=bad.NSizeGrid+1;
reject(@()sixgr.phy.broadcast.generateSIB1Transmission(cfg,bad),'sixgr:phy:broadcast:SIB1AssociationMismatch');
bad=association; bad.SampleRate_Hz=bad.SampleRate_Hz+1;
reject(@()sixgr.phy.broadcast.generateSIB1Transmission(cfg,bad),'sixgr:phy:broadcast:SIB1AssociationMismatch');
bad=association; bad.SSB.PDCCHConfigSIB1=mod(bad.SSB.PDCCHConfigSIB1+1,256);
reject(@()sixgr.phy.broadcast.generateSIB1Transmission(cfg,bad),'sixgr:phy:broadcast:SIB1AssociationMismatch');
bad=association; index=bad.SSBTiming.SelectedSSBIndex+1;
bad.SSBBurstPlan.ActiveBitmap(index)=false;
reject(@()sixgr.phy.broadcast.generateSIB1Transmission(cfg,bad),'sixgr:phy:broadcast:InvalidSIB1Association');
bad=association; bad.SSBBurstPlan.PrecoderMatrices{index}=-bad.SSBBurstPlan.PrecoderMatrices{index};
reject(@()sixgr.phy.broadcast.generateSIB1Transmission(cfg,bad),'sixgr:phy:broadcast:SIB1AssociationMismatch');
bad=rmfield(association,'SSBBurstPlan');
reject(@()sixgr.phy.broadcast.generateSIB1Transmission(cfg,bad),'sixgr:phy:broadcast:InvalidSIB1Association');
bad=association; bad.WaveformDomain='invented_physical_mapping';
reject(@()sixgr.phy.broadcast.generateSIB1Transmission(cfg,bad),'sixgr:phy:broadcast:InvalidSIB1SpatialMapping');
after=sixgr.runtime.RuntimeCallLedger.snapshot(); added=after(height(ledger)+1:end,:);
assert(~any(ismember(added.FunctionName,["sixgr.phy.dl.PDCCH_Tx","sixgr.phy.dl.PDSCH_Tx"])) && ...
    isequal(rng,before),'Rejected associations must fail before native encoding or any random draw.');
end

function cfg=localConfiguration(ordinal,folder)
if ordinal==1
    % Same declared native component geometry as testSIB1WaveformRecoveryAWGN.
    cfg=sixgr.config.defaultConfig();
    cfg.run.strictMode=true;
    cfg.phy.sib1.enable=true; cfg.phy.pdcch.enable=true;
    cfg.phy.pdcch.blindSearch=true; cfg.phy.pdcch.dmrs.enable=true;
    cfg.phy.carrier.NCellID=17;
    cfg.phy.carrier.SubcarrierSpacing=30; cfg.phy.carrier.SubcarrierSpacing_kHz=30;
    cfg.phy.carrier.NSizeGrid=51;
    cfg.phy.channelBandwidth_MHz=20; cfg.frequency.bandwidth_hz=20e6;
    cfg.initial_access.type0=struct('monitoring_occasion_ordinal',3);
    cfg.initial_access.sib1.pdsch=struct('prb_start',0,'num_prb',24, ...
        'symbol_start',2,'num_symbols',12,'mcs',0,'rv',0,'ptrs_enabled',false);
    cfg.phy.sib1.coreset0Index=0; cfg.phy.sib1.searchSpaceZero=0;
    cfg.phy.carrier.NFrame=0; cfg.phy.carrier.NSlot=0;
else
    scenario=sixgr.lls6g.config.loadScenarioConfig( ...
        'simulator/configs/scenarios/lls_causal_access_to_data_wiring.yaml');
    cfg=sixgr.config.normalizeConfig(sixgr.lls6g.buildInternalConfig(scenario,folder));
    c=sixgr.phy.grid.makeCarrier(cfg);
    cfg=sixgr.phy.grid.applyRuntimeCarrierTimeline(cfg,2*double(c.SlotsPerFrame)+1);
end
cfg.phy.ssb.runtimeSSBIndex=0;
cfg.phy.sib1.transmissionScope="selected_ssb_occasion";
end

function reject(fcn,id)
try
    fcn();
catch cause
    assert(strcmp(cause.identifier,id),'test:WrongSIB1Guard','Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingSIB1Guard','Expected %s.',id);
end

function localReleaseLedger(owned)
if owned, sixgr.runtime.RuntimeCallLedger.reset(); end
end
