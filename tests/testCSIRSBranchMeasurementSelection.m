function ok=testCSIRSBranchMeasurementSelection()
% Analytical measurement-record fixtures, not simulated RF/CSI observations.
m=struct('Available',true,'RSRPPerAntenna_dBm',[-80 -83], ...
    'RSSIPerAntenna_dBm',[-57 -64],'RSRQPerAntenna_dB',[-13 -9], ...
    'NumReceiveAntennas',2,'NumRB',10,'Source',"analytical_branch_record_unit_fixture");
s=sixgr.phy.refsig.selectCSIRSBranchMeasurements(m);
assert(s.RSRP_dBm==-80 && s.RSRPReceiveBranch1Based==1 && s.RSSI_dBm==-57);
assert(s.RSRQ_dB==-9 && s.RSRQReceiveBranch1Based==2 && ...
    s.RSRQNumeratorRSRP_dBm==-83 && s.RSRQDenominatorRSSI_dBm==-64);
assert(s.RSRQ_dB>=max(m.RSRQPerAntenna_dB) && ...
    abs(s.RSRQ_dB-(10*log10(s.NumRB)+s.RSRQNumeratorRSRP_dBm-s.RSRQDenominatorRSSI_dBm))<1e-12);
assert(s.MeasurementSource==m.Source,'A unit record must not acquire a measured-PHY source label.');
for n=[1 4 8]
    q=m; q.NumReceiveAntennas=n;
    q.RSRPPerAntenna_dBm=repmat(-80,1,n);
    q.RSSIPerAntenna_dBm=repmat(-57,1,n);
    q.RSRQPerAntenna_dB=repmat(-13,1,n);
    t=sixgr.phy.refsig.selectCSIRSBranchMeasurements(q);
    assert(t.RSRP_dBm==-80 && t.RSSI_dBm==-57 && t.RSRQ_dB==-13, ...
        'Adding equal-power diversity branches must not invent a total-power RSSI gain.');
end
bad=m; bad.RSRQPerAntenna_dB(1)=-3;
reject(@()sixgr.phy.refsig.selectCSIRSBranchMeasurements(bad),'sixgr:phy:CSIRSBranchRSRQClosure');
bad=m; bad.RSSIPerAntenna_dBm(1)=NaN;
reject(@()sixgr.phy.refsig.selectCSIRSBranchMeasurements(bad),'sixgr:phy:CSIRSBranchMeasurementShape');
bad=m; bad.Available=false;
reject(@()sixgr.phy.refsig.selectCSIRSBranchMeasurements(bad),'sixgr:phy:CSIRSBranchMeasurementsUnavailable');
ok=true;
end
function reject(fn,id)
try, fn(); catch cause, assert(strcmp(cause.identifier,id),cause.message); return; end
error('test:ExpectedFailure','Expected %s.',id);
end
