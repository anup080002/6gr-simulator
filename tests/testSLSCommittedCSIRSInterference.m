function ok=testSLSCommittedCSIRSInterference()
% Native per-cell CSI-RS, committed beam/power identities and finite DL
% reference interference. Independent OFDM/FIR demodulation is the oracle;
% no BLER fixture, reservation, or analytical SINR acts as a waveform result.
cfg=sixgr.config.defaultConfig();
cfg=sixgr.util.mergeStruct(cfg,sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/system/calibrated_link_abstraction.yaml'));
cfg=sixgr.util.mergeStruct(cfg,sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/system/finite_srs_csirs_interference.yaml'));
cfg.run.seed=113; cfg.run.executionID='committed_csirs_interference';
cfg.phy.carrier=struct('NSizeGrid',24,'NStartGrid',0,'SubcarrierSpacing',30,'NCellID',1);
cfg.phy.duplex.mode='TDD'; cfg.phy.fc_Hz=4e9; cfg.phy.numerology.scs_kHz=30;
cfg.phy.srs.enable=false;
cfg.phy.csirs=struct('enable',true,'nPorts',2,'period_slots',5,'offset_slots',0, ...
    'numResources',2,'resourceIDs',[7 19],'rowNumbers',[3 3], ...
    'symbolLocationsByResource',[13 13],'subcarrierLocationsByResource',[0 4], ...
    'rbOffsetsByResource',[0 0],'numRBsByResource',[24 24], ...
    'precoderMatrices',cat(3,eye(2),[1 1i;1i 1]/sqrt(2)));
cfg.phy.mimo.strict=true;
cfg.phy.frameStructure.SlotState.CommonDirection=repmat('D',5,14);
cfg.phy.frameStructure.SlotState.ResolvedDirection=repmat("DL",5,14);
cfg.scenario.bs.noiseFigure_dB=7; cfg.scenario.ue.noiseFigure_dB=9;
cfg.channel=struct('model','TDL-A','tdlProfile','TDL-A','delaySpread_s',30e-9, ...
    'doppler_Hz',70,'normalizeChannelOutputs',false,'awgnOnly',false);
cfg.rf=struct(); cfg.phy.impairments=struct();
cfg.system.linkAbstraction.networkSpatial.bsPorts=2;
cfg.system.linkAbstraction.networkSpatial.uePorts=2;
cfg.system.linkAbstraction.networkSpatial.dlAntennaBasis='configured_csirs_elements';
cfg.system.linkAbstraction.networkSpatial.csirsScramblingIDs=[11 37];
cfg.system.linkAbstraction.dlFeedback.panel.Ports=2;
cfg.phy.csi.reportConfiguration.NumCSIResources=2;
large=struct('Pathloss_dB',[80 85;87 81],'TxPower_dBm',[30 27;30 27]);
state=struct('TTI',1,'AbsoluteSlot0',0,'ServingCells',[1 2],'RNTIByUE',[4660 4661], ...
    'GrantsDL',struct([]),'GrantsUL',struct([]),'GrantCellsDL',[],'GrantCellsUL',[], ...
    'LargeScaleState',large);
provider=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
old=cfg; old.system.linkAbstraction.networkSpatial.interferencePopulation='scheduled_shared_data_grants_only';
baseline=sixgr.system.abstraction.NetworkSpatialGrantProvider(old);
bad=cfg; bad.system.linkAbstraction.networkSpatial.dlAntennaBasis='direct_ports';
reject(@()sixgr.system.abstraction.NetworkSpatialGrantProvider(bad), ...
    'sixgr:abstraction:CSIRSEmissionBasis');
provider.commitSlotPopulation(state); baseline.commitSlotPopulation(state);
emissions=provider.committedCSIRSEmissions(1);
assert(numel(emissions)==4 && isequal([emissions.CRI],[0 1 0 1]));
for e=emissions
    actual=(e.Symbols.*sqrt(e.TransmitPowerPerRE_W))*e.Precoder.';
    assert(max(abs(sum(abs(actual).^2,2)-e.AggregateAntennaEPRE_W))<1e-14);
    assert(abs(e.AggregateAntennaEPRE_W-e.ConfiguredTotalPower_W/288)<1e-14);
    assert(ismember(e.ResourceID,[7 19]) && e.AbsoluteSlot0==0);
end
% A cell-common signal is emitted once, not once per attached UE.
more=state; more.ServingCells=[1 1 2]; more.RNTIByUE=[4660 4662 4661];
more.LargeScaleState.TxPower_dBm=repmat(large.TxPower_dBm(1,:),3,1);
assert(isequaln(emissions,sixgr.system.abstraction.buildScheduledCSIRSEmissions(cfg,more)));
% The same native producer must preserve the configured 64-TXRU/eight-beam
% basis. This checks source mapping/power, not full-band array qualification.
wide=cfg; wide.system.linkAbstraction.networkSpatial.bsPorts=64;
wide.phy.csirs.numResources=8; wide.phy.csirs.resourceIDs=100+(0:7);
wide.phy.csirs.rowNumbers=3*ones(1,8);
wide.phy.csirs.symbolLocationsByResource=[10 10 10 10 12 12 12 12];
wide.phy.csirs.subcarrierLocationsByResource=[0 2 4 6 0 2 4 6];
wide.phy.csirs.rbOffsetsByResource=zeros(1,8);
wide.phy.csirs.numRBsByResource=24*ones(1,8);
wide.phy.csirs.precoderMatrices=complex(zeros(64,2,8));
F=fft(eye(64))/sqrt(64);
for r=1:8, wide.phy.csirs.precoderMatrices(:,:,r)=F(:,2*r-1:2*r); end
wideEmissions=sixgr.system.abstraction.buildScheduledCSIRSEmissions(wide,state);
assert(numel(wideEmissions)==16);
for e=wideEmissions
    actual=(e.Symbols.*sqrt(e.TransmitPowerPerRE_W))*e.Precoder.';
    assert(size(actual,2)==64 && max(abs(sum(abs(actual).^2,2)-e.AggregateAntennaEPRE_W))<1e-14);
    assert(all(sum(abs(actual).^2,1)>0),'Every configured TXRU must contribute native samples.');
end
provider.commitSlotPopulation(state); % identical commit is idempotent
bad=state; bad.LargeScaleState.TxPower_dBm(:,1)=31;
reject(@()provider.commitSlotPopulation(bad),'sixgr:abstraction:SlotHistoryMutation');
off=cfg; off.phy.csirs.enable=false;
assert(isempty(sixgr.system.abstraction.buildScheduledCSIRSEmissions(off,state)));
offSlot=state; offSlot.TTI=2; offSlot.AbsoluteSlot0=1;
assert(isempty(sixgr.system.abstraction.buildScheduledCSIRSEmissions(cfg,offSlot)));
bad=cfg; bad.system.linkAbstraction.networkSpatial.csirsScramblingIDs=[11 1024];
reject(@()sixgr.system.abstraction.buildScheduledCSIRSEmissions(bad,state), ...
    'sixgr:abstraction:CSIRSEmissionIdentity');
bad=state; bad.LargeScaleState.TxPower_dBm(2,1)=28;
reject(@()sixgr.system.abstraction.buildScheduledCSIRSEmissions(cfg,bad), ...
    'sixgr:abstraction:CSIRSEmissionPower');
% Verify actual native symbols and beam mapping separately from the emitter.
carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30,'NCellID',1);
for e=emissions
    rs=nrCSIRSConfig('RowNumber',3,'SymbolLocations',13, ...
        'SubcarrierLocations',4*e.CRI,'NumRB',24,'RBOffset',0, ...
        'CSIRSPeriod',[5 0],'NID',e.ScramblingID,'Density','one');
    assert(string(rs.CDMType)=="FD-CDM2", ...
        'Native CSI-RS row 3 must derive FD-CDM2; it is not a writable override.');
    native=nrResourceGrid(carrier,2); native(nrCSIRSIndices(carrier,rs))=nrCSIRS(carrier,rs);
    flat=reshape(native,[],2)*cfg.phy.csirs.precoderMatrices(:,:,e.CRI+1).';
    idx=sub2ind([288 14],e.Coordinates0Based(:,1)+1,e.Coordinates0Based(:,2)+1);
    assert(norm(e.Symbols*e.Precoder.'-flat(idx,:),'fro')<1e-12);
end
% The receive support is evaluated from the committed sample clock.
provider.commitSlotPopulation(offSlot); baseline.commitSlotPopulation(offSlot);
ctx=struct('TTI',1,'Direction',"DL",'UEIndex',1,'ServingCellID',1,'CRI',0);
coords=emissions(1).Coordinates0Based;
a=provider.evaluateReferenceInterference(ctx,coords);
b=baseline.evaluateReferenceInterference(ctx,coords);
assert(a.CSIRSInterferenceIncluded && ~a.WaveformMeasured && ~a.PrimaryStudyAccepted);
assert(numel(a.CSIRSEmissionPopulation)==3 && ...
    ~any([a.CSIRSEmissionPopulation.ServingCellID]==1 & [a.CSIRSEmissionPopulation.CRI]==0));
assert(any([a.CSIRSEmissionPopulation.ServingCellID]==1 & [a.CSIRSEmissionPopulation.CRI]==1), ...
    'Do not discard interference from all serving-cell beam resources.');
expected=complex(zeros(size(a.ExplicitCSIRSResponse)));
for e=emissions(2:end)
    expected=expected+independentWaveform(cfg,e,a.ReceiveWindow,coords,large);
end
relativeError=norm(expected-a.ExplicitCSIRSResponse,'fro')/norm(expected,'fro');
assert(relativeError<2e-10,'test:CSIRSNetworkWaveformMismatch', ...
    'Native aggregate CSI-RS waveform differs by %g.',relativeError);
for k=1:size(coords,1)
    v=expected(:,k); delta=a.ExternalCovariance(:,:,k)-b.ExternalCovariance(:,:,k);
    assert(norm(delta-v*v','fro')<1e-10*max(norm(v*v','fro'),realmin));
end
reject(@()provider.evaluateReferenceInterference(rmfield(ctx,'CRI'),coords), ...
    'sixgr:abstraction:CSIRSReferenceIdentity');
wrong=ctx; wrong.CRI=7;
reject(@()provider.evaluateReferenceInterference(wrong,coords), ...
    'sixgr:abstraction:CSIRSReferenceIdentity');
wrong=ctx; wrong.Direction="UL";
reject(@()provider.evaluateReferenceInterference(wrong,coords), ...
    'sixgr:abstraction:CrossLinkUnsupported');
ofdm=nrOFDMInfo(carrier);
native=sixgr.system.abstraction.createNetworkSpatialChannel(cfg,ofdm.SampleRate,"DL");
newID=sixgr.system.abstraction.networkChannelCalibrationIdentity(cfg,native.Object);
oldID=sixgr.system.abstraction.networkChannelCalibrationIdentity(old,native.Object);
assert(newID.ProfileID~=oldID.ProfileID,'Changed interference cannot borrow the old BLER calibration identity.');
dataIntegration(cfg,large,false);
longDelay=cfg; longDelay.channel.delaySpread_s=1e-6;
dataIntegration(longDelay,large,true);
folder=tempname(fullfile(pwd,'logs')); mkdir(folder);
save(fullfile(folder,'csirs_network_interference.mat'),'cfg','emissions','a','b','expected','relativeError');
fprintf('SLS_COMMITTED_CSIRS_PASS cells=2 resources=2 emissions=4 independent_waveform_error=%g evidence=%s\n',relativeError,folder);
ok=true;
end
function dataIntegration(cfg,large,expectLeakage)
% A real frozen PDSCH consumes only the part of the prior CSI-RS waveform
% that reaches its FFT windows. Short-delay CP-contained propagation must
% not manufacture interference; the long-delay case must include the tail.
cfg.run.pdschExecutionProfile='phy_calibration'; cfg.run.puschExecutionProfile='phy_calibration';
cfg.phy.nTxAnt=2; cfg.phy.nRxAnt=2; cfg.channel.nTxAnt=2; cfg.channel.nRxAnt=2;
cfg.scenario.bs.nTxAnt=2; cfg.scenario.ue.nRxAnt=2;
cfg.antenna.bs.numElements=2; cfg.antenna.bs.numRFChains=2;
cfg.antenna.ue.numElements=2; cfg.antenna.ue.numRFChains=2;
cfg.phy.beamManagement.hybridBeamformingEnabled=false;
cfg.phy.ssb.enable=false; cfg.phy.trs.enable=false;
cfg.phy.csiim.enable=false; cfg.phy.ptrs.enable=false;
mcs=sixgr.link.resolveMCSProfile('qam64_table1',1);
cfg.phy.pdsch.numLayers=2; cfg.phy.pdsch.nLayers=2;
cfg.phy.pdsch.numPorts=2; cfg.phy.pdsch.nPorts=2;
cfg.phy.pdsch.modulation='QPSK'; cfg.phy.pdsch.codeRate=mcs.TargetCodeRate;
cfg.phy.pdsch.mcsTable='qam64_table1'; cfg.phy.pdsch.mcsIndex=1;
cfg.phy.pdsch.dmrs.portSet=0:1; cfg.phy.pdsch.enablePTRS=false;
cfg.phy.pdsch.mappingType='B'; cfg.phy.pdsch.dmrs.numCDMGroupsWithoutData=1;
cfg.phy.pdsch.xOverhead=0;
g=struct('Direction','DL','Frame',0,'Slot',1,'ScheduledAbsoluteSlot',1, ...
    'RNTI',4660,'UEIndex',1,'ServingCell',1,'PRBSet',0,'SymbolAllocation',[0 2], ...
    'Modulation','QPSK','NumLayers',2,'Layers',2,'NumLogicalPorts',2,'NumRFChains',2, ...
    'TargetCodeRate',mcs.TargetCodeRate,'MCSIndex',1,'MCSTable','qam64_table1', ...
    'PrecodingMatrixLogicalPorts',eye(2)/sqrt(2),'PrecodingMatrix',eye(2)/sqrt(2), ...
    'PrecoderNormalizationConvention','unit_frobenius','PrecoderSource','numerical_contract_fixture');
g.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,"DL",g,'Frame',0,'Slot',1);
[~,carrier,pdsch]=sixgr.system.abstraction.scheduledDataREMap(cfg,g,1);
[~,resourceInfo]=nrPDSCHIndices(carrier,pdsch);
g=rmfield(g,'PHYGrant');
g.NREPerPRB=resourceInfo.NREPerPRB;
g.TBSBits=nrTBS(g.Modulation,g.NumLayers,numel(g.PRBSet),g.NREPerPRB,g.TargetCodeRate,0);
g.HARQ=struct('HarqID',0,'RV',0);
g.PHYGrant=sixgr.phy.grant.freezePHYGrant(cfg,"DL",g,'Frame',0,'Slot',1);
provider=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
old=cfg; old.system.linkAbstraction.networkSpatial.interferencePopulation='scheduled_shared_data_grants_only';
baseline=sixgr.system.abstraction.NetworkSpatialGrantProvider(old);
state=struct('TTI',1,'AbsoluteSlot0',0,'ServingCells',[1 2],'RNTIByUE',[4660 4661], ...
    'GrantsDL',struct([]),'GrantsUL',struct([]),'GrantCellsDL',[],'GrantCellsUL',[], ...
    'LargeScaleState',large);
provider.commitSlotPopulation(state); baseline.commitSlotPopulation(state);
state.TTI=2; state.AbsoluteSlot0=1; state.GrantsDL=g; state.GrantCellsDL=1;
provider.commitSlotPopulation(state); baseline.commitSlotPopulation(state);
ctx=struct('TTI',2,'Direction',"DL",'Grant',g,'ServingCellID',1);
a=provider.evaluate(ctx,state); b=baseline.evaluate(ctx,state);
expectedCount=4*double(expectLeakage);
assert(a.CSIRSInterferenceIncluded && a.CSIRSEmissionCount==expectedCount && ...
    a.ChannelProfileID~=b.ChannelProfileID && ~a.ReferenceSignalInterferenceQualified, ...
    'Expected %d overlapping CSI-RS emitters; observed %d at delay spread %g s.', ...
    expectedCount,a.CSIRSEmissionCount,cfg.channel.delaySpread_s);
expected=complex(zeros(size(a.FiniteWindow.ExplicitCSIRSResponse)));
oracleWindow=a.FiniteWindow.ReceiveWindow;
% Independently replay the previous slot even when the production receive
% support correctly excludes it, so the zero-leakage check is not circular.
oracleWindow.AbsoluteSlots0=0:1; oracleWindow.TTIs=1:2;
for e=provider.committedCSIRSEmissions(1)
    expected=expected+independentWaveform(cfg,e,oracleWindow,a.Coordinates0Based,large);
end
if expectLeakage
    assert(norm(expected,'fro')>0,'The long-delay case must exercise nonzero previous-slot CSI-RS leakage.');
    relativeError=norm(a.FiniteWindow.ExplicitCSIRSResponse-expected,'fro')/norm(expected,'fro');
    assert(relativeError<2e-10);
    assert(norm(a.ExternalCovariance(:)-b.ExternalCovariance(:))>0);
    assert(any(a.FiniteWindow.SpatialResult.SINRLinear<b.FiniteWindow.SpatialResult.SINRLinear,'all'));
else
    assert(norm(expected,'fro')==0 && norm(a.FiniteWindow.ExplicitCSIRSResponse,'fro')==0, ...
        'The independent CP-contained waveform must contribute zero previous-slot leakage.');
    assert(isequal(a.ExternalCovariance,b.ExternalCovariance));
    relativeError=0; % Exact equality of two independently calculated zero responses.
end
verifyPrimaryTrace(cfg,provider,state,ctx,a);
fprintf('SLS_CSIRS_DATA_INTERFERENCE_PASS native_frozen_PDSCH=1 overlapping_emitters=%d delay_s=%g waveform_error=%g\n', ...
    expectedCount,cfg.channel.delaySpread_s,relativeError);
end
function verifyPrimaryTrace(cfg,provider,state,ctx,observation)
% Exercise the actual calibrated PHY trace/export handoff. This deliberately
% unqualified numerical BLER fixture tests wiring only; the native pilot
% propagation above supplies the interference evidence, not this curve.
ctx.TransportBlockIdentity="csirs_export_numerical_fixture_only";
ctx.IsRetransmission=false;
ctx.TBSBits=ctx.Grant.PHYGrant.CodingLayout.TBSBits;
ctx.NumLayers=ctx.Grant.NumLayers;
ctx.TargetCodeRate=ctx.Grant.TargetCodeRate;
ctx.SCS_kHz=cfg.phy.carrier.SubcarrierSpacing;
ctx.ChannelModel=string(cfg.channel.model);
key=sixgr.system.CalibratedLinkPHY.calibrationKey(ctx,observation);
curve=struct('CurveID',"csirs_export_numerical_fixture_only",'Key',key,'RVSequence',0, ...
    'SINRAxes_dB',{{[-100;100]}},'BetaLinear',1,'TrialCount',[2000;2000], ...
    'ErrorCount',[2000;2000],'ValidationTrialCount',[2000;2000], ...
    'ValidationErrorCount',[2000;2000]);
calibration=struct('Schema',"sixgr.calibrated_sls_link/v1", ...
    'CalibrationID',"csirs_trace_fixture_not_physical_calibration", ...
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
phy.setSlotContext(state); [ack,bler]=phy.decode(ctx);
trace=phy.NetworkSpatialTrace;
assert(~ack && bler==1 && ~phy.CalibrationQualified && height(trace)==1 && ...
    ~trace.WaveformBacked && trace.SourceClassification=="development_fixture_not_study_result");
assert(trace.CSIRSInterferenceIncluded && trace.CSIRSEmissionCount==observation.CSIRSEmissionCount && ...
    ~trace.ReferenceSignalInterferenceQualified, ...
    'Computed CSI-RS emissions must reach the primary trace without claiming qualification.');
file=fullfile(folder,'system_network_spatial_evidence.csv');
sixgr.util.csvWriteTable(file,trace,'PreserveSchema',true);
persisted=readtable(file);
for name=["CSIRSInterferenceIncluded","CSIRSEmissionCount","ReferenceSignalInterferenceQualified"]
    assert(ismember(name,string(persisted.Properties.VariableNames)) && ...
        isequal(double(trace.(name)),double(persisted.(name))));
end
fprintf('SLS_CSIRS_PRIMARY_TRACE_PASS actual_provider=1 csv_roundtrip=1 calibration_fixture_only=1 evidence=%s\n',folder);
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
error('test:MissingRejection','Expected %s.',id);
end
