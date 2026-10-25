function [summary, observations] = summarizeChannelNMSEReport(T, signal)
% Producer-contract NMSE reduction; no archive/PHY re-execution or fitting.
% SRS has a separate qualification owner and is deliberately unsupported here.
arguments
    T table
    signal (1,1) string {mustBeMember(signal,["DL","UL","TRS","CSI-RS"])}
end
summary = struct2table(summaryPrototype(), 'AsArray', true); summary = summary([],:);
observations = struct2table(observationPrototype(), 'AsArray', true); observations = observations([],:);
% Runtime startup tables can retain named 0-by-0 variables after struct2table
% of an empty trial struct. There are no operands or observations to validate
% in that case. Preserve typed empty outputs rather than creating a row or
% requiring a measurement-column shape before its first observation exists.
% Use height, not isempty: nonempty observations retain every guard below.
if height(T)==0
    return;
end
numericFields = ["NMSE_dB","NMSEScoringAvailable","ChannelEstimateReferenceUsedByReceiver", ...
    "ChannelNMSEReferenceUsedByReceiver","ChannelNMSEGainOrPhaseFitted", ...
    "ChannelNMSEGainFitted","ChannelNMSEPhaseAligned", ...
    "ChannelEstimateGainOrPhaseFitted","ChannelEstimateReferenceRFImpairmentsIncluded", ...
    "ChannelNMSEReferenceIncludesRFImpairments","ChannelEstimateComparedValues", ...
    "ChannelNMSEComparedComplexValues","ChannelNMSEPilotResourceCount", ...
    "ChannelEstimateErrorEnergy","ChannelEstimateReferenceEnergy", ...
    "ChannelNMSEErrorEnergy","ChannelNMSEReferenceEnergy", ...
    "ChannelNMSEMeasuredResourceCount","ChannelNMSEConfiguredResourceCount","ChannelNMSEAllResourcesMeasured"];
for name = numericFields
    if ismember(name,string(T.Properties.VariableNames))
        assert(size(T.(name),2)==1,'sixgr:report:NMSEColumnShape', ...
            '%s must be one scalar per original observation.',name);
        T.(name)=sixgr.truth.numericMeasurementColumn(T.(name),name);
    end
end
flagFields = ["NMSEScoringAvailable","ChannelEstimateReferenceUsedByReceiver", ...
    "ChannelNMSEReferenceUsedByReceiver","ChannelNMSEGainOrPhaseFitted", ...
    "ChannelNMSEGainFitted","ChannelNMSEPhaseAligned", ...
    "ChannelEstimateGainOrPhaseFitted","ChannelEstimateReferenceRFImpairmentsIncluded", ...
    "ChannelNMSEReferenceIncludesRFImpairments","ChannelNMSEAllResourcesMeasured"];
for name = flagFields
    if ismember(name,string(T.Properties.VariableNames))
        assert(all(T.(name)==0|T.(name)==1|isnan(T.(name))), ...
            'sixgr:report:NMSEAuthorityValue','%s must be zero, one or unavailable.',name);
    end
end
for k=1:height(T)
    row=T(k,:); record=observationPrototype(); record.Signal=signal; record.SourceRow=k;
    record.ReportedNMSE_dB=num(row,'NMSE_dB');
    [record,contract] = adapter(row,record,signal);
    record.PopulationJSON=population(row);
    record.ObservationIdentityJSON=projection(row,["Slot","Frame","Seed","TrialSeed","NoiseSeed","NoiseStreamSeed", ...
        "ObservationID","ChannelObservationID", ...
        "ObservationStartSample","ObservationEndSampleExclusive","ObservationSampleRateHz", ...
        "ReceiverObservationSHA256","ReceiverWindowID","ExecutedResourceIntervalsJSON", ...
        "SourceArtifact","SourceCSV","SourceFile","SweepAggregateSourceCSV","SweepAggregateRunFolder"]);
    record.SupportConfigurationJSON=support(row);
    record.SupportConfigurationComplete=completeSupport(row);
    record.ConfiguredSNR_dB=num(row,'ConfiguredSNR_dB');
    if ~isfinite(record.ConfiguredSNR_dB)
        record.ConfiguredSNR_dB=num(row,'SNR_dB');
        record.OperatingPointSource="SNR_dB_source_metadata";
    else
        record.OperatingPointSource="ConfiguredSNR_dB";
    end
    for name=["ChannelEstimateObservationID","CSIChannelEstimateObservationID", ...
            "ChannelEstimateResourcesCSV","ChannelEstimateResourcesCSVSHA256", ...
            "ChannelEstimateMATFile","ChannelEstimateMATFileSHA256"]
        record.(name)=txt(row,name);
    end
    if contract
        validateIndependentFlags(row);
        if record.Adapter~="isolated_executed_data_scoring/v1" && isnan(record.PilotResourceCount)
            record.Status="unavailable_original_pilot_resource_count";
        elseif any(isnan([record.ErrorEnergy,record.ReferenceEnergy,record.ComparedValues]))
            record.Status="unavailable_original_energy_or_compared_count";
        elseif isnan(record.ReportedNMSE_dB)
            record.Status="unavailable_original_NMSE";
        else
            assert(isfinite(record.ReportedNMSE_dB)||record.ReportedNMSE_dB==-Inf, ...
                'sixgr:report:InvalidChannelNMSE','Positive infinity is not a finite-reference NMSE observation.');
            assert(isfinite(record.ErrorEnergy)&&record.ErrorEnergy>=0 && ...
                isfinite(record.ReferenceEnergy)&&record.ReferenceEnergy>0 && ...
                isfinite(record.ComparedValues)&&record.ComparedValues>0 && ...
                record.ComparedValues==fix(record.ComparedValues), ...
                'sixgr:report:NMSEEnergyContract', ...
                'An available producer NMSE requires nonnegative error, positive reference and exact compared count.');
            if ~isnan(record.PilotResourceCount)
                assert(isfinite(record.PilotResourceCount)&&record.PilotResourceCount>0 && ...
                    record.PilotResourceCount==fix(record.PilotResourceCount) && ...
                    record.PilotResourceCount<=record.ComparedValues, ...
                    'sixgr:report:NMSESupportCount','Invalid original pilot support count.');
            end
            record.NMSE_dB=ratioDB(record.ErrorEnergy,record.ReferenceEnergy);
            assert(close(record.NMSE_dB,record.ReportedNMSE_dB), ...
                'sixgr:report:NMSEEnergyClosure','Original NMSE does not match its original error/reference energies.');
            validateAliases(row,record);
            record.MeasurementAvailable=true;
            record.Status="available_original_producer_contract_not_archive_reaudit";
        end
    end
    key=struct('Signal',signal,'Adapter',record.Adapter, ...
        'ReferenceSource',record.ReferenceSource,'ReferencePlane',record.ReferencePlane, ...
        'ReferenceRFImpairmentsIncluded',record.ReferenceRFImpairmentsIncluded, ...
        'ComparedValues',record.ComparedValues,'PilotResourceCount',record.PilotResourceCount, ...
        'PopulationJSON',record.PopulationJSON,'SupportConfigurationJSON',record.SupportConfigurationJSON);
    record.PopulationID=string(sixgr.util.sha256Hex(jsonencode(key)));
    seriesKey=key;
    seriesKey.PopulationJSON=population(row,false);
    % Exclude only explicit operating-point coordinates. In particular,
    % differing original run/config hashes and configured seeds still differ;
    % unknown cross-run compatibility is never inferred by the plot consumer.
    record.PopulationSeriesJSON=string(jsonencode(sixgr.util.jsonSafeValue(seriesKey)));
    record.PopulationSeriesID=string(sixgr.util.sha256Hex(char(record.PopulationSeriesJSON)));
    observations=[observations;struct2table(record,'AsArray',true)]; %#ok<AGROW>
end
keys=unique(observations.PopulationID(observations.MeasurementAvailable),'stable');
for key=reshape(keys,1,[])
    part=observations(observations.PopulationID==key & observations.MeasurementAvailable,:);
    row=summaryPrototype();
    for name=["Signal","Adapter","PopulationID","PopulationJSON","SupportConfigurationJSON", ...
            "PopulationSeriesID","PopulationSeriesJSON", ...
            "ReferenceSource","ReferencePlane","ReferenceRFImpairmentsIncluded", ...
            "ConfiguredSNR_dB","OperatingPointSource"]
        row.(name)=part.(name)(1);
    end
    values=sort(part.NMSE_dB); peak=max(values);
    row.MeanNMSE_dB=peak;
    if isfinite(peak), row.MeanNMSE_dB=peak+10*log10(mean(10.^((values-peak)/10))); end
    row.P05NMSE_dB=values(ceil(.05*numel(values)));
    row.P95NMSE_dB=values(ceil(.95*numel(values)));
    row.MaxNMSE_dB=values(end);
    row.MeasurementCount=height(part);
    row.SourceObservationRowsJSON=string(jsonencode(part.SourceRow.'));
    row.SupportConfigurationComplete=all(part.SupportConfigurationComplete);
    row.PooledEnergyAvailable=height(part)==1 || row.SupportConfigurationComplete;
    if row.PooledEnergyAvailable
        row.ErrorEnergy=sum(part.ErrorEnergy); row.ReferenceEnergy=sum(part.ReferenceEnergy);
        assert(isfinite(row.ErrorEnergy)&&isfinite(row.ReferenceEnergy), ...
            'sixgr:report:NMSEEnergyOverflow','Pooled energies must remain representable.');
        row.PooledNMSE_dB=ratioDB(row.ErrorEnergy,row.ReferenceEnergy);
        row.PooledEnergyStatus="original_energy_sums_within_explicit_population";
    else
        row.PooledEnergyStatus="unavailable_cross_observation_exact_support_configuration_not_retained";
    end
    summary=[summary;struct2table(row,'AsArray',true)]; %#ok<AGROW>
end
end

function [r,ok]=adapter(T,r,signal)
ok=false;
direction=txt(T,'Direction');
if strlength(direction)>0
    expected="DL"; if signal=="UL", expected="UL"; end
    assert(direction==expected,'sixgr:report:NMSESignalIdentity', ...
        'Declared trial direction disagrees with the source family.');
end
if signal=="DL" || signal=="UL"
    channel="PDSCH"; if signal=="UL", channel="PUSCH"; end
    r.ReferenceSource=txt(T,'NMSESource');
    r.ReferencePlane=txt(T,'ChannelEstimateReferencePlane');
    r.ReferenceRFImpairmentsIncluded=num(T,'ChannelEstimateReferenceRFImpairmentsIncluded');
    source="same_executed_desired_link_waveform_post_decode_"+channel+"_DMRS_LS";
    plane="effective_"+channel+"_layer_channel_on_recorded_RX_clock_with_executed_RX_CFO_and_received_correction_before_other_RX_RF";
    coefficientSource="same_executed_channel_samples_and_actual_"+channel+"_linear_operators";
    coefficientPlane="nominal_linear_effective_"+channel+"_layer_channel_on_actual_receiver_FFT_clock";
    if txt(T,'ChannelEstimateCaptureStatus')~="measured_and_independently_scored_after_reception" || ...
            strlength(txt(T,'ChannelEstimateObservationID'))==0
        return;
    end
    if ~(r.ReferenceSource==source && r.ReferencePlane==plane && r.ReferenceRFImpairmentsIncluded==1) && ...
            ~(r.ReferenceSource==coefficientSource && r.ReferencePlane==coefficientPlane && r.ReferenceRFImpairmentsIncluded==0)
        r.Status="excluded_unsupported_or_unmatched_data_reference_contract"; return;
    end
    validateIndependentFlags(T);
    if strlength(txt(T,'ChannelObservationID'))>0
        r.Adapter="shared_data_independent_pilot_score/v1";
        assert(txt(T,'ChannelObservationID')==txt(T,'ChannelEstimateObservationID'), ...
            'sixgr:report:NMSEObservationIdentity','Shared capture and estimate identities disagree.');
        if num(T,'NMSEScoringAvailable')~=1 || num(T,'ChannelNMSEGainOrPhaseFitted')~=0 || ...
                num(T,'ChannelNMSEReferenceUsedByReceiver')~=0 || ...
                num(T,'ChannelEstimateReferenceUsedByReceiver')~=0
            r.Status="unavailable_explicit_shared_reference_authority"; return;
        end
        r.ErrorEnergy=num(T,'ChannelNMSEErrorEnergy');
        r.ReferenceEnergy=num(T,'ChannelNMSEReferenceEnergy');
        r.ComparedValues=num(T,'ChannelNMSEComparedComplexValues');
        r.PilotResourceCount=num(T,'ChannelNMSEPilotResourceCount');
    elseif startsWith(txt(T,'ChannelEstimateObservationID'),"isolated_hest_")
        r.Adapter="isolated_executed_data_scoring/v1";
        if r.ReferenceSource~=source || num(T,'ChannelEstimateReferenceUsedByReceiver')~=0
            r.Status="unavailable_explicit_isolated_reference_authority"; return;
        end
        % This exact producer enforces no fitting in its independent scorer;
        % it predates a flat no-fit flag. Do not fabricate that missing field.
        r.ErrorEnergy=num(T,'ChannelEstimateErrorEnergy');
        r.ReferenceEnergy=num(T,'ChannelEstimateReferenceEnergy');
        r.ComparedValues=num(T,'ChannelEstimateComparedValues');
    else
        r.Status="excluded_unknown_data_scoring_producer"; return;
    end
elseif signal=="TRS"
    r.Adapter="TRS_independent_complex_pilot_score/v1";
    r.ReferenceSource=txt(T,'NMSEReferenceSource');
    r.ReferencePlane=txt(T,'ChannelNMSEReferencePlane');
    r.ReferenceRFImpairmentsIncluded=num(T,'ChannelNMSEReferenceIncludesRFImpairments');
    if num(T,'NMSEScoringAvailable')~=1 || ...
            txt(T,'ChannelNMSEQualificationMode')~="independent_complex_pilot_resources_no_gain_or_phase_fit"
        r.Status="unavailable_explicit_TRS_reference_authority"; return;
    end
    validateIndependentFlags(T);
    nominal=ismember(r.ReferenceSource,["applied_channel_gain_truth_shared_NR_path_filter_reference", ...
        "applied_identity_AWGN_operator_TRS_port_reference","applied_fixed_matrix_AWGN_operator_TRS_port_reference", ...
        "applied_piecewise_matrix_AWGN_operator_TRS_port_reference"]) && ...
        r.ReferencePlane=="nominal_linear_TRS_port_response_with_executed_fading_loss_and_declared_TX_power" && ...
        r.ReferenceRFImpairmentsIncluded==0;
    matched=r.ReferenceSource=="same_executed_desired_link_waveform_post_decode_TRS_pilot_ratio" && ...
        r.ReferencePlane=="effective_TRS_port_channel_on_recorded_RX_timing_clock_with_executed_RX_CFO_and_received_frequency_correction_before_other_RX_RF" && ...
        r.ReferenceRFImpairmentsIncluded==1;
    if ~(nominal||matched)
        r.Status="excluded_unsupported_or_unmatched_TRS_reference_contract"; return;
    end
    r.ErrorEnergy=num(T,'ChannelNMSEErrorEnergy'); r.ReferenceEnergy=num(T,'ChannelNMSEReferenceEnergy');
    r.ComparedValues=num(T,'ChannelNMSEComparedComplexValues'); r.PilotResourceCount=num(T,'ChannelNMSEPilotResourceCount');
else
    r.Adapter="CSI_RS_nominal_linear_pilot_score/v1";
    r.ReferenceSource=txt(T,'ChannelNMSESource'); r.ReferencePlane=txt(T,'ChannelNMSEReferencePlane');
    r.ReferenceRFImpairmentsIncluded=num(T,'ChannelNMSEReferenceIncludesRFImpairments');
    if num(T,'NMSEScoringAvailable')==1 && ...
            txt(T,'ChannelNMSEQualificationMode')=="same_execution_nominal_linear_channel_no_gain_or_phase_fit"
        validateIndependentFlags(T);
    end
    if num(T,'NMSEScoringAvailable')~=1 || num(T,'ChannelNMSEGainOrPhaseFitted')~=0 || ...
            num(T,'ChannelNMSEReferenceUsedByReceiver')~=0
        r.Status="unavailable_explicit_CSI_RS_reference_authority"; return;
    end
    if r.ReferenceSource~="executed_channel_coefficients_and_actual_resource_precoders_after_CSI_selection" || ...
            r.ReferencePlane~="nominal_linear_CSI_RS_port_channel_on_actual_RX_FFT_clock" || ...
            r.ReferenceRFImpairmentsIncluded~=0 || ...
            txt(T,'ChannelNMSEQualificationMode')~="same_execution_nominal_linear_channel_no_gain_or_phase_fit" || ...
            txt(T,'ChannelNMSEScope')~="all_available_received_CSI_RS_resources_and_all_pilot_ports_RX_branches"
        r.Status="excluded_unsupported_CSI_RS_reference_contract"; return;
    end
    measured=num(T,'ChannelNMSEMeasuredResourceCount'); configured=num(T,'ChannelNMSEConfiguredResourceCount');
    if any(isnan([measured configured num(T,'ChannelNMSEAllResourcesMeasured')]))
        r.Status="unavailable_original_CSI_RS_resource_population"; return;
    end
    assert(isfinite(measured)&&measured>0&&measured==fix(measured) && ...
        isfinite(configured)&&configured>=measured&&configured==fix(configured) && ...
        num(T,'ChannelNMSEAllResourcesMeasured')==double(measured==configured), ...
        'sixgr:report:NMSESupportCount','Original CSI-RS measured/configured populations disagree.');
    r.ErrorEnergy=num(T,'ChannelNMSEErrorEnergy'); r.ReferenceEnergy=num(T,'ChannelNMSEReferenceEnergy');
    r.ComparedValues=num(T,'ChannelNMSEComparedComplexValues'); r.PilotResourceCount=num(T,'ChannelNMSEPilotResourceCount');
end
ok=true;
end

function validateIndependentFlags(T)
for field=["ChannelNMSEGainOrPhaseFitted","ChannelEstimateGainOrPhaseFitted", ...
        "ChannelNMSEGainFitted","ChannelNMSEPhaseAligned", ...
        "ChannelNMSEReferenceUsedByReceiver","ChannelEstimateReferenceUsedByReceiver"]
    if num(T,field)==1
        error('sixgr:report:NMSEAuthorityConflict','Independent reference contract conflicts with %s.',field);
    end
end
end

function validateAliases(T,r)
for pair={"ChannelNMSEErrorEnergy",r.ErrorEnergy;"ChannelEstimateErrorEnergy",r.ErrorEnergy; ...
        "ChannelNMSEReferenceEnergy",r.ReferenceEnergy;"ChannelEstimateReferenceEnergy",r.ReferenceEnergy; ...
        "ChannelNMSEComparedComplexValues",r.ComparedValues;"ChannelEstimateComparedValues",r.ComparedValues}.'
    v=num(T,pair{1});
    if r.Adapter=="isolated_executed_data_scoring/v1" && ...
            startsWith(string(pair{1}),"ChannelNMSE") && num(T,'NMSEScoringAvailable')~=1
        continue; % Inactive shared-schema defaults do not assert a second score.
    end
    if ~isnan(v)
        assert(close(v,pair{2}),'sixgr:report:NMSEAliasConflict','Original %s disagrees with the selected producer contract.',pair{1});
    end
end
for name=["ChannelNMSEReferencePlane","ChannelEstimateReferencePlane"]
    if r.Adapter=="isolated_executed_data_scoring/v1" && ...
            name=="ChannelNMSEReferencePlane" && num(T,'NMSEScoringAvailable')~=1, continue; end
    value=txt(T,name);
    if strlength(value)>0 && value~="unavailable"
        assert(value==r.ReferencePlane,'sixgr:report:NMSEAliasConflict','Reference-plane aliases disagree.');
    end
end
for name=["ChannelEstimateReferenceRFImpairmentsIncluded","ChannelNMSEReferenceIncludesRFImpairments"]
    value=num(T,name);
    if ~isnan(value)
        assert(value==r.ReferenceRFImpairmentsIncluded,'sixgr:report:NMSEAliasConflict', ...
            'Original reference RF-scope fields disagree.');
    end
end
end

function token=population(T,includeOperatingPoint)
if nargin<2, includeOperatingPoint=true; end
% Seed is the original per-trial/frame seed (base+trial-1), not a configured
% campaign cohort. It and incidental noise seeds remain observation provenance.
% Source*/Prepared* seeds are explicitly frozen configuration inputs, not draws.
fields=["RunID","RunTag","ExecutionID","ScenarioID","ConfigHash","RandomSeed","ChannelSeed", ...
    "SourceRandomSeed","SourceChannelSeed","PreparedRandomSeed","PreparedChannelSeed", ...
    "SweepPointIndex","SweepAggregatePointIndex","PointIndex","ConfiguredSNR_dB","SNR_dB", ...
    "UEIndex","UEID","RNTI","CellID","ServingCell","ReceiverID","ReceiverClockDomain", ...
    "ReceiverClockEpoch","ConfigurationEpoch","RFConfigurationEpoch","ChannelModelApplied","ChannelModel","ChannelFadingApplied", ...
    "DopplerHz","ChannelNMSEMeasuredResourceCount","ChannelNMSEConfiguredResourceCount","ChannelNMSEScope"];
if ~includeOperatingPoint
    fields=fields(~ismember(fields,["SweepPointIndex","SweepAggregatePointIndex","PointIndex","ConfiguredSNR_dB","SNR_dB"]));
end
token=projection(T,fields);
end

function token=support(T)
token=projection(T,["PRBSet","PRBSetJSON","SymbolAllocation","SymbolAllocationJSON", ...
    "DMRSPortSet","DMRSPortSetJSON","DMRSConfigType","DMRSLength","DMRSAdditionalPosition","DMRSTypeAPosition", ...
    "Layers","NumLayers","NumRxAnt","NumRxAntennas","NumTxAnt","NumLogicalPorts", ...
    "NSizeGrid","NStartGrid","SubcarrierSpacing_kHz","SubcarrierSpacing","HestDimensions", ...
    "ResourceID","ResourceGridPRBCount","ResourceSymbolsPerSlot"]);
end

function yes=completeSupport(T)
% Count/shape equality alone is not an exact pilot-support configuration.
% Current rows without these original allocation operands keep their valid
% individual/mean observations but cannot make a cross-observation pooled claim.
yes=all(ismember(["PRBSet","SymbolAllocation","DMRSPortSet", ...
    "DMRSConfigType","DMRSLength","DMRSAdditionalPosition","DMRSTypeAPosition","NSizeGrid","SubcarrierSpacing"], ...
    string(T.Properties.VariableNames))) && ...
    (isfinite(num(T,'NumRxAnt')) || isfinite(num(T,'NumRxAntennas')));
if yes
    for name=["PRBSet","SymbolAllocation","DMRSPortSet"]
        value=T.(name); if iscell(value)&&isscalar(value), value=value{1}; end
        yes=yes && isnumeric(value) && ~isempty(value) && all(isfinite(value),'all');
        if isnumeric(value) && ~isempty(value) && all(isfinite(value),'all')
            assert(isreal(value)&&isvector(value)&&all(value>=0 & value==fix(value),'all'), ...
                'sixgr:report:NMSESupportConfiguration','Original %s requires nonnegative integer coordinates.',name);
            if name=="SymbolAllocation"
                assert(numel(value)==2&&value(2)>0,'sixgr:report:NMSESupportConfiguration', ...
                    'Original symbol allocation requires start and positive length.');
            else
                assert(numel(unique(value))==numel(value),'sixgr:report:NMSESupportConfiguration', ...
                    'Original support coordinates must not contain duplicates.');
            end
        end
    end
    for name=["DMRSConfigType","DMRSLength","DMRSAdditionalPosition","DMRSTypeAPosition","NSizeGrid","SubcarrierSpacing"]
        yes=yes && isfinite(num(T,name));
    end
end
end

function token=projection(T,fields)
p=struct();
for name=fields
    if ~ismember(name,string(T.Properties.VariableNames)), continue; end
    value=T.(name);
    if iscell(value)&&isscalar(value), value=value{1}; end
    if ischar(value), value=string(value); end
    p.(name)=value;
end
token=string(jsonencode(sixgr.util.jsonSafeValue(p)));
end

function value=num(T,name)
value=NaN;
if ~ismember(name,string(T.Properties.VariableNames)), return; end
raw=T.(name);
assert(numel(raw)==1,'sixgr:report:NMSEColumnShape','%s must be scalar per original row.',name);
value=sixgr.truth.numericMeasurementColumn(raw,name);
end

function value=txt(T,name)
value="";
if ~ismember(name,string(T.Properties.VariableNames)), return; end
value=string(T.(name));
assert(isscalar(value),'sixgr:report:NMSEColumnShape','%s must retain scalar text.',name);
if ismissing(value), value=""; end
end

function value=ratioDB(errorEnergy,referenceEnergy)
if errorEnergy==0, value=-Inf; else, value=10*(log10(errorEnergy)-log10(referenceEnergy)); end
end

function yes=close(a,b)
yes=isequaln(a,b) || (isfinite(a)&&isfinite(b)&&abs(a-b)<=512*eps(max(1,max(abs([a b])))));
end

function r=observationPrototype()
r=struct('Signal',"",'SourceRow',NaN,'Adapter',"",'MeasurementAvailable',false, ...
    'Status',"unavailable_original_producer_reference_contract",'ReportedNMSE_dB',NaN,'NMSE_dB',NaN, ...
    'ErrorEnergy',NaN,'ReferenceEnergy',NaN,'ComparedValues',NaN,'PilotResourceCount',NaN, ...
    'ReferenceSource',"",'ReferencePlane',"",'ReferenceRFImpairmentsIncluded',NaN, ...
    'PopulationJSON',"",'ObservationIdentityJSON',"",'SupportConfigurationJSON',"",'PopulationID',"", ...
    'PopulationSeriesID',"",'PopulationSeriesJSON',"", ...
    'SupportConfigurationComplete',false,'ConfiguredSNR_dB',NaN,'OperatingPointSource',"", ...
    'ChannelEstimateObservationID',"",'CSIChannelEstimateObservationID',"", ...
    'ChannelEstimateResourcesCSV',"",'ChannelEstimateResourcesCSVSHA256',"", ...
    'ChannelEstimateMATFile',"",'ChannelEstimateMATFileSHA256',"", ...
    'EvidenceValidationScope',"original_producer_row_contract_not_independent_archive_reaudit", ...
    'CountsTowardCoverage',false,'StatisticalIndependenceClaimed',false);
end

function r=summaryPrototype()
r=struct('Signal',"",'Adapter',"",'PopulationID',"",'PopulationJSON',"",'SupportConfigurationJSON',"", ...
    'PopulationSeriesID',"",'PopulationSeriesJSON',"", ...
    'ReferenceSource',"",'ReferencePlane',"",'ReferenceRFImpairmentsIncluded',NaN, ...
    'ConfiguredSNR_dB',NaN,'OperatingPointSource',"",'MeanNMSE_dB',NaN,'P05NMSE_dB',NaN, ...
    'P95NMSE_dB',NaN,'MaxNMSE_dB',NaN,'MeasurementCount',0,'SourceObservationRowsJSON',"", ...
    'MeanDefinition',"equal_observation_mean_linear_normalized_error", ...
    'PercentileDefinition',"empirical_inverse_CDF_of_normalized_error_power_rank_ceil_p_N", ...
    'SupportConfigurationComplete',false,'PooledEnergyAvailable',false,'ErrorEnergy',NaN, ...
    'ReferenceEnergy',NaN,'PooledNMSE_dB',NaN,'PooledEnergyStatus',"", ...
    'PooledDefinition',"sum_original_error_energy_divided_by_sum_original_reference_energy", ...
    'PopulationDefinition',"identical_supplied_population_reference_support_fields_unrecorded_fields_not_inferred", ...
    'StatisticalIndependenceClaimed',false,'ConfidenceIntervalAvailable',false);
end
