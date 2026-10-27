function ok=testSRSDetectedPathPower()
% Held-out analytic two-path response, not a declared physical RF execution.
N=64; scs=30000; resolution=1/(N*scs); k=(0:N-1).';
delay1=2*resolution; delay2=8*resolution;
a=2e-6*exp(.3i); b=1.4e-6*exp(-.2i);
response=a*exp(-1i*2*pi*k*scs*delay1)+b*exp(-1i*2*pi*k*scs*delay2);
coords=[k zeros(N,2)]; noise=zeros(size(response));
policy=struct('Enabled',true,'DelayMin_us',0,'DelayMax_us',12*resolution*1e6, ...
    'DelayStep_us',resolution*1e6,'PeakRelativeThreshold_dB',-6, ...
    'NoiseThreshold_dB',6,'MinimumPathSeparation_us',resolution*1e6,'MaximumPaths',8);
binding=struct('ReferencePlane',"internal_physical_receive_element_before_RX_front_end", ...
    'ResponseUnit',"sqrt_W",'SubcarrierSpacingHz',scs, ...
    'ObservationSHA256',string(repmat('a',1,64)),'ReceivedGridSHA256',string(repmat('b',1,64)), ...
    'TruthChannelConsumed',false,'PostRFEstimateConsumed',false);
before=rng; r=sixgr.phy.srs.measureSRSDetectedPathPower(response,coords,noise,policy,binding);
assert(isequal(before,rng)&&r.Available&&numel(r.Paths)==2&& ...
    ~r.IndependentAccuracyQualified&&r.SelectionBiasPresent);
assert(max(abs([r.Paths.DelayRelativeToOriginalFFT_s]-[delay1 delay2]))<1e-14);
assert(max(abs([r.Paths.PathPower_W]-abs([a b]).^2))<1e-24);
assert(r.Paths(1).FirstDetectedPath&&~r.Paths(2).FirstDetectedPath);
limited=policy; limited.MaximumPaths=1;
weakFirst=b*exp(-1i*2*pi*k*scs*delay1)+a*exp(-1i*2*pi*k*scs*delay2);
first=sixgr.phy.srs.measureSRSDetectedPathPower(weakFirst,coords,noise,limited,binding);
assert(numel(first.Paths)==1&&abs(first.Paths.DelayRelativeToOriginalFFT_s-delay1)<1e-14, ...
    'First detected in time must survive a stronger later peak and output cap.');
% Mean squared frequency response is total multipath energy, not either path.
assert(all(abs([r.Paths.PathPower_W]-mean(abs(response).^2))>1e-13));
empty=sixgr.phy.srs.measureSRSDetectedPathPower(zeros(size(response)),coords,noise,policy,binding);
assert(empty.Available&&isempty(empty.Paths)&&contains(empty.Status,"no_path"));
for mutation=1:4
    c=coords; q=policy; v=binding;
    switch mutation
        case 1, c(2,:)=c(1,:);
        case 2, v.ObservationSHA256="missing";
        case 3, v.TruthChannelConsumed=true;
        case 4, q.DelayMax_us=1/scs*1e6;
    end
    rejected=false;
    try, sixgr.phy.srs.measureSRSDetectedPathPower(response,c,noise,q,v);
    catch cause, rejected=strcmp(cause.identifier,'sixgr:srs:DetectedPathPowerInput'); end
    assert(rejected,'test:SRSPathGuard','Reject altered support/plane/identity/ambiguity.');
end
ok=true; fprintf('testSRSDetectedPathPower PASS\n');
end
