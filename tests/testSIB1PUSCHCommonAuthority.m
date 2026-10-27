function ok=testSIB1PUSCHCommonAuthority()
% Actual UPER -> original tree -> installed common timing/power; no RF claim.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig();
cfg.phy.carrier.SubcarrierSpacing=30;
cfg.phy.carrier.NSizeGrid=51;
cfg.phy.channelBandwidth_MHz=20;
cfg.frequency.bandwidth_hz=20e6;
row=struct('k2',4,'mappingType',"typeA",'startSymbolAndLength',27);
common=struct('groupHoppingEnabledTransformPrecoding',"enabled", ...
    'pusch_TimeDomainAllocationList',row,'msg3_DeltaPreamble',-1,'p0_NominalWithGrant',-100);
cfg.rrc.sib1.pusch_config_common=common;
tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
[bits,enc]=sixgr.rrc.asn1.encodeSIB1UPER(tree);
[rx,dec]=sixgr.rrc.asn1.decodeSIB1UPER(bits);
[same,cmp]=sixgr.rrc.asn1.compareSIB1Trees(tree,rx);
assert(same && enc.PayloadHash==dec.PayloadHash && cmp.TxTreeHash==cmp.RxTreeHash);
received=rx.message.c1.systemInformationBlockType1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.pusch_ConfigCommon;
assert(isequaln(received,common),'Actual common IE operands must survive the decoder.');
e=struct('SIB1RxTree',rx,'SIB1PayloadHashRx',dec.PayloadHash,'SIB1RxTreeHash',cmp.RxTreeHash);
[installed,~]=sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,e);
c=installed.UECommonCellConfiguration;
assert(c.PUSCHConfigCommonPresent && c.PUSCHCommonTiming.Available && ...
    isequal(c.PUSCHConfigCommon,received) && c.PUSCHCommonTiming.K2Slots==4 && ...
    c.PUSCHCommonTiming.K2Present && c.PUSCHCommonTiming.TreeHash==cmp.RxTreeHash && ...
    c.PUSCHCommonTiming.PayloadHash==dec.PayloadHash && ...
    installed.random_access.pusch_common_msg3_delta_preamble==-2);
% Do not default a missing list. A missing k2 inside a received row does
% have a normative BWP-numerology-dependent default, retained separately.
for scs=[15 30 60 120]
    absent=rmfield(row,'k2');
    t=sixgr.rrc.asn1.resolvePUSCHConfigCommon(struct('pusch_TimeDomainAllocationList',absent),scs);
    assert(t.Available && ~t.K2Present && t.K2Slots==1+(scs==60)+2*(scs==120) && ...
        t.K2Source=="standard_default_absent_k2_field");
end
for value={struct(),struct('msg3_DeltaPreamble',6)}
    next=cfg; next.rrc.sib1.pusch_config_common=value{1};
    original=sixgr.rrc.asn1.buildBCCHDLSCHMessage(next);
    decoded=sixgr.rrc.asn1.decodeSIB1UPER(sixgr.rrc.asn1.encodeSIB1UPER(original));
    assert(sixgr.rrc.asn1.compareSIB1Trees(original,decoded));
    timing=sixgr.rrc.asn1.resolvePUSCHConfigCommon(value{1},30);
    assert(~timing.Available);
end
cfg.rrc.sib1=rmfield(cfg.rrc.sib1,'pusch_config_common');
absent=sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
decoded=sixgr.rrc.asn1.decodeSIB1UPER(sixgr.rrc.asn1.encodeSIB1UPER(absent));
assert(~isfield(decoded.message.c1.systemInformationBlockType1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP,'pusch_ConfigCommon'));
bad=common; bad.p0_NominalWithGrant=-99;
localReject(@()sixgr.rrc.asn1.resolvePUSCHConfigCommon(bad,30));
bad=common; bad.pusch_TimeDomainAllocationList.k2=33;
localReject(@()sixgr.rrc.asn1.resolvePUSCHConfigCommon(bad,30));
bad=common; bad.unknown=1;
localReject(@()sixgr.rrc.asn1.resolvePUSCHConfigCommon(bad,30));
ok=true;
end
function localReject(f)
observed=""; try, f(); catch ME, observed=string(ME.identifier); end
assert(observed=="sixgr:rrc:asn1:UnsupportedSIB1IE",'Malformed common fields must fail closed.');
end
