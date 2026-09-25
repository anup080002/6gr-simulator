function [ok,actual,request,received,physicalChannel,receivedReport,receivedPUSCH]=testNRCSIReportEngineTypeII(sourceSlot,episodeSeed)
% Measured CSI-RS -> Type-II RI/PMI/CQI -> independently decoded report.
% This component is not an access/shared-scheduler scenario qualification.
setup6GRSimToolkit('Verbose',false);
if nargin<1, sourceSlot=0; end
if nargin<2, episodeSeed=38214224; end
validateattributes(sourceSlot,{'numeric'},{'scalar','integer','nonnegative','finite'});
validateattributes(episodeSeed,{'numeric'},{'scalar','integer','nonnegative','finite','<',2^32-1});
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
rng(episodeSeed,'twister');
carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',15,'NCellID',17);
carrier.NSlot=sourceSlot;
csirs=nrCSIRSConfig('CSIRSType','nzp','RowNumber',4,'Density','one', ...
    'SymbolLocations',5,'SubcarrierLocations',0,'NumRB',24);
dmrs=nrPDSCHDMRSConfig;
indices=nrCSIRSIndices(carrier,csirs); symbols=nrCSIRS(carrier,csirs);
grid=nrResourceGrid(carrier,4); grid(indices)=symbols;
waveform=nrOFDMModulate(carrier,grid);
physicalChannel=[1 .2 .3i .1; .1i .2 1 -.4i];
[captured,noise]=sixgr.phy.waveform.addOccupiedREAWGN( ...
    waveform*physicalChannel.',carrier,20,'Seed',episodeSeed, ...
    'SignalEnergyPerOccupiedRE',mean(abs(symbols).^2));
receivedGrid=nrOFDMDemodulate(carrier,captured);
[H,nVar]=nrChannelEstimate(carrier,receivedGrid,indices,symbols,'CDMLengths',[2 1]);
assert(isfinite(nVar) && nVar>0 && noise.RequestedEsN0_dB==20);
snapshots=reshape(permute(H,[3 4 1 2]),2,4,[]);
measurement=sixgr.phy.mimo.CSIMeasurementState( ...
    MeasurementID="typeII_measured_csirs",UEID="UE-1", ...
    ResourceType="NZP-CSI-RS",ResourceID="CSI-RS-0",ResourceOrdinal=0, ...
    Slot=sourceSlot,MaxAgeSlots=4,ChannelEstimate=snapshots,NoiseVariance=nVar, ...
    Provenance="measured_noisy_csirs_ofdm_component");
request=struct('ReportConfigID',"typeII_measured_report",'Epoch',0, ...
    'CodebookType',"typeII",'Ports',4,'Rank',1,'MaxRank',2,'AllowedRanks',[1 2], ...
    'N1',2,'N2',1,'O1',4,'O2',1,'NumberOfBeams',2,'PhaseAlphabetSize',4, ...
    'ReportQuantity',"cri-ri-li-pmi-cqi",'NumCSIResources',1, ...
    'FrequencyGranularity',"wideband",'UCIChannel',"PUSCH");
expired=struct('Strict',true,'RankDomain',[1 2],'CQITable',"table1", ...
    'ReportConfiguration',request,'CurrentSlot',measurement.Slot+measurement.MaxAgeSlots+1);
localReject(@()sixgr.phy.mimo.NRCSIReportEngine.run( ...
    carrier,csirs,dmrs,H,nVar,expired,measurement), ...
    'sixgr:mimo:StaleMeasurementState');
% A non-finite consumer clock must not make both age comparisons false.
for invalidSlot=[NaN Inf -1 .5]
    invalidClock=expired; invalidClock.CurrentSlot=invalidSlot;
    localReject(@()sixgr.phy.mimo.NRCSIReportEngine.run( ...
        carrier,csirs,dmrs,H,nVar,invalidClock,measurement), ...
        'sixgr:mimo:InvalidMeasurementTime');
end
measurement.validateAt(measurement.Slot+measurement.MaxAgeSlots);
cases=0;
for alphabet=[4 8]
 for ranks={1,2,[1 2]}
    request.PhaseAlphabetSize=alphabet;
    cfg=struct('Strict',true,'RankDomain',ranks{1},'CQITable',"table1", ...
        'ReportConfiguration',request);
    actual=sixgr.phy.mimo.NRCSIReportEngine.run(carrier,csirs,dmrs,H,nVar,cfg,measurement);
    reference=nrCSIReportConfig('NSizeBWP',24,'CodebookType','type2', ...
        'PanelDimensions',[1 2 1],'NumberOfBeams',2,'PhaseAlphabetSize',alphabet, ...
        'CQIFormatIndicator','wideband','PMIFormatIndicator','wideband');
    restriction=zeros(1,2); restriction(ranks{1})=1; reference.RIRestriction=restriction;
    ri=nr5g.internal.nrRISelect(carrier,csirs,reference,H,nVar,'MaxSE');
    [cqi,pmi,ci,pi]=nr5g.internal.nrCQIReport(carrier,csirs,reference,dmrs,ri,H,nVar);
    assert(actual.RI==ri && ismember(ri,ranks{1}) && actual.CQI==cqi(1));
    assert(isequal(actual.PMISet,pmi) && isnan(actual.PMI));
    assert(abs(actual.CQIEffectiveSINR_dB-ci.EffectiveSINR(1))<1e-12);
    expectedReceiverSINR=10*log10(expm1(mean(log1p(pi.SINRPerREPMI),'all')));
    assert(abs(actual.WidebandSINR_dB-expectedReceiverSINR)<1e-12);
    assert(norm(actual.Precoder_W-pi.W,'fro')<=actual.PrecoderMatrixToolboxFrobeniusBound);
    assert(~actual.ConfiguredSNRUsed && ~actual.ConfiguredOracleUsed && ~actual.SVDThresholdUsed);
    % The gNB bootstrap rank is deliberately different. All selection fields
    % and the deterministic matrix must be recoverable from received bits.
    installed=request; installed.Rank=3-ri;
    receiver=sixgr.phy.mimo.CSIReportConfiguration(installed,0);
    values=receiver.decode(actual.CSIPart1Bits,actual.CSIPart2Bits);
    assert(values.RI==ri && values.CQI_CW0==cqi(1) && ...
        isequal(values.PMIComponents,actual.PMIComponents));
    assert(isequal(values.Precoder_W,actual.Precoder_W));
    payload=sixgr.phy.dl.packCSIFeedbackPayload(actual,cfg);
    assert(payload.BitExactSupported && payload.SeparateEncoding && ...
        payload.WireFormatQualification=="qualified_typeII_wideband_pusch_codec_only");
    cases=cases+1;
 end
end
% Exercise the production CSI_Feedback facade on the same captured CSI-RS
% estimate. Its persisted fields must identify the actual measured report.
facadeCfg.phy.mimo=struct('strict',true,'N1',2,'N2',1,'O1',4,'O2',1);
facadeCfg.phy.csi=struct('reportCSI',true,'reportCQI',true,'reportRI',true, ...
    'reportPMI',true,'reportCRI',true,'maxRank',2,'rankDomain',[1 2], ...
    'cqiTable',"table1",'reportConfiguration',request);
facade=sixgr.phy.dl.CSI_Feedback(measurement.ChannelEstimate,nVar,facadeCfg, ...
    'MeasurementState',measurement,'ReportConfiguration',request, ...
    'Carrier',carrier,'CSIRSConfig',csirs,'PDSCHDMRSConfig',dmrs,'FullChannelEstimate',H);
assert(facade.CSIReportConfigID==request.ReportConfigID && ...
    facade.CSIConfigurationEpoch==request.Epoch && facade.CSIUCIChannel=="PUSCH");
assert(isequal(int8(sixgr.runtime.RawCSVArrayCodec.decode(facade.CSIPart1BitsToken)),actual.CSIPart1Bits) && ...
    isequal(int8(sixgr.runtime.RawCSVArrayCodec.decode(facade.CSIPart2BitsToken)),actual.CSIPart2Bits));
disp('TYPEII_MEASURED_CSI_FACADE_WIRE_PASS');
[received,receivedReport,receivedPUSCH]=localMeasuredReportOverPUSCH(actual,request,sourceSlot,episodeSeed+1);
% Unsupported profiles fail before selection, rather than using Type-I.
bad=cfg; bad.ReportConfiguration.UCIChannel="PUCCH";
localReject(@()sixgr.phy.mimo.NRCSIReportEngine.run(carrier,csirs,dmrs,H,nVar,bad,measurement), ...
    'sixgr:mimo:UnsupportedCSIReportLayout');
bad=cfg; bad.RankDomain=[1 3];
localReject(@()sixgr.phy.mimo.NRCSIReportEngine.run(carrier,csirs,dmrs,H,nVar,bad,measurement), ...
    'sixgr:mimo:InvalidRI');
fprintf('TYPEII_MEASURED_REPORT_ENGINE_PASS cases=%d measured_noise=%.12g configured_grid_noise=%.12g\n', ...
    cases,nVar,noise.GridNoiseVariance);
ok=true;
end

function [received,report,rx]=localMeasuredReportOverPUSCH(measured,request,sourceSlot,noiseSeed)
cfg=sixgr.config.defaultConfig();
cfg.channel.model="AWGN"; cfg.channel.awgnOnly=true;
cfg.phy.nTxAnt=1; cfg.phy.nRxAnt=1;
cfg.channel.nTxAnt=1; cfg.channel.nRxAnt=1;
cfg.scenario.ue.nTxAnt=1; cfg.antenna.ue.numElements=1;
cfg.phy.carrier.NSizeGrid=12; cfg.phy.carrier.SubcarrierSpacing=30;
% CSI-RS uses 1 ms slots; the isolated PUSCH uses 0.5 ms slots.
cfg.phy.carrier.NSlot=2*(sourceSlot+1);
cfg.phy.pusch.prbSet=0:5; cfg.phy.pusch.symbolAllocation=[0 14];
cfg.phy.pusch.modulation="QPSK"; cfg.phy.pusch.codeRate=.3;
cfg.phy.pusch.mcsIndex=4; cfg.phy.pusch.numLayers=1; cfg.phy.pusch.nLayers=1;
cfg.phy.pusch.numAntennaPorts=1; cfg.phy.pusch.numPorts=1;
cfg.phy.pusch.transmissionScheme="nonCodebook";
cfg.phy.pusch.transformPrecoding=false; cfg.phy.pusch.enablePTRS=false;
cfg.phy.pusch.equalizer="MMSE";
cfg.phy.pusch.dmrs.typeAPosition=2; cfg.phy.pusch.dmrs.configurationType=1;
cfg.phy.pusch.dmrs.additionalPosition=1; cfg.phy.pusch.dmrs.maxLength=1;
cfg.phy.pusch.dmrs.numCDMGroupsWithoutData=2;
cfg.phy.channelEstimation.method="LS";
payload=sixgr.phy.ul.pusch.PUSCHUCIPayload('HARQACK',int8([1;0]), ...
    'CSIPart1',measured.CSIPart1Bits,'CSIPart2',measured.CSIPart2Bits);
tx=sixgr.phy.ul.PUSCH_Tx(cfg,'UCIPayload',payload,'InitialIMCSPerCodeword',4);
[capture,noise]=sixgr.phy.waveform.addOccupiedREAWGN(tx.Waveform,tx.Carrier,30, ...
    'Seed',noiseSeed,'SignalEnergyPerOccupiedRE',1);
% Explicit fixture obligation, not a claimed shared-runtime scheduling trace.
observationID="typeII_measured_report_slot_"+string(sourceSlot)+"_seed_"+string(noiseSeed);
obligation=struct('ObservationID',observationID, ...
    'ConfigurationEpoch',0,'AssignmentDigest',"declared_ul_assignment", ...
    'HARQMappingDigest',"declared_two_assignments",'HARQACKBitCount',2, ...
    'ConfiguredGrantUCIBitCount',0,'CSIReportConfigID',request.ReportConfigID, ...
    'CSIConfigurationEpoch',0);
context=sixgr.phy.ul.pusch.PUSCHUCIReceiveContext(obligation);
request.Rank=3-measured.RI;
installed=sixgr.phy.mimo.CSIReportConfiguration(request,0);
% TX report metadata is deliberately unusable in the receiver configuration.
cfg.phy.csi.reportConfiguration=struct('Rank',NaN,'TXPart2BitCount',999);
rx=sixgr.phy.ul.PUSCH_Rx(capture,cfg,'Carrier',tx.Carrier,'PUSCH',tx.PUSCH, ...
    'TransportBlockSize',tx.TransportBlockSize,'TargetCodeRate',tx.TargetCodeRate, ...
    'RV',tx.RV,'InitialIMCSPerCodeword',4,'UCIReceiveContext',context, ...
    'UCIReportConfiguration',installed,'NoiseVar',noise.SampleNoiseVariance,'NoiseVarDomain','time');
assert(rx.Ok && ~rx.CRCError && isequal(rx.TransportBlock,tx.TransportBlock));
assert(isequal(rx.DecodedHARQACKBits,payload.HARQACK) && ~rx.UCIReferenceScoringAvailable);
assert(rx.CSIPresenceResolved && rx.CSIReportDetected && ...
    rx.UCIReceiverEvidence.CSIPart1DecodedBeforePart2);
received=installed.decode(rx.DecodedCSIPart1Bits,rx.DecodedCSIPart2Bits);
% Component receive record. Timing/identity describe this declared fixture,
% not a claimed received-DCI/shared-runtime scheduling trace.
report=struct('CSIReportConfigID',installed.ReportConfigID, ...
    'CSIConfigurationEpoch',installed.Epoch,'CSIUCIChannel',installed.UCIChannel, ...
    'CSIPart1BitsToken',string(sixgr.runtime.RawCSVArrayCodec.encode(rx.DecodedCSIPart1Bits)), ...
    'CSIPart2BitsToken',string(sixgr.runtime.RawCSVArrayCodec.encode(rx.DecodedCSIPart2Bits)), ...
    'CSIUCIDecodeOk',logical(rx.CSIReportDetected), ...
    'SourceSignal',"received_CSI_UCI",'ReportIdentity',observationID, ...
    'RNTI',1,'ServingCell',1,'SourceSlot',sourceSlot+1, ...
    'DueSlot',sourceSlot+2,'DeliveredSlot',sourceSlot+2, ...
    'RI',received.RI,'PMI',NaN,'CRI',received.CRI);
assert(received.RI==measured.RI && received.CQI_CW0==measured.CQI && ...
    isequal(received.PMIComponents,measured.PMIComponents) && ...
    isequal(received.Precoder_W,measured.Precoder_W));
assert(~rx.CSIPresenceEvidence.TransmitterMetadataUsed);
fprintf('TYPEII_MEASURED_CSIRS_TO_PUSCH_PASS ri=%d cqi=%d part1=%d part2=%d no_tx_reference=1\n', ...
    received.RI,received.CQI_CW0,numel(rx.DecodedCSIPart1Bits),numel(rx.DecodedCSIPart2Bits));
end

function localReject(action,id)
try, action(); catch ex
    assert(string(ex.identifier)==id,'Expected %s, got %s: %s',id,ex.identifier,ex.message); return;
end
error('test:ExpectedFailure','Unsupported measured Type-II report was accepted.');
end
