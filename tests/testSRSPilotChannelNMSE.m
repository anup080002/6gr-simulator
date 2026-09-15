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
% Canonical export must retain actual scoring availability, including the
% exact-zero-error (-Inf dB) case. This remains an algebra fixture, not RF.
for scale=[1,2]
    score=sixgr.phy.srs.pilotChannelNMSE(scale*reference,reference,indices);
    evidence=struct('Source',"explicit_channel_algebra_fixture", ...
        'ReferencePlane',"explicit_unit_test_reference_plane", ...
        'RFImpairmentsIncluded',false,'ReceiverEstimatorInput',false,'GainOrPhaseFitted',false);
    output=struct('ChannelNMSEScoring',score,'ChannelNMSEReferenceEvidence',evidence);
    row=table(score.dB,score.dB,string(evidence.Source), ...
        'VariableNames',{'NMSE_dB','TrueChannelNMSE_dB','NMSEReferenceSource'});
    bound=sixgr.truth.bindSharedSRSNMSEEvidence(row,output);
    assert(bound.NMSEScoringAvailable && bound.ChannelNMSEComparedComplexValues==48 && ...
        bound.ChannelNMSEPilotResourceCount==24 && isequaln(bound.NMSE_dB,score.dB) && ...
        bound.ChannelNMSEReferencePlane==evidence.ReferencePlane && ...
        bound.ChannelNMSEReferenceIncludesRFImpairments==0);
    wrong=output; wrong.ChannelNMSEScoring.Available=false;
    localError(@()sixgr.truth.bindSharedSRSNMSEEvidence(row,wrong), ...
        'sixgr:truth:InconsistentSRSNMSEScoring');
    wrong=output; wrong.ChannelNMSEScoring.ComparedComplexValueCount=47;
    localError(@()sixgr.truth.bindSharedSRSNMSEEvidence(row,wrong), ...
        'sixgr:truth:IncompleteSRSNMSEScoring');
    localError(@()sixgr.truth.bindSharedSRSNMSEEvidence(row,struct()), ...
        'sixgr:truth:MissingSRSNMSEScoring');
end
empty=table(NaN,NaN,"",'VariableNames',{'NMSE_dB','TrueChannelNMSE_dB','NMSEReferenceSource'});
bound=sixgr.truth.bindSharedSRSNMSEEvidence(empty,struct());
assert(~bound.NMSEScoringAvailable && isnan(bound.NMSE_dB) && ...
    bound.ChannelNMSEComparedComplexValues==0 && bound.ChannelNMSEReferencePlane=="unavailable");
fprintf('SRS_PILOT_CHANNEL_NMSE_PASS: all branches/ports; no phase/gain fit or missing-value masking.\n');
ok=true;
end
function localError(action,id)
try, action(); catch e, assert(string(e.identifier)==id); return; end
error('test:MissingExpectedError','Expected %s.',id);
end
