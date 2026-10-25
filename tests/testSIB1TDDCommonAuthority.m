function ok=testSIB1TDDCommonAuthority()
% Actual generated-UPER round trips and received config installation.
% No radio reception, PRACH validity/association or scheduler claim.
setup6GRSimToolkit('Verbose',false);
root=fileparts(fileparts(mfilename('fullpath')));
band=sixgr.lls6g.config.readConfigFile(fullfile(root,'simulator','configs','bands','c4_20_4ghz_tdd.yaml'));
cfg=sixgr.config.defaultConfig();
cfg.frequency.band_name='n77';
cfg.phy.fc_Hz=4e9;
cfg.phy.carrier.SubcarrierSpacing=30;
cfg.phy.carrier.NSizeGrid=51;
cfg.phy.prach.configurationIndex=157;
cfg.phy.prach.preambleFormat='B4';
cfg.phy.prach.subcarrierSpacing_kHz=30;
cfg.phy.duplex.tddCommon=band.frame.tdd_common;
[received,bits,original]=roundtrip(cfg);
ie=original.message.c1.systemInformationBlockType1.servingCellConfigCommon.tdd_UL_DL_ConfigurationCommon;
assert(string(ie.referenceSubcarrierSpacing)=="kHz30" && ...
    string(ie.pattern1.dl_UL_TransmissionPeriodicity)=="ms2p5");
assert(ie.pattern1.nrofDownlinkSlots==3 && ie.pattern1.nrofDownlinkSymbols==10 && ...
    ie.pattern1.nrofUplinkSlots==1 && ie.pattern1.nrofUplinkSymbols==2 && ~isfield(ie,'pattern2'));
% A changed resolved YAML common policy changes actual wire bytes. The UE
% receives the old original payload here, not the changed transmitter map.
changed=cfg; changed.phy.duplex.tddCommon.Pattern1.NumDownlinkSymbols=9;
[changedRx,changedBits]=roundtrip(changed);
assert(~isequal(bits,changedBits));
[installed,evidence]=sixgr.mac.ra.installDecodedSIB1RACHConfig(changed,received);
common=installed.UECommonCellConfiguration;
assert(common.TDDConfigCommonPresent && sixgr.rrc.asn1.compareSIB1Trees(common.TDDConfigCommon,ie));
assert(isequaln(installed.phy.duplex.tddCommon,changed.phy.duplex.tddCommon));
expected=[repmat('D',3,14);[repmat('D',1,10) 'FFUU'];repmat('U',1,14)];
assert(isequal(common.TDDCommonRuntime.InitialULBWP.CommonDirection,expected));
assert(isequal(common.TDDCommonRuntime.InitialDLBWP.CommonDirection,expected));
assert(common.TDDCommonRuntime.InitialULBWP.AlignmentEpoch=="first_symbol_even_frame");
assert(any(evidence.Parameter=="tdd_ul_dl_config_common") && all(strlength(evidence.TreeHash)>0));
changedInstalled=sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,changedRx);
assert(changedInstalled.UECommonCellConfiguration.TDDConfigCommon.pattern1.nrofDownlinkSymbols==9);

% Explicit absence remains absent through real UPER, even when the caller
% retains a host common map or previously installed received configuration.
absent=cfg; absent.rrc.sib1.tdd_ul_dl_config_common=[];
[absentRx,absentBits]=roundtrip(absent);
assert(~isequal(bits,absentBits));
absentInstalled=sixgr.mac.ra.installDecodedSIB1RACHConfig(installed,absentRx);
c=absentInstalled.UECommonCellConfiguration;
assert(~c.TDDConfigCommonPresent && isempty(fieldnames(c.TDDConfigCommon)) && ...
    isempty(fieldnames(c.TDDCommonRuntime)) && ~isfield(absentInstalled.random_access,'tdd_ul_dl_config_common'));
assert(~absentInstalled.random_access.tdd_config_common_present);
fdd=cfg; fdd.phy.duplex.mode='FDD';
fddTree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(fdd);
assert(~isfield(fddTree.message.c1.systemInformationBlockType1.servingCellConfigCommon,'tdd_UL_DL_ConfigurationCommon'));

% Original base enum and v1530 remain distinct from their effective period;
% DL30/UL15 maps derive from the received BWP clocks, not the host carrier.
mixed=cfg; mixed.phy.duplex=struct('mode','TDD');
mixed.rrc.sib1.initial_dl_bwp=struct('start_rb',0,'size_rb',24,'scs_khz',30);
mixed.rrc.sib1.initial_ul_bwp=struct('start_rb',0,'size_rb',24,'scs_khz',15);
ext=struct('referenceSubcarrierSpacing',"kHz15", ...
    'pattern1',p("ms10",3,0,0,0),'pattern2',p("ms2",0,0,2,0));
ext.pattern1.dl_UL_TransmissionPeriodicity_v1530="ms3";
mixed.rrc.sib1.tdd_ul_dl_config_common=ext;
[rxExt,bitsExt]=roundtrip(mixed);
x=sixgr.mac.ra.installDecodedSIB1RACHConfig(changed,rxExt);
assert(sixgr.rrc.asn1.compareSIB1Trees(x.UECommonCellConfiguration.TDDConfigCommon,ext));
r=x.UECommonCellConfiguration.TDDCommonRuntime;
assert(r.EffectiveConfig.Pattern1.PeriodicityMilliseconds==3 && ...
    r.InitialULBWP.ActiveSlotsPerPattern==5 && r.InitialDLBWP.ActiveSlotsPerPattern==10);
assert(isequal(r.InitialULBWP.CommonDirection,[repmat('D',3,14);repmat('U',2,14)]));
assert(isequal(r.InitialDLBWP.CommonDirection,[repmat('D',6,14);repmat('U',4,14)]));
other=mixed; other.rrc.sib1.tdd_ul_dl_config_common.pattern1.dl_UL_TransmissionPeriodicity="ms0p5";
[~,otherBits]=roundtrip(other); assert(~isequal(otherBits,bitsExt));
% Same physical map is permitted with a differently represented base enum.
other.phy.duplex.tddCommon=struct('ReferenceSubcarrierSpacingKHz',15, ...
    'Pattern1',policy(3,3,0,0,0),'Pattern2',policy(2,0,0,2,0));
roundtrip(other);

% Extension ms4 without pattern2, and native extended-CP BWP mapping.
four=cfg; four.phy.duplex=struct('mode','TDD');
four.rrc.sib1.tdd_ul_dl_config_common=struct('referenceSubcarrierSpacing',"kHz30",'pattern1',p("ms0p5",4,0,4,0));
four.rrc.sib1.tdd_ul_dl_config_common.pattern1.dl_UL_TransmissionPeriodicity_v1530="ms4";
roundtrip(four);
extended=four; extended.rrc.sib1.tdd_ul_dl_config_common=struct('referenceSubcarrierSpacing',"kHz60",'pattern1',p("ms1",1,2,1,2));
for direction=["dl","ul"]
    extended.rrc.sib1.("initial_"+direction+"_bwp")=struct('start_rb',0,'size_rb',24,'scs_khz',60,'cyclic_prefix',"extended");
end
[rxExtended,~]=roundtrip(extended);
e=sixgr.mac.ra.installDecodedSIB1RACHConfig(struct(),rxExtended);
assert(e.UECommonCellConfiguration.TDDCommonRuntime.InitialULBWP.SymbolsPerSlot==12);

bad=cfg; bad.rrc.sib1.tdd_ul_dl_config_common=ie;
bad.rrc.sib1.tdd_ul_dl_config_common.pattern1.nrofDownlinkSymbols=9;
reject(@()sixgr.rrc.asn1.buildBCCHDLSCHMessage(bad),'sixgr:rrc:asn1:TDDCommonTransmitMismatch');
bad=mixed; bad.rrc.sib1.tdd_ul_dl_config_common.referenceSubcarrierSpacing="kHz30";
reject(@()sixgr.rrc.asn1.buildBCCHDLSCHMessage(bad),'sixgr:phy:frame:ReferenceSCSExceedsActiveBWPSCS');
bad=original; bad.message.c1.systemInformationBlockType1.servingCellConfigCommon.tdd_UL_DL_ConfigurationCommon=[];
reject(@()sixgr.rrc.asn1.encodeSIB1UPER(bad),'sixgr:rrc:asn1:InvalidTDDCommonIE');
bad=original; bad.message.c1.systemInformationBlockType1.servingCellConfigCommon.tdd_UL_DL_ConfigurationCommon.pattern1.nrofDownlinkSlots=true;
reject(@()sixgr.rrc.asn1.encodeSIB1UPER(bad),'sixgr:rrc:asn1:InvalidTDDPatternCount');
bad=original; bad.message.c1.systemInformationBlockType1.servingCellConfigCommon.tdd_UL_DL_ConfigurationCommon.pattern1.unknown=1;
reject(@()sixgr.rrc.asn1.encodeSIB1UPER(bad),'sixgr:rrc:asn1:UnsupportedTDDCommonField');
ok=true;
fprintf('PASS testSIB1TDDCommonAuthority: actual UPER/installation/presence and changed-policy authority; no PHY/PRACH claim.\n');
end

function [received,bits,tree]=roundtrip(cfg)
tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
[bits,tx]=sixgr.rrc.asn1.encodeSIB1UPER(tree);
[received,rx]=sixgr.rrc.asn1.decodeSIB1UPER(bits);
assert(sixgr.rrc.asn1.compareSIB1Trees(tree,received));
assert(string(tx.PayloadHash)==string(rx.PayloadHash));
assert(isequal(bits,sixgr.rrc.asn1.encodeSIB1UPER(received)));
end
function out=p(period,d,ds,u,us)
out=struct('dl_UL_TransmissionPeriodicity',period,'nrofDownlinkSlots',d, ...
    'nrofDownlinkSymbols',ds,'nrofUplinkSlots',u,'nrofUplinkSymbols',us);
end
function out=policy(period,d,ds,u,us)
out=struct('PeriodicityMilliseconds',period,'NumDownlinkSlots',d, ...
    'NumDownlinkSymbols',ds,'NumUplinkSlots',u,'NumUplinkSymbols',us);
end
function reject(fn,id)
try, fn(); catch cause
    assert(string(cause.identifier)==string(id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('testSIB1TDDCommonAuthority:MissingRejection','Expected %s.',id);
end
