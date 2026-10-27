function ok=testCommonCRNTIDCISizing()
% Pinned fallback wire widths and CSS Step0; no received-control claim.
base=sixgr.phy.pdcch.DCIContext.fromLegacy(struct('NSizeGrid',51, ...
    'RNTIType',"C-RNTI",'RNTIValue',4660,'SearchSpaceType',"CSS"),"0_0");
d=base.Data; d.CORESET0Size=24; d.CORESET0Start=6;
d.ActiveULBWPSize=25; d.ActiveULBWPStart=12;
d.ULTimeDomainAllocations=[0 0 11 4];
d.DLTimeDomainAllocations=[0 2 12 0];
d.HARQProcessCount=4;
c=sixgr.phy.pdcch.DCIContext(d);
s=sixgr.phy.pdcch.DCISchemaEngine.resolve(c);
a=sixgr.phy.pdcch.DCISizeAlignmentEngine.resolve(c);
assert(s.RawBits==31 && s.TimeAssignmentBits==4 && s.FrequencyAssignmentBits==11);
assert(a.Selected.AlignedBits==37 && a.Selected.PaddingBits==6 && a.Selected.TruncatedFrequencyBits==0);
f=struct('format_identifier',0,'frequency_resource_assignment',55, ...
    'time_resource_assignment',0,'frequency_hopping',0,'mcs',1, ...
    'ndi',1,'rv',0,'harq_process',2,'tpc_command_for_pusch',1);
tx=sixgr.phy.pdcch.DCIPacker.pack(f,c);
literal=int8('0000001101110000000001100001001000000'-'0').';
assert(isequal(tx.Bits,literal));
rx=sixgr.phy.pdcch.DCIParser.parse(literal,c);
assert(rx.Fields.prb_start==4 && rx.Fields.num_prb==2 && ...
    rx.Fields.reference_start==0 && rx.Fields.timing_offset_slots==4 && rx.Fields.num_symbols==11);
bad=literal;bad(end)=1;
mustFail(@()sixgr.phy.pdcch.DCIParser.parse(bad,c),'sixgr:phy:pdcch:dci_size_alignment_failure');
bad=f;bad.time_resource_assignment=1;
other=sixgr.phy.pdcch.DCIPacker.pack(bad,c);
mustFail(@()sixgr.phy.pdcch.DCIParser.parse(other.Bits,c),'sixgr:phy:pdcch:field_out_of_range');

% A large initial UL BWP cannot force the common DL payload to grow.
d.InitialULBWPSize=275;d.CORESET0Size=6;d.CORESET0Start=0;
c=sixgr.phy.pdcch.DCIContext(d);
a=sixgr.phy.pdcch.DCISizeAlignmentEngine.resolve(c);
assert(a.Selected.RawBits==36 && a.Selected.AlignedBits==33 && ...
    a.Selected.TruncatedFrequencyBits==3 && a.Selected.PaddingBits==0);
tx=sixgr.phy.pdcch.DCIPacker.pack(f,c);
literal=int8('000000001101110000000001100001001'-'0').';
assert(isequal(tx.Bits,literal));
rx=sixgr.phy.pdcch.DCIParser.parse(literal,c);
assert(rx.Fields.prb_start==55 && rx.Fields.num_prb==1);
bad=f;bad.frequency_resource_assignment=8192;
mustFail(@()sixgr.phy.pdcch.DCIPacker.pack(bad,c),'sixgr:phy:pdcch:field_out_of_range');
% USS uses active geometry and its separate max-size padding rule.
d.SearchSpaceType="USS";d.ActiveULBWPSize=275;d.ActiveDLBWPSize=6;
c=sixgr.phy.pdcch.DCIContext(d);a=sixgr.phy.pdcch.DCISizeAlignmentEngine.resolve(c);
assert(a.Selected.AlignedBits==36 && a.Selected.TruncatedFrequencyBits==0);
assert(a.Rows(string({a.Rows.DCIFormat})=="1_0").PaddingBits==3);
bad=d;bad.SULIndicatorPresent=true;
mustFail(@()sixgr.phy.pdcch.DCISchemaEngine.resolve(sixgr.phy.pdcch.DCIContext(bad)), ...
    'sixgr:phy:pdcch:unsupported_fallback_dci_configuration');
ok=true;
fprintf('COMMON_CRNTI_DCI_SIZING_PASS fixed_TDRA4=1 CSS_padding6=1 CSS_truncation3=1 original_initial_BWP=1 RF=0\n');
end
function mustFail(f,id)
try,f();catch e,assert(string(e.identifier)==string(id),e.message);return;end
error('sixgr:test:ExpectedFailure','Expected %s.',id);
end
