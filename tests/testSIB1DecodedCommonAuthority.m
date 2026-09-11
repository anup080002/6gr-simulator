function ok = testSIB1DecodedCommonAuthority()
% Actual UPER must preserve allocation, numerology and common-control IEs.
setup6GRSimToolkit('Verbose',false);
cfg = sixgr.config.defaultConfig();
cfg.frequency.band_name = 'n77';
cfg.phy.carrier.NSizeGrid = 25;
cfg.phy.carrier.SubcarrierSpacing = 15;
cfg.phy.prach.configurationIndex = 157;
cfg.phy.prach.preambleFormat = 'B4';
cfg.phy.prach.subcarrierSpacing_kHz = 30;
tree = sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
received = sixgr.rrc.asn1.decodeSIB1UPER(sixgr.rrc.asn1.encodeSIB1UPER(tree));
[installed, evidence] = sixgr.mac.ra.installDecodedSIB1RACHConfig(struct(), received);
assert(installed.random_access.initial_ul_bwp_size == 25);
assert(installed.random_access.initial_ul_bwp_start == 0);
assert(installed.UECommonCellConfiguration.InitialULBWP.SubcarrierSpacing_kHz == 15);
assert(installed.UECommonCellConfiguration.RACHConfigCommon.PRACHSubcarrierSpacing_kHz == 30);
assert(~installed.UECommonCellConfiguration.PDCCHConfigCommonPresent);
assert(isempty(fieldnames(installed.UECommonCellConfiguration.PUSCHConfigCommon)));
assert(isempty(fieldnames(installed.UECommonCellConfiguration.PUCCHConfigCommon)));
assert(~installed.UECommonCellConfiguration.PUCCHConfigCommonPresent);
assert(~isfield(installed.random_access,'pucch_common_resource'));
assert(~any(contains(evidence.ValidationStatus,'decoded_anchor_profile')));
serv = received.message.c1.systemInformationBlockType1.servingCellConfigCommon;
assert(~isfield(serv,'dmrs_TypeA_Position'));
assert(~isfield(serv.downlinkConfigCommon.initialDownlinkBWP,'pdcch_ConfigCommon'));

% Distinct, shifted BWPs and mixed PRACH/data numerology must survive the
% actual codec, not be reconstructed from carrier bandwidth at the UE.
cfg.phy.carrier.NSizeGrid = 106;
cfg.initial_access.sib1.initial_ul_bwp = struct('start_rb',7,'size_rb',52,'scs_khz',15);
cfg.initial_access.sib1.initial_dl_bwp = struct('start_rb',12,'size_rb',48,'scs_khz',30);
common = localCommon();
cfg.initial_access.sib1.pdcch_config_common = common;
cfg.initial_access.sib1.pucch_config_common = localPUCCHCommon();
tree = sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
bits = sixgr.rrc.asn1.encodeSIB1UPER(tree);
received = sixgr.rrc.asn1.decodeSIB1UPER(bits);
assert(sixgr.rrc.asn1.compareSIB1Trees(tree, received));
assert(isequal(bits, sixgr.rrc.asn1.encodeSIB1UPER(received)));
% Scalar MATLAB strings and char scalars are the same ASN.1 string value,
% and a singleton SEQUENCE OF is still a list. Preserve real differences.
representation = tree;
representation.message.c1.systemInformationBlockType1.servingCellConfigCommon. ...
    downlinkConfigCommon.initialDownlinkBWP.pdcch_ConfigCommon. ...
    commonSearchSpaceList.searchSpaceType = "common";
assert(sixgr.rrc.asn1.compareSIB1Trees(representation,received));
space=representation.message.c1.systemInformationBlockType1.servingCellConfigCommon. ...
    downlinkConfigCommon.initialDownlinkBWP.pdcch_ConfigCommon.commonSearchSpaceList;
representation.message.c1.systemInformationBlockType1.servingCellConfigCommon. ...
    downlinkConfigCommon.initialDownlinkBWP.pdcch_ConfigCommon.commonSearchSpaceList={space};
assert(sixgr.rrc.asn1.compareSIB1Trees(representation,received));
representation.message.c1.systemInformationBlockType1.servingCellConfigCommon. ...
    downlinkConfigCommon.initialDownlinkBWP.pdcch_ConfigCommon.ra_SearchSpace=2;
assert(~sixgr.rrc.asn1.compareSIB1Trees(representation,received));
installed = sixgr.mac.ra.installDecodedSIB1RACHConfig(struct(), received);
ue = installed.UECommonCellConfiguration;
assert(ue.InitialULBWP.StartRB == 7 && ue.InitialULBWP.SizeRB == 52);
assert(ue.InitialDLBWP.StartRB == 12 && ue.InitialDLBWP.SizeRB == 48);
assert(ue.InitialDLBWP.SubcarrierSpacing_kHz == 30 && ue.InitialULBWP.SubcarrierSpacing_kHz == 15);
assert(ue.PDCCHConfigCommonPresent && ue.PDCCHConfigCommon.ra_SearchSpace == 1);
assert(ue.PDCCHConfigCommon.commonControlResourceSet.duration == 2);
assert(isequal(double(ue.PDCCHConfigCommon.commonSearchSpaceList.nrofCandidates(:).'),[0 0 1 0 0]));
assert(ue.PUCCHConfigCommonPresent);
assert(ue.PUCCHConfigCommon.pucch_ResourceCommon == 0);
assert(string(ue.PUCCHConfigCommon.pucch_GroupHopping) == "neither");
assert(ue.PUCCHConfigCommon.hoppingId == 1);
assert(ue.PUCCHConfigCommon.p0_nominal == -90);
assert(installed.random_access.pucch_common_resource == 0);
assert(string(installed.random_access.pucch_group_hopping) == "neither");
assert(installed.random_access.pucch_hopping_id == 1);
assert(installed.random_access.pucch_p0_nominal_dbm == -90);

% Exercise both type-1 RIV branches and offsets independent of duplex.
for allocation = [0 25; 7 52; 2 273; 0 275; 100 175; 274 1].'
    cfg.initial_access.sib1.initial_ul_bwp.start_rb = allocation(1);
    cfg.initial_access.sib1.initial_ul_bwp.size_rb = allocation(2);
    tree = sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
    received = sixgr.rrc.asn1.decodeSIB1UPER(sixgr.rrc.asn1.encodeSIB1UPER(tree));
    installed = sixgr.mac.ra.installDecodedSIB1RACHConfig(struct(), received);
    assert(installed.random_access.initial_ul_bwp_start == allocation(1));
    assert(installed.random_access.initial_ul_bwp_size == allocation(2));
end

function common = localPUCCHCommon()
common = struct('pucch_ResourceCommon',0, ...
    'pucch_GroupHopping','neither','hoppingId',1,'p0_nominal',-90);
end
ok = true;
disp('SIB1_DECODED_COMMON_AUTHORITY_PASS');
end

function common = localCommon()
common = struct('commonControlResourceSet', struct( ...
    'controlResourceSetId',1, 'frequencyDomainResources',char("1111" + string(repmat('0',1,41))), ...
    'duration',2, 'cce_REG_MappingType','nonInterleaved', 'precoderGranularity','sameAsREG-bundle'), ...
    'commonSearchSpaceList',struct('searchSpaceId',1,'controlResourceSetId',1, ...
    'monitoringSlotPeriodicityAndOffset',struct('periodicity','sl2','offset',1), ...
    'monitoringSymbolsWithinSlot','10000000000000','nrofCandidates',[0 0 1 0 0], ...
    'searchSpaceType','common'), 'ra_SearchSpace',1);
end
