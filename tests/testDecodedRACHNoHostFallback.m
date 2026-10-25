function testDecodedRACHNoHostFallback
% Semantic installation only: no received waveform or PRACH validity claim.
cfg=sixgr.config.defaultConfig();
tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
host=struct('random_access',struct('frequency_start',99, ...
    'preamble_received_target_power_dbm',-60,'restricted_set','RestrictedSetTypeB'));
[installed,rows]=sixgr.mac.ra.installDecodedSIB1RACHConfig(host,tree);
r=tree.message.c1.systemInformationBlockType1.servingCellConfigCommon. ...
    uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon;
assert(installed.random_access.frequency_start==r.msg1FrequencyStart);
assert(installed.random_access.preamble_received_target_power_dbm==r.preambleReceivedTargetPower_dBm);
assert(string(installed.random_access.restricted_set)==string(r.restrictedSet));
assert(any(rows.Parameter=="frequency_start" & rows.ValidationStatus=="decoded"));
absent=tree;
absent.message.c1.systemInformationBlockType1.servingCellConfigCommon. ...
    uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon=rmfield(r,'nPreambles');
host.random_access.preamble_count=12;
[defaults,defaultRows]=sixgr.mac.ra.installDecodedSIB1RACHConfig(host,absent);
assert(defaults.random_access.preamble_count==64);
assert(any(defaultRows.Parameter=="preamble_count" & ...
    defaultRows.ValidationStatus=="standard_default_absent_decoded_operand"));
odd=tree;
odd.message.c1.systemInformationBlockType1.servingCellConfigCommon. ...
    uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon.preambleReceivedTargetPower_dBm=-95;
try
    sixgr.mac.ra.installDecodedSIB1RACHConfig(host,odd);
    error('test:ExpectedInvalidPower','Odd received target power was accepted.');
catch cause
    assert(strcmp(cause.identifier,'sixgr:mac:ra:InvalidDecodedRACHTargetPower'));
end
fields=["configurationIndex","rootSequenceIndex","zeroCorrelationZoneConfig", ...
    "restrictedSet","msg1FDM","msg1FrequencyStart", ...
    "preambleReceivedTargetPower_dBm","powerRampingStep","preambleTransMax","raResponseWindow"];
for field=fields
    missing=tree;
    missing.message.c1.systemInformationBlockType1.servingCellConfigCommon. ...
        uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon=rmfield(r,field);
    for seed={struct(),host}
        rejected=false;
        try
            sixgr.mac.ra.installDecodedSIB1RACHConfig(seed{1},missing);
        catch cause
            assert(strcmp(cause.identifier,'sixgr:mac:ra:MissingDecodedRACHOperand'), ...
                'Unexpected rejection for %s: %s',field,cause.identifier);
            rejected=true;
        end
        assert(rejected,'Missing received %s must not be installed from host configuration.',field);
    end
end
assert(isequal(host.random_access.frequency_start,99));
missing=tree;
missing.message.c1.systemInformationBlockType1.servingCellConfigCommon. ...
    uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon=rmfield(r,'preambleFormat');
host.random_access.prach_format='B4';
reject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(host,missing), ...
    'sixgr:mac:ra:MissingDecodedPRACHFormatAnchor');
invalid={'powerRampingStep','dB2junk';'powerRampingStep','dB3'; ...
    'preambleTransMax','junkn10';'preambleTransMax','n9'; ...
    'raResponseWindow','sl10junk';'raResponseWindow','sl3'; ...
    'msg1FDM',2;'msg1FDM','n2';'msg1FDM',' two '};
for k=1:size(invalid,1)
    bad=tree;
    bad.message.c1.systemInformationBlockType1.servingCellConfigCommon. ...
        uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon.(invalid{k,1})=invalid{k,2};
    reject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(host,bad), ...
        'sixgr:mac:ra:InvalidDecodedRACHEnum');
end
% A present common PUCCH IE does not authorize absent optional host values.
pucch=tree;
pucch.message.c1.systemInformationBlockType1.servingCellConfigCommon. ...
    uplinkConfigCommon.initialUplinkBWP.pucch_ConfigCommon= ...
    struct('pucch_ResourceCommon',0,'pucch_GroupHopping','neither');
host.random_access.pucch_hopping_id=999;
host.random_access.pucch_p0_nominal_dbm=-50;
clean=sixgr.mac.ra.installDecodedSIB1RACHConfig(host,pucch);
assert(~isfield(clean.random_access,'pucch_hopping_id'));
assert(~isfield(clean.random_access,'pucch_p0_nominal_dbm'));
fprintf('DECODED_RACH_NO_HOST_FALLBACK_PASS semantic_installation_only PHY=0\n');
end

function reject(fn,id)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s.',id,cause.identifier);
    return;
end
error('test:ExpectedRejection','Expected %s.',id);
end
