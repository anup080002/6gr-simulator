function ok=testRARCommonTDRAAuthority()
% Actual SIB1 UPER codec/install + RAR bits, no RF/access-completion claim.
[~,f]=testCellRARTransmissionContext();
[received,common,receipt]=decodedN40MACCommonCodecFixture(f.Config,1,1);
rxCommon=sixgr.mac.ra.resolveRARCommonPUSCHContext(received);
tx=f.RAContext;rx=tx;rx.PUSCHCommonContext=rxCommon;
assert(tx.PUSCHCommonContext.Source=="original_gNB_authored_SIB1_PUSCH_ConfigCommon" && ...
    rxCommon.Source=="original_received_SIB1_PUSCH_ConfigCommon" && ...
    rxCommon.Identity.PayloadHash==receipt.PayloadHash && ...
    rxCommon.Identity.TreeHash==receipt.TreeHash && common.InitialULBWP.SizeRB==51);
g=sixgr.mac.ra.buildRARULGrant(tx);
assert(g.TimeResourceAssignment==0&&g.K2==4&&g.Msg3AdditionalDelaySlots==3 && ...
    g.SymbolStart==0&&g.NumSymbols==11&&g.MappingType=="A" && ...
    g.TimeDomainAllocation.SourceKind=="original_common_PUSCH_tdra_list" && ...
    isequal(g.BitVector(16:19),zeros(4,1,'int8')) && ...
    tx.Msg3Slot==tx.Msg2Slot+7 && f.Config.random_access.timing.msg3_k2_slots==4);
wire=sixgr.mac.ra.encodeMACRAR('RAPID',7,'TimingAdvanceCommand',28, ...
    'TemporaryCRNTI',4660,'ULGrant',g);
% Contradict the producer's selected MCS/index; only received RAR bits and
% the actual common list determine the receiver allocation.
rx.Msg3PUSCH.MCS=15;rx.RARGrantConfig.time_resource_assignment=1;
r=sixgr.mac.ra.decodeMACRAR(wire.Bytes,rx);
assert(r.ULGrant.MCS==g.MCS&&r.ULGrant.TimeResourceAssignment==0 && ...
    r.ULGrant.K2==4&&r.ULGrant.NumSymbols==11 && ...
    r.ULGrant.TimeDomainAllocation.CommonContextSHA256==rxCommon.SHA256);
bad=tx;bad.Msg3PUSCH.NumSymbols=14;
reject(@()sixgr.mac.ra.buildRARULGrant(bad),'sixgr:mac:ra:RARTDRAAllocationMismatch');
bad=tx;bad.RARGrantConfig.time_resource_assignment=1;
reject(@()sixgr.mac.ra.buildRARULGrant(bad),'sixgr:mac:ra:RARCommonTDRAIndexOutOfRange');
bits=g.BitVector;bits(19)=1;
reject(@()sixgr.mac.ra.RARULGrantCodec.decode(bits,rx),'sixgr:mac:ra:RARCommonTDRAIndexOutOfRange');
bad=rx;bad.PUSCHCommonContext.Timing.K2Slots=9;
reject(@()sixgr.mac.ra.RARULGrantCodec.decode(g.BitVector,bad),'sixgr:mac:ra:RARCommonPUSCHAuthority');
badcfg=f.Config;badcfg.random_access.timing.msg3_k2_slots=1;
reject(@()sixgr.truth.buildCellRARTransmissionContext(badcfg,f.Calendar,f.DeclaredReceiverReceipt), ...
    'sixgr:phy:ia:RARConfiguredK2Mismatch');
declared=f.Config;
declared.initial_access.sib1.pusch_config_common.pusch_TimeDomainAllocationList= ...
    struct('mappingType',"typeA",'startSymbolAndLength',69);
c=sixgr.mac.ra.resolveRARCommonPUSCHContext(declared);
a=sixgr.mac.ra.resolveRARTimeDomainAllocation(0,30,"normal",c);
assert(a.K2==1&&~a.K2FieldPresent&&a.K2Source=="standard_default_absent_k2_field" && ...
    a.Msg3AdditionalDelaySlots==3);
absent=declared;absent.initial_access.sib1=rmfield(absent.initial_access.sib1,'pusch_config_common');
c=sixgr.mac.ra.resolveRARCommonPUSCHContext(absent);
a=sixgr.mac.ra.resolveRARTimeDomainAllocation(0,30,"normal",c);
assert(~c.CommonIEPresent&&~c.Timing.Available&&a.K2==1&&a.NumSymbols==14&& ...
    a.SourceKind=="default_A_no_common_tdra_list");
ok=true;
fprintf('RAR_COMMON_TDRA_PASS actual_SIB1_codec=1 K2=4 delta=3 SLIV=69 matched_RAR_bits=1 RFexecutions=0\n');
end
function reject(f,id)
try,f();catch e,assert(string(e.identifier)==id,'Expected %s, got %s: %s',id,e.identifier,e.message);return;end
error('test:RARCommonGuardMissing','Expected %s.',id);
end
