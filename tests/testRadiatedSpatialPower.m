function ok=testRadiatedSpatialPower()
% Component quadrature and native polarized radiator comparison only.
% Declared input samples are not a hardware power calibration or LLS run.
setup6GRSimToolkit('Verbose',false);
before=rng;
x=[1 1i; 2 -1; -1i .2; 0 0];
spatial=sixgr.rf.measurePhysicalTXSpatialPower(x);
field=struct('Contract',"transmit_array_field_gain/v1", ...
    'H',ones(2,8),'V',zeros(2,8),'SolidAngle_sr',ones(8,1)*pi/2, ...
    'AzimuthElevation_deg',[(-157.5:45:157.5);zeros(1,8)], ...
    'FrequencyHz',2.35e9,'Source',"declared_constant_field_component_fixture", ...
    'Scope',"native_gain_pattern_no_feed_or_mutual_coupling_calibration");
out=sixgr.rf.integrateRadiatedSpatialPower(spatial,field,"sqrt_mW");
expected=mean(abs(sum(x,2)).^2);
assert(abs(out.ModelTRP_mW-expected)<1e-12 && ...
    max(abs(out.ModelDirectionalEIRP_mW-expected))<1e-12 && ...
    ~out.PowerRenormalizationApplied && ~out.HardwareConformanceVerified);
% Orthogonal polarizations must add as powers, not coherent amplitudes.
field.H=repmat([1;0],1,8); field.V=repmat([0;1],1,8);
out=sixgr.rf.integrateRadiatedSpatialPower(spatial,field,"sqrt_mW");
assert(abs(out.ModelTRP_mW-spatial.TotalMeanSquare)<1e-12);
reject(@()sixgr.rf.integrateRadiatedSpatialPower(spatial,field,"normalized"), ...
    'RF:RadiationAbsolutePowerRequired');
bad=spatial; bad.SecondMoment(1,2)=bad.SecondMoment(1,2)+1;
reject(@()sixgr.rf.integrateRadiatedSpatialPower(bad,field,"sqrt_mW"), ...
    'RF:RadiationSpatialSource');
bad=field; bad.SolidAngle_sr=bad.SolidAngle_sr/2;
reject(@()sixgr.rf.integrateRadiatedSpatialPower(spatial,bad,"sqrt_mW"), ...
    'RF:RadiationFieldContract');
% Check the transmit phase convention against native polarized radiation.
fc=2.35e9;
array=phased.ULA('NumElements',2,'ElementSpacing',physconst('LightSpeed')/fc*.37, ...
    'Element',phased.ShortDipoleAntennaElement('FrequencyRange',[1e9 4e9]));
installed=struct('ArrayObj',array,'NumElements',2,'Fc_Hz',fc);
field=sixgr.rf.sampleArrayRadiationField(installed,12,6);
out=sixgr.rf.integrateRadiatedSpatialPower(spatial,field,"sqrt_mW");
radiator=phased.Radiator('Sensor',clone(array),'OperatingFrequency',fc, ...
    'Polarization','Combined','SensorGainMeasure','dB');
native=radiator(x,field.AzimuthElevation_deg,eye(3));
power=zeros(1,numel(native));
for k=1:numel(native)
    power(k)=mean(abs(native(k).X).^2+abs(native(k).Y).^2+abs(native(k).Z).^2);
end
assert(max(abs(power-out.ModelDirectionalEIRP_mW))<1e-11*max(power), ...
    'test:RadiationTransmitConvention','Compare actual polarized radiated sample powers at every direction.');
assert(isequal(rng,before));
fprintf('RADIATED_SPATIAL_POWER_PASS native_polarized_comparison=1 runtime_integration=0 hardware_qualification=0\n');
ok=true;
end

function reject(fn,id)
try, fn(); catch err, assert(strcmp(err.identifier,id),'Expected %s got %s',id,err.identifier); return; end
error('test:RadiationExpectedError','Expected %s',id);
end
