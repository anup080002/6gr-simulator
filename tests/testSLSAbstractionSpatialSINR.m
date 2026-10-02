function ok=testSLSAbstractionSpatialSINR()
% Numerical fixtures only; no fixture is exported as physical calibration.
f=@sixgr.system.abstraction.evaluateSpatialSINR;
H=eye(2); noise=.1*eye(2);
r=f(H,eye(2)/sqrt(2),1,noise);
assert(max(abs(r.SINRLinear-5),[],'all')<1e-12);
assert(all(r.InterLayerInterferencePower==0,'all'));
r1=f(H,[1;0],1,noise);
assert(abs(r1.SINRLinear-10)<1e-12); % same total power, not doubled for rank 2
assert(~r.WaveformBacked && ~r.CalibrationApplied);
H=[1 .7+.2i;.3i 1]; F=eye(2)/sqrt(2);
R=[.2 .03i;-.03i .1];
r=f(H,F,1,R); G=H*F;
errorCov=(eye(2)+G'*(R\G))\eye(2);
reference=1./real(diag(errorCov))-1;
assert(max(abs(r.SINRLinear-reference.'))<1e-11);
assert(any(r.InterLayerInterferencePower>0,'all'));
% Frequency-selective resources are not collapsed to one channel scalar.
hp=cat(3,H,2*H,zeros(2)); rp=cat(3,R,2*R,R);
r=f(hp,F,[1;2;1],rp);
one=f(H,F,1,R); two=f(2*H,F,2,2*R);
assert(max(abs(r.SINRLinear(1,:)-one.SINRLinear))<1e-12);
assert(max(abs(r.SINRLinear(2,:)-two.SINRLinear))<1e-12);
assert(all(r.SINRLinear(3,:)==0) && all(r.SINR_dB(3,:)==-Inf));
% More external interference lowers both layer SINRs.
interfered=f(H,F,1,R+eye(2));
assert(all(interfered.SINRLinear<one.SINRLinear));
% Rectangular four-transmit/two-receive channel remains two-dimensional.
r=f([eye(2) zeros(2)], [eye(2);zeros(2)]/sqrt(2),1,noise);
assert(isequal(size(r.SINRLinear),[1 2]) && max(abs(r.SINRLinear-5))<1e-12);
localThrows(@()f(H,eye(2),1,R),'sixgr:abstraction:PrecoderPower');
localThrows(@()f(H,F,1,[1 1;0 1]),'sixgr:abstraction:Covariance');
localThrows(@()f(H,F,1,zeros(2)),'sixgr:abstraction:Covariance');
localThrows(@()f(H,F,[1 2],R),'sixgr:abstraction:PowerDimensions');
% Independent ZF reference: H=[1 .5;0 1], F=I/sqrt(2), P=2.
% Unit desired-layer output; noise enhancement is [1.25,1].
z=f([1 .5;0 1],eye(2)/sqrt(2),2,eye(2),"zf");
assert(max(abs(z.SINRLinear-[.8 1]))<1e-12 && z.ReceiverType=="zf");
assert(max(abs(z.InterLayerInterferencePower),[],'all')<1e-24);
% Complex rectangular channel and colored interference, independently
% evaluated with the explicit mathematical pseudoinverse.
Hz=[1 .3i;.2+.1i 1;.4 -.2i]; Rz=diag([.2 .3 .4]);
z=f(Hz,eye(2)/sqrt(2),1,Rz,"zf"); A=Hz/sqrt(2); B=pinv(A);
expected=1./real(diag(B*Rz*B'));
assert(max(abs(z.SINRLinear-expected.'))<1e-11);
localThrows(@()f(ones(2),F,1,R,"zf"),'sixgr:abstraction:ZFRankDeficient');
ok=true; fprintf('SLS_ABSTRACTION_SPATIAL_SINR_PASS\n');
end
function localThrows(fun,id)
caught=false;
try, fun(); catch ME, caught=strcmp(ME.identifier,id); end
assert(caught,'Expected %s.',id);
end
