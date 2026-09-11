function ok=testSRSPilotChannelNMSE()
% Exact algebra fixtures, not simulated waveform evidence.
setup6GRSimToolkit('Verbose',false);
reference=complex(zeros(12,2,2,2));
reference(:,:,1,1)=1; reference(:,:,2,1)=-1;
reference(:,:,1,2)=2j; reference(:,:,2,2)=-2j;
indices=[(1:12)';(25:36)'];
s=sixgr.phy.srs.pilotChannelNMSE(reference,reference,indices);
assert(s.Linear==0 && s.dB==-Inf && s.ComparedComplexValueCount==48);
s=sixgr.phy.srs.pilotChannelNMSE(2*reference,reference,indices);
assert(s.Linear==1 && s.dB==0 && all(s.PerReceiveAntennaPortLinear==1,'all'));
s=sixgr.phy.srs.pilotChannelNMSE(1j*reference,reference,indices);
assert(abs(s.Linear-2)<1e-14,'Phase error must not be fitted away.');
bad=reference; bad(1,1,2,2)=NaN;
localError(@()sixgr.phy.srs.pilotChannelNMSE(bad,reference,indices), ...
    'sixgr:srs:IncompletePilotChannelReference');
localError(@()sixgr.phy.srs.pilotChannelNMSE(reference(:,:,:,1),reference,indices), ...
    'sixgr:srs:ChannelReferenceShapeMismatch');
localError(@()sixgr.phy.srs.pilotChannelNMSE(reference,reference,[indices;indices(1)]), ...
    'sixgr:srs:DuplicatePilotReference');
fprintf('SRS_PILOT_CHANNEL_NMSE_PASS: all branches/ports; no phase/gain fit or missing-value masking.\n');
ok=true;
end
function localError(action,id)
try, action(); catch e, assert(string(e.identifier)==id); return; end
error('test:MissingExpectedError','Expected %s.',id);
end
