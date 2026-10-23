function ok=testSRSReceiveBranchPlane()
% Native SRS waveform + real retained RF intervals, declared channel/input
% boundary. Tests modeled branch measurement, not a shared SRS/RA campaign.
setup6GRSimToolkit('Verbose',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml');
cfg=sixgr.lls6g.buildInternalConfig(scenario,tempdir);
a=sixgr.rf.AntennaArrayFactory.build(cfg,'bs');
cfg.lls6g.userContext.RuntimeServingBSAntenna=a;
cfg.lls6g.userContext.RuntimeServingBSAntennaMeta=struct('Azimuth_deg',0, ...
    'Heading_deg',NaN,'Tilt_deg',0,'PositionX_m',0,'PositionY_m',0,'PositionZ_m',25);
carrier=sixgr.phy.grid.makeCarrier(cfg); native=nrOFDMInfo(carrier);
fs=double(native.SampleRate); epoch=double(cfg.rf.configurationEpoch); endpoint="gnb_1_rx";
binding=sixgr.rf.resolveReceiveBranchLayout(cfg,endpoint,'UL',64,fs,epoch);
assert(binding.Available&&~binding.Layout.ExecutionVerified);
cloned=cfg;
cloned.lls6g.userContext.RuntimeServingBSAntenna.ArrayObj=clone(a.ArrayObj);
cloneBinding=sixgr.rf.resolveReceiveBranchLayout(cloned,endpoint,'UL',64,fs,epoch);
assert(isequaln(cloneBinding,binding),'Equivalent native array clones preserve the installed branch layout.');
reordered=cfg; other=clone(a.ArrayObj); other.ElementSet=other.ElementSet([2 1]);
assert(isequal(getElementPosition(other),getElementPosition(a.ArrayObj)), ...
    'This negative must change co-located polarization order, not positions.');
reordered.lls6g.userContext.RuntimeServingBSAntenna.ArrayObj=other;
reject(@()sixgr.rf.resolveReceiveBranchLayout(reordered,endpoint,'UL',64,fs,epoch), ...
    'RF:ReceiveBranchInstallation');
% Real production registration retains one numeric layout, not a rebuilt
% array or a full-width waveform. No physical interval has run on this owner.
owner=sixgr.truth.SharedWaveformPhysicalRuntime(fs,0,epoch);
owner.addReceiver(endpoint,cfg,'UL',64,false);
assert(isequaln(owner.receiveBranchLayout(endpoint),binding));
owner.validateReceiverInstallation(endpoint,cfg,'UL',64);
changed=cfg; changed.lls6g.userContext.RuntimeServingBSAntennaMeta.Azimuth_deg=2;
reject(@()owner.validateReceiverInstallation(endpoint,changed,'UL',64),'RF:ReceiveBranchOwnerMismatch');
% Absent legacy geometry is unavailable; explicit bad geometry is an error,
% including when a scenario has not declared an RF reference type.
missing=cfg; missing.lls6g.userContext=rmfield(missing.lls6g.userContext, ...
    {'RuntimeServingBSAntenna','RuntimeServingBSAntennaMeta'});
absent=sixgr.rf.resolveReceiveBranchLayout(missing,endpoint,'UL',64,fs,epoch);
assert(~absent.Available&&absent.Status=="unavailable_no_installed_receive_array"&& ...
    isempty(fieldnames(absent.Layout)));
noReference=cfg; noReference.rf=rmfield(noReference.rf,'bsPowerReference');
untyped=sixgr.rf.resolveReceiveBranchLayout(noReference,endpoint,'UL',64,fs,epoch);
assert(~untyped.Available&&untyped.Status=="validated_geometry_unavailable_explicit_RF_reference"&& ...
    isequaln(untyped.Installation,binding.Installation));
bad=noReference; bad.lls6g.userContext.RuntimeServingBSAntenna.ElementPositions_m(1,1)=100;
reject(@()sixgr.rf.resolveReceiveBranchLayout(bad,endpoint,'UL',64,fs,epoch),'RF:ReceiveBranchInstallation');
bad=cfg; bad.rf.bsPowerReference=rmfield(bad.rf.bsPowerReference,'RFType');
reject(@()sixgr.rf.resolveReceiveBranchLayout(bad,endpoint,'UL',64,fs,epoch),'RF:ReceiveBranchInstallation');

srs=nrSRSConfig('NumSRSPorts',2,'NumSRSSymbols',2,'SymbolStart',12, ...
    'Repetition',2,'KTC',2,'CSRS',0,'BSRS',0,'BHop',0,'SRSPeriod','on');
indices=nrSRSIndices(carrier,srs); symbols=nrSRS(carrier,srs);
grid=nrResourceGrid(carrier,2); grid(indices)=symbols;
H=[linspace(1,.2,64);1i*linspace(.3,.1,64)];
received=reshape(reshape(grid,[],2)*H,size(grid,1),size(grid,2),64);
[wave,info]=nrOFDMModulate(carrier,received,'Windowing',0);
assert(info.SampleRate==fs);
first=10000; stop=first+size(wave,1); split=first+floor(size(wave,1)/2);
stream=sixgr.rf.runtime.RFImpairmentStream(cfg,'rx','UL',fs,64,first,epoch,false);
observation=sixgr.phy.waveform.WaveformObservationBuffer(first,stop,fs,64);
segments=cell(2,1); bounds=[first split stop];
for k=1:2
    chunk=sixgr.phy.waveform.WaveformChunk(wave(bounds(k)-first+1:bounds(k+1)-first,:),bounds(k));
    actual=stream.apply(chunk,epoch);
    rx=actual.Replay;
    rx.WaveformAmplitudeUnit="sqrt_mW";
    rx.ReceiveBranchExecution=sixgr.rf.ReceiveBranchLayout.bindExecution( ...
        binding.Layout,chunk,chunk,actual,stream,endpoint);
    execution=struct('Source','composed_tx_retained_rf_per_link_channel_sum_receiver_noise_rf', ...
        'ApproximationMode','none','StartSample',bounds(k),'EndSampleExclusive',bounds(k+1), ...
        'SampleRateHz',fs,'ConfigurationEpoch',epoch,'RX',struct('ID',endpoint,'Replay',rx));
    segments{k}=struct('StartSample',bounds(k),'EndSampleExclusive',bounds(k+1),'Execution',execution);
    observation.append(chunk,fs);
end
% Public callers cannot opt into the canonical owner's no-rehash route.
% Inspect exact method authority as well as exercising MATLAB access denial;
% no internal RF/argument error is accepted as that denial.
definition=?sixgr.rf.ReceiveBranchLayout;
method=definition.MethodList(string({definition.MethodList.Name})=="bindOriginalOwnerExecution");
assert(isscalar(method)); access=method.Access;
if iscell(access), assert(isscalar(access)); access=access{1}; end
assert(isa(access,'meta.class')&&isscalar(access)&& ...
    string(access.Name)=="sixgr.truth.SharedWaveformPhysicalRuntime");
denied=false;
try
    sixgr.rf.ReceiveBranchLayout.bindOriginalOwnerExecution( ...
        binding.Layout,chunk,chunk,actual,stream,endpoint);
catch cause
    assert(startsWith(string(cause.identifier),"MATLAB:")&& ...
        contains(string(cause.message),"bindOriginalOwnerExecution"), ...
        'Expected MATLAB method-access denial, got %s.',cause.identifier);
    denied=true;
end
assert(denied,'The original-owner route must not be publicly callable.');
replay=struct('ReceiverID',endpoint,'RuntimeChannelStartSample',first,'RuntimeChannelEndSample',stop, ...
    'WaveformAmplitudeUnit','sqrt_mW','ReceiveStreamExecutionSegments',{segments});
plane=struct('ReceiverID',endpoint+":pre_rf",'ObservationID',"declared_native_SRS_real_RF_intervals", ...
    'Observation',observation,'ReceiveBranchLayout',binding);
resource=struct('ResourceID',17,'ConfigHash',"declared_native_SRS_two_port_component", ...
    'Scope',"actual_native_waveform_and_RF_not_shared_channel_capture");
out=measure(plane,replay);
assert(out.SRSAbsolutePowerAvailable&&out.SRSAbsolutePowerReferencePlane== ...
    "modeled_receiver_branch_after_identity_combining_before_RX_front_end", ...
    'test:SRSBranchPlaneUnavailable','%s: %s',out.SRSAbsolutePowerStatus,out.SRSAbsolutePowerErrorIdentifier);
e=jsondecode(out.SRSAbsolutePowerEvidenceJSON);
assert(e.ReceiveBranchBinding.Available&&~e.ReceiveBranchBinding.HardwareConformanceVerified&& ...
    ~e.AccuracyQualified&&numel(e.ReceiveBranchBinding.IntervalReceipts)==2&& ...
    string(e.ReceiveBranchBinding.Layout.LayoutSHA256)==binding.Layout.LayoutSHA256&& ...
    out.SRS_RSRP_dBm==max(out.SRSRSRPPerReceiveAntenna_dBm));
legacy=plane; legacy=rmfield(legacy,'ReceiveBranchLayout'); legacyOut=measure(legacy,replay);
assert(legacyOut.SRSAbsolutePowerAvailable&&legacyOut.SRS_RSRP_dBm==out.SRS_RSRP_dBm&& ...
    legacyOut.SRSAbsolutePowerReferencePlane=="internal_physical_receive_element_before_RX_front_end");
legacy.ReceiveBranchLayout=untyped; noType=measure(legacy,replay);
noTypeEvidence=jsondecode(noType.SRSAbsolutePowerEvidenceJSON);
assert(noType.SRSAbsolutePowerAvailable&&noType.SRS_RSRP_dBm==out.SRS_RSRP_dBm&& ...
    ~noTypeEvidence.ReceiveBranchBinding.Available);
% Even a byte-identical different buffer is not the owner's original plane.
substitute=sixgr.phy.waveform.WaveformObservationBuffer(first,stop,fs,64);
substitute.append(sixgr.phy.waveform.WaveformChunk(wave,first),fs);
assert(substitute.sampleHash()==observation.sampleHash());
badPlane=plane; badPlane.Observation=substitute;
rejected=measure(badPlane,replay);
assert(~rejected.SRSAbsolutePowerAvailable&& ...
    rejected.SRSAbsolutePowerErrorIdentifier=="sixgr:srs:AntennaPowerPlane");
badPlane=plane; badPlane.ReceiverID=endpoint+":post_rf";
rejected=measure(badPlane,replay);
assert(~rejected.SRSAbsolutePowerAvailable&& ...
    rejected.SRSAbsolutePowerErrorIdentifier=="sixgr:srs:AntennaPowerPlane");
item=struct('Context',struct(),'Planes',struct( ...
    'ReceiverID',endpoint+":pre_rf",'Observation',observation));
input=struct('Replay',replay,'PhysicalMeasurementObservation',substitute);
reject(@()sixgr.truth.receiveSharedSRSMeasurement(struct(),item,input), ...
    'sixgr:truth:SRSAntennaPlaneIdentity');
item.Planes.ReceiverID="gnb_2_rx:pre_rf";
input.PhysicalMeasurementObservation=observation;
reject(@()sixgr.truth.receiveSharedSRSMeasurement(struct(),item,input), ...
    'sixgr:truth:SRSAntennaPlaneIdentity');
bad=replay; bad.ReceiveStreamExecutionSegments{1}.Execution.RX.Replay= ...
    rmfield(bad.ReceiveStreamExecutionSegments{1}.Execution.RX.Replay,'ReceiveBranchExecution');
unavailable(plane,bad);
bad=replay; bad.ReceiveStreamExecutionSegments{1}.Execution.RX.Replay.ReceiveBranchExecution.LayoutSHA256="poison";
unavailable(plane,bad);
bad=replay; bad.ReceiveStreamExecutionSegments{1}.Execution.RX.Replay.RFInputWaveformSHA256="poison";
unavailable(plane,bad);
badPlane=plane;
badPlane.ReceiveBranchLayout=sixgr.rf.resolveReceiveBranchLayout(cfg,"gnb_2_rx",'UL',64,fs,epoch);
unavailable(badPlane,replay);
badPlane=plane;
badPlane.ReceiveBranchLayout=sixgr.rf.resolveReceiveBranchLayout(cfg,endpoint,'UL',64,fs,epoch+1);
unavailable(badPlane,replay);
bad=replay; bad.ReceiveStreamExecutionSegments{2}.StartSample=split+1;
rejected=measure(plane,bad);
assert(~rejected.SRSAbsolutePowerAvailable&&rejected.SRSAbsolutePowerErrorIdentifier=="sixgr:srs:AntennaPowerCoverage");
fprintf('SRS_RECEIVE_BRANCH_PLANE_PASS actual_RF_intervals=2 modeled_branches=64 shared_channel=0 hardware_qualification=0\n');
ok=true;

    function result=measure(p,r)
        result=sixgr.phy.srs.measureSRSAntennaPower(carrier,srs,observation,r,[0 0],resource,p);
    end
    function unavailable(p,r)
        result=measure(p,r);
        assert(~result.SRSAbsolutePowerAvailable&&isnan(result.SRS_RSRP_dBm)&& ...
            result.SRSAbsolutePowerErrorIdentifier=="RF:ReceiveBranchObservation", ...
            'Expected branch integrity rejection; got %s.',result.SRSAbsolutePowerErrorIdentifier);
    end
end

function reject(fn,id)
try, fn(); catch cause, assert(strcmp(cause.identifier,id),'Expected %s got %s',id,cause.identifier); return; end
error('test:SRSBranchExpectedError','Expected %s.',id);
end
