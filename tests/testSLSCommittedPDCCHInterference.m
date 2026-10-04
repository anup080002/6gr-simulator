function ok=testSLSCommittedPDCCHInterference()
% Actual native coding and finite propagation; not BLER/control qualification.
cfg=sixgr.config.defaultConfig();
for fragment=["calibrated_link_abstraction","finite_srs_csirs_interference","finite_pdcch_interference"]
    cfg=sixgr.util.mergeStruct(cfg,sixgr.lls6g.config.readConfigFile( ...
        fullfile('simulator','configs','system',fragment+'.yaml')));
end
cfg.run.seed=113; cfg.run.executionID='committed_pdcch_interference';
cfg.phy.carrier=struct('NSizeGrid',24,'NStartGrid',0,'SubcarrierSpacing',30,'NCellID',1);
cfg.phy.duplex.mode='TDD'; cfg.phy.fc_Hz=4e9; cfg.phy.numerology.scs_kHz=30;
cfg.phy.srs.enable=false; cfg.phy.csirs.enable=false;
cfg.phy.csirs.precoderMatrices=eye(2);
cfg.phy.csi.reportConfiguration.NumCSIResources=1;
cfg.phy.frameStructure.SlotState.CommonDirection=repmat('D',5,14);
cfg.phy.frameStructure.SlotState.ResolvedDirection=repmat("DL",5,14);
cfg.scenario.bs.noiseFigure_dB=7; cfg.scenario.ue.noiseFigure_dB=9;
cfg.channel=struct('model','TDL-A','tdlProfile','TDL-A','delaySpread_s',30e-9, ...
    'doppler_Hz',70,'normalizeChannelOutputs',false,'awgnOnly',false);
cfg.rf=struct(); cfg.phy.impairments=struct();
cfg.phy.mimo.strict=true;
cfg.phy.pdcch=struct('enable',true,'dmrs',struct('enable',true), ...
    'aggregationLevel',2,'aggregationLevels',2,'nStartBWP',0,'nSizeBWP',24, ...
    'coreset',struct('id',1,'duration',2,'frequencyResources',ones(1,4), ...
        'mappingType','noninterleaved','regBundleSize',6,'shiftIndex',0), ...
    'searchSpace',struct('id',1,'startSymbol',0,'slotPeriodAndOffset',[1 0], ...
        'duration',1,'configuredNumCandidates',[0 4 0 0 0]));
p=cfg.system.linkAbstraction.networkSpatial;
p.bsPorts=2; p.uePorts=2; p.csirsScramblingIDs=[11 37];
p.pdcchScramblingIDs=[11 37]; p.pdcchPrecoderMatrices=[1 1;1 -1]/sqrt(2);
cfg.system.linkAbstraction.networkSpatial=p;
cfg.system.linkAbstraction.dlFeedback.panel.Ports=2;
large=struct('Pathloss_dB',[80 85;87 81],'TxPower_dBm',[30 27;30 27]);
state=struct('TTI',1,'AbsoluteSlot0',0,'ServingCells',[1 2],'RNTIByUE',[201 202], ...
    'GrantsDL',struct([]),'GrantsUL',struct([]),'GrantCellsDL',[],'GrantCellsUL',[], ...
    'LargeScaleState',large);
g=struct('Direction','DL','ControlAbsoluteSlot',0,'ScheduledAbsoluteSlot',1, ...
    'RNTI',201,'UEIndex',1,'SystemServingCellID',1, ...
    'DCI',struct('Bits',uint8(mod((0:31).',2))));
h=g; h.RNTI=202; h.UEIndex=2; h.SystemServingCellID=2; h.DCI.Bits=1-h.DCI.Bits;
u=g; u.Direction='UL'; u.ScheduledAbsoluteSlot=2; u.DCI.Bits=circshift(g.DCI.Bits,1);
state=sixgr.system.bindSLSIssuedControlPopulation(state,[g h],[1 2],u,1);
provider=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
provider.commitSlotPopulation(state); provider.commitSlotPopulation(state);
emissions=provider.committedPDCCHEmissions(1);
assert(numel(emissions)==3 && nnz([emissions.ServingCellID]==1)==2);
a=emissions(1); b=emissions(3);
assert(isempty(intersect(a.Coordinates0Based,b.Coordinates0Based,'rows')), ...
    'Distinct issued DL/UL control must use nonoverlapping candidates in the same cell.');
carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30,'NCellID',1);
authored=[state.IssuedGrantsDL;state.IssuedGrantsUL];
owners=[state.IssuedGrantCellsDL;state.IssuedGrantCellsUL];
decodedEvidence=struct('RNTI',{},'ScramblingID',{},'ControlAbsoluteSlot0',{}, ...
    'Candidate',{},'DecodedBits',{},'CRCMask',{},'Scope',{});
for emissionIndex=1:numel(emissions)
    e=emissions(emissionIndex); issued=authored(emissionIndex);
    receiverRNTI=issued.RNTI; receiverNID=p.pdcchScramblingIDs(owners(emissionIndex));
    assert(e.RNTI==receiverRNTI && e.ScramblingID==receiverNID && ...
        e.AbsoluteSlot0==issued.ControlAbsoluteSlot && ...
        e.ScheduledAbsoluteSlot0==issued.ScheduledAbsoluteSlot);
    % Independent native resource/coding reconstruction, not the emitter's
    % transmitted grid or any synthetic expected receive samples.
    core=nrCORESETConfig('CORESETID',1,'Duration',2,'FrequencyResources',ones(1,4), ...
        'CCEREGMapping','noninterleaved','REGBundleSize',6,'ShiftIndex',0);
    search=nrSearchSpaceConfig('SearchSpaceID',1,'CORESETID',1, ...
        'StartSymbolWithinSlot',0,'SlotPeriodAndOffset',[1 0], ...
        'Duration',1,'NumCandidates',[0 4 0 0 0]);
    control=nrPDCCHConfig('NStartBWP',0,'NSizeBWP',24,'CORESET',core, ...
        'SearchSpace',search,'AggregationLevel',2,'AllocatedCandidate',e.Candidate, ...
        'RNTI',receiverRNTI,'DMRSScramblingID',receiverNID);
    [ind,dmrs,di]=nrPDCCHResources(carrier,control);
    cw=nrDCIEncode(e.DCIBits,e.RNTI,2*numel(ind));
    grid=nrResourceGrid(carrier); grid(ind)=nrPDCCH(cw,e.ScramblingID,e.RNTI); grid(di)=dmrs;
    idx=sub2ind([288 14],e.Coordinates0Based(:,1)+1,e.Coordinates0Based(:,2)+1);
    assert(isequal(cw,e.DCICodeword) && norm(grid(idx)-e.Symbols)<1e-12);
    % Decode the producer's symbols using independently installed receiver
    % identity/resources. Do not feed the reconstructed expected codeword
    % into the decoder. This noiseless coding check is not a BLER campaign,
    % blind candidate detector, or end-to-end control-delivery qualification.
    receivedGrid=nrResourceGrid(carrier); receivedGrid(idx)=e.Symbols;
    llr=nrPDCCHDecode(receivedGrid(ind),receiverNID,receiverRNTI,1);
    [decoded,crcMask]=nrDCIDecode(llr,numel(issued.DCI.Bits),8,receiverRNTI);
    assert(crcMask==0 && isequal(double(decoded(:)),double(issued.DCI.Bits(:))), ...
        'test:PDCCHIssuedPayloadDecode','Emitted PDCCH must recover the authored DCI with a valid CRC.');
    decodedEvidence(emissionIndex)=struct('RNTI',receiverRNTI, ...
        'ScramblingID',receiverNID,'ControlAbsoluteSlot0',e.AbsoluteSlot0, ...
        'Candidate',e.Candidate,'DecodedBits',decoded,'CRCMask',crcMask, ...
        'Scope',"noiseless_known_candidate_coding_check");
    actual=(e.Symbols.*sqrt(e.TransmitPowerPerRE_W))*e.Precoder.';
    assert(max(abs(sum(abs(actual).^2,2)-e.AggregateAntennaEPRE_W))<1e-14);
end
reference=cfg; reference.system.linkAbstraction.networkSpatial.interferencePopulation='scheduled_shared_data_and_srs';
for malformed={[],[0;NaN;1],[0;2;1],ones(2,2),'0101'}
    bad=state; bad.IssuedGrantsDL(1).DCI.Bits=malformed{1};
    reject(@()sixgr.system.abstraction.buildScheduledPDCCHEmissions(cfg,bad), ...
        'sixgr:abstraction:PDCCHEmissionPayload');
end
reject(@()sixgr.system.abstraction.buildScheduledPDCCHEmissions(cfg,rmfield(state,'IssuedGrantsUL')), ...
    'sixgr:abstraction:PDCCHIssuedPopulation');
bad=cfg; bad.system.linkAbstraction.networkSpatial.pdcchPrecoderMatrices=ones(2,2);
reject(@()sixgr.system.abstraction.buildScheduledPDCCHEmissions(bad,state), ...
    'sixgr:abstraction:PDCCHEmissionBasis');
bad=cfg; bad.phy.pdcch.aggregationLevel=3;
reject(@()sixgr.system.abstraction.buildScheduledPDCCHEmissions(bad,state), ...
    'sixgr:abstraction:PDCCHEmissionAggregation');
bad=state; bad.IssuedGrantsDL(1).DCI.Bits(1)=1-bad.IssuedGrantsDL(1).DCI.Bits(1);
reject(@()provider.commitSlotPopulation(bad),'sixgr:abstraction:SlotHistoryMutation');
idle=state; idle.TTI=2; idle.AbsoluteSlot0=1;
idle=sixgr.system.bindSLSIssuedControlPopulation(idle,struct([]),[],struct([]),[]);
provider.commitSlotPopulation(idle);
assert(isempty(provider.committedPDCCHEmissions(2)),'No control is emitted merely because earlier DCI schedules data now.');
ofdm=nrOFDMInfo(carrier);
native=sixgr.system.abstraction.createNetworkSpatialChannel(cfg,ofdm.SampleRate,"DL");
id=sixgr.system.abstraction.networkChannelCalibrationIdentity(cfg,native.Object);
old=sixgr.system.abstraction.networkChannelCalibrationIdentity(reference,native.Object);
assert(id.ProfileID~=old.ProfileID);
[observed,withoutControl,expected,errorRelative]=finitePropagation(cfg,state,idle);
ssbEvidence=ssbPropagation(cfg,state,idle);
dataConsumer(cfg,state,idle);
dataConsumer(ssbEvidence.Config,state,idle);
folder=tempname(fullfile(pwd,'logs')); mkdir(folder);
save(fullfile(folder,'pdcch_emissions.mat'),'cfg','emissions','id', ...
    'decodedEvidence','observed','withoutControl','expected','errorRelative','ssbEvidence');
fprintf('SLS_COMMITTED_PDCCH_PASS emissions=3 decoded_dci=3 no_idle_reemit=1 waveform_error=%g evidence=%s\n',errorRelative,folder);
ok=true;
end
function [a,b,expected,errorRelative]=finitePropagation(cfg,state,idle)
% Long-delay native fading intentionally reaches the subsequent CSI symbol.
% This is a finite-operator numerical qualification point, not typical-link BLER.
cfg.channel.delaySpread_s=1e-6;
cfg.phy.csirs=struct('enable',true,'nPorts',2,'period_slots',5,'offset_slots',0, ...
    'numResources',1,'resourceIDs',7,'rowNumbers',3,'symbolLocationsByResource',2, ...
    'subcarrierLocationsByResource',0,'rbOffsetsByResource',0,'numRBsByResource',24, ...
    'precoderMatrices',eye(2));
provider=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
baselineCfg=cfg;
baselineCfg.system.linkAbstraction.networkSpatial.interferencePopulation='scheduled_shared_data_and_srs_and_csirs';
baseline=sixgr.system.abstraction.NetworkSpatialGrantProvider(baselineCfg);
provider.commitSlotPopulation(state); provider.commitSlotPopulation(idle);
baseline.commitSlotPopulation(state); baseline.commitSlotPopulation(idle);
rs=provider.committedCSIRSEmissions(1); coords=rs(1).Coordinates0Based;
ctx=struct('TTI',1,'Direction',"DL",'UEIndex',1,'ServingCellID',1,'CRI',0);
a=provider.evaluateReferenceInterference(ctx,coords);
b=baseline.evaluateReferenceInterference(ctx,coords);
assert(a.PDCCHInterferenceIncluded && numel(a.PDCCHEmissionPopulation)==3 && ...
    ~a.WaveformMeasured && ~a.PrimaryStudyAccepted && ~a.CommonControlInterferenceQualified);
expected=complex(zeros(size(a.ExplicitPDCCHResponse)));
for e=provider.committedPDCCHEmissions(1)
    expected=expected+independentWaveform(cfg,e,a.ReceiveWindow,coords,state.LargeScaleState);
end
assert(norm(expected,'fro')>0,'The test must exercise real control-to-CSI leakage.');
errorRelative=norm(expected-a.ExplicitPDCCHResponse,'fro')/norm(expected,'fro');
assert(errorRelative<2e-10,'test:PDCCHNetworkWaveformMismatch','Relative waveform error %g',errorRelative);
% All explicit emissions use the declared native phase. Preserve cross
% terms with other-cell CSI; summing separate pilot powers would be wrong.
for k=1:size(coords,1)
    c=b.ExplicitReferenceResponse(:,k); p=expected(:,k);
    delta=(c+p)*(c+p)'-c*c';
    actual=a.ExternalCovariance(:,:,k)-b.ExternalCovariance(:,:,k);
    assert(norm(actual-delta,'fro')<1e-10*max(norm(delta,'fro'),realmin));
end
end
function evidence=ssbPropagation(cfg,state,idle)
% Actual SSB population, with the same independent native OFDM/FIR oracle
% as control above. It must reach a subsequent CSI FFT window via real delay
% spread, not through a fabricated reservation-power term.
cfg=sixgr.util.mergeStruct(cfg,sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/system/native_ssb_emission.yaml'));
cfg.channel.delaySpread_s=1e-6;
cfg.phy.carrier.centerFrequency_Hz=4e9; cfg.phy.frequencyRange='FR1';
cfg.frequency.band_context='n77'; cfg.frequency.spectrum='unpaired';
cfg.initial_access.enabled=false;
cfg.phy.ssb=struct('enable',true,'blockPattern','Case C','Lmax',8, ...
    'scs_kHz',30,'periodicity_ms',20,'halfFrameIndex',0,'NCRBSSB',0,'KSSB',0, ...
    'activeBitmap',[1 1 0 0 0 0 0 0],'perSSBPower_dB',[0 -3 0 0 0 0 0 0], ...
    'precoderMatrices',repmat([1 1;1 -1]/sqrt(2),4,1));
cfg.phy.pbch.enable=true;
cfg.phy.mib=struct('pdcchConfigSIB1',17,'dmrsTypeAPosition',2, ...
    'cellBarred',true,'intraFreqReselection',false);
cfg.system.linkAbstraction.networkSpatial.ssbCellIDs=[11 37];
cfg.phy.csirs=struct('enable',true,'nPorts',2,'period_slots',5,'offset_slots',0, ...
    'numResources',1,'resourceIDs',7,'rowNumbers',3,'symbolLocationsByResource',12, ...
    'subcarrierLocationsByResource',0,'rbOffsetsByResource',0,'numRBsByResource',24, ...
    'precoderMatrices',eye(2));
provider=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
baselineCfg=cfg; baselineCfg.system.linkAbstraction.networkSpatial.ssbInterferenceEnabled=false;
baseline=sixgr.system.abstraction.NetworkSpatialGrantProvider(baselineCfg);
provider.commitSlotPopulation(state); provider.commitSlotPopulation(idle);
baseline.commitSlotPopulation(state); baseline.commitSlotPopulation(idle);
population=provider.committedSSBEmissions(1);
assert(numel(population)==4 && isempty(provider.committedSSBEmissions(2)));
for e=population
    assert(size(e.ReservedCoordinates0Based,1)==960 && numel(e.Symbols)==830);
    for control=provider.committedPDCCHEmissions(1)
        if control.ServingCellID~=e.ServingCellID, continue; end
        assert(isempty(intersect(control.Coordinates0Based,e.ReservedCoordinates0Based,'rows')));
    end
end
rs=provider.committedCSIRSEmissions(1); coords=rs(1).Coordinates0Based;
ctx=struct('TTI',1,'Direction',"DL",'UEIndex',1,'ServingCellID',1,'CRI',0);
a=provider.evaluateReferenceInterference(ctx,coords);
b=baseline.evaluateReferenceInterference(ctx,coords);
assert(a.SSBInterferenceIncluded && ~b.SSBInterferenceIncluded && ...
    ~isempty(a.SSBEmissionPopulation) && ~a.PrimaryStudyAccepted && ~a.WaveformMeasured);
expected=complex(zeros(size(a.ExplicitSSBResponse)));
for e=population
    expected=expected+independentWaveform(cfg,e,a.ReceiveWindow,coords,state.LargeScaleState);
end
assert(norm(expected,'fro')>0,'The independent waveform must exercise SSB-to-CSI leakage.');
errorRelative=norm(a.ExplicitSSBResponse-expected,'fro')/norm(expected,'fro');
assert(errorRelative<2e-10,'test:SSBNetworkWaveformMismatch','Relative waveform error %g',errorRelative);
for k=1:size(coords,1)
    c=b.ExplicitReferenceResponse(:,k); s=expected(:,k);
    delta=(c+s)*(c+s)'-c*c';
    actual=a.ExternalCovariance(:,:,k)-b.ExternalCovariance(:,:,k);
    assert(norm(actual-delta,'fro')<1e-10*max(norm(delta,'fro'),realmin));
end
carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30); ofdm=nrOFDMInfo(carrier);
native=sixgr.system.abstraction.createNetworkSpatialChannel(cfg,ofdm.SampleRate,"DL");
identity=sixgr.system.abstraction.networkChannelCalibrationIdentity(cfg,native.Object);
oldIdentity=sixgr.system.abstraction.networkChannelCalibrationIdentity(baselineCfg,native.Object);
assert(identity.ProfileID~=oldIdentity.ProfileID && identity.SSBInterferenceEnabled);
% A same-cell resource collision is a configuration error, not extra
% interference between independently generated serving-cell channels.
bad=cfg; bad.phy.csirs.symbolLocationsByResource=2;
broken=sixgr.system.abstraction.NetworkSpatialGrantProvider(bad);
reject(@()broken.commitSlotPopulation(state),'sixgr:abstraction:SSBCSIRSCollision');
evidence=struct('Config',cfg,'Population',population,'Observation',a, ...
    'WithoutSSB',b,'IndependentResponse',expected,'RelativeError',errorRelative, ...
    'CalibrationIdentity',identity,'PrimaryStudyAccepted',false);
fprintf('SLS_SSB_INTERFERENCE_PASS emissions=4 exact_empty_REs=1 waveform_error=%g\n',errorRelative);
end
function dataConsumer(cfg,state,idle)
% Exercise the real finite provider -> calibrated decoder -> persisted trace.
% A visibly test-only curve exercises dispatch/accounting, not BLER physics.
cfg.run.pdschExecutionProfile='phy_calibration'; cfg.run.puschExecutionProfile='phy_calibration';
cfg.phy.nTxAnt=2; cfg.phy.nRxAnt=2; cfg.channel.nTxAnt=2; cfg.channel.nRxAnt=2;
cfg.scenario.bs.nTxAnt=2; cfg.scenario.ue.nRxAnt=2;
cfg.antenna.bs.numElements=2; cfg.antenna.bs.numRFChains=2;
cfg.antenna.ue.numElements=2; cfg.antenna.ue.numRFChains=2;
cfg.phy.beamManagement.hybridBeamformingEnabled=false;
cfg.phy.trs.enable=false; cfg.phy.csirs.enable=false;
cfg.phy.csiim.enable=false; cfg.phy.ptrs.enable=false;
ssb=logical(sixgr.util.structGet(cfg,'system.linkAbstraction.networkSpatial.ssbInterferenceEnabled',false));
if ~ssb, cfg.phy.ssb.enable=false; end
cfg.channel.delaySpread_s=1e-6;
mcs=sixgr.link.resolveMCSProfile('qam64_table1',1);
cfg.phy.pdsch.numLayers=2; cfg.phy.pdsch.nLayers=2;
cfg.phy.pdsch.numPorts=2; cfg.phy.pdsch.nPorts=2;
cfg.phy.pdsch.modulation='QPSK'; cfg.phy.pdsch.codeRate=mcs.TargetCodeRate;
cfg.phy.pdsch.mcsTable='qam64_table1'; cfg.phy.pdsch.mcsIndex=1;
cfg.phy.pdsch.dmrs.portSet=0:1; cfg.phy.pdsch.enablePTRS=false;
cfg.phy.pdsch.mappingType='B'; cfg.phy.pdsch.dmrs.numCDMGroupsWithoutData=1;
cfg.phy.pdsch.xOverhead=0;
% PRB 22 is outside the 240-subcarrier SSB; symbols start after PDCCH.
g=struct('Direction','DL','Frame',0,'Slot',0,'ScheduledAbsoluteSlot',0, ...
    'RNTI',201,'UEIndex',1,'ServingCell',1,'PRBSet',22,'SymbolAllocation',[2 10], ...
    'Modulation','QPSK','NumLayers',2,'Layers',2,'NumLogicalPorts',2,'NumRFChains',2, ...
    'TargetCodeRate',mcs.TargetCodeRate,'MCSIndex',1,'MCSTable','qam64_table1', ...
    'PrecodingMatrixLogicalPorts',eye(2)/sqrt(2),'PrecodingMatrix',eye(2)/sqrt(2), ...
    'PrecoderNormalizationConvention','unit_frobenius','PrecoderSource','numerical_contract_fixture');
g.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,"DL",g,'Frame',0,'Slot',0);
[~,carrier,pdsch]=sixgr.system.abstraction.scheduledDataREMap(cfg,g,0);
[~,resourceInfo]=nrPDSCHIndices(carrier,pdsch);
g=rmfield(g,'PHYGrant'); g.NREPerPRB=resourceInfo.NREPerPRB;
g.TBSBits=nrTBS(g.Modulation,g.NumLayers,numel(g.PRBSet),g.NREPerPRB,g.TargetCodeRate,0);
g.HARQ=struct('HarqID',0,'RV',0);
g.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,"DL",g,'Frame',0,'Slot',0);
state.GrantsDL=g; state.GrantCellsDL=1;
provider=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
provider.commitSlotPopulation(state); provider.commitSlotPopulation(idle);
ctx=struct('TTI',1,'Direction',"DL",'Grant',g,'ServingCellID',1, ...
    'TransportBlockIdentity',"control_export_fixture_only",'IsRetransmission',false, ...
    'TBSBits',g.PHYGrant.CodingLayout.TBSBits,'NumLayers',g.NumLayers, ...
    'TargetCodeRate',g.TargetCodeRate,'SCS_kHz',30,'ChannelModel',string(cfg.channel.model));
o=provider.evaluate(ctx,state);
sixgr.system.abstraction.validateFiniteInterferencePopulation(cfg,o);
assert(o.PDCCHInterferenceIncluded && o.SSBInterferenceIncluded==ssb && ...
    o.PDCCHEmissionCount>0 && (~ssb || o.SSBEmissionCount>0));
% Keep exact population provenance strict: accepting a newly implemented
% producer must not admit an unknown label, a missing population or an oracle.
bad=o; bad.FiniteWindow.SourceClassification="modeled_committed_finite_window_shared_data_unknown";
reject(@()sixgr.system.abstraction.validateFiniteInterferencePopulation(cfg,bad),'sixgr:abstraction:FiniteSpatialEvidence');
bad=o; bad.FiniteWindow.PDCCHInterferenceIncluded=false;
reject(@()sixgr.system.abstraction.validateFiniteInterferencePopulation(cfg,bad),'sixgr:abstraction:FiniteSpatialEvidence');
bad=o; bad.PDCCHEmissionCount=bad.PDCCHEmissionCount+1;
reject(@()sixgr.system.abstraction.validateFiniteInterferencePopulation(cfg,bad),'sixgr:abstraction:FiniteSpatialEvidence');
bad=o; bad.FiniteWindow.ReferenceObservationOnly=true;
reject(@()sixgr.system.abstraction.validateFiniteInterferencePopulation(cfg,bad),'sixgr:abstraction:FiniteSpatialEvidence');
bad=o; bad.FiniteWindow.WaveformMeasured=true;
reject(@()sixgr.system.abstraction.validateFiniteInterferencePopulation(cfg,bad),'sixgr:abstraction:FiniteSpatialEvidence');
other=cfg; other.system.linkAbstraction.networkSpatial.interferencePopulation='scheduled_shared_data_and_srs_and_csirs';
reject(@()sixgr.system.abstraction.validateFiniteInterferencePopulation(other,o),'sixgr:abstraction:FiniteSpatialEvidence');
key=sixgr.system.CalibratedLinkPHY.calibrationKey(ctx,o);
curve=struct('CurveID',"control_export_fixture_only",'Key',key,'RVSequence',0, ...
    'SINRAxes_dB',{{[-100;100]}},'BetaLinear',1,'TrialCount',[2000;2000], ...
    'ErrorCount',[2000;2000],'ValidationTrialCount',[2000;2000],'ValidationErrorCount',[2000;2000]);
calibration=struct('Schema',"sixgr.calibrated_sls_link/v1", ...
    'CalibrationID',"control_trace_fixture_not_physical_calibration", ...
    'SourceClassification',"development_fixture_not_physical_calibration",'Curves',curve);
folder=tempname(fullfile(pwd,'logs')); mkdir(folder);
file=fullfile(folder,'trace_fixture_not_calibration.mat'); save(file,'calibration');
cfg.system.linkAbstraction.calibrationFile=file;
cfg.system.linkAbstraction.calibrationSHA256=sixgr.csi.studyFileSHA256(file);
cfg.system.linkAbstraction.allowDevelopmentFixtures=true;
cfg.system.linkAbstraction.spatialProviderClass=class(provider);
cfg.system.linkAbstraction.dlFeedback.enabled=false;
cfg.system.linkAbstraction.spatialFeedback.enabled=false;
phy=sixgr.system.CalibratedLinkPHY(cfg,struct('SpatialGrantProvider',provider),99);
% Reception needs the following committed slot for finite-channel tails.
% Deliver at that current clock; do not rewind the provider to the source
% slot merely because ctx retains the original transmission identity.
phy.setSlotContext(idle); [ack,bler]=phy.decode(ctx);
trace=phy.NetworkSpatialTrace;
assert(~ack && bler==1 && ~phy.CalibrationQualified && height(trace)==1 && ...
    ~trace.WaveformBacked && trace.SourceClassification=="development_fixture_not_study_result");
file=fullfile(folder,'system_network_spatial_evidence.csv');
sixgr.util.csvWriteTable(file,trace,'PreserveSchema',true); persisted=readtable(file);
for channel=["PDCCH","SSB"]
    for suffix=["InterferenceIncluded","EmissionCount"]
        field=channel+suffix;
        assert(ismember(field,string(persisted.Properties.VariableNames)) && ...
            isequal(double(o.(field)),double(trace.(field))) && ...
            isequal(double(trace.(field)),double(persisted.(field))));
    end
end
fprintf('SLS_CONTROL_DATA_CONSUMER_PASS ssb=%d frozen_grant=1 csv_roundtrip=1 fixture_only=1 evidence=%s\n',ssb,folder);
end
function expected=independentWaveform(cfg,e,window,coords,large)
carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30);
first=window.AbsoluteSlots0(1); carrier.NSlot=mod(first,carrier.SlotsPerFrame);
ofdm=nrOFDMInfo(carrier); nsym=numel(window.TTIs)*14;
grid=complex(zeros(288,nsym,2)); source=e.Coordinates0Based;
source(:,2)=source(:,2)+(e.AbsoluteSlot0-first)*14;
values=(e.Symbols.*sqrt(e.TransmitPowerPerRE_W))*e.Precoder.';
for port=1:2
    ix=sub2ind(size(grid),source(:,1)+1,source(:,2)+1,repmat(port,size(source,1),1));
    grid(ix)=values(:,port);
end
wave=nrOFDMModulate(carrier,grid,'Nfft',ofdm.Nfft,'SampleRate',ofdm.SampleRate,'Windowing',0);
native=sixgr.system.abstraction.createNetworkSpatialChannel(cfg,ofdm.SampleRate,"DL");
ch=native.Object; release(ch); ch.ChannelFiltering=false; ch.ChannelResponseOutput='path-gains';
ch.PathGainSampleRate='signal'; ch.RandomStream='mt19937ar with seed';
hash=char(sixgr.util.sha256Hex(uint8(char(string(cfg.run.seed)+"_network_link_1_"+e.ServingCellID))));
ch.Seed=mod(hex2dec(hash(1:8)),2^32-1);
ch.InitialTime=sixgr.phy.frame.slotStartSample(carrier,first,ofdm.SampleRate)/ofdm.SampleRate;
metadata=info(ch); trim=metadata.ChannelFilterDelay;
padding=trim+ceil(max(metadata.PathDelays)*ofdm.SampleRate);
ch.NumTimeSamples=size(wave,1)+padding; [gains,~]=ch();
gains=gains*10^(-large.Pathloss_dB(1,e.ServingCellID)/20); filters=getPathFilters(ch);
rx=sixgr.phy.waveform.applySampledFadingChannel([wave;zeros(padding,2)],filters,gains, ...
    complex(zeros(size(filters,1)-1,2,size(filters,2))));
demod=nrOFDMDemodulate(carrier,rx(trim+(1:size(wave,1)),:), ...
    'Nfft',ofdm.Nfft,'SampleRate',ofdm.SampleRate,'CyclicPrefixFraction',.5);
coords(:,2)=coords(:,2)+(window.ObservationTTI-1-first)*14;
demod=reshape(demod,288*nsym,2);
expected=demod(sub2ind([288 nsym],coords(:,1)+1,coords(:,2)+1),:).';
end
function reject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingRejection','Expected %s',id);
end
