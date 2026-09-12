function ok=testAppliedBeamPatternConvention()
% Independent free-space transmit phase convention, not a PMI reconstruction.
fc=3e9; c=299792458; lambda=c/fc;
array=phased.NRRectangularPanelArray('Size',[1 4 1 1], ...
    'Spacing',[lambda/2 lambda/2 lambda 2*lambda], ...
    'ElementSet',{phased.IsotropicAntennaElement('FrequencyRange',[1e9 5e9])});
position=getElementPosition(array);
az=-75:1:75; el=[0 1]; desiredAz=30;
u=[cosd(desiredAz);sind(desiredAz);0];
% exp(jwt) and exp(-jkr) give exp(+jk r_element dot u) in the far field.
w=exp(-1i*2*pi/lambda*(position.'*u))/2;
directions=[cosd(az);sind(az);zeros(size(az))];
field=w.'*exp(1i*2*pi/lambda*(position.'*directions));
reference=abs(field).^2;
d=sixgr.truth.sampleAppliedDataPrecoderPattern(array,fc,az,el,w);
power=10.^(d(1,:)/10);
assert(max(abs(power/max(power)-reference/max(reference)))<1e-8, ...
    'test:TransmitPatternConvention','Directivity cut must match independent transmit far-field power.');
[~,peak]=max(power); assert(az(peak)==desiredAz);
dScaled=sixgr.truth.sampleAppliedDataPrecoderPattern(array,fc,az,el,3*w);
% Compare linear directivity: dB subtraction at floating-point array nulls
% is ill-conditioned, even when the absolute power discrepancy is tiny.
linear=10.^(d(:)/10); linearScaled=10.^(dScaled(:)/10);
relativeError=max(abs(linearScaled-linear))/max(linear);
fprintf('APPLIED_BEAM_SCALE relative_linear_error=%.17g max_db_difference=%.17g\n', ...
    relativeError,max(abs(dScaled(:)-d(:))));
assert(relativeError<1e-8,'Directivity must be invariant to common weight scale.');
fprintf('APPLIED_BEAM_CONVENTION_PASS independent transmit phase, peak=+30 deg, scale invariant\n');
ok=true;
end
