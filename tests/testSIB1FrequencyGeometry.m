function ok=testSIB1FrequencyGeometry()
% Original n40 frequency IEs, real UPER, and physical installation bounds.
source=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(source,tempdir);
tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
serv=tree.message.c1.systemInformationBlockType1.servingCellConfigCommon;
assert(cfg.phy.carrier.NSizeGrid==51&&cfg.phy.carrier.SubcarrierSpacing==30);
assert(serv.downlinkConfigCommon.frequencyInfoDL.offsetToPointA==30);
assert(~isfield(serv.uplinkConfigCommon.frequencyInfoUL,'absoluteFrequencyPointA')&& ...
    ~isfield(serv.uplinkConfigCommon.frequencyInfoUL,'frequencyBandList'));
bits=sixgr.rrc.asn1.encodeSIB1UPER(tree);rx=sixgr.rrc.asn1.decodeSIB1UPER(bits);
assert(sixgr.rrc.asn1.compareSIB1Trees(tree,rx));
installed=sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,rx);
g=installed.UECommonCellConfiguration.PhysicalGeometry;
assert(g.Valid&&g.UL.SizeRB==51&&g.UL.StartRB==0&&g.UL.SubcarrierSpacing_kHz==30);
assert(installed.UECommonCellConfiguration.RACHConfigCommon.Msg1FrequencyStart==0);
% Point A follows the actual grid center convention. It is not a present
% TDD UL IE or a measured RF-frequency accuracy claim.
point=cfg.phy.fc_Hz-51*12*30e3/2;
assert(point==2340820000&&point/5e3==468164);
% Paired UL signals its own original UL Point A, not the DL center.
paired=cfg;paired.phy.duplex.mode="FDD";
paired.phy.duplex.fdd.ulCenterFrequencyHz=1750e6;
[~,ul]=sixgr.rrc.asn1.resolveSIB1FrequencyInfo(paired,3,30,51,1845e6);
assert(ul.absoluteFrequencyPointA==348164&&ul.frequencyBandList.freqBandIndicatorNR==3);
% Narrow BWP encoding/geometry is supported; this does not claim that the
% present cell PRACH receiver can retarget an independently narrower BWP.
narrow=rx;
for name=["downlinkConfigCommon","uplinkConfigCommon"]
    if name=="downlinkConfigCommon",bwp='initialDownlinkBWP';else,bwp='initialUplinkBWP';end
    narrow.message.c1.systemInformationBlockType1.servingCellConfigCommon.(name).(bwp).genericParameters.locationAndBandwidth= ...
        sixgr.bwop.RIVFDRA.encode(275,5,40);
end
g=sixgr.rrc.asn1.validateSIB1PhysicalGeometry(narrow,cfg);
assert(g.UL.StartRB==5&&g.UL.SizeRB==40);
bad=rx;bad.message.c1.systemInformationBlockType1.servingCellConfigCommon. ...
    uplinkConfigCommon.initialUplinkBWP.genericParameters.locationAndBandwidth=sixgr.bwop.RIVFDRA.encode(275,0,106);
mustReject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,bad),'sixgr:rrc:asn1:BWPOutsideCarrier');
bad=rx;bad.message.c1.systemInformationBlockType1.servingCellConfigCommon. ...
    uplinkConfigCommon.initialUplinkBWP.genericParameters.subcarrierSpacing="kHz15";
mustReject(@()sixgr.rrc.asn1.validateSIB1PhysicalGeometry(bad,cfg),'sixgr:rrc:asn1:BWPWithoutCarrierSCS');
bad=rx;bad.message.c1.systemInformationBlockType1.servingCellConfigCommon. ...
    uplinkConfigCommon.frequencyInfoUL.absoluteFrequencyPointA=470000;
% Syntax decoding preserves a received erroneous field. It cannot become
% an installed TDD configuration or be silently stripped from the wire.
badbits=sixgr.rrc.asn1.encodeSIB1UPER(bad);bad=sixgr.rrc.asn1.decodeSIB1UPER(badbits);
assert(bad.message.c1.systemInformationBlockType1.servingCellConfigCommon. ...
    uplinkConfigCommon.frequencyInfoUL.absoluteFrequencyPointA==470000);
mustReject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,bad),'sixgr:rrc:asn1:TDDULFrequencyPresence');
changed=cfg;changed.rrc.sib1.offset_to_point_a=0;
mustReject(@()sixgr.rrc.asn1.buildBCCHDLSCHMessage(changed),'sixgr:rrc:asn1:SSBPointAMismatch');
ok=true;disp('SIB1_FREQUENCY_GEOMETRY_PASS n40_51PRB_30kHz TDD_optional_absent actual_UPER=1 RF_execution=0');
end
function mustReject(action,id)
actual="";try,action();catch ex,actual=string(ex.identifier);end
assert(actual==id,'Expected %s, observed %s.',id,actual);
end
