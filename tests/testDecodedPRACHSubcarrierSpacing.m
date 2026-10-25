function testDecodedPRACHSubcarrierSpacing()
% Semantic numerology boundary only; no PHY or table-decoder qualification.
f=@sixgr.mac.ra.resolveDecodedPRACHSubcarrierSpacing;
for format=["0","1","2","3"]
    r=struct('preambleFormat',format);
    expected=1.25; if format=="3", expected=5; end
    [scs,source]=f(r); assert(scs==expected && source=="decoded_index_derived_long_format_spacing");
    r.msg1SubcarrierSpacing_kHz=expected; assert(f(r)==expected);
    r.msg1SubcarrierSpacing_kHz=30; reject(@()f(r),'InvalidDecodedPRACHSpacing');
end
for format=["A1","B4","C2","A1/B1"]
    r=struct('preambleFormat',format);
    reject(@()f(r),'MissingDecodedPRACHSpacing');
    for scs=[15 30 60 120]
        r.msg1SubcarrierSpacing_kHz=scs;
        [actual,source]=f(r); assert(actual==scs && source=="decoded_short_msg1_subcarrier_spacing");
    end
    for bad={NaN,[],[15 30],"30",true,1.25,5}
        r.msg1SubcarrierSpacing_kHz=bad{1}; reject(@()f(r),'InvalidDecodedPRACHSpacing');
    end
end
% Actual installation must not borrow a contradictory host/BWP SCS.
cfg=sixgr.config.defaultConfig(); tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
s=tree.message.c1.systemInformationBlockType1.servingCellConfigCommon;
r=s.uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon;
r.preambleFormat="0"; r.configurationIndex=16;
r=rmfield(r,'msg1SubcarrierSpacing_kHz');
s.uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon=r;
s.uplinkConfigCommon.initialUplinkBWP.genericParameters.subcarrierSpacing="kHz30";
tree.message.c1.systemInformationBlockType1.servingCellConfigCommon=s;
cfg.random_access.subcarrier_spacing_khz=60;
[installed,rows]=sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,tree);
assert(installed.random_access.subcarrier_spacing_khz==1.25);
assert(any(rows.Parameter=="subcarrier_spacing_khz" & rows.ValidationStatus=="decoded_index_derived_long_format_spacing"));
r.preambleFormat="B4"; s.uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon=r;
tree.message.c1.systemInformationBlockType1.servingCellConfigCommon=s;
reject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,tree),'MissingDecodedPRACHSpacing');
fprintf('DECODED_PRACH_SPACING_PASS semantic_installation_only PHY=0\n');
end
function reject(fn,suffix)
try
    fn();
catch cause
    assert(endsWith(string(cause.identifier),suffix),'Expected %s, got %s',suffix,cause.identifier);
    return;
end
error('test:ExpectedRejection','Expected %s',suffix);
end
