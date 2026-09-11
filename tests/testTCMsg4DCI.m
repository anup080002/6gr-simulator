function ok = testTCMsg4DCI()
% Independent field-position vectors; not a MAC/RRC or feedback qualification.
for nRB = [24 48 96]
    reference = struct('FrequencyReferenceSize',nRB,'FrequencyReferenceStart',7, ...
        'FrequencyReferenceSource',"scenario_coreset0",'DMRSTypeAPosition',2, ...
        'CyclicPrefix',"normal",'SharedSpectrum',false,'FrequencyRange',"FR1", ...
        'TimeAllocationSource',"38.214_default_A",'ConfigurationEpoch',3);
    context = sixgr.phy.pdcch.TCMsg4DCIContext.create(reference,4660,false);
    % Full-CORESET allocation: independent long-allocation RIV expression.
    riv = 2*nRB-1;
    fields = struct('format_identifier',1,'frequency_resource_assignment',riv, ...
        'time_resource_assignment',0,'vrb_to_prb_mapping',0,'mcs',0, ...
        'ndi',1,'rv',0,'harq_process',5,'dai',0,'tpc_command_for_pucch',2, ...
        'pucch_resource_indicator',6,'pdsch_to_harq_feedback_timing',3);
    width = ceil(log2(nRB*(nRB+1)/2));
    literal = ['1' dec2bin(riv,width) '0000' '0' '00000' '1' '00' '0101' '00' '10' '110' '011'];
    dci = sixgr.phy.pdcch.DCIPacker.pack(fields,context);
    assert(isequal(dci.Bits,int8(literal(:)-'0')) && numel(dci.Bits)==width+28);
    parsed = sixgr.phy.pdcch.DCIParser.parse(int8(literal(:)-'0'),context);
    assert(parsed.Fields.prb_start==0 && parsed.Fields.num_prb==nRB && ...
        parsed.Fields.reference_start==7 && parsed.Fields.symbol_start==2 && parsed.Fields.num_symbols==12);
    assert(parsed.Fields.harq_process==5 && parsed.Fields.pucch_resource_indicator==6 && ...
        parsed.Fields.pdsch_to_harq_feedback_timing==3 && ~context.Data.LegacyCompatibility);
    bad = fields; bad.dai=1;
    localReject(@()sixgr.phy.pdcch.DCIPacker.pack(bad,context),'sixgr:phy:pdcch:field_out_of_range');
    bad = fields; bad.format_identifier=0;
    localReject(@()sixgr.phy.pdcch.DCIPacker.pack(bad,context),'sixgr:phy:pdcch:field_out_of_range');
    localReject(@()sixgr.phy.pdcch.DCIParser.parse(zeros(32,1),context), ...
        'sixgr:phy:pdcch:payload_length_mismatch');
    localReject(@()sixgr.phy.pdcch.TCMsg4DCIContext.create(reference,4660,true), ...
        'sixgr:phy:pdcch:unsupported_tc_msg4_repetitions');
    badRef=reference; badRef.FrequencyReferenceSource="scenario_initial_dl_bwp";
    localReject(@()sixgr.phy.pdcch.TCMsg4DCIContext.create(badRef,4660,false), ...
        'sixgr:phy:pdcch:invalid_tc_msg4_context');
end
legacy=struct('NSizeGrid',24,'RNTIType',"TC-RNTI");
localReject(@()sixgr.phy.pdcch.DCIContext.fromLegacy(legacy,"1_0"), ...
    'sixgr:phy:pdcch:missing_dci_context');
ok=true;
fprintf('TC_MSG4_DCI_BIT_VECTOR_PASS: CORESET0 24/48/96 RB, exact fields and strict negative vectors.\n');
end

function localReject(fn,id)
try, fn(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, received %s: %s',id,cause.identifier,cause.message);
    return;
end
error('testTCMsg4DCI:MissingRejection','Expected %s',id);
end
