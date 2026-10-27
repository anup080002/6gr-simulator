function evidence=validateSIB1PhysicalGeometry(msg,cfg)
% Installability is separate from lossless ASN.1 syntax decoding.
% TS 38.331 V18.8.0 BWP and FrequencyInfo{DL,UL}-SIB descriptions.
serv=msg.message.c1.systemInformationBlockType1.servingCellConfigCommon;
installed=sixgr.util.structGet(cfg,'phy.carrier',struct());
assert(all(isfield(installed,{'NSizeGrid','SubcarrierSpacing'})), ...
    'sixgr:rrc:asn1:MissingInstalledCarrier','Physical installation requires the original installed receiver carrier grid.');
duplex=string(sixgr.util.structGet(cfg,'phy.duplex.mode',""));
ul=serv.uplinkConfigCommon.frequencyInfoUL;
if duplex=="TDD"
    assert(~isfield(ul,'absoluteFrequencyPointA')&&~isfield(ul,'frequencyBandList'), ...
        'sixgr:rrc:asn1:TDDULFrequencyPresence','TS38.331 Cond FDD-OrSUL requires both UL frequency fields absent for TDD.');
elseif duplex=="FDD"
    assert(isfield(ul,'absoluteFrequencyPointA')&&isfield(ul,'frequencyBandList'), ...
        'sixgr:rrc:asn1:FDDULFrequencyMissing','Paired UL requires original Point A and band IEs.');
else
    error('sixgr:rrc:asn1:MissingInstalledCarrier','Original receiver duplex context is required.');
end
evidence=struct('Reference',"TS38.331_V18.8.0_BWP_FrequencyInfo_SCS_SpecificCarrier", ...
    'Scope',"received_IE_bounds_against_installed_carrier_not_RF_frequency_accuracy", ...
    'RFReferencePointQualified',false);
for direction=["DL","UL"]
    if direction=="DL",common=serv.downlinkConfigCommon;bwp=common.initialDownlinkBWP;freq=common.frequencyInfoDL;
    else,common=serv.uplinkConfigCommon;bwp=common.initialUplinkBWP;freq=common.frequencyInfoUL;end
    carriers=freq.scs_SpecificCarrierList;
    scs=str2double(erase(string(bwp.genericParameters.subcarrierSpacing),"kHz"));
    scss=arrayfun(@(x) str2double(erase(string(x.subcarrierSpacing),"kHz")),carriers);
    match=find(scss==scs);
    assert(numel(match)==1,'sixgr:rrc:asn1:BWPWithoutCarrierSCS', ...
        'The initial %s BWP requires one original SCS-SpecificCarrier at its own numerology.',direction);
    c=carriers(match);[start,count]=sixgr.bwop.RIVFDRA.decode(275,bwp.genericParameters.locationAndBandwidth);
    assert(start>=0&&count>0&&start+count<=c.carrierBandwidth, ...
        'sixgr:rrc:asn1:BWPOutsideCarrier','Initial %s BWP interval [%g,%g) exceeds its %g-PRB carrier.',direction,start,start+count,c.carrierBandwidth);
    carrierStart=double(c.offsetToCarrier);carrierCount=double(c.carrierBandwidth);
    assert(scs==installed.SubcarrierSpacing&&carrierCount==installed.NSizeGrid&& ...
        carrierStart==sixgr.util.structGet(installed,'NStartGrid',0), ...
        'sixgr:rrc:asn1:ReceivedCarrierGridMismatch', ...
        'Original received %s carrier geometry differs from the installed physical grid; do not coerce it.',direction);
    evidence.(direction)=struct('StartRBRelativeToCarrier',start,'StartRB',carrierStart+start, ...
        'SizeRB',count,'SubcarrierSpacing_kHz',scs,'CarrierStartRB',carrierStart,'CarrierSizeRB',carrierCount);
end
if duplex=="TDD"
    assert(evidence.DL.StartRB+evidence.DL.SizeRB/2==evidence.UL.StartRB+evidence.UL.SizeRB/2, ...
        'sixgr:rrc:asn1:TDDInitialBWPCenterMismatch', ...
        'The initial TDD BWP pair must share its physical center frequency.');
end
evidence.Valid=true;
end
