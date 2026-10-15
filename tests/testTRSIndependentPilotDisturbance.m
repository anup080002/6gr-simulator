function ok=testTRSIndependentPilotDisturbance()
% Exact complex-sample algebra/guards; not a measured propagation campaign.
setup6GRSimToolkit('Verbose',false);
defaults=sixgr.phy.trs.scoreTRSPilotDisturbance();
assert(~defaults.IndependentPilotSNDRAvailable && isnan(defaults.IndependentPilotSNDR_dB));
d=struct('Slot',7,'Detected',true,'RxGrid',complex(zeros(12,14,2)), ...
    'ReferenceIndices',[1;8;65],'ReferenceSymbols',[1;1i;-1]);
ref=complex(nan(12,14,2)); indices=d.ReferenceIndices;
for r=1:2
    at=indices+(r-1)*12*14;
    ref(at)=r+0.5i;
    d.RxGrid(at)=(r+0.5i)*d.ReferenceSymbols+0.1*r;
end
e=struct('Source',"same_executed_desired_link_waveform_post_decode_TRS_pilot_ratio", ...
    'ReceiverEstimatorInput',false,'GainOrPhaseFitted',false,'AdditionalChannelExecutions',0, ...
    'AdditionalRFExecutions',0,'ReferencePlane',"declared_test_receiver_clock");
det=struct('SlotDetections',d);
s=sixgr.phy.trs.scoreTRSPilotDisturbance(det,{ref},{e});
assert(s.IndependentPilotComparedComplexValues==6 && s.IndependentPilotSNDRAvailable);
assert(abs(s.IndependentPilotSignalEnergy-16.5)<1e-12 && ...
    abs(s.IndependentPilotDisturbanceEnergy-0.15)<1e-12 && ...
    abs(s.IndependentPilotSNDR_dB-10*log10(110))<1e-12);
% Ratios pool actual linear energies, not dB scores or best RX branches.
det.SlotDetections(2)=d; det.SlotDetections(2).Slot=8;
det.SlotDetections(2).RxGrid=2*d.RxGrid;
s2=sixgr.phy.trs.scoreTRSPilotDisturbance(det,{ref,2*ref},{e,e});
assert(abs(s2.IndependentPilotSignalEnergy-5*16.5)<1e-12 && ...
    abs(s2.IndependentPilotDisturbanceEnergy-5*0.15)<1e-12 && ...
    s2.IndependentPilotComparedComplexValues==12);
bad=e; bad.GainOrPhaseFitted=true;
localReject(@()sixgr.phy.trs.scoreTRSPilotDisturbance(struct('SlotDetections',d),{ref},{bad}), ...
    'sixgr:phy:trs:InvalidPilotDisturbanceAuthority');
badRef=ref; badRef(indices(1))=NaN;
localReject(@()sixgr.phy.trs.scoreTRSPilotDisturbance(struct('SlotDetections',d),{badRef},{e}), ...
    'sixgr:phy:trs:MissingPilotDisturbanceSamples');
% No normalization may hide the wrong independent reference amplitude.
wrong=sixgr.phy.trs.scoreTRSPilotDisturbance(struct('SlotDetections',d),{2*ref},{e});
assert(wrong.IndependentPilotSNDR_dB<s.IndependentPilotSNDR_dB-10);
for r=1:2
    at=indices+(r-1)*12*14;
    d.RxGrid(at)=ref(at).*d.ReferenceSymbols;
end
exact=sixgr.phy.trs.scoreTRSPilotDisturbance(struct('SlotDetections',d),{ref},{e});
assert(exact.IndependentPilotDisturbanceEnergy==0 && isinf(exact.IndependentPilotSNDR_dB));
ok=true; fprintf('TRS_INDEPENDENT_PILOT_DISTURBANCE_PASS\n');
end
function localReject(f,identifier)
try
    f(); error('test:GuardBypassed','Expected strict evidence rejection.');
catch cause
    assert(strcmp(cause.identifier,identifier),'%s',cause.identifier);
end
end
