function ok=testSLSCommittedPUCCHInterference()
% Native coded PUCCH -> committed finite propagation. No received-UCI claim.
cfg=sixgr.config.defaultConfig();
for fragment=["calibrated_link_abstraction","finite_srs_interference","native_pucch_interference"]
    cfg=sixgr.util.mergeStruct(cfg,sixgr.lls6g.config.readConfigFile( ...
        fullfile('simulator','configs','system',fragment+".yaml")));
end
cfg.run.seed=113; cfg.run.executionID='committed_pucch_interference';
cfg.phy.carrier=struct('NSizeGrid',24,'NStartGrid',0,'SubcarrierSpacing',30,'NCellID',1);
cfg.phy.duplex.mode='TDD'; cfg.phy.fc_Hz=4e9; cfg.phy.numerology.scs_kHz=30;
cfg.phy.frameStructure.SlotState.CommonDirection=repmat('U',5,14);
cfg.phy.frameStructure.SlotState.ResolvedDirection=repmat("UL",5,14);
cfg.scenario.bs.noiseFigure_dB=7; cfg.scenario.ue.noiseFigure_dB=9;
cfg.channel=struct('model','TDL-A','tdlProfile','TDL-A','delaySpread_s',30e-9, ...
    'doppler_Hz',70,'normalizeChannelOutputs',false,'awgnOnly',false);
cfg.rf=struct(); cfg.phy.impairments=struct(); cfg.phy.srs.enable=false;
cfg.system.linkAbstraction.networkSpatial.bsPorts=2;
cfg.system.linkAbstraction.networkSpatial.uePorts=2;
cfg.system.linkAbstraction.allowDevelopmentFixtures=true;
cfg=sixgr.util.mergeStruct(cfg,sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/validation/sls_pucch_two_port_spatial_vector.yaml'));
f=sixgr.phy.pucch.PUCCHFixtureFactory.connected(2,int8(mod((0:19).',2)), ...
    'NSizeGrid',24,'SCS',30,'RNTI',4661);
data=f.Report.Data; data.ServingCell=2;
report=sixgr.phy.pucch.UCIReport(data);
data=f.UEContext.Data; data.UEID=2; data.ServingCell=2; data.PUCCHCell=2;
ue=sixgr.phy.pucch.PUCCHUEContext(data);
[assignment,report]=sixgr.phy.pucch.PUCCHTransmissionAssignment.fromCombinedUCI(report,ue,f.FrameState);
[assignment,spatial]=sixgr.system.abstraction.bindConfiguredPUCCHSpatialVector(cfg,assignment);
cfg.validation.pucch_resources=struct('DeclaredComponentRRC',f.RRCContext.Data);
b=struct('AbsoluteSlot0',0,'UEIndex',2,'ServingCellID',2,'RNTI',4661, ...
    'Precoder',spatial.Precoder,'SpatialStateDigest',assignment.SpatialRelationState.Digest, ...
    'SourceClassification',"declared_component_fixture_not_study_result");
b.Obligation=struct('ResourceID',"declared_fixture_uci", ...
    'AbsoluteSlot0',0,'UEIndex',2,'RNTI',4661,'CellID',2,'Transport',"PUCCH", ...
    'HARQBits',20,'SRBits',0,'CSIPart1Bits',0,'CSIPart2Bits',0);
e=sixgr.system.abstraction.executePUCCHEmission(f.Carrier,assignment,report,b);
provider=sixgr.system.abstraction.NetworkSpatialGrantProvider(cfg);
off=cfg; off.system.linkAbstraction.networkSpatial.pucchInterferenceEnabled=false;
baseline=sixgr.system.abstraction.NetworkSpatialGrantProvider(off);
large=struct('Pathloss_dB',[80 85;87 81],'TxPower_dBm',30*ones(2));
state=struct('TTI',1,'AbsoluteSlot0',0,'ServingCells',[1 2],'RNTIByUE',[4660 4661], ...
    'GrantsDL',struct([]),'GrantsUL',struct([]),'GrantCellsDL',[],'GrantCellsUL',[], ...
    'LargeScaleState',large);
reject(@()provider.commitSlotPopulation(state),'sixgr:abstraction:PUCCHEmissionPopulation');
state.PUCCHEmissions=e;
% Explicit audit fixture: the native generator/finite response remains real,
% but this standalone test does not claim a production MAC grant source.
state.UCIEmissionObligations=b.Obligation;
state.PUCCHEmissionAudit=table("declared_fixture_uci",0,2,4661,2,"PUCCH",20,0,0,0, ...
    "native_PUCCH_transmitted_modeled_control",true,e.SHA256,"",false, ...
    "modeled_SLS_ideal_delayed_control",true,0, ...
    'VariableNames',{'ObligationID','AbsoluteSlot0','UEIndex','RNTI','CellID','Transport', ...
    'HARQBits','SRBits','CSIPart1Bits','CSIPart2Bits','Disposition','NativeWaveformExecuted', ...
    'EmissionSHA256','ReplacementPUSCHGrantSHA256','PhysicalReceptionQualified','SourceClassification', ...
    'SRPayloadKnown','PositiveSRCount'});
reject(@()baseline.commitSlotPopulation(state),'sixgr:abstraction:PUCCHEmissionPolicy');
bad=state; bad.PUCCHEmissions.Symbols(1)=-bad.PUCCHEmissions.Symbols(1);
reject(@()provider.commitSlotPopulation(bad),'sixgr:abstraction:PUCCHEmissionMutation');
bad=state; bad.GrantsUL=struct('UEIndex',2,'SymbolAllocation',[12 2]); bad.GrantCellsUL=2;
reject(@()provider.commitSlotPopulation(bad),'sixgr:abstraction:PUCCHSimultaneousPowerUnsupported');
bad=state; bad.PUCCHEmissions=struct([]);
reject(@()provider.commitSlotPopulation(bad),'sixgr:abstraction:PUCCHEmissionCoverage');
bad=state; bad.PUCCHEmissionAudit=table();
reject(@()provider.commitSlotPopulation(bad),'sixgr:abstraction:PUCCHEmissionCoverage');
bad=state; bad.PUCCHEmissionAudit.ObligationID="wrong_owner";
reject(@()provider.commitSlotPopulation(bad),'sixgr:abstraction:PUCCHEmissionCoverage');
% Rewriting both audit and ledger must not reassign a retained same-UE TX.
bad=state; bad.PUCCHEmissionAudit.ObligationID="different_same_ue_occasion";
bad.UCIEmissionObligations.ResourceID=bad.PUCCHEmissionAudit.ObligationID;
reject(@()provider.commitSlotPopulation(bad),'sixgr:abstraction:PUCCHEmissionCoverage');
bad=state; bad.PUCCHEmissionAudit.HARQBits=19;
bad.UCIEmissionObligations.HARQBits=19;
reject(@()provider.commitSlotPopulation(bad),'sixgr:abstraction:PUCCHEmissionCoverage');
bad=state; bad.PUCCHEmissionAudit.PhysicalReceptionQualified=true;
reject(@()provider.commitSlotPopulation(bad),'sixgr:abstraction:PUCCHEmissionCoverage');
bad=state; bad.PUCCHEmissions=struct([]);
bad.PUCCHEmissionAudit.NativeWaveformExecuted=false; bad.PUCCHEmissionAudit.EmissionSHA256="";
bad.PUCCHEmissionAudit.Disposition="owned_negative_SR_no_transmission";
reject(@()provider.commitSlotPopulation(bad),'sixgr:abstraction:PUCCHEmissionCoverage');
bad.UCIEmissionObligations.HARQBits=0; bad.UCIEmissionObligations.SRBits=1;
bad.PUCCHEmissionAudit.HARQBits=0; bad.PUCCHEmissionAudit.SRBits=1;
bad.PUCCHEmissionAudit.PositiveSRCount=1;
reject(@()provider.commitSlotPopulation(bad),'sixgr:abstraction:PUCCHEmissionCoverage');
% Only a genuinely owned negative standalone SR may have no waveform.
bad.PUCCHEmissionAudit.PositiveSRCount=0;
sixgr.system.abstraction.validateCommittedPUCCHEmissions(cfg,bad,struct([]));
provider.commitSlotPopulation(state); provider.commitSlotPopulation(state);
baseline.commitSlotPopulation(rmfield(state,{'PUCCHEmissions','UCIEmissionObligations','PUCCHEmissionAudit'}));
state.TTI=2; state.AbsoluteSlot0=1; state.PUCCHEmissions=struct([]);
state.UCIEmissionObligations=struct([]); state.PUCCHEmissionAudit=table();
provider.commitSlotPopulation(state);
baseline.commitSlotPopulation(rmfield(state,{'PUCCHEmissions','UCIEmissionObligations','PUCCHEmissionAudit'}));
coords=[(48:59).' repmat(12,12,1)];
ctx=struct('TTI',1,'Direction',"UL",'UEIndex',1,'ServingCellID',1);
a=provider.evaluateReferenceInterference(ctx,coords);
t=baseline.evaluateReferenceInterference(ctx,coords);
assert(a.PUCCHInterferenceIncluded && isscalar(a.PUCCHEmissionPopulation) && ...
    a.PUCCHEmissionPopulation.SHA256==e.SHA256 && ...
    ~a.WaveformMeasured && ~a.PrimaryStudyAccepted);
expected=independentWaveform(cfg,e,a.ReceiveWindow,coords,large);
relativeError=norm(a.ExplicitPUCCHResponse-expected,'fro')/norm(expected,'fro');
assert(relativeError<2e-10,'test:PUCCHNetworkWaveformMismatch','Native PUCCH response differs by %g.',relativeError);
for k=1:size(coords,1)
    v=expected(:,k); delta=a.ExternalCovariance(:,:,k)-t.ExternalCovariance(:,:,k);
    assert(norm(delta-v*v','fro')<1e-10*max(norm(v*v','fro'),realmin));
end
% A changed producer population must not accept a previous calibration key.
ofdm=nrOFDMInfo(f.Carrier);
native=sixgr.system.abstraction.createNetworkSpatialChannel(cfg,ofdm.SampleRate,"DL");
x=sixgr.system.abstraction.networkChannelCalibrationIdentity(cfg,native.Object);
y=sixgr.system.abstraction.networkChannelCalibrationIdentity(off,native.Object);
assert(x.ProfileID~=y.ProfileID);
fprintf('SLS_COMMITTED_PUCCH_PASS native_symbols=1 independent_waveform_error=%g qualification_claim=0\n',relativeError);
ok=true;
end
function expected=independentWaveform(cfg,e,window,coords,large)
carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30);
first=window.AbsoluteSlots0(1); carrier.NSlot=mod(first,carrier.SlotsPerFrame);
ofdm=nrOFDMInfo(carrier); nsym=numel(window.TTIs)*14;
grid=complex(zeros(288,nsym,2)); source=e.Coordinates0Based;
source(:,2)=source(:,2)+(e.AbsoluteSlot0-first)*14;
values=(e.Symbols.*sqrt(e.TransmitPowerPerRE_W))*e.Precoder.';
for port=1:2
    indices=sub2ind(size(grid),source(:,1)+1,source(:,2)+1,repmat(port,size(source,1),1));
    grid(indices)=values(:,port);
end
wave=nrOFDMModulate(carrier,grid,'Nfft',ofdm.Nfft,'SampleRate',ofdm.SampleRate,'Windowing',0);
native=sixgr.system.abstraction.createNetworkSpatialChannel(cfg,ofdm.SampleRate,"DL");
ch=native.Object; release(ch); ch.ChannelFiltering=false; ch.ChannelResponseOutput='path-gains';
ch.PathGainSampleRate='signal'; ch.RandomStream='mt19937ar with seed';
hash=char(sixgr.util.sha256Hex(uint8(char(string(cfg.run.seed)+"_network_link_"+e.UEIndex+"_1"))));
ch.Seed=mod(hex2dec(hash(1:8)),2^32-1);
ch.InitialTime=sixgr.phy.frame.slotStartSample(carrier,first,ofdm.SampleRate)/ofdm.SampleRate;
swapTransmitAndReceive(ch); metadata=info(ch); trim=metadata.ChannelFilterDelay;
padding=trim+ceil(max(metadata.PathDelays)*ofdm.SampleRate);
ch.NumTimeSamples=size(wave,1)+padding; [gains,~]=ch();
gains=gains*10^(-large.Pathloss_dB(e.UEIndex,1)/20); filters=getPathFilters(ch);
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
