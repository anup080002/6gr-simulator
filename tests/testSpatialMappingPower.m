function ok=testSpatialMappingPower()
% Actual complex OFDM samples, numerical mappings and CSV roundtrip.
% This is digital mapping qualification, not RF or decoded link performance.
setup6GRSimToolkit('Verbose',false);
before=rng;
carrier=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30);
grid=complex(zeros(288,14,4));
for k=1:4
    grid(7:265,2:13,k)=reshape(exp(1i*(1:259*12)*(.13*k)),259,12)*k/4;
end
x=nrOFDMModulate(carrier,grid,'Windowing',0);
for precision=["double","single"]
    a=cast(x,precision);
    W=cast(exp(2i*pi*(0:7)'*(0:3)/8)/sqrt(8),precision);
    b=a*W.';
    evidence=sixgr.rf.measureSpatialMappingPower(a,b,W);
    assert(evidence.SampleCount==size(a,1) && evidence.InputColumns==4 && ...
        evidence.OutputColumns==8 && ~evidence.RadiatedPowerClaimed && ...
        evidence.CovarianceResidual<=evidence.NumericalTolerance);
    expected=double(W)*conj(double(a)'*double(a))/size(a,1)*double(W)';
    assert(norm(expected-evidence.OutputSecondMoment,'fro')<= ...
        evidence.NumericalTolerance+1e-13);
    encoded=sixgr.runtime.RawCSVArrayCodec.encode(evidence.OutputSecondMoment);
    assert(isequaln(sixgr.runtime.RawCSVArrayCodec.decode(encoded),evidence.OutputSecondMoment));
    assert(abs(evidence.InputMeanSquare-evidence.OutputMeanSquare)<= ...
        128*double(eps(precision))*max(1,evidence.InputMeanSquare));
    bad=b; bad(:,1)=bad(:,1)*2;
    reject(@()sixgr.rf.measureSpatialMappingPower(a,bad,W),'RF:SpatialMappingMismatch');
    reject(@()sixgr.rf.measureSpatialMappingPower(a,b,conj(W)),'RF:SpatialMappingMismatch');
end
% Full mapper -> completed-trial binder uses its actual element-domain IQ.
ant=struct('NumElements',4,'NumLogicalPorts',4,'NumLayers',4, ...
    'NumCodewords',1,'NumWaveformColumns',4,'NumRxAntennas',4, ...
    'NumRFChains',4,'ElementDomainPrecoding',true,'WaveformDomain','element');
coding=struct('NumLayers',4,'NumCodewords',1,'DMRSPortSet',0:3, ...
    'PTRSEnabled',false,'PTRSPortSet',[]);
precoding=struct('Matrix',eye(4),'MatrixLogicalPorts',eye(4), ...
    'NumPorts',4,'NumLogicalPorts',4,'NumLayers',4);
grant=struct('IsFrozen',true,'Direction','DL','GrantContextId','spatial_unit', ...
    'AntennaArchitecture',ant,'CodingLayout',coding,'PrecodingState',precoding, ...
    'ResourceAllocation',struct('PRBSet',0:23,'PRBCount',24,'SymbolAllocation',[0 14]));
cfg.rf.txSpatialPowerEnabled=true;
[y,w,m]=sixgr.truth.mapDataWaveformToPhysicalElements(x,cfg,grant,"bs","pdsch");
assert(isequal(x,y));
row=table("DL",4,'VariableNames',{'Direction','NumLayers'});
bound=sixgr.truth.bindExecutedDataAntennaEvidence(row,grant,m,w,x);
assert(bound.DataMappingInputMeanSquare==bound.DataMappingOutputMeanSquare && ...
    bound.DataMappingInputArraySHA256==bound.DataMappingOutputArraySHA256);
meta=struct('logical_run_id',"spatial_mapping_component",'run_id',19);
public=sixgr.truth.buildLLSPublicOutputTables(struct('pdsch_table',bound), ...
    sixgr.truth.llsOutputContract(),meta);
for name=string(bound.Properties.VariableNames)
    if name=="Direction", continue; end
    assert(ismember(name,string(public.pdsch_runtime_event_table.Properties.VariableNames)) && ...
        isequaln(public.pdsch_runtime_event_table.(name),bound.(name)), ...
        'test:SpatialMappingPublication','Public projection lost or changed %s.',name);
end
folder=fullfile(pwd,'results','validation','spatial_mapping_power');
if ~isfolder(folder), mkdir(folder); end
file=fullfile(folder,['mapping_' char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')) '.csv']);
sixgr.util.csvWriteTable(file,bound,'PreserveSchema',true,'RoundTripNumericText',true);
roundtrip=sixgr.util.csvReadTable(file,'TextType','string');
assert(isequaln(sixgr.runtime.RawCSVArrayCodec.decode( ...
    roundtrip.DataMappingOutputSecondMomentArray),m.SpatialMappingPower.OutputSecondMoment));
bad=m; bad.SpatialMappingPower.OutputMeanSquare=0;
reject(@()sixgr.truth.bindExecutedDataAntennaEvidence(row,grant,bad,w,x), ...
    'sixgr:truth:ExecutedDataAntennaEvidenceMismatch');
id='sixgr:truth:ExecutedDataAntennaEvidenceMismatch';
bad=m; bad.SpatialMappingPower.NumericalTolerance=Inf;
reject(@()sixgr.truth.bindExecutedDataAntennaEvidence(row,grant,bad,w,x),id);
reject(@()sixgr.truth.bindExecutedDataAntennaEvidence(row,grant,m,w,-x),id);
reject(@()sixgr.truth.bindExecutedDataAntennaEvidence(row,grant,m,w),id);
bad=m; bad.SpatialMappingPower.SampleCount=size(x,1)+1;
reject(@()sixgr.truth.bindExecutedDataAntennaEvidence(row,grant,bad,w,x),id);
bad=m; bad.SpatialMappingPower.ReferencePlane="post_RF";
reject(@()sixgr.truth.bindExecutedDataAntennaEvidence(row,grant,bad,w,x),id);
assert(isequal(before,rng),'Measurement must not alter RNG or PHY samples.');
fprintf('SPATIAL_MAPPING_POWER_PASS actual_OFDM=1 double_single=1 CSV_roundtrip=1 radiation_qualified=0\n');
ok=true;
end

function reject(fn,id)
try, fn(); catch err, assert(strcmp(err.identifier,id),'Expected %s got %s',id,err.identifier); return; end
error('test:SpatialMappingExpectedError','Expected %s',id);
end
