function ok=testCSIRSSINRReference()
% Declared-grid arithmetic tests, not original owner or accuracy qualification.
setup6GRSimToolkit('Verbose',false);
support=[0 0;1 0];
d=complex(zeros(4,2,3)); u=d;
desiredPower=[4 1 0]; disturbancePower=[4 .1 2];
for r=1:3
    d(:,:,r)=sqrt(desiredPower(r));
    u(:,:,r)=1i*sqrt(disturbancePower(r));
end
m=measurement([2 3 -1],[4 .2 2],[.5 15 -.5]);
original=m;
a=sixgr.phy.refsig.compareCSIRSSINRReference(d,d+u,support,8,m,"normalized_complex_baseband");
assert(isequaln(m,original)&&a.MeasuredSelectedColumn1==2&&a.ReferenceSelectedColumn1==2);
close(a.ReferenceDesiredPerReceiveColumn,[4 1 0]);
close(a.ReferenceDisturbancePerReceiveColumn,[4 .1 2]);
close(a.ReferenceRatioPerReceiveColumn,[1 10 0]);
close(a.CrossEnergyOnDisturbanceSupport,[0 0 0]);
assert(a.ReferenceSINR_dB(3)==-Inf&&isnan(a.MeasuredSINR_dB(3))&& ...
    ~a.StandardizedAccuracyQualified&&~a.IndependentOriginalSamplesProved);
close(a.MeasuredSelectedColumnError_dB,10*log10(15/10));
% A corrected original estimator ratio is NOT reconstructed as signal/noise.
m.SignalPowerEstimation.SignedPort3000SNRLinearPerBranch=[.3 9 -.7];
m.CSI_SINRPerReceiveAntenna_dB=[10*log10(.3) 10*log10(9) NaN];
m.CSI_SINR_dB=10*log10(9);
b=sixgr.phy.refsig.compareCSIRSSINRReference(d,d+u,support,8,m,"normalized_complex_baseband");
assert(isequal(b.MeasuredPowerRatioPerReceiveColumn,[.5 15 -.5])&& ...
    isequal(b.MeasuredEstimatorRatioPerReceiveColumn,[.3 9 -.7]));
% Absolute-grid conversion acts once on BOTH powers; ratio is invariant.
mAbs=m; scale=8^2*1000;
mAbs.DesiredPowerPerReceiveAntenna=m.DesiredPowerPerReceiveAntenna/scale;
mAbs.NoiseInterferencePowerPerReceiveAntenna=m.NoiseInterferencePowerPerReceiveAntenna/scale;
c=sixgr.phy.refsig.compareCSIRSSINRReference(d,d+u,support,8,mAbs,"sqrt_mW");
close(c.ReferenceDesiredPerReceiveColumn,a.ReferenceDesiredPerReceiveColumn/scale);
close(c.ReferenceRatioPerReceiveColumn,a.ReferenceRatioPerReceiveColumn);
% Dedicated CSI-IM uses its own original REs, including coherent residual.
u(:,2,:)=3*u(:,2,:);
im=withCSIIM(m,d+u,[5;6]);
q=sixgr.phy.refsig.compareCSIRSSINRReference(d,d+u,support,8,im,"normalized_complex_baseband");
assert(q.DedicatedCSIIM&&isequal(q.DisturbanceSupport0Based,[0 1;1 1]));
close(q.ReferenceDisturbancePerReceiveColumn,9*a.ReferenceDisturbancePerReceiveColumn);
assert(q.OriginalCSIIMSecondMomentVerified);
% Absolute single-precision measurement divides in the ORIGINAL class before
% double accumulation. It must not be rejected by a double-first conversion.
ds=single(d); ys=single(d+u); divisor=cast(8*sqrt(1000),'like',ys);
ims=withCSIIM(m,ys./divisor,[5;6]);
s=sixgr.phy.refsig.compareCSIRSSINRReference(ds,ys,support,8,ims,"sqrt_mW");
assert(s.OriginalCSIIMSecondMomentVerified);
% +Inf, undefined 0/0, exact zero desired, and nonpositive measured values
% remain distinguishable after JSON encoding, without an epsilon floor.
dz=complex(zeros(4,2,3)); dz(:,:,1)=1;
z=measurement([1 0 -1],[0 0 1],[Inf NaN -1]);
v=sixgr.phy.refsig.compareCSIRSSINRReference(dz,dz,support,8,z,"normalized_complex_baseband");
assert(v.ReferenceRatioPerReceiveColumn(1)==Inf&&isnan(v.ReferenceRatioPerReceiveColumn(2))&& ...
    v.ReferenceBothZero(2)&&v.NumericTokens.ReferenceSINR_dB(1)=="Inf"&& ...
    v.NumericTokens.ReferenceSINR_dB(2)=="NaN"&&isnan(v.ReportedError_dB));
roundtrip=jsondecode(jsonencode(v));
assert(string(roundtrip.NumericTokens.ReferenceSINR_dB(1))=="Inf");
% Native no-CSIIM retains log(0)=-Inf, unlike signed-estimate policies.
native=measurement([0 1 0],[1 1 1],[0 1 0]);
native.SignalPowerEstimation=struct(); native.CSI_SINRPerReceiveAntenna_dB=[-Inf 0 -Inf];
native.CSI_SINR_dB=0; native.ReceiveBranch1Based=2;
nv=sixgr.phy.refsig.compareCSIRSSINRReference(d,d+u,support,8,native,"normalized_complex_baseband");
assert(nv.MeasuredSINR_dB(1)==-Inf&&nv.NumericTokens.MeasuredSINR_dB(1)=="-Inf");
% Preserve original complex covariance in JSON-safe evidence, not its real part.
complexM=m; complexM.InterferenceMeasurement.Covariance=[1 1i;-1i 2];
cv=sixgr.phy.refsig.compareCSIRSSINRReference(d,d+u,support,8,complexM,"normalized_complex_baseband");
jsonencode(sixgr.util.jsonSafeValue(cv));
% Reject mismatched original column/report and malformed resource support.
call=@(x)sixgr.phy.refsig.compareCSIRSSINRReference(d,d+u,support,8,x,"normalized_complex_baseband");
bad=m; bad.ReceiveBranch1Based=1; reject(@()call(bad));
bad=m; bad.CSI_SINR_dB=11; reject(@()call(bad));
bad=m; bad.CSI_SINRPerReceiveAntenna_dB(1)=NaN; reject(@()call(bad));
bad=m; bad.NoiseInterferencePowerPerReceiveAntenna(1)=-1; reject(@()call(bad));
bad=im; bad.InterferenceMeasurement.Plan.PhysicalIndices1Based=[1;2]; reject(@()call(bad));
bad=im; bad.InterferenceMeasurement.SampleCount=3; reject(@()call(bad));
bad=m; bad.ReferencePort=3001; reject(@()call(bad));
bad=m; bad.ReferenceRECount=1; reject(@()call(bad));
bad=im; bad.InterferenceMeasurement.Covariance(1,2)=bad.InterferenceMeasurement.Covariance(1,2)+1i; reject(@()call(bad));
bad=im; bad.InterferenceMeasurement.PowerPerReceiveAntenna(1)=bad.InterferenceMeasurement.PowerPerReceiveAntenna(1)*1.01; reject(@()call(bad));
bad=im; bad.InterferenceMeasurement.MeanPower=bad.InterferenceMeasurement.MeanPower*1.01; reject(@()call(bad));
bad=im; bad.NoiseInterferencePowerPerReceiveAntenna(1)=bad.NoiseInterferencePowerPerReceiveAntenna(1)*1.01; reject(@()call(bad));
% Internally consistent fabricated second moments still fail original-sample
% binding, even if a matching SINR log and selected column are supplied.
bad=withCSIIM(m,2*(d+u),[5;6]); reject(@()call(bad));
% Reject original text/character codepoints BEFORE numeric conversion.
% These single codepoints previously reproduced the desired scalar values.
bad=m; bad.ReferencePort=char(3000); reject(@()call(bad));
bad=m; bad.ReferenceRECount=char(2); reject(@()call(bad));
bad=m; bad.ReceiveBranch1Based=char(2); reject(@()call(bad));
bad=m; bad.InterferenceMeasurement.Plan.Enabled=char(0); reject(@()call(bad));
bad=m; bad.SignalPowerEstimation=[]; reject(@()call(bad));
for field=["DesiredPowerPerReceiveAntenna","NoiseInterferencePowerPerReceiveAntenna", ...
        "CSI_SINRPerReceiveAntenna_dB"]
    bad=m; bad.(field)=char([2 3 0]); reject(@()call(bad));
end
bad=m; bad.CSI_SINR_dB='1'; reject(@()call(bad));
bad=m; bad.SignalPowerEstimation.SignedPort3000SNRLinearPerBranch=char([2 3 0]); reject(@()call(bad));
% Integer-valued moments demonstrate the exact char-codepoint bypass, not
% just malformed numerical values that would already fail arithmetic.
integerGrid=complex(ones(size(d))); integerIM=withCSIIM(m,integerGrid,[5;6]);
integerCall=@(x)sixgr.phy.refsig.compareCSIRSSINRReference(d,integerGrid,support,8,x,"normalized_complex_baseband");
integerCall(integerIM);
for field=["Covariance","PowerPerReceiveAntenna","MeanPower","Available","SampleCount"]
    bad=integerIM; bad.InterferenceMeasurement.(field)=char(double(bad.InterferenceMeasurement.(field)));
    reject(@()integerCall(bad));
end
for field=["Enabled","Scheduled","NumRE","PhysicalIndices1Based"]
    bad=integerIM; bad.InterferenceMeasurement.Plan.(field)=char(double(bad.InterferenceMeasurement.Plan.(field)));
    reject(@()integerCall(bad));
end
actualMeasurementProducer();
fprintf('CSI_SINR_REFERENCE_PASS declared_grid=1 original_owner=0 standards_accuracy=0\n');
ok=true;
end
function actualMeasurementProducer()
% Actual measurement producer on declared grids. This verifies its schema
% and sample arithmetic, not a new original shared RF/channel execution.
c=nrCarrierConfig('NSizeGrid',24,'SubcarrierSpacing',30);
rs=nrCSIRSConfig('CSIRSType','nzp','CSIRSPeriod','on','RowNumber',2, ...
    'Density','one','SymbolLocations',2,'SubcarrierLocations',0,'NumRB',24);
cfg.phy.csiim=struct('enabled',true,'resource_id',0,'pattern',1, ...
    'subcarrier',4,'symbol',13,'starting_rb',0,'num_rbs',24, ...
    'period_slots',5,'offset_slots',0);
x=nrResourceGrid(c,1); idx=nrCSIRSIndices(c,rs); x(idx)=nrCSIRS(c,rs);
desired=cat(3,x,2i*x);
stream=RandStream('mt19937ar','Seed',822417);
y=desired+.1*complex(randn(stream,size(desired)),randn(stream,size(desired)));
[k,l]=ind2sub([size(x,1) size(x,2)],double(idx)); support=[k-1 l-1];
nfft=512;
for unit=["normalized_complex_baseband","sqrt_mW"]
    raw=y; clean=desired; measurementGrid=raw;
    if unit=="sqrt_mW"
        scale=single(nfft*sqrt(1000)); raw=single(y).*scale; clean=single(desired).*scale;
        measurementGrid=raw./scale;
    end
    measured=sixgr.phy.refsig.measureCSISINRFromResourceGrid(c,rs,measurementGrid,cfg);
    a=sixgr.phy.refsig.compareCSIRSSINRReference(clean,raw,support,nfft,measured,unit);
    assert(a.OriginalCSIIMSecondMomentVerified&& ...
        isequal(a.OriginalCSIIMCovariance,measured.InterferenceMeasurement.Covariance));
end
end

function m=measurement(ps,pn,linear)
logs=nan(size(linear)); positive=linear>0; logs(positive)=10*log10(linear(positive));
[value,column]=max(logs,[],'omitnan');
if isnan(value), column=NaN; end
m=struct('DesiredPowerPerReceiveAntenna',ps,'NoiseInterferencePowerPerReceiveAntenna',pn, ...
    'CSI_SINRPerReceiveAntenna_dB',logs,'CSI_SINR_dB',value,'ReceiveBranch1Based',column, ...
    'SignalPowerEstimation',struct('SignedPort3000SNRLinearPerBranch',linear), ...
    'InterferenceMeasurement',struct('Plan',struct('Enabled',false)), ...
    'ReferencePort',3000,'ReferenceRECount',2, ...
    'Source',"declared_component_test",'DisturbanceSource',"declared_component_test");
end
function m=withCSIIM(m,grid,idx)
flat=reshape(double(grid),[],size(grid,3)); values=flat(idx,:);
covariance=values.'*conj(values)/numel(idx); covariance=(covariance+covariance')/2;
power=real(diag(covariance)).';
m.InterferenceMeasurement=struct('Available',true,'SampleCount',numel(idx), ...
    'Covariance',covariance,'PowerPerReceiveAntenna',power,'MeanPower',mean(power), ...
    'Source',"configured_CSI_IM_received_RE_second_moment", ...
    'Plan',struct('Enabled',true,'Scheduled',true,'PhysicalIndices1Based',idx,'NumRE',numel(idx)));
m.NoiseInterferencePowerPerReceiveAntenna=power;
linear=m.DesiredPowerPerReceiveAntenna./power;
m.SignalPowerEstimation.SignedPort3000SNRLinearPerBranch=linear;
logs=nan(size(linear)); positive=linear>0; logs(positive)=10*log10(linear(positive));
m.CSI_SINRPerReceiveAntenna_dB=logs;
[m.CSI_SINR_dB,m.ReceiveBranch1Based]=max(logs,[],'omitnan');
end
function close(a,b)
assert(isequal(size(a),size(b))&&all(abs(a-b)<=1e-12*max(1,abs(b)),'all'));
end
function reject(call)
try
    call();
catch e
    assert(string(e.identifier)=="sixgr:refsig:CSIRSSINRReferenceOperands"); return;
end
error('test:MissingRejection','Malformed SINR evidence was accepted.');
end
