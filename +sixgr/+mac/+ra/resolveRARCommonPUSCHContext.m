function context=resolveRARCommonPUSCHContext(cfg)
% Preserve common PUSCH IE authority for RAR TDRA interpretation.
% This is a configuration binding, never proof of received SI or a grant.
ue=sixgr.util.structGet(cfg,'UECommonCellConfiguration',struct());
gnb=sixgr.util.structGet(cfg,'GNBCommonCellConfiguration',struct());
id='sixgr:mac:ra:RARCommonPUSCHAuthority';
assert(isempty(fieldnames(ue))||isempty(fieldnames(gnb)),id, ...
    'Do not mix authored gNB and decoded UE common configuration.');
carrier=sixgr.phy.grid.makeCarrier(cfg);
if ~isempty(fieldnames(ue))
    required={'Source','PUSCHConfigCommon','PUSCHConfigCommonPresent','InitialULBWP', ...
        'PayloadHash','TreeHash','ConfigurationEpoch'};
    assert(isstruct(ue)&&isscalar(ue)&&all(isfield(ue,required)) && ...
        string(ue.Source)=="decoded_sib1",id,'The UE common context must retain its original decoded source and complete IE/clock identity.');
    common=ue.PUSCHConfigCommon;present=ue.PUSCHConfigCommonPresent;bwp=ue.InitialULBWP;
    source="original_received_SIB1_PUSCH_ConfigCommon";
    identity=struct('PayloadHash',string(ue.PayloadHash),'TreeHash',string(ue.TreeHash), ...
        'ConfigurationEpoch',ue.ConfigurationEpoch);
    for n=["PayloadHash","TreeHash"]
        assert(~isempty(regexp(char(identity.(n)),'^[0-9a-fA-F]{64}$','once')),id, ...
            'Received common authority requires original nonempty payload/tree digests.');
    end
elseif ~isempty(fieldnames(gnb))
    assert(isstruct(gnb)&&isscalar(gnb) && ...
        all(isfield(gnb,{'ConfigurationSource','PUSCHConfigCommon','PUSCHConfigCommonPresent','InitialULBWP','CellCalendarSHA256'})) && ...
        gnb.ConfigurationSource=="original_gNB_common_configuration", ...
        id,'The gNB must use its original authored common UL IE and calendar.');
    common=gnb.PUSCHConfigCommon;present=gnb.PUSCHConfigCommonPresent;bwp=gnb.InitialULBWP;
    source="original_gNB_authored_SIB1_PUSCH_ConfigCommon";
    identity=struct('CellCalendarSHA256',string(gnb.CellCalendarSHA256));
else
    common=sixgr.util.structGet(cfg,'initial_access.sib1.pusch_config_common',struct());
    present=~isempty(fieldnames(common));
    bwp=struct('StartRB',double(carrier.NStartGrid),'SizeRB',double(carrier.NSizeGrid), ...
        'SubcarrierSpacing_kHz',double(carrier.SubcarrierSpacing),'CyclicPrefix',string(carrier.CyclicPrefix));
    source="declared_common_configuration_not_received_SIB1";
    identity=struct('CommonIESHA256',localHash(common));
end
assert(islogical(present)&&isscalar(present)&&isstruct(common)&&isscalar(common) && ...
    (present||isempty(fieldnames(common))),id,'Preserve original common IE presence.');
assert(bwp.StartRB==carrier.NStartGrid&&bwp.SizeRB==carrier.NSizeGrid && ...
    bwp.SubcarrierSpacing_kHz==carrier.SubcarrierSpacing && ...
    string(bwp.CyclicPrefix)==string(carrier.CyclicPrefix), ...
    'sixgr:mac:ra:RARInitialULBWPUnsupported', ...
    'The supported RAR FDRA receiver requires an initial UL BWP aligned to the physical carrier.');
[timing,common]=sixgr.rrc.asn1.resolvePUSCHConfigCommon(common,bwp.SubcarrierSpacing_kHz);
context=struct('ContractVersion',"RAR_common_PUSCH_configuration/v1", ...
    'Source',source,'Identity',identity,'CommonIEPresent',present, ...
    'OriginalIE',common,'Timing',timing,'InitialULBWP',bwp);
context.SHA256=localHash(context);
end
function h=localHash(v)
h=string(sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(v))));
end
