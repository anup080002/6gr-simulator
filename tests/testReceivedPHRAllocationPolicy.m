function ok=testReceivedPHRAllocationPolicy()
% Quantized interval resource-policy arithmetic, not physical power accuracy.
cfg.phy.mac.uplinkControl=struct('Enabled',true,'PHRAllocationPolicy',"constant_terms_quantized_lower_bound",'PHRAllocationMargin_dB',1);
cfg.phy.carrier.SubcarrierSpacing=30;
cfg.phy.pusch.powerControl=struct('p0PUSCH_dBm',-80,'alpha',1,'deltaTF_dB',0,'adjustmentMode','accumulated');
a=struct('NumPRB',40,'SubcarrierSpacing',30,'SymbolAllocation',[0 10], ...
    'MCSIndex',1,'MCSTable',"qam64_table1",'NumLayers',4, ...
    'PowerConfigurationSHA256',sixgr.l2.mac.MACHash.of(cfg.phy.pusch.powerControl));
[~,~,~,r]=sixgr.l2.mac.BSR_PHR.decodeSingleEntryPHR( ...
    sixgr.l2.mac.BSR_PHR.encodeSingleEntryPHR(-2,23,false));
r.ReferenceAllocation=a; r.ReceiptSHA256="original_received_report";
ue.ReceivedPHREvidence=struct('Usable',true,'Reason',"original_received_quantized_interval",'Report',r);
m=struct('MCSIndex',1,'MCSTable',"qam64_table1");
[prbs,e]=sixgr.l2.mac.receivedPHRAllocationLimit(cfg,ue,0:50,[0 10],m,4);
assert(e.Applied&&numel(prbs)==floor(40*10^(-3/10))&&e.PHLowerBound_dB==-2&& ...
    e.ReceiptSHA256==r.ReceiptSHA256&&contains(e.Assumption,"not_independently_measured"));
for change=1:5
    bad=cfg; v=ue; rank=4; mm=m; symbols=[0 10];
    switch change
        case 1, bad.phy.pusch.powerControl.alpha=.8;
        case 2, mm.MCSIndex=2;
        case 3, rank=2;
        case 4, symbols=[0 9];
        case 5, v.ReceivedPHREvidence.Report.PowerBackoff=true;
    end
    [p,e]=sixgr.l2.mac.receivedPHRAllocationLimit(bad,v,0:50,symbols,mm,rank);
    assert(~e.Applied&&isequal(p,0:50));
end
ue.ReceivedPHREvidence.Usable=false; ue.ReceivedPHREvidence.Reason="received_phr_not_yet_available";
[p,e]=sixgr.l2.mac.receivedPHRAllocationLimit(cfg,ue,0:50,[0 10],m,4);
assert(~e.Applied&&e.Status=="received_phr_not_yet_available"&&numel(p)==51);
ue.ReceivedPHREvidence.Usable=true; ue.ReceivedPHREvidence.Report.PHRange_dB=[-Inf -32];
[~,e]=sixgr.l2.mac.receivedPHRAllocationLimit(cfg,ue,0:50,[0 10],m,4); assert(~e.Applied);
ue.ReceivedPHREvidence.Report.PHRange_dB=[-32 -31];
[p,e]=sixgr.l2.mac.receivedPHRAllocationLimit(cfg,ue,0:50,[0 10],m,4);
assert(e.Applied&&isempty(p),'Do not fabricate a one-PRB grant when the explicit cap is zero.');
ok=true;
end
