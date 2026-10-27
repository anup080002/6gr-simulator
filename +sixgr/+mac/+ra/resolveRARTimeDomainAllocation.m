function row=resolveRARTimeDomainAllocation(index,scs,cp,common)
% TS38.214 V18.8 6.1.2.1.1 Table1: original common list precedes default A.
% Supported common-list physical branch: non-repeated Type A starting at0.
validateattributes(index,{'numeric'},{'scalar','real','finite','integer','>=',0,'<=',15});
row=sixgr.phy.frame.TimeDomainResourceAllocationCatalog.resolvePUSCHDefaultA(index,scs,cp);
if nargin<4||isempty(fieldnames(common)),return;end
id='sixgr:mac:ra:RARCommonPUSCHAuthority';
assert(common.ContractVersion=="RAR_common_PUSCH_configuration/v1" && ...
    common.SHA256==localHash(rmfield(common,'SHA256')) && ...
    common.InitialULBWP.SubcarrierSpacing_kHz==scs && ...
    string(common.InitialULBWP.CyclicPrefix)==string(cp),id,'Retain the exact original common context.');
[timing,ie]=sixgr.rrc.asn1.resolvePUSCHConfigCommon(common.OriginalIE,scs);
assert(isequaln(timing,common.Timing)&&isequaln(ie,common.OriginalIE) && ...
    (common.CommonIEPresent||isempty(fieldnames(ie))),id,'Do not replace original timing operands.');
if ~timing.Available,return;end
assert(index<numel(timing.K2Slots),'sixgr:mac:ra:RARCommonTDRAIndexOutOfRange', ...
    'The received RAR index has no row in the original common list; default A cannot rescue it.');
k=index+1;
[first,count]=sixgr.phy.frame.ResourceAllocationValidator.decodeSLIV(timing.StartSymbolAndLength(k),row.SymbolsPerSlot);
assert(timing.MappingType(k)=="typeA"&&first==0&&count>=4, ...
    'sixgr:mac:ra:UnsupportedRARCommonMapping', ...
    'This common-list Msg3 branch supports non-repeated Type A starting at0 with at least4 symbols.');
% Keep the original numerology-dependent Msg3 additional delta from Table5;
% the configured K2 changes only the common allocation's slot offset.
row.MappingType="A";row.StartSymbol=first;row.NumSymbols=count;row.K2=timing.K2Slots(k);
row.TableNumber="6.1.2.1.1-1_common_list";
row.StandardReference="TS38.214_V18.8.0_6.1.2.1.1_Table1_and_Table5";
row.SourceKind="original_common_PUSCH_tdra_list";
row.CommonContextSHA256=common.SHA256;
row.OriginalCommonRow=ie.pusch_TimeDomainAllocationList(k);
if iscell(row.OriginalCommonRow),row.OriginalCommonRow=row.OriginalCommonRow{1};end
row.K2FieldPresent=timing.K2Present(k);row.K2Source=timing.K2Source(k);
end
function h=localHash(v)
h=string(sixgr.util.sha256Hex(jsonencode(sixgr.util.jsonSafeValue(v))));
end
