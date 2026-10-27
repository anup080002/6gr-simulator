function [value,evidence]=resolvePUCCHDeltaTF(carrier,planned)
% TS 38.213 V18.8.0 7.2.1, ordinary single-slot unicast PUCCH.
% Operands come from the selected transmitted report and physical RE map.
assert(isa(carrier,'nrCarrierConfig') && isstruct(planned) && ...
    isa(planned.Plan,'sixgr.phy.pucch.PUCCHResourcePlan') && ...
    isa(planned.Report,'sixgr.phy.pucch.UCIReport') && ...
    planned.Report.Digest==planned.Plan.ReportDigest, ...
    'sixgr:phy:pucch:DeltaTFBinding','Require the selected original typed report/resource.');
r=planned.Plan.Resource; format=r.Format;
s=sixgr.phy.pucch.UCIReportSerializer.serialize(planned.Report);
owners=string(s.Layout.BitOwner);
harq=sum(owners=="HARQ_ACK"); sr=sum(owners=="SR");
csi=sum(owners=="CSI_PART1" | owners=="CSI_PART2");
information=harq+sr+csi;
assert(information>0 && information==s.InformationBitCount && ...
    s.PaddingBitCount==0,'sixgr:phy:pucch:UnsupportedDeltaTF', ...
    'Empty/padded or separately coded sequences require their own power procedure.');
nsym=double(r.Data.NumSymbols); nre=NaN; crc=0; bpre=NaN;
codingDigest=""; modulationBits=NaN;
if format<=1
    assert(csi==0 && harq<=2 && sr<=1,'sixgr:phy:pucch:UnsupportedDeltaTF', ...
        'Short-format power supports ordinary HARQ/SR only.');
    nref=2; deltaUCI=0;
    if format==1
        nref=double(carrier.SymbolsPerSlot);
        % Positive SR-only transmits b(0)=0. With HARQ, SR is conveyed by
        % resource selection; it is not an additional format-1 data bit.
        modulationBits=max(1,harq);
        deltaUCI=10*log10(modulationBits);
    end
    value=10*log10(nref/nsym)+deltaUCI;
    definition="short_format_symbol_duration_and_original_UCI_count";
else
    assert(any(format==[2 3 4]),'sixgr:phy:pucch:UnsupportedDeltaTF','Unknown PUCCH format.');
    native=r.toolboxConfig();
    [ind,info]=nrPUCCHIndices(carrier,native);
    dmrs=nrPUCCHDMRSIndices(carrier,native);
    K=12*double(carrier.NSizeGrid); L=double(carrier.SymbolsPerSlot);
    data=unique(mod(double(ind(:))-1,K*L));
    pilot=unique(mod(double(dmrs(:))-1,K*L));
    assert(isempty(intersect(data,pilot)) && ~isempty(data), ...
        'sixgr:phy:pucch:DeltaTFBinding','Power N_RE must exclude the actual DM-RS support.');
    nre=numel(data); % Physical REs, not despread G/Qm (especially format 4).
    coding=sixgr.phy.pucch.UCIEncodingPlan(information,double(info.G));
    assert(coding.Valid,'sixgr:phy:pucch:UnsupportedDeltaTF','Unsupported UCI coding population.');
    crc=double(coding.TotalCRCBits);
    codingDigest=string(coding.Digest);
    if information<=11
        value=10*log10(6*information/nre);
        definition="small_UCI_6_times_information_bits_per_physical_data_RE";
    else
        bpre=(information+crc)/nre;
        value=10*log10(expm1(log(2)*2.4*bpre));
        definition="large_UCI_exponential_information_plus_actual_CRC_per_physical_data_RE";
    end
end
assert(isfinite(value),'sixgr:phy:pucch:DeltaTFBinding','Finite supported resource power is required.');
evidence=struct('ContractVersion',"sixgr.pucch.payload_resource_delta_tf/v1", ...
    'SpecVersion',"TS38.213_V18.8.0_7.2.1",'Format',format, ...
    'ReportDigest',planned.Report.Digest,'ResourceDigest',r.Digest, ...
    'SerializationDigest',s.Digest,'HARQACKBits',harq,'SRBits',sr,'CSIBits',csi, ...
    'InformationBits',information,'PaddingBits',s.PaddingBitCount,'CRCBits',crc, ...
    'Format1ModulationBits',modulationBits,'CodingPlanDigest',codingDigest, ...
    'PhysicalDataREs',nre,'Symbols',nsym,'BPRE',bpre,'DeltaTF_dB',value, ...
    'Definition',definition,'Scope',"ordinary_single_slot_unicast_no_repetition_multicast_or_interlacing");
evidence.SHA256=string(sixgr.util.sha256Hex(char(jsonencode(evidence))));
end
