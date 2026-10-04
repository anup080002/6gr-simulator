function ok=testSLSModeledCSIRSPowerReference()
% Algebraic producer negatives complement the native-grid integration test.
% Declared deterministic CSI symbols/channel, not waveform qualification.
cfg=sixgr.lls6g.config.readConfigFile('simulator/configs/system/modeled_csirs_power_reference.yaml');
B=[1 1;1 -1]/sqrt(2); logical=[1 1;1 -1;-1 1;-1 -1];
physical=logical*B.'; coords=[(0:3).' zeros(4,1)];
e=struct('Signal',"CSI-RS",'ServingCellID',1,'ResourceID',0,'AbsoluteSlot0',1, ...
    'Coordinates0Based',coords,'Symbols',physical*sqrt(2),'Precoder',eye(2)/sqrt(2), ...
    'TransmitPowerPerRE_W',ones(4,1)*0.002, ...
    'PhysicalPrecoderSHA256',string(sixgr.phy.mimo.MatrixContract.digest(B)));
e.SHA256=hash(e);
H=zeros(2,2,4);
% Alternating phase must not cancel RSRP. Port 3001 has a very different
% gain and must not contaminate the port-3000 measurement.
for q=1:4, H(:,:,q)=(-1)^q*[0.1 9;0.2 11]; end
o=struct('ExecutionID',"power_reference_fixture",'UEIndex',1,'RNTI',4660,'ServingCell',1, ...
    'SourceAbsoluteSlot0',1,'ReferenceResourceID',0,'ReferenceEmissionSHA256',e.SHA256, ...
    'PortToElementMatrix',B,'ChannelEstimate',H,'Coordinates0Based',coords);
r=sixgr.system.abstraction.modelCSIRSPowerReference(cfg,o,e);
assert(abs(r.TransmitEPRE_W-0.002)<1e-14 && abs(r.RSRP_W-0.00008)<1e-14 && ...
    abs(r.PathlossdB-10*log10(25))<1e-12 && r.SelectedReceiveBranch0==1 && ...
    r.ReferenceRECount==4 && ~r.WaveformMeasured && ~r.PhysicalEstimationQualified);
% Neither cell total power nor configured SINR is an RSRP substitute.
changed=cfg; changed.channel.SNRdB=-30; changed.phy.pucch.pathloss_db=1;
r2=sixgr.system.abstraction.modelCSIRSPowerReference(changed,o,e);
assert(isequal(r,r2));
bad=e; bad.Symbols(1,1)=bad.Symbols(1,1)+1;
reject(@()sixgr.system.abstraction.modelCSIRSPowerReference(cfg,o,bad),'sixgr:abstraction:PowerReferenceEmission');
bad=o; bad.ServingCell=2;
reject(@()sixgr.system.abstraction.modelCSIRSPowerReference(cfg,bad,e),'sixgr:abstraction:PowerReferenceEmission');
bad=o; bad.PortToElementMatrix=eye(2);
reject(@()sixgr.system.abstraction.modelCSIRSPowerReference(cfg,bad,e),'sixgr:abstraction:PowerReferenceBasis');
bad=cfg; bad.system.linkAbstraction.dynamicPUCCH.powerReference.filterCoefficient=4;
reject(@()sixgr.system.abstraction.modelCSIRSPowerReference(bad,o,e),'sixgr:abstraction:PowerReferencePolicy');
bad=cfg; bad.system.linkAbstraction.dynamicPUCCH.powerReference.referenceSignalID=1;
assert(isempty(sixgr.system.abstraction.modelCSIRSPowerReference(bad,o,e)));
ok=true;
end
function h=hash(v)
h=string(sixgr.util.sha256Hex(uint8(unicode2native(jsonencode(sixgr.util.jsonSafeValue(v)),'UTF-8'))));
end
function reject(f,id)
try
    f();
catch err
    assert(strcmp(err.identifier,id),'Unexpected error: %s',err.identifier); return;
end
error('test:ExpectedRejection','Expected %s.',id);
end
