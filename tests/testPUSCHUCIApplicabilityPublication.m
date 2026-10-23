function ok=testPUSCHUCIApplicabilityPublication()
% Declared publication-boundary fixtures, not executed PHY observations.
% Exercise the actual public builder using the raw runULPUSCHThroughput
% Applied/Source/EvidenceSource schema. Applied means receiver processing,
% not transmitted presence, a decoded field, accepted CSI, or TB CRC success.
% Each case reports independently before the final assertion, so a missing
% projection cannot hide contradictory/unknown provenance regressions.
setup6GRSimToolkit('Verbose',false);
definition="receiver_uci_processing_applied_not_presence_or_decode_success";
receiverSource="nrULSCHDemultiplex_nrUCIDecode_independent_receive_schema";
failures=strings(0,1); caseCount=0;

% Exact currently emitted receiver sources; component/research origins stay
% visible and do not acquire an independent-receiver qualification here.
sources=[receiverSource; ...
    "nrULSCHDemultiplex_nrUCIDecode_typed_payload"; ...
    "experimental_explicit_Qm_UCI_typed_payload_component"; ...
    "experimental_explicit_Qm_UCI_independent_receive_schema"; ...
    "nrULSCHDemultiplex_nrUCIDecode_receive_schema_core"; ...
    "independent_CSI_presence_interpretations_and_received_ULSCH_CRC"; ...
    "received_LLR_with_configured_invariant_resource_mapping"];
for k=1:numel(sources)
    source=localRaw(true,sources(k));
    runCase("current_receiver_source_"+string(k), ...
        @() localCheck(source,1,sources(k),definition));
end

source=localRaw(false,"no_uci_payload_requested");
runCase("explicit_receiver_no_uci_request", ...
    @() localCheck(source,0,"no_uci_payload_requested",definition));
% This no-payload token is shared by TX and RX. Unlike receiver-specific
% demultiplexer sources it needs original returned-receiver provenance.
source.RuntimeEvidenceSource=[]; source.RuntimeMaterializationStatus=[];
runCase("shared_no_payload_source_without_receiver_provenance", ...
    @() localCheck(source,NaN,"",definition));
source.RuntimeEvidenceSource="sixgr.phy.ul.PUSCH_Tx";
runCase("shared_no_payload_source_with_declared_tx_provenance", ...
    @() localCheck(source,NaN,"",definition));
source=localRaw(false,receiverSource);
runCase("receiver_zero_budget_false_has_blank_evidence_by_design", ...
    @() localCheck(source,0,receiverSource,definition));
source=localRaw(NaN,receiverSource);
runCase("explicit_unknown_applied",@() localCheck(source,NaN,"",definition));
source=localRaw(true,receiverSource); source.UCIOnPUSCHApplied=[];
runCase("missing_applied_despite_receiver_source", ...
    @() localCheck(source,NaN,"",definition));
source=localRaw(false,""); source.UCIOnPUSCHEvidenceSource="";
runCase("pre_rx_default_false_is_unknown", ...
    @() localCheck(source,NaN,"",definition));
source=localRaw(true,"pending_dl_harq_and_or_csi_nrULSCHMultiplex");
source.UCIOnPUSCHEvidenceSource="pending_feedback_table_reserved_after_pdcch_grant_binding";
runCase("planned_reservation_is_not_receiver_processing", ...
    @() localCheck(source,NaN,"",definition));
source=localRaw(true,"nrULSCHInfo_nrUCIEncode_nrULSCHMultiplex_typed_payload");
source.UCIOnPUSCHEvidenceSource="";
runCase("transmitter_multiplexing_is_not_receiver_processing", ...
    @() localCheck(source,NaN,"",definition));
source=localRaw(true,"future_rx_demultiplexer_unreviewed_source");
runCase("unknown_source_cannot_qualify_by_substring", ...
    @() localCheck(source,NaN,"",definition));
source=localRaw(true,receiverSource); source.UCIOnPUSCHEvidenceSource="";
runCase("positive_receiver_processing_requires_retained_receiver_evidence", ...
    @() localCheck(source,NaN,"",definition));

% These are declared returned partial-reception/outcome facts, not a new
% receive operation. Independent UCI can execute without usable UL-SCH.
source=localRaw(true,"received_LLR_with_configured_invariant_resource_mapping");
source.CRCPass=NaN; source.CRCApplicable=false;
source.DecodeAttempted=false; source.DecodeUsable=false;
source.PartialReception=true; source.CSIPresenceResolved=false;
source.CSIReportDetected=false; source.CSIPart1Usable=false;
runCase("partial_unresolved_csi_and_no_tb_crc_still_processed", ...
    @() localCheck(source,1,source.UCIOnPUSCHSource,definition));
source=localRaw(true,receiverSource); source.CRCPass=0;
source.CSIPresenceResolved=true; source.CSIReportDetected=false;
runCase("absent_csi_and_failed_tb_crc_still_processed", ...
    @() localCheck(source,1,receiverSource,definition));

% No repository producer establishes a meaning for a bare legacy Flag.
% Preserve its value under Input*, never silently reinterpret its plane.
source=localRaw(true,receiverSource);
source(:,["UCIOnPUSCHApplied","UCIOnPUSCHSource","UCIOnPUSCHEvidenceSource"])=[];
source.UCIOnPUSCHFlag=true;
runCase("bare_legacy_flag_retained_but_plane_unknown", ...
    @() localCheck(source,NaN,"",definition));
source.UCIOnPUSCHFlag=NaN;
runCase("legacy_nan_does_not_become_logical_true", ...
    @() localCheck(source,NaN,"",definition));
source=localLegacy(localRaw(true,receiverSource),true,definition,receiverSource);
source.UCIOnPUSCHApplied=[];
runCase("qualified_same_plane_legacy_when_applied_absent", ...
    @() localCheck(source,1,receiverSource,definition));
source=localLegacy(localRaw(true,receiverSource),true,definition,receiverSource);
runCase("same_plane_equal_values", ...
    @() localCheck(source,1,receiverSource,definition));
source=localLegacy(localRaw(true,receiverSource),false,definition,receiverSource);
runCase("same_plane_true_vs_false_rejected",@() localConflict(source));
source=localLegacy(localRaw(false,"no_uci_payload_requested"),true,definition,receiverSource);
runCase("same_plane_false_vs_true_rejected",@() localConflict(source));
source=localLegacy(localRaw(NaN,receiverSource),true,definition,receiverSource);
runCase("explicit_applied_unknown_not_backfilled_from_legacy", ...
    @() localCheck(source,NaN,"",definition));
source=localLegacy(localRaw(false,"no_uci_payload_requested"),true, ...
    "scheduled_uci_reservation_not_receiver_processing", ...
    "pending_dl_harq_and_or_csi_nrULSCHMultiplex");
runCase("known_different_scheduling_plane_retained_separately", ...
    @() localCheck(source,0,"no_uci_payload_requested",definition));
source=localLegacy(localRaw(true,receiverSource),false, ...
    "transmitter_uci_multiplexing_not_receiver_processing", ...
    "nrULSCHInfo_nrUCIEncode_nrULSCHMultiplex_typed_payload");
runCase("known_different_transmitter_plane_retained_separately", ...
    @() localCheck(source,1,receiverSource,definition));
source=localLegacy(localRaw(true,receiverSource),false,definition, ...
    "future_rx_demultiplexer_unreviewed_source");
runCase("unqualified_legacy_source_is_not_same_plane_authority", ...
    @() localCheck(source,1,receiverSource,definition));

source=[localRaw(1,receiverSource);localRaw(NaN,receiverSource); ...
    localRaw(0,"no_uci_payload_requested")];
source.Slot=[29;4;18];
runCase("mixed_rows_order_values_and_original_types", ...
    @() localCheck(source,[1;NaN;0],"",definition));
runCase("empty_source_has_no_placeholder",@localEmpty);
% Additional persistence/strictness checks; the original 32 boundary cases
% above remain intact. These are declared schemas, not receiver executions.
runCase("producer_canonicalize_default_csv_public_roundtrip", ...
    @() localPersistence(definition,receiverSource));
runCase("numeric_unknown_blank_provenance_survives_default_csv", ...
    @() localUnknownPersistence(definition));
runCase("public_contract_declares_processing_evidence",@localContract);
for invalid={2,Inf,-1,"not-a-boolean",[1 0]}
    source=localRaw(true,receiverSource); source.UCIOnPUSCHApplied=invalid{1};
    runCase("invalid_processing_value_"+string(caseCount+1), ...
        @() localRejectValue(source));
end
for token=["true","false","NaN","<missing>",""]
    source=localRaw(true,receiverSource); source.UCIOnPUSCHApplied=token;
    expected=NaN;
    if token=="true", expected=1; elseif token=="false", expected=0; end
    runCase("csv_processing_scalar_"+string(caseCount+1), ...
        @() localCheck(source,expected,"",definition));
end
source=localLegacy(localRaw(true,receiverSource),false, ...
    "scheduled_uci_reservation_not_receiver_processing","declared-planner");
source.InputUCIOnPUSCHFlag=true;
runCase("existing_original_evidence_cannot_be_overwritten",@() localConflict(source));
fprintf('PUSCH_UCI_APPLICABILITY_PUBLICATION cases=%d failures=%d waveform_execution=0 declared_fixture=1\n', ...
    caseCount,numel(failures));
if ~isempty(failures)
    assert(isempty(failures),'test:PUSCHUCIApplicabilityPublication', ...
        '%d/%d publication cases failed:\n%s',numel(failures),caseCount,char(join(failures,newline)));
end
ok=true;

    function runCase(name,action)
        caseCount=caseCount+1;
        try
            action();
            fprintf('PUSCH_UCI_PUBLICATION_CASE %s PASS\n',name);
        catch failure
            failures(end+1,1)=name+": "+string(failure.identifier)+" "+string(failure.message); %#ok<AGROW>
            fprintf('PUSCH_UCI_PUBLICATION_CASE %s FAIL %s\n',name,failure.identifier);
        end
    end
end

function T=localRaw(applied,source)
T=table(7,1,true,true,true,applied,string(source),"", ...
    'VariableNames',{'Slot','CRCPass','CRCApplicable','DecodeAttempted','DecodeUsable', ...
    'UCIOnPUSCHApplied','UCIOnPUSCHSource','UCIOnPUSCHEvidenceSource'});
if isequal(applied,true) || isequal(applied,1)
    T.UCIOnPUSCHEvidenceSource="same_waveform_pusch_rx_uci_demultiplexer";
end
% Exact current runUL returned-receiver producer fields. The fixtures remain
% declared schemas; these strings do not create waveform evidence in a test.
T.RuntimeEvidenceSource="sixgr.link.runULPUSCHThroughput_returned_receiver";
T.RuntimeMaterializationStatus="active_waveform_pusch_runtime";
end

function T=localLegacy(T,flag,definition,source)
T.UCIOnPUSCHFlag=flag;
T.UCIOnPUSCHFlagDefinition=definition;
T.UCIOnPUSCHFlagSource=source;
end

function localCheck(source,expected,expectedSource,definition)
out=localPublish(source);
assert(height(out)==height(source) && isequal(out.Slot,source.Slot), ...
    'test:PUSCHUCIPopulationChanged','Keep exact row count and order.');
required=["UCIOnPUSCHFlag","UCIOnPUSCHFlagDefinition", ...
    "UCIOnPUSCHFlagSource","UCIOnPUSCHFlagStatus"];
assert(all(ismember(required,string(out.Properties.VariableNames))), ...
    'test:PUSCHUCIProjectionContract','Retain processing definition, source and diagnostic status.');
assert(isnumeric(out.UCIOnPUSCHFlag) && isequaln(double(out.UCIOnPUSCHFlag),double(expected)), ...
    'test:PUSCHUCIProcessingValue','Receiver processing must retain 0/1/NaN, not logical-coerce unknown.');
assert(all(string(out.UCIOnPUSCHFlagDefinition)==definition), ...
    'test:PUSCHUCIProcessingDefinition','Processing is not presence, successful decoding or CSI delivery.');
assert(all(~ismissing(string(out.UCIOnPUSCHFlagStatus)) & strlength(string(out.UCIOnPUSCHFlagStatus))>0), ...
    'test:PUSCHUCIProcessingReason','Every row needs a qualification/unavailability reason.');
if strlength(expectedSource)>0
    assert(all(string(out.UCIOnPUSCHFlagSource)==expectedSource), ...
        'test:PUSCHUCIProcessingSource','Preserve the exact qualified receiver/component source.');
end
names=string(source.Properties.VariableNames);
retained=["UCIOnPUSCHApplied","UCIOnPUSCHSource","UCIOnPUSCHEvidenceSource", ...
    "CRCPass","CRCApplicable","DecodeAttempted","DecodeUsable", ...
    "RuntimeEvidenceSource","RuntimeMaterializationStatus", ...
    "PartialReception","CSIPresenceResolved","CSIReportDetected","CSIPart1Usable"];
for name=intersect(names,retained,'stable')
    assert(ismember(name,string(out.Properties.VariableNames)) && isequaln(out.(name),source.(name)), ...
        'test:PUSCHUCISourceChanged','Retain original %s without processing-to-outcome inference.',name);
end
for name=intersect(names,["UCIOnPUSCHFlag","UCIOnPUSCHFlagDefinition","UCIOnPUSCHFlagSource"],'stable')
    inputName="Input"+name;
    assert(ismember(inputName,string(out.Properties.VariableNames)) && isequaln(out.(inputName),source.(name)), ...
        'test:PUSCHUCILegacySourceLost','Preserve original legacy %s separately, including its plane.',name);
end
if ~ismember("UCIOnPUSCHApplied",names) && ismember("UCIOnPUSCHApplied",string(out.Properties.VariableNames))
    assert(isnumeric(out.UCIOnPUSCHApplied) && all(isnan(out.UCIOnPUSCHApplied)), ...
        'test:PUSCHUCIRawAppliedInvented','Missing original Applied cannot become a synthesized raw fact.');
end
end

function localConflict(source)
try
    localPublish(source);
catch failure
    assert(strcmp(failure.identifier,'sixgr:truth:PUSCHUCIApplicabilityConflict'), ...
        'test:PUSCHUCIWrongConflict','Reject contradictory same-plane evidence specifically, not an unrelated error.');
    return;
end
error('test:PUSCHUCIMissedConflict','Known contradictory receiver-processing facts must not be resolved by alias priority or OR.');
end

function out=localPublish(source)
before=source; beforeRNG=rng;
meta=struct('logical_run_id',"declared_pusch_uci_publication_boundary",'run_id',23);
tables=sixgr.truth.buildLLSPublicOutputTables(struct('pusch_table',source), ...
    sixgr.truth.llsOutputContract(),meta);
assert(isequaln(source,before) && isequal(rng,beforeRNG), ...
    'test:PUSCHUCIPublicationMutation','Projection must not mutate original source or execute stochastic work.');
out=tables.pusch_runtime_event_table;
end

function localEmpty()
out=localPublish(table());
assert(isempty(out),'test:PUSCHUCIPlaceholder','Unavailable source cannot create an execution row.');
end

function localRejectValue(source)
try
    localPublish(source);
catch failure
    assert(strcmp(failure.identifier,'sixgr:truth:InvalidPUSCHUCIProcessingValue'), ...
        'test:PUSCHUCIInvalidValueError','Malformed values must fail the dedicated binary/unknown guard.');
    return;
end
error('test:PUSCHUCIInvalidValueAccepted','Do not silently convert arbitrary values to true or unknown.');
end

function localPersistence(definition,receiverSource)
source=[localRaw(1,receiverSource);localRaw(NaN,receiverSource);localRaw(0,"no_uci_payload_requested")];
source.Slot=[29;4;18]; source.CSIReportDetected=[0;NaN;0];
source.UCIOnPUSCHFlag=[0;NaN;1];
source.UCIOnPUSCHFlagDefinition=repmat("scheduled_uci_reservation_not_receiver_processing",3,1);
source.UCIOnPUSCHFlagSource=["declared-planner";"";"declared-planner"];
source.UCIOnPUSCHFlagStatus=["declared-reservation";"";"declared-reservation"];
canonical=sixgr.truth.canonicalizeLLSLiveSignalChainTable("ul_pusch_trials",source);
for name=string(source.Properties.VariableNames)
    assert(isequaln(canonical.(name),source.(name)), ...
        'test:PUSCHUCICanonicalMutation','Canonical annotation must preserve supplied %s.',name);
end
folder=tempname; mkdir(folder); cleanup=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
path=fullfile(folder,'declared_ul_pusch_trials.csv');
sixgr.util.csvWriteTable(path,canonical,'RoundTripNumericText',true);
loaded=sixgr.util.csvReadTable(path,'TextType','string');
localCheck(loaded,[1;NaN;0],"",definition);
out=localPublish(loaded);
publicPath=fullfile(folder,'declared_pusch_runtime_event_table.csv');
sixgr.util.csvWriteTable(publicPath,out,'RoundTripNumericText',true);
roundtrip=sixgr.util.csvReadTable(publicPath,'TextType','string');
assert(isequaln(double(roundtrip.UCIOnPUSCHFlag),[1;NaN;0]) && ...
    isequaln(double(roundtrip.InputUCIOnPUSCHFlag),[0;NaN;1]) && ...
    isequaln(double(roundtrip.UCIOnPUSCHApplied),[1;NaN;0]) && ...
    isequaln(double(roundtrip.CSIReportDetected),[0;NaN;0]) && ...
    isequal(roundtrip.Slot,source.Slot));
assert(all(string(roundtrip.UCIOnPUSCHFlagDefinition)==definition));
assert(all(string(roundtrip.InputUCIOnPUSCHFlagDefinition)==source.UCIOnPUSCHFlagDefinition));
assert(~contains(fileread(path),'active_ul_pusch_trials'), ...
    'test:PUSCHUCIFabricatedSource','Blank UCI provenance cannot acquire a display-generated runtime source.');
end

function localUnknownPersistence(definition)
source=localRaw(NaN,""); source.UCIOnPUSCHEvidenceSource="";
source.RuntimeEvidenceSource=""; source.RuntimeMaterializationStatus="";
source.UCIOnPUSCHFlag=NaN; source.UCIOnPUSCHFlagDefinition="";
source.UCIOnPUSCHFlagSource=""; source.UCIOnPUSCHFlagStatus="";
source.CSIReportDetected=NaN; source.UnrelatedUnavailableMeasurement=NaN;
canonical=sixgr.truth.canonicalizeLLSLiveSignalChainTable("ul_pusch_trials",source);
assert(isequaln(canonical,source),'test:PUSCHUCIBlankProvenanceMutation', ...
    'Do not decorate explicit blank provenance or infer receiver execution.');
folder=tempname; mkdir(folder); cleanup=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
path=fullfile(folder,'declared_unknown_ul.csv');
sixgr.util.csvWriteTable(path,canonical,'RoundTripNumericText',true);
loaded=sixgr.util.csvReadTable(path,'TextType','string');
required=setdiff(string(source.Properties.VariableNames),"UnrelatedUnavailableMeasurement",'stable');
assert(all(ismember(required,string(loaded.Properties.VariableNames))) && ...
    ~ismember("UnrelatedUnavailableMeasurement",string(loaded.Properties.VariableNames)));
localCheck(loaded,NaN,"",definition);
out=localPublish(loaded);
publicPath=fullfile(folder,'declared_unknown_public.csv');
sixgr.util.csvWriteTable(publicPath,out,'RoundTripNumericText',true);
roundtrip=sixgr.util.csvReadTable(publicPath,'TextType','string');
required=["UCIOnPUSCHFlag","UCIOnPUSCHFlagSource","UCIOnPUSCHFlagDefinition", ...
    "UCIOnPUSCHApplied","UCIOnPUSCHSource","UCIOnPUSCHEvidenceSource", ...
    "InputUCIOnPUSCHFlag","InputUCIOnPUSCHFlagDefinition","InputUCIOnPUSCHFlagSource", ...
    "InputUCIOnPUSCHFlagStatus","RuntimeEvidenceSource","RuntimeMaterializationStatus","CSIReportDetected"];
assert(all(ismember(required,string(roundtrip.Properties.VariableNames))) && ...
    isnan(double(roundtrip.UCIOnPUSCHFlag)) && isnan(double(roundtrip.UCIOnPUSCHApplied)));
assert(string(roundtrip.UCIOnPUSCHFlagDefinition)==definition);
for name=["UCIOnPUSCHFlagSource","UCIOnPUSCHSource","UCIOnPUSCHEvidenceSource", ...
        "InputUCIOnPUSCHFlagDefinition","InputUCIOnPUSCHFlagSource","RuntimeEvidenceSource","RuntimeMaterializationStatus"]
    token=lower(strtrim(string(roundtrip.(name))));
    assert(ismissing(token) || any(token==["","nan","<missing>"]), ...
        'test:PUSCHUCIUnknownSourceChanged','Blank %s must remain unavailable after persistence.',name);
end
assert(~sixgr.truth.isImmutableIdentityField("UCIOnPUSCHUnrelatedMeasurement"), ...
    'test:PUSCHUCIOverbroadIdentityGuard','Preserve only the declared evidence fields.');
end

function localContract()
contract=sixgr.truth.llsOutputContract();
row=contract.Outputs(string(contract.Outputs.OutputId)=="pusch_runtime_event_table",:);
columns=split(string(row.OptionalColumns),"|");
assert(all(ismember(["UCIOnPUSCHFlag","UCIOnPUSCHFlagDefinition", ...
    "UCIOnPUSCHFlagSource","UCIOnPUSCHFlagStatus","UCIOnPUSCHApplied", ...
    "UCIOnPUSCHSource","UCIOnPUSCHEvidenceSource","InputUCIOnPUSCHFlag"],columns)));
end
