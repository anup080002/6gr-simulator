function ok=testCSIRSPortReferenceInputs()
% Native CSI-only TX preparation, 24 carrier PRBs/four waveform columns.
% No RF/channel/receiver, received-control, installed-array or RSRP accuracy
% qualification. Mathematical reference IFFTs are not extra transmissions.
setup6GRSimToolkit('Verbose',false);
before=rng; restore=onCleanup(@()rng(before)); %#ok<NASGU>
names=["native_single_port","multi_resource_multiport","absolute_scale_once", ...
    "extended_cp_nonzero_origin","original_operand_negatives","operator_and_stage_negatives"];
checks={@singlePort,@multiport,@absoluteScale,@extendedCP,@operandNegatives,@operatorNegatives};
passed=false(size(checks)); failures=strings(size(checks));
for k=1:numel(checks)
    try
        checks{k}(); passed(k)=true;
        fprintf('CSI_PORT_REFERENCE_INPUTS %s PASS\n',names(k));
    catch cause
        failures(k)=string(cause.identifier)+": "+string(cause.message);
        fprintf('CSI_PORT_REFERENCE_INPUTS %s FAIL %s\n',names(k),failures(k));
    end
end
assert(all(passed),'test:CSIRSPortReferenceInputs', ...
    '%d/%d groups passed: %s',nnz(passed),numel(passed),strjoin(failures(~passed),' | '));
fprintf('CSI_PORT_REFERENCE_INPUTS_PASS groups=%d native_TX_only=1 received_power_qualified=0\n',numel(checks));
ok=true;
end

function singlePort()
p=prepare(1,1,"normalized_complex_baseband",15,"normal",2,0);
r=verify(p);
assert(numel(r.Components)==1&&r.Components.ReferencePortNumber==3000 && ...
    r.Evidence.AmplitudeScale==1&&r.Evidence.WaveformColumnCount==4);
% A logical port is spread across ALL four physical waveform columns, not
% treated as the matching ordinal of a channel's TX dimension.
assert(all(abs(r.Components.WaveformColumnWeights)>0));
end

function multiport()
for ports=[2 4]
    p=prepare(ports,2,"normalized_complex_baseband",30,"normal",4,4);
    r=verify(p);
    assert(numel(r.Components)==2*ports&&r.Evidence.ResourceCount==2);
    assert(isequal([r.Components.LogicalPortIndex0],repmat(0:ports-1,1,2)) && ...
        isequal([r.Components.ResourceID],[repmat(17,1,ports) repmat(29,1,ports)]));
    % Independent native demodulation of the reconstructed physical input
    % checks mapped REs, not the helper's closure scalar alone.
    samples=expand(r);
    decoded=nrOFDMDemodulate(p.Carrier,samples,'Nfft',p.Tx.OFDMInfo.Nfft, ...
        'SampleRate',p.SampleRateHz,'CyclicPrefixFraction',0.5);
    assert(norm(decoded(:)-p.Tx.Grid(:))/norm(p.Tx.Grid(:))<1e-11);
end
end

function absoluteScale()
p=prepare(2,1,"sqrt_mW",30,"normal",3,0);
r=verify(p);
assert(r.Evidence.WaveformAmplitudeUnit=="sqrt_mW" && ...
    p.PowerContext.AmplitudeScale~=1 && ...
    r.Evidence.AmplitudeScale==p.PowerContext.AmplitudeScale);
% Compare against original emitted input, not a recreated power policy.
input=expand(r); source=p.TransmitSamples;
assert(norm(input(:)-source(:))/norm(source(:))<1e-11);
assert(abs(sum(abs(input(:)).^2)/sum(abs(p.Tx.Waveform(:)).^2)- ...
    p.PowerContext.AmplitudeScale^2)<1e-10*p.PowerContext.AmplitudeScale^2);
end

function extendedCP()
p=prepare(4,1,"normalized_complex_baseband",60,"extended",7,4);
r=verify(p);
assert(p.Carrier.NSlot==6&&p.Carrier.SymbolsPerSlot==12 && ...
    r.Evidence.OriginalOperator.Carrier.NStartGrid==4 && ...
    r.Evidence.AbsoluteSlotIndex0==6);
end

function operandNegatives()
p=prepare(2,2,"normalized_complex_baseband",30,"normal",4,0);
id='sixgr:refsig:InvalidCSIRSPortReferenceInputs';
map='sixgr:refsig:CSIRSPortReferenceMappingMismatch';
closure='sixgr:refsig:CSIRSPortReferenceClosure';
baseline=sixgr.phy.refsig.buildCSIRSPortReferenceInputs(p);
b=p; b.ReceiverConfig.phy.csirs.precoderMatrices=999;
b.ReceiverConfig.phy.carrier.NSizeGrid=99;
assert(isequaln(sixgr.phy.refsig.buildCSIRSPortReferenceInputs(b),baseline), ...
    'Current configuration must not reconstruct or replace original prepared operands.');
b=p; b.Tx.OFDMInfo.GridSHA256="changed"; reject(b,id);
b=p; b.Tx.CSIRSInfo=rmfield(b.Tx.CSIRSInfo,'Resources'); reject(b,map);
b=p; b.ReferenceIdentity.ResourceIDs="invented"; reject(b,map);
b=p; b.TransmitSamples(1,1)=b.TransmitSamples(1,1)+1; reject(b,id);
b=p; b.PowerContext.AmplitudeScale=2; b.Tx.PowerContext=b.PowerContext; reject(b,id);
b=p; b.Tx.CSIRSInfo.Resources(1).Symbols(1)=2*b.Tx.CSIRSInfo.Resources(1).Symbols(1);
b.Tx.CSIRSSymbols=vertcat(b.Tx.CSIRSInfo.Resources.Symbols); reject(b,map);
b=p; b.Tx.CSIRSInfo.Resources(1).Indices(2)=b.Tx.CSIRSInfo.Resources(1).Indices(1);
b.Tx.CSIRSIndices=vertcat(b.Tx.CSIRSInfo.Resources.Indices); reject(b,map);
b=p; b.Tx.CSIRSRuntimeEvent.ResourceEvents(1).WaveformPrecoderMatrix(1,1)=2;
b.TxInfo.CSIRSRuntimeEvent=b.Tx.CSIRSRuntimeEvent; reject(b,map);
% Resealing the altered map does not bypass its original mapped-event join.
b.Tx.CSIRSRuntimeEvent.ResourceEvents(1).WaveformPrecoderDigest= ...
    sixgr.phy.mimo.MatrixContract.digest(b.Tx.CSIRSRuntimeEvent.ResourceEvents(1).WaveformPrecoderMatrix);
b.TxInfo.CSIRSRuntimeEvent=b.Tx.CSIRSRuntimeEvent; reject(b,map);
b=p; b.Tx.CSIRSRuntimeEvent.ResourceEvents(1).ResourceID=99;
b.TxInfo.CSIRSRuntimeEvent=b.Tx.CSIRSRuntimeEvent; reject(b,map);
b=p; b.Tx.CSIRSRuntimeEvent.WaveformSymbols(1)=0;
b.TxInfo.CSIRSRuntimeEvent=b.Tx.CSIRSRuntimeEvent; reject(b,map);
% Retained event/grid hashes cannot authorize an altered aggregate waveform.
% Reseal its hash and exact scale relation to reach the independent closure.
b=p; b.Tx.Waveform(1,1)=b.Tx.Waveform(1,1)+0.01;
b.TransmitSamples=b.Tx.Waveform.*cast(b.PowerContext.AmplitudeScale,'like',b.Tx.Waveform);
b.Tx.OFDMInfo.WaveformSHA256=sixgr.phy.waveform.WaveformHash.numeric(b.Tx.Waveform);
b.TxInfo.OFDM=b.Tx.OFDMInfo; reject(b,closure);
% No non-CSI signal may be hidden in the original component's physical grid.
b=p; b.Tx.Grid(1,1,1)=1;
b.Tx.OFDMInfo.GridSHA256=sixgr.phy.waveform.WaveformHash.numeric(b.Tx.Grid);
b.ReferenceIdentity.PhysicalGridDigest=sixgr.phy.mimo.MatrixContract.digest(b.Tx.Grid);
b.TxInfo.PortGrid=b.Tx.Grid; b.TxInfo.OFDM=b.Tx.OFDMInfo; reject(b,closure);
end

function operatorNegatives()
p=prepare(2,1,"normalized_complex_baseband",30,"normal",3,0);
id='sixgr:refsig:InvalidCSIRSPortReferenceInputs';
op='sixgr:refsig:UnsupportedCSIRSPortReferenceOperator';
b=p; b.RFExecutionDeferred=false; reject(b,id);
b=p; b.ChannelExecutionDeferred=false; reject(b,id);
b=p; b.PowerContext.PAApplied=true; b.Tx.PowerContext=b.PowerContext; reject(b,id);
b=p; b.PowerContext.PAEnabled=true; b.PowerContext.PAExecutionDeferred=false;
b.Tx.PowerContext=b.PowerContext; reject(b,id);
b=p; b.PowerContext.WaveformAmplitudeUnit="watts"; b.Tx.PowerContext=b.PowerContext; reject(b,id);
b=p; b.Tx.OFDMInfo.EngineUsed="canonical_unitary_math"; reject(b,op);
b=p; b.Tx.OFDMInfo.SampleRate=1.1*b.Tx.OFDMInfo.SampleRate; reject(b,op);
b=p; b.Tx.OFDMInfo.Windowing=2; reject(b,op);
b=p; b.Tx.OFDMInfo.CyclicPrefixLengths(1)=b.Tx.OFDMInfo.CyclicPrefixLengths(1)+1; reject(b,op);
b=p; b.Tx.OFDMInfo.SymbolPhases(1)=0.3; b.TxInfo.OFDM=b.Tx.OFDMInfo; reject(b,op);
b=p; b.Timeline.CarrierSlotIndex0=b.Timeline.CarrierSlotIndex0+1; reject(b,id);
% Coordinated absolute relabeling cannot move unchanged native samples to
% another frame merely by updating all absolute-clock aliases together.
b=p; shift=double(p.Carrier.SlotsPerFrame);
b.RuntimeSlot=b.RuntimeSlot+shift;
b.Timeline.AbsoluteSlotIndexOneBased=b.Timeline.AbsoluteSlotIndexOneBased+shift;
b.Timeline.AbsoluteSlotIndex0=b.Timeline.AbsoluteSlotIndex0+shift;
b.ReferenceIdentity.AbsoluteSlotIndex0=b.ReferenceIdentity.AbsoluteSlotIndex0+shift;
reject(b,id);
% An enabled but deferred PA remains valid: the reference is BEFORE that
% nonlinear operation, never a claim that the PA was disabled in execution.
cfg=config(2,1,"normalized_complex_baseband",30,"normal",0);
cfg.rf.pa.enable=true;
cfg.rf.frontend.pa.reference_domain="normalized_complex_baseband_full_scale";
deferred=sixgr.link.prepareCSIRSTransmission(cfg,20,'RuntimeSlot',3,'Frame',1);
assert(deferred.PowerContext.PAEnabled&&deferred.PAExecutionDeferred&&~deferred.PowerContext.PAApplied);
verify(deferred);
end

function r=verify(p)
before=rng;
hashes=[sixgr.phy.waveform.WaveformHash.numeric(p.Tx.Grid), ...
    sixgr.phy.waveform.WaveformHash.numeric(p.Tx.Waveform), ...
    sixgr.phy.waveform.WaveformHash.numeric(p.TransmitSamples)];
original=p;
r=sixgr.phy.refsig.buildCSIRSPortReferenceInputs(p);
assert(isequal(before,rng)&&isequaln(p,original));
e=r.Evidence;
assert(e.OriginalGridSHA256==hashes(1)&&e.OriginalWaveformSHA256==hashes(2) && ...
    e.OriginalTransmitSamplesSHA256==hashes(3));
assert(r.EvidenceSHA256==sixgr.util.sha256Hex(char(r.EvidenceJSON)) && ...
    e.AdditionalReferenceOFDMModulations==numel(r.Components) && ...
    e.AdditionalPhysicalTransmissions==0&&e.AdditionalRFExecutions==0 && ...
    e.AdditionalChannelExecutions==0&&e.AdditionalChannelEstimations==0 && ...
    e.AdditionalPowerContextApplications==0&&e.AdditionalCalibrationProbes==0 && ...
    ~e.ReferenceUsedByReceiver&&~e.SeparatelyTransmittedPortSamples && ...
    ~e.InstalledPhysicalOwnerBound&&~e.MultiportReceivedPowerQualified && ...
    ~e.StandardizedPowerAccuracyQualified);
assert(all([e.Closure.Grid e.Closure.UnscaledWaveform e.Closure.ScaledPreRFInput]<= ...
    e.Closure.RelativeTolerance));
actual=expand(r);
assert(norm(actual(:)-p.TransmitSamples(:))/max(norm(p.TransmitSamples(:)),realmin)<1e-11);
for k=1:numel(r.Components)
    c=r.Components(k); receipt=e.Components(k);
    assert(size(c.Samples,2)==1&&iscolumn(c.WaveformColumnWeights));
    expanded=c.Samples*c.WaveformColumnWeights.';
    assert(receipt.ExpandedPreRFInputSHA256==sixgr.phy.waveform.WaveformHash.numeric(expanded));
    assert(~isfield(receipt,'Samples')&&~isfield(receipt,'WaveformColumnWeights'));
end
end

function samples=expand(r)
samples=complex(zeros(r.Evidence.NumSamples,r.Evidence.WaveformColumnCount));
for k=1:numel(r.Components)
    c=r.Components(k); samples=samples+c.Samples*c.WaveformColumnWeights.';
end
end

function p=prepare(ports,resources,unit,scs,cp,slot,start)
cfg=config(ports,resources,unit,scs,cp,start);
p=sixgr.link.prepareCSIRSTransmission(cfg,20,'RuntimeSlot',slot,'Frame',1);
end

function cfg=config(ports,resources,unit,scs,cp,start)
% Declared bounded component; no scheduler, received CSI or scenario claim.
cfg=sixgr.config.defaultConfig();
cfg.phy.carrier.NSizeGrid=24; cfg.phy.carrier.NStartGrid=start;
cfg.phy.carrier.SubcarrierSpacing=scs; cfg.phy.carrier.CyclicPrefix=char(cp);
cfg.channel.nTxAnt=4; cfg.phy.nTxAnt=4;
cfg.rf.pa.enable=false; cfg.phy.csiim.enabled=false;
cfg.phy.synchronization=struct('maxTimingUncertaintySamples',0);
cfg.integration=struct('run_mode','FIXED_SNR_SWEEP', ...
    'configured_snr_is_link_authority',true,'power_reference_mode','normalized_unit_es');
if unit=="sqrt_mW"
    cfg.integration=struct('run_mode','GEOMETRY_NETWORK', ...
        'configured_snr_is_link_authority',false,'power_reference_mode','absolute_calibrated_sqrt_mw');
end
row=2; if ports==2, row=3; elseif ports==4, row=4; end
cfg.phy.csirs.enable=true; cfg.phy.csirs.period_slots=1; cfg.phy.csirs.offset_slots=0;
cfg.phy.csirs.nPorts=ports; cfg.phy.csirs.numPorts=ports;
cfg.phy.csirs.numResources=resources; cfg.phy.csirs.resourceSetID=9;
ids=[17 29]; locations=[3 8];
cfg.phy.csirs.resourceID=ids(1); cfg.phy.csirs.resourceIDs=ids(1:resources);
cfg.phy.csirs.rowNumber=row; cfg.phy.csirs.rowNumbers=repmat(row,1,resources);
cfg.phy.csirs.symbolLocations=locations(1);
cfg.phy.csirs.symbolLocationsByResource=locations(1:resources);
cfg.phy.csirs.subcarrierLocations=0;
cfg.phy.csirs.subcarrierLocationsByResource=zeros(1,resources);
cfg.phy.csirs.rbOffset=0; cfg.phy.csirs.rbOffsetsByResource=zeros(1,resources);
% Native CSI-RS requires at least 24 allocated RBs and rejects an allocation
% larger than this carrier. Author both as 24; do not assume silent clipping.
% No control-plane allocation or scheduled reception is claimed.
cfg.phy.csirs.numRB=24; cfg.phy.csirs.numRBsByResource=24*ones(1,resources);
cfg.phy.csirs.density='one'; cfg.phy.csirs.cdmType='noCDM';
if ports>1, cfg.phy.csirs.cdmType='fd-CDM2'; end
basis=exp(1i*2*pi*(0:3).'*(0:3)/4)/2;
W=complex(zeros(4,ports,resources));
for k=1:resources
    W(:,:,k)=basis(:,1:ports)*exp(1i*(k-1)*0.37);
end
cfg.phy.csirs.precoderMatrices=W;
cfg.phy.csirs.precoderBeamIndices=repmat(0:ports-1,resources,1);
end

function reject(p,identifier)
try
    sixgr.phy.refsig.buildCSIRSPortReferenceInputs(p);
catch cause
    assert(strcmp(cause.identifier,identifier),'test:CSIRSPortReferenceWrongFailure', ...
        'Expected %s, got %s: %s',identifier,cause.identifier,cause.message);
    return;
end
error('test:CSIRSPortReferenceMissingFailure','Expected %s.',identifier);
end
