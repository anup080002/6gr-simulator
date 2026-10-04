function ok=testCalibrationSpatialFeature()
% A decoded MIMO calibration trial must use its applied channel and layers.
h=complex(zeros(2,1,2,2));
h(:,:,1,1)=1; h(:,:,2,2)=1;
tx=struct();
tx.PDSCHLayerIndices=[1 3;2 4];
tx.PDSCHLayerSymbols=ones(2,2);
tx.PDSCHPortSymbols=tx.PDSCHLayerSymbols*(eye(2)/sqrt(2)).';
tx.PDSCH=struct('NumLayers',2);
tx.PrecodeInfo=struct('MatrixPorts',eye(2)/sqrt(2), ...
    'MatrixPortsPerPRG',eye(2)/sqrt(2), ...
    'HybridElementDomainApplied',false);
d=struct('Tx',tx,'TrueChannelGrid',h, ...
    'NoiseInfo',struct('GridNoiseVariance',0.1));
f=sixgr.calibration.extractAppliedSpatialSINR(d,"lmmse");
assert(isequal(size(f.SINRLinear),[2 2]) && ...
    max(abs(f.SINRLinear-5),[],'all')<1e-10 && ...
    f.DataRECount==4 && f.WaveformBacked && ...
    contains(f.SourceClassification,"not_receiver_measurement") && ...
    contains(f.SINRSource,"not_receiver_measurement"));

% Rank one reduces to the established applied-channel Es/N0 expression.
single=d;
single.TrueChannelGrid=reshape([1;2],[2 1 1 1]);
single.Tx.PDSCHLayerIndices=[1;2];
single.Tx.PDSCHLayerSymbols=ones(2,1);
single.Tx.PDSCHPortSymbols=ones(2,1);
single.Tx.PDSCH.NumLayers=1;
single.Tx.PrecodeInfo.MatrixPorts=1;
single.Tx.PrecodeInfo.MatrixPortsPerPRG=1;
one=sixgr.calibration.extractAppliedSpatialSINR(single,"lmmse");
assert(max(abs(one.SINRLinear(:)-[10;40]))<1e-10);

% Compare the actual LMMSE filter against independent matrix arithmetic.
h(:,:,1,2)=0.8; d.TrueChannelGrid=h;
f=sixgr.calibration.extractAppliedSpatialSINR(d,"lmmse");
g=[1 0.8;0 1]/sqrt(2);
w=(g*g'+0.1*eye(2))\g;
response=w'*g;
expected=zeros(1,2);
for layer=1:2
    other=3-layer;
    expected(layer)=abs(response(layer,layer))^2 / ...
        (abs(response(layer,other))^2+0.1*real(w(:,layer)'*w(:,layer)));
end
assert(max(abs(f.SINRLinear(1,:)-expected))<1e-10);
assert(max(abs(f.SINRLinear(2,:)-expected))<1e-10);

% Allocation/noise evidence must not execute a diagonal detector. A finite
% channel predictor has its own effective channel and rank test. Here a
% singular diagonal channel deliberately rejects ZF, but the independently
% validated input metadata remains usable and contains NO SINR claim.
singular=d; singular.TrueChannelGrid(:)=1;
[metadata,allocation,channel]=sixgr.calibration.resolveAppliedSpatialEvidence(singular);
assert(metadata.DataRECount==4 && metadata.GridNoiseVariance==.1 && ...
    ~isfield(metadata,'SINRLinear') && ~isfield(metadata,'SINRSource') && ...
    isequal(allocation.Coordinates0Based,[0 0;1 0]) && ...
    isequal(channel,repmat(ones(2),1,1,2)));
localReject(@()sixgr.calibration.extractAppliedSpatialSINR(singular,"zf"), ...
    'sixgr:abstraction:ZFRankDeficient');

bad=d;
bad.Tx.PrecodeInfo.MatrixPortsPerPRG=cat(3,eye(2)/sqrt(2), ...
    [0 1;1 0]/sqrt(2));
localReject(@()sixgr.calibration.extractAppliedSpatialSINR(bad,"lmmse"), ...
    'sixgr:calibration:SpatialFeaturePRG');
bad=d; bad.NoiseInfo.GridNoiseVariance=0;
localReject(@()sixgr.calibration.extractAppliedSpatialSINR(bad,"lmmse"), ...
    'sixgr:calibration:SpatialFeatureNoise');
bad=d; bad.Tx.PDSCHPortSymbols(1,1)=0;
localReject(@()sixgr.calibration.extractAppliedSpatialSINR(bad,"lmmse"), ...
    'sixgr:calibration:SpatialFeaturePrecoder');
bad=d; bad.Tx.PDSCHLayerIndices=[1 3;2 3];
localReject(@()sixgr.calibration.extractAppliedSpatialSINR(bad,"lmmse"), ...
    'sixgr:calibration:SpatialFeatureMapping');
bad=d; bad.Tx.PDSCHLayerIndices=[1 4;2 3];
localReject(@()sixgr.calibration.extractAppliedSpatialSINR(bad,"lmmse"), ...
    'sixgr:calibration:SpatialFeatureMapping');
ok=true; fprintf('CALIBRATION_SPATIAL_FEATURE_PASS\n');
end

function localReject(fn,id)
try
    fn();
catch ME
    assert(strcmp(ME.identifier,id),'Expected %s, got %s: %s', ...
        id,ME.identifier,ME.message);
    return
end
error('test:MissingRejection','Expected %s.',id);
end
