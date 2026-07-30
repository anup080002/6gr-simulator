classdef EvidenceAdapterRegistry
    %EVIDENCEADAPTERREGISTRY Versioned lossless Phase-18 schema adapters.
    %
    % Adapters derive canonical fields only from observed source columns.
    % A missing semantic measurement is never filled from configuration.
    methods (Static)
        function T = aliases()
            T = table("full_stack_subcase_results.csv", ...
                "full_stack_subcase_status.csv","phase18-alias-v1", ...
                'VariableNames',{'RequestedIdentity','CanonicalIdentity', ...
                'AdapterVersion'});
        end

        function [adapted,results] = adapt(fileName,T,expressions,sourceHash)
            expressions = string(expressions(:));
            columns = strings(0,1);
            for expression = reshape(expressions,1,[])
                ast = sixgr.integration.qualification. ...
                    ValueExpressionParser.parse(expression);
                columns = [columns;sixgr.integration.qualification. ...
                    ValueExpressionParser.referencedColumns(ast)]; %#ok<AGROW>
            end
            columns = unique(columns(strlength(columns)>0),"stable");
            missing = columns(~ismember(columns, ...
                string(T.Properties.VariableNames)));
            adapted = T;
            results = sixgr.integration.qualification. ...
                EvidenceAdapterRegistry.emptyResults();
            if isempty(missing)
                return;
            end
            derived = struct();
            metadata = repmat(localMetadataRow(),0,1);
            hasScalar = false;
            for target = reshape(missing,1,[])
                [found,value,sourceColumns,formula] = localDerive( ...
                    string(fileName),target,T);
                if ~found
                    continue;
                end
                derived.(char(target)) = value;
                hasScalar = hasScalar || isscalar(value);
                row = localMetadataRow();
                row.AdapterID = "ADAPT-" + upper(regexprep( ...
                    erase(string(fileName),".csv") + "-" + target, ...
                    '[^A-Za-z0-9]','-'));
                row.SourceSchemaID = localSchemaID(fileName,T);
                row.TargetSchemaID = "phase18:" + string(fileName) + ...
                    ":" + target;
                row.SourceArtifact = string(fileName);
                row.TargetArtifact = string(fileName);
                row.SourceColumns = strjoin(sourceColumns,"|");
                row.TargetColumns = target;
                row.DerivedColumns = target;
                row.TransformationFormula = formula;
                row.Lossless = true;
                row.RowsIn = height(T);
                row.SourceArtifactSHA256 = lower(string(sourceHash));
                row.AdapterVersion = "phase18-evidence-adapter-v1";
                row.OutputArtifactSHA256 = "";
                row.Status = "PASS";
                row.Details = "Derived exclusively from observed runtime columns.";
                metadata(end+1,1) = row; %#ok<AGROW>
            end
            names = string(fieldnames(derived));
            if isempty(names)
                return;
            end
            lengths = zeros(numel(names),1);
            for nameIndex=1:numel(names)
                lengths(nameIndex)=numel(derived.(char(names(nameIndex))));
            end
            cardinalityChanged = any(lengths~=height(T));
            if hasScalar
                canonical = table();
                for target = reshape(columns,1,[])
                    if isfield(derived,char(target))
                        value = derived.(char(target));
                        if ~isscalar(value)
                            error("FULLSTACK:SchemaAdapterShapeMismatch", ...
                                "Adapter mixes scalar and vector targets.");
                        end
                        canonical.(char(target)) = value;
                    elseif ismember(target,string(T.Properties.VariableNames))
                        raw = T.(char(target));
                        uniqueRaw = unique(string(raw));
                        if numel(uniqueRaw)~=1
                            error("FULLSTACK:SchemaAdapterWouldLoseRows", ...
                                "Cannot losslessly reduce column '%s'.",target);
                        end
                        canonical.(char(target)) = raw(1);
                    end
                end
                adapted = canonical;
            elseif cardinalityChanged
                if any(lengths~=lengths(1)) || ...
                        any(~ismember(columns,names))
                    error("FULLSTACK:SchemaAdapterShapeMismatch", ...
                        "Cardinality-changing adapter cannot retain unrelated source columns.");
                end
                canonical=table();
                for target=reshape(names,1,[])
                    canonical.(char(target))=derived.(char(target));
                end
                adapted=canonical;
            else
                for target = reshape(names,1,[])
                    value = derived.(char(target));
                    if numel(value)~=height(T)
                        error("FULLSTACK:SchemaAdapterShapeMismatch", ...
                            "Vector adapter for '%s' changed row cardinality.", ...
                            target);
                    end
                    adapted.(char(target)) = value;
                end
            end
            if ~isempty(metadata)
                results = struct2table(metadata,"AsArray",true);
                results.RowsOut(:) = height(adapted);
            end
        end

        function T = emptyResults()
            T = struct2table(repmat(localMetadataRow(),0,1), ...
                "AsArray",true);
        end

        function T = unsupported(fileName,sourceColumns, ...
                targetColumns,sourceHash,details)
            row=localMetadataRow();
            sourceColumns=string(sourceColumns(:));
            targetColumns=string(targetColumns(:));
            row.AdapterID="ADAPT-UNSUPPORTED-"+upper(regexprep( ...
                erase(string(fileName),".csv"),'[^A-Za-z0-9]','-'));
            row.SourceArtifact=string(fileName);
            row.TargetArtifact=string(fileName);
            row.SourceSchemaID=localSchemaText(fileName,sourceColumns);
            row.TargetSchemaID="phase18:"+string(fileName)+":" + ...
                strjoin(targetColumns,"|");
            row.SourceColumns=strjoin(sourceColumns,"|");
            row.TargetColumns=strjoin(targetColumns,"|");
            row.Lossless=false;
            row.SourceArtifactSHA256=lower(string(sourceHash));
            row.AdapterVersion="phase18-evidence-adapter-v1";
            row.Status="UNSUPPORTED";
            row.FailureCode="FULLSTACK:SchemaAdapterUnsupported";
            row.Details=string(details);
            T=struct2table(row,"AsArray",true);
        end
    end
end

function [found,value,sourceColumns,formula] = localDerive(fileName,target,T)
found = true;
value = [];
sourceColumns = strings(0,1);
formula = "";
key = lower(string(fileName)) + "::" + string(target);
switch key
    case {"frame_numerology_matrix.csv::CaseID", ...
            "carrier_grid_matrix.csv::CaseID", ...
            "slot_symbol_ownership.csv::CaseID", ...
            "allocation_legality.csv::CaseID", ...
            "ofdm_roundtrip.csv::CaseID", ...
            "bwp_switch_trace.csv::CaseID", ...
            "component_carrier_trace.csv::CaseID"}
        [value,sourceColumns,formula] = localRename(T,"TestID");
    case "frame_numerology_matrix.csv::SymbolsPerSlot"
        [value,sourceColumns,formula] = ...
            localRename(T,"ResolvedSymbolsPerSlot");
    case "frame_numerology_matrix.csv::SlotsPerSubframe"
        [value,sourceColumns,formula] = ...
            localRename(T,"ResolvedSlotsPerSubframe");
    case "frame_numerology_matrix.csv::SlotsPerFrame"
        [value,sourceColumns,formula] = ...
            localRename(T,"ResolvedSlotsPerFrame");
    case "carrier_grid_matrix.csv::Bandwidth_MHz"
        [value,sourceColumns,formula] = ...
            localRename(T,"ChannelBandwidth_MHz");
    case "carrier_grid_matrix.csv::SCS_kHz"
        [value,sourceColumns,formula] = ...
            localRename(T,"CarrierSCS_kHz");
    case "carrier_grid_matrix.csv::NSizeGrid"
        [value,sourceColumns,formula] = localRename(T,"ResolvedNRB");
    case "carrier_grid_matrix.csv::Guardband_kHz"
        low=localNumeric(T,"GuardbandLow_Hz");
        high=localNumeric(T,"GuardbandHigh_Hz");
        value=min(low,high)/1000;
        sourceColumns=["GuardbandLow_Hz","GuardbandHigh_Hz"];
        formula="min(GuardbandLow_Hz,GuardbandHigh_Hz)/1000";
    case "slot_symbol_ownership.csv::AbsoluteSlot"
        % The source evidence explicitly records Frame=0 for this
        % qualification vector, so Slot is already its absolute slot.
        frame=localNumeric(T,"Frame");
        if any(frame~=0)
            error("FULLSTACK:SchemaAdapterUnsupportedFrameIndex", ...
                "AbsoluteSlot requires slots-per-frame when Frame is nonzero.");
        end
        [value,sourceColumns,formula]=localRename(T,"Slot");
    case "slot_symbol_ownership.csv::CommonOwnership"
        [value,sourceColumns,formula]=localRename(T,"CommonDirection");
    case "slot_symbol_ownership.csv::DedicatedOwnership"
        [value,sourceColumns,formula]=localRename(T,"DedicatedDirection");
    case "slot_symbol_ownership.csv::ResolvedOwnership"
        [value,sourceColumns,formula]=localRename(T,"ResolvedDirection");
    case "allocation_legality.csv::AllocationID"
        [value,sourceColumns,formula]=localRename(T,"TestID");
    case "allocation_legality.csv::Legal"
        [value,sourceColumns,formula]=localRename(T,"ActualValid");
    case "allocation_legality.csv::ErrorIdentifier"
        [value,sourceColumns,formula]=localRename(T,"ReasonCode");
    case "ofdm_roundtrip.csv::EVM_pct"
        [value,sourceColumns,formula]=localRename(T,"EVMPercent");
    case "bwp_switch_trace.csv::AbsoluteSlot"
        [value,sourceColumns,formula]=localRename(T,"AbsSlot");
    case "bwp_switch_trace.csv::NewBWPID"
        [value,sourceColumns,formula]=localRename(T,"ActiveBWPID");
    case "bwp_switch_trace.csv::CommandSource"
        [value,sourceColumns,formula]=localRename(T,"TriggerSource");
    case "bwp_switch_trace.csv::ActivationSlot"
        [value,sourceColumns,formula]=localRename(T,"ActivationAbsSlot");
    case "component_carrier_trace.csv::AbsoluteSlot"
        [value,sourceColumns,formula]=localRename(T,"AbsSlot");
    case "component_carrier_trace.csv::ControlCC"
        [value,sourceColumns,formula]=localRename(T,"SchedulingCCID");
    case "component_carrier_trace.csv::ScheduledCC"
        [value,sourceColumns,formula]=localRename(T,"ScheduledCCID");
    case "component_carrier_trace.csv::GrantID"
        [value,sourceColumns,formula]=localRename(T,"TestID");
    case "frame_image_audit.csv::Image"
        [value,sourceColumns,formula]=localRename(T,"ImageFile");
    case "frame_image_audit.csv::PNG_SHA256"
        [value,sourceColumns,formula]=localRename(T,"ImageSHA256");
    case "slot_symbol_ownership.csv::IllegalFixedDirectionOverrideCount"
        value = nnz(~localPass(T));
        sourceColumns = ["CommonDirection","DedicatedDirection", ...
            "ResolvedDirection","Status"];
        formula = "count(Status!=PASS) in dedicated TDD ownership evidence";
    case "resource_grid_occupancy.csv::IllegalCollisionCount"
        collision = localLogical(T,"CollisionFlag");
        reservedReason = strtrim(string(localColumn(T,"ReservedReason")));
        unreserved = ismissing(reservedReason) | strlength(reservedReason) == 0;
        value = nnz(collision & unreserved);
        sourceColumns = ["CollisionFlag","ReservedReason"];
        formula = "count(CollisionFlag AND empty(ReservedReason))";
    case "waveform_ofdm_roundtrip.csv::GridNMSE"
        [value,sourceColumns,formula] = localRename(T,"NMSE");
    case "waveform_parseval.csv::RelativeEnergyError"
        [value,sourceColumns,formula] = localRename(T,"RelativeError");
    case "waveform_transform_precoding.csv::DFTRoundTripNMSE"
        [value,sourceColumns,formula] = localRename(T,"RoundTripNMSE");
    case {"waveform_power_ledger.csv::AnalyticalMeasuredError_dB", ...
            "channel_absolute_power_ledger.csv::AnalyticalMeasuredError_dB"}
        [value,sourceColumns,formula] = localRename(T,"Error_dB");
    case "channel_geometry_state.csv::Delay_s"
        [value,sourceColumns,formula] = localRename(T,"PropagationDelay_s");
    case "rf_cfo_tracking.csv::InjectedCFO_Hz"
        [value,sourceColumns,formula] = localRename(T,"TrueCFO_Hz");
    case "rf_iq_compensation.csv::EVM_After_pct"
        [value,sourceColumns,formula] = localRename(T,"EVMAfter_pct");
    case "rf_iq_compensation.csv::EVM_Before_pct"
        [value,sourceColumns,formula] = localRename(T,"EVMBefore_pct");
    case "rf_dpd_validation.csv::HoldoutACLR_After_dB"
        [value,sourceColumns,formula] = localRename(T,"ACLRAfter_dB");
    case "rf_dpd_validation.csv::HoldoutACLR_Before_dB"
        [value,sourceColumns,formula] = localRename(T,"ACLRBefore_dB");
    case "rf_ul_power_control.csv::RequestedMeasuredError_dB"
        requested = localNumeric(T,"RequestedPower_dBm");
        measured = localNumeric(T,"MeasuredPower_dBm");
        value = requested-measured;
        sourceColumns = ["RequestedPower_dBm","MeasuredPower_dBm"];
        formula = "RequestedPower_dBm-MeasuredPower_dBm";
    case "channel_interference_covariance.csv::CovarianceMismatch"
        er = localNumeric(T,"ExpectedReal")-localNumeric(T,"ActualReal");
        ei = localNumeric(T,"ExpectedImag")-localNumeric(T,"ActualImag");
        value = hypot(er,ei);
        sourceColumns = ["ExpectedReal","ActualReal", ...
            "ExpectedImag","ActualImag"];
        formula = "hypot(ExpectedReal-ActualReal,ExpectedImag-ActualImag)";
    case "channel_interference_contributions.csv::CompositeMinusSumNMSE"
        value = localCompositeNMSE(T);
        sourceColumns = ["CaseID","SampleIndex0","ContributionReal", ...
            "ContributionImag","CompositeReal","CompositeImag"];
        formula = "per_sample_abs2(composite-sum(contributions))/max(abs2(composite),eps)";
    case "waveform_stream_continuity.csv::MismatchSamples"
        expected = localNumeric(T,"SampleCountExpected");
        actual = localNumeric(T,"SampleCountActual");
        value = sum(abs(expected-actual));
        sourceColumns = ["SampleCountExpected","SampleCountActual"];
        formula = "sum(abs(SampleCountExpected-SampleCountActual))";
    case "pdcch_blind_trials.csv::OracleCandidateInputsUsed"
        known = localLogical(T,"KnownLocationUsed");
        timing = localLogical(T,"OracleTimingUsed");
        value = nnz(known|timing);
        sourceColumns = ["KnownLocationUsed","OracleTimingUsed"];
        formula = "count(KnownLocationUsed OR OracleTimingUsed)";
    case "pdcch_blind_trials.csv::FalseGrantCount"
        value = nnz(localLogical(T,"FalseAlarm"));
        sourceColumns = "FalseAlarm";
        formula = "count(FalseAlarm)";
    case "pdcch_grant_authority.csv::InvalidDCIGrantCount"
        invalid = ~(localLogical(T,"CRCCheckPassed") & ...
            localLogical(T,"RNTIMatch") & localLogical(T,"ContextCurrent"));
        value = nnz(invalid & localLogical(T,"AssignmentCreated"));
        sourceColumns = ["CRCCheckPassed","RNTIMatch", ...
            "ContextCurrent","AssignmentCreated"];
        formula = "count(AssignmentCreated AND NOT(CRCCheckPassed AND RNTIMatch AND ContextCurrent))";
    case "pucch_format_matrix.csv::RequiredFormatsPassed"
        valid = localLogical(T,"Valid")==localLogical(T,"ExpectedValid");
        valid = valid & localPass(T);
        value = numel(unique(string(T.Format(valid))));
        sourceColumns = ["Format","Valid","ExpectedValid","Status"];
        formula = "count(unique(Format where Valid==ExpectedValid and Status==PASS))";
    case "pucch_uci_serialization.csv::MismatchCount"
        value = nnz(localLogical(T,"Mismatch"));
        sourceColumns = "Mismatch";
        formula = "count(Mismatch)";
    case "pucch_timing_k1_tdd.csv::ScanForwardOrMovedResourceCount"
        moved = localLogical(T,"SymbolShiftApplied") | ...
            localNumeric(T,"DueSlot")~=localNumeric(T,"ExpectedDueSlot");
        value = nnz(moved);
        sourceColumns = ["SymbolShiftApplied","DueSlot","ExpectedDueSlot"];
        formula = "count(SymbolShiftApplied OR DueSlot!=ExpectedDueSlot)";
    case "rsla_resource_ownership.csv::UnresolvedCollisionCount"
        state = lower(string(localColumn(T,"CollisionStatus")));
        value = nnz(~startsWith(state,"resolved"));
        sourceColumns = "CollisionStatus";
        formula = "count(NOT startsWith(CollisionStatus,'resolved'))";
    case "rsla_measurement_results.csv::ConfiguredMeasurementSubstitutionCount"
        provenance = lower(string(localColumn(T,"Provenance")));
        value = nnz(contains(provenance,"config"));
        sourceColumns = "Provenance";
        formula = "count(contains(lower(Provenance),'config'))";
    case "rsla_trs_tracking.csv::CorrectionNotAppliedCount"
        value = nnz(~localLogical(T,"CorrectionApplied"));
        sourceColumns = "CorrectionApplied";
        formula = "count(NOT CorrectionApplied)";
    case "rsla_csi_uci_roundtrip.csv::BitMismatchCount"
        informationBits = localNumeric(T,"InformationBits");
        semanticRows = upper(string(localColumn(T,"Status")))=="PASS" & ...
            informationBits>0;
        crc = lower(string(localColumn(T,"CRCStatus")))=="true";
        semantic = lower(string(localColumn(T,"SemanticStatus")))=="true";
        mismatch = semanticRows & (informationBits~= ...
            localNumeric(T,"DecodedBits") | ~crc | ~semantic);
        value = nnz(mismatch);
        sourceColumns = ["InformationBits","DecodedBits", ...
            "CRCStatus","SemanticStatus"];
        formula = "count(InformationBits!=DecodedBits OR NOT CRCStatus OR NOT SemanticStatus)";
    case "rsla_link_adaptation_decisions.csv::ConfiguredSNRDecisionCount"
        source = lower(string(localColumn(T,"DecisionSource")));
        value = nnz(contains(source,"configured_snr"));
        sourceColumns = "DecisionSource";
        formula = "count(contains(lower(DecisionSource),'configured_snr'))";
    case "rsla_effective_sinr_trials.csv::FallbackCalibrationCount"
        method = lower(string(localColumn(T,"Method")));
        calibration = string(localColumn(T,"CalibrationDatasetID"));
        value = nnz(contains(method,"fallback") | ismissing(calibration) | ...
            strlength(strtrim(calibration))==0);
        sourceColumns = ["Method","CalibrationDatasetID"];
        formula = "count(contains(lower(Method),'fallback') OR missing(CalibrationDatasetID))";
    case {"rsla_olla_state.csv::StateLeakageCount", ...
            "channel_geometry_state.csv::ConfiguredBackfillCount", ...
            "channel_doppler_phase.csv::PhaseDiscontinuityCount", ...
            "channel_pathloss_trials.csv::EquationMismatchCount", ...
            "rf_sco_resampler.csv::SampleCountMismatch", ...
            "rf_phase_noise_tracking.csv::MaskMismatchCount", ...
            "mac_harq_process_states.csv::IdentityMismatchCount", ...
            "mac_soft_buffer_ledger.csv::InvalidCombineCount", ...
            "mac_bsr_state.csv::TableMismatchCount", ...
            "mac_phr_state.csv::MappingMismatchCount", ...
            "pdcp_count_state.csv::COUNTStateMismatchCount"}
        value = nnz(~localPass(T));
        sourceColumns = "Status";
        formula = "count(Status!=PASS) in dedicated conformance artifact";
    case "channel_doppler_phase.csv::DopplerSignMismatchCount"
        expected = localNumeric(T,"ExpectedDoppler_Hz");
        actual = localNumeric(T,"ActualDoppler_Hz");
        value = nnz(sign(expected)~=sign(actual));
        sourceColumns = ["ExpectedDoppler_Hz","ActualDoppler_Hz"];
        formula = "count(sign(ExpectedDoppler_Hz)!=sign(ActualDoppler_Hz))";
    case "channel_los_state.csv::ObservedNLOSRowCount"
        value = nnz(upper(string(localColumn(T,"LOSState")))=="NLOS");
        sourceColumns = "LOSState";
        formula = "count(LOSState==NLOS)";
    case "channel_o2i_trials.csv::RuntimeO2IRowCount"
        value = height(T);
        sourceColumns = string(T.Properties.VariableNames);
        formula = "row_count(runtime O2I evidence)";
    case "rf_blocker_trials.csv::SampleDomainBlockerAppliedCount"
        value = nnz(localPass(T));
        sourceColumns = "Status";
        formula = "count(Status==PASS) in sample-domain blocker trials";
    case "mac_timing_decisions.csv::IllegalTimingAcceptedCount"
        legal = localLogical(T,"TDDLegal") & ...
            localLogical(T,"ProcessingLegal") & ...
            localLogical(T,"ResourceLegal");
        value = nnz(~legal & localPass(T));
        sourceColumns = ["TDDLegal","ProcessingLegal", ...
            "ResourceLegal","Status"];
        formula = "count(NOT(all legality flags) AND Status==PASS)";
    case "mac_timing_advance_state.csv::AppliedSampleShiftMismatchCount"
        value = nnz(localNumeric(T,"NTA")~= ...
            localNumeric(T,"AppliedSampleShift"));
        sourceColumns = ["NTA","AppliedSampleShift"];
        formula = "count(NTA!=AppliedSampleShift)";
    case "mac_scheduler_grants.csv::IllegalGrantCount"
        value = nnz(~localLogical(T,"Committed") | ~localPass(T));
        sourceColumns = ["Committed","Status"];
        formula = "count(NOT Committed OR Status!=PASS)";
    case "mac_pdu_roundtrip.csv::EncodeDecodeMismatchCount"
        value = sum(localNumeric(T,"ByteMismatchCount") + ...
            localNumeric(T,"UnownedBytes") + ...
            localNumeric(T,"OverlappingBytes"));
        sourceColumns = ["ByteMismatchCount","UnownedBytes", ...
            "OverlappingBytes"];
        formula = "sum(ByteMismatchCount+UnownedBytes+OverlappingBytes)";
    case {"rlc_pdu_encoding.csv::BitMismatchCount", ...
            "rlc_status_pdus.csv::BitMismatchCount", ...
            "pdcp_security_results.csv::VectorMismatchCount", ...
            "rrc_asn1_messages.csv::UPERMismatchCount"}
        value = sum(localNumeric(T,"MismatchCount"));
        sourceColumns = "MismatchCount";
        formula = "sum(MismatchCount)";
    case "sdap_qfi_drb_mapping.csv::FallbackMappingCount"
        source = lower(string(localColumn(T,"DecisionSource")));
        value = nnz(contains(source,"fallback"));
        sourceColumns = "DecisionSource";
        formula = "count(contains(lower(DecisionSource),'fallback'))";
    case "radio_bearer_config.csv::NonAtomicCommitCount"
        value = nnz(~localLogical(T,"Atomic"));
        sourceColumns = "Atomic";
        formula = "count(NOT Atomic)";
    case "mac_conservation_ledger.csv::ByteConservationError"
        value = sum(abs(localNumeric(T,"EquationErrorBytes")));
        sourceColumns = "EquationErrorBytes";
        formula = "sum(abs(EquationErrorBytes))";
    case "handover_events.csv::SuccessfulHandoverCount"
        value = nnz(upper(string(localColumn(T,"ToState")))=="HO_COMPLETE");
        sourceColumns = "ToState";
        formula = "count(ToState==HO_COMPLETE)";
    case "rrc_state_transitions.csv::ReestablishmentSuccessCount"
        event = upper(string(localColumn(T,"Event")));
        value = nnz(event=="RRC_REESTABLISHMENT_COMPLETE_DECODED");
        sourceColumns = "Event";
        formula = "count(Event==RRC_REESTABLISHMENT_COMPLETE_DECODED)";
    case "full_stack_artifact_manifest.csv::PlaceholderCount"
        value = nnz(localLogical(T,"Placeholder"));
        sourceColumns = "Placeholder";
        formula = "count(Placeholder)";
    otherwise
        found = false;
end
end

function [value,sourceColumns,formula] = localRename(T,source)
value = localColumn(T,source);
sourceColumns = string(source);
formula = "lossless_rename(" + string(source) + ")";
end

function values = localCompositeNMSE(T)
caseID = string(localColumn(T,"CaseID"));
sample = localNumeric(T,"SampleIndex0");
keys = caseID + "|" + string(sample);
[uniqueKeys,~,group] = unique(keys,"stable");
values = zeros(numel(uniqueKeys),1);
cr = localNumeric(T,"ContributionReal");
ci = localNumeric(T,"ContributionImag");
xr = localNumeric(T,"CompositeReal");
xi = localNumeric(T,"CompositeImag");
for index = 1:numel(uniqueKeys)
    mask = group==index;
    composite = complex(xr(find(mask,1)),xi(find(mask,1)));
    contribution = sum(complex(cr(mask),ci(mask)));
    values(index) = abs(composite-contribution)^2/ ...
        max(abs(composite)^2,eps);
end
end

function value = localColumn(T,name)
if ~ismember(string(name),string(T.Properties.VariableNames))
    error("FULLSTACK:SchemaAdapterSourceColumnMissing", ...
        "Adapter source column '%s' is absent.",name);
end
value = T.(char(name));
if iscell(value)
    value = string(value);
end
end

function value = localNumeric(T,name)
raw = localColumn(T,name);
if isnumeric(raw) || islogical(raw)
    value = double(raw);
else
    value = str2double(string(raw));
end
if isempty(value) || any(~isfinite(value(:)))
    error("FULLSTACK:SchemaAdapterNonFiniteSource", ...
        "Adapter source column '%s' is missing or nonfinite.",name);
end
end

function value = localLogical(T,name)
raw = localColumn(T,name);
if islogical(raw)
    value = raw;
elseif isnumeric(raw)
    if any(~ismember(raw(:),[0 1]))
        error("FULLSTACK:SchemaAdapterInvalidLogical", ...
            "Adapter source column '%s' is not logical.",name);
    end
    value = logical(raw);
else
    text = lower(strtrim(string(raw)));
    trueMask = ismember(text,["true","1","yes","pass"]);
    falseMask = ismember(text,["false","0","no","fail"]);
    if any(~(trueMask|falseMask))
        error("FULLSTACK:SchemaAdapterInvalidLogical", ...
            "Adapter source column '%s' has noncanonical values.",name);
    end
    value = trueMask;
end
end

function value = localPass(T)
value = upper(strtrim(string(localColumn(T,"Status"))))=="PASS";
end

function value = localSchemaID(fileName,T)
columns = strjoin(string(T.Properties.VariableNames),"|");
value = string(fileName) + ":" + lower(string(sixgr.util.sha256Hex( ...
    unicode2native(char(columns),"UTF-8"))));
end

function value=localSchemaText(fileName,columns)
text=strjoin(string(columns(:)),"|");
value=string(fileName)+":"+lower(string(sixgr.util.sha256Hex( ...
    unicode2native(char(text),"UTF-8"))));
end

function value = localValueDigest(raw)
if isnumeric(raw)
    text = strjoin(compose("%.17g",double(raw(:).')),"|");
elseif islogical(raw)
    text = strjoin(lower(string(raw(:).')),"|");
else
    text = strjoin(string(raw(:).'),"|");
end
value = lower(string(sixgr.util.sha256Hex( ...
    unicode2native(char(text),"UTF-8"))));
end

function row = localMetadataRow()
row = struct("AdapterID","","Domain","","SourceArtifact","", ...
    "TargetArtifact","","SourceSchemaID","","TargetSchemaID","", ...
    "SourceColumns","","TargetColumns","","TransformationFormula","", ...
    "DerivedColumns","","RowsIn",0,"RowsOut",0,"Lossless",false, ...
    "SourceArtifactSHA256","","AdapterVersion","", ...
    "OutputArtifactSHA256","","Status","","FailureCode","", ...
    "Details","");
end
