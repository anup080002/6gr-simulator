function evidence = captureLinkEnergyEvidence(tx, desiredWaveform, noiseReceipt, identity, waveformAmplitudeUnit, measurement)
%CAPTURELINKENERGYEVIDENCE Retain original single-CW SCH energy operands.
% Call only at the original pre-noise/pre-RX-front-end owner, with its
% isolated desired-link samples and ORIGINAL addOccupiedREAWGN receipt.
% This post-hoc OFDM measurement executes no channel/noise/receiver again.
% It does not qualify the caller's execution or invent a lifecycle identity.
% Grid energy includes whatever desired-waveform leakage is actually on the
% data support. It is NOT isolated-layer modulation Es or post-EQ SINR.
arguments
    tx (1,1) struct
    desiredWaveform {mustBeNumeric}
    noiseReceipt (1,1) struct
    identity (1,1) struct
    waveformAmplitudeUnit (1,1) string
    measurement (1,1) struct = struct()
end
evidence=struct('Version',"branch_mean_sch_energy/v1", ...
    'Source',"sixgr.link.captureLinkEnergyEvidence",'Available',false, ...
    'Status',"not_available_missing_original_operands",'Identity',identity, ...
    'WaveformAmplitudeUnit',waveformAmplitudeUnit, ...
    'ReferencePlane',"noiseless_desired_received_grid_on_SCH_data_support_pre_noise_pre_RX_front_end", ...
    'EnergyDefinition',"sum_grid_energy_over_SCH_support_divided_by_receive_branch_count", ...
    'NoiseDefinition',"expected_complex_grid_variance_of_original_added_AWGN_not_interference", ...
    'Scope',"per_attempt_branch_mean_support_energy_not_per_layer_Es_not_combined_HARQ_energy", ...
    'AdditionalChannelExecutions',0,'AdditionalNoiseExecutions',0, ...
    'AdditionalReceiverExecutions',0,'CountsTowardCoverage',false);
% JSON null cannot distinguish an original scalar NaN from an empty array
% or infinity. Seal the exact unavailable scalar fields BEFORE encoding;
% never fill them from another receiver/configuration identity namespace.
evidence.IdentityValueContract="scalar_identity_with_explicit_numeric_NaN/v1";
evidence.IdentityMissingNumericFields=missingNumericIdentityFields(identity);
for name=evidence.IdentityMissingNumericFields'
    evidence.Identity.(name)=struct('ValueState',"original_numeric_scalar_NaN", ...
        'OriginalClass',string(class(identity.(name))),'OriginalSize',[1 1]);
end
require(isfield(identity,'Direction') && any(string(identity.Direction)==["DL","UL"]), ...
    'Original direction identity is required.');
require(any(waveformAmplitudeUnit==["sqrt_mW","normalized_complex_baseband"]), ...
    'Retain the actual waveform amplitude unit.');
direction=string(identity.Direction); family="PDSCH"; if direction=="UL", family="PUSCH"; end
required=["Carrier",family,family+"Indices","CodingLayouts","TransportBlock","G","Waveform"];
if ~all(isfield(tx,required)), return; end
layouts=tx.CodingLayouts;
if ~iscell(layouts) || numel(layouts)~=1
    evidence.Status="not_available_multi_codeword_energy_partition_not_retained"; return;
end
if direction=="UL"
    % A shared-channel support cannot be divided by G_ULSCH while it also
    % carries UCI. An absent flag is not proof of SCH-only mapping.
    if ~isfield(tx,'UCIOnPUSCHApplied') || ~isequal(tx.UCIOnPUSCHApplied,false)
        evidence.Status="not_available_UCI_or_unknown_SCH_only_support"; return;
    end
    uciFields=["HARQACKBits","CSIPart1Bits","CSIPart2Bits","ConfiguredGrantUCIBits"];
    if ~all(isfield(tx,[uciFields,"DataRateMatchedBitCount"]))
        evidence.Status="not_available_original_UL_SCH_only_budget_not_retained"; return;
    end
    for name=uciFields
        require(isempty(tx.(name)),'An explicit no-UCI flag must agree with original empty UCI payloads.');
    end
    require(isequal(double(tx.DataRateMatchedBitCount),double(tx.G)), ...
        'An explicit no-UCI flag must agree with actual G_ULSCH.');
end
require(isfloat(desiredWaveform) && ismatrix(desiredWaveform) && ~isempty(desiredWaveform) && ...
    all(isfinite(desiredWaveform),'all'),'Original finite noiseless desired-link samples are required.');
carrier=tx.Carrier; channel=tx.(family);
modulation=string(channel.Modulation);
if isfield(tx,'Modulation'), modulation=string(tx.Modulation); end
[qm,canonical]=sixgr.report.reportModulationOrder(modulation);
require(isscalar(qm) && isfinite(qm),'Retain one supported codeword modulation.');
indices=double(tx.(family+"Indices")(:)); K=12*double(carrier.NSizeGrid); L=double(carrier.SymbolsPerSlot);
require(~isempty(indices) && all(isfinite(indices) & indices>=1 & indices==fix(indices)), ...
    'Original one-based data indices are required.');
tf=unique(mod(indices-1,K*L)+1,'stable');
% Do not infer data support from total PRBs or desired/configured rate.
for name=["DMRSIndices","PTRSIndices"]
    if ~isfield(tx,name)
        evidence.Status="not_available_original_pilot_support_not_retained"; return;
    end
    pilots=double(tx.(name)(:));
    require(all(isfinite(pilots) & pilots>=1 & pilots==fix(pilots)), 'Invalid original pilot support.');
    require(isempty(intersect(tf,mod(pilots-1,K*L)+1)), 'Pilot REs cannot enter the SCH data support.');
end
if isfield(tx,'CSIRSIndices')
    pilots=double(tx.CSIRSIndices(:));
    require(all(isfinite(pilots) & pilots>=1 & pilots==fix(pilots)) && ...
        isempty(intersect(tf,mod(pilots-1,K*L)+1)), ...
        'CSI-RS cannot be counted as occupied SCH data support.');
end
symbolsName=family+"LayerSymbolsForEvidence";
if ~isfield(tx,symbolsName), evidence.Status="not_available_original_data_symbols_not_retained"; return; end
symbols=tx.(symbolsName);
require(isnumeric(symbols) && ~isempty(symbols) && all(isfinite(symbols),'all'), ...
    'Original data-symbol population must be finite.');
layers=double(channel.NumLayers);
require(isscalar(layers) && isfinite(layers) && layers>=1 && layers<=4 && layers==fix(layers) && ...
    numel(symbols)==numel(tf)*layers,'Single-codeword symbols must cover the exact common data support on every layer.');
require(isfloat(tx.Waveform) && ismatrix(tx.Waveform) && ~isempty(tx.Waveform) && ...
    all(isfinite(tx.Waveform),'all'),'Retain the original finite transmitted waveform identity.');
g=double(tx.G); bits=tx.TransportBlock;
require(isnumeric(bits) && isvector(bits) && ~isempty(bits) && all(bits(:)==0 | bits(:)==1), ...
    'Retain the actual transport block, excluding its CRC.');
require(isscalar(g) && isfinite(g) && g>0 && g==fix(g) && g==qm*numel(symbols), ...
    'SCH coded bits must match the actual single-codeword modulation-symbol population.');
layout=layouts{1};
require(isstruct(layout) && isfield(layout,'RateMatchAccounting') && ...
    all(isfield(layout,["RateMatchedBitCount","TransportBlockSize","Modulation","NumLayers"])) && ...
    double(layout.RateMatchedBitCount)==g && double(layout.TransportBlockSize)==numel(bits) && ...
    sixgr.report.reportModulationOrder(string(layout.Modulation))==qm && double(layout.NumLayers)==layers, ...
    'Original filler-aware rate-matcher accounting must match G.');
accounting=layout.RateMatchAccounting;
coding=table("LDPCSelectionAccounting/v2",string(jsonencode({accounting})),g, ...
    'VariableNames',{'CodingAccountingVersion','RateMatchAccountingJSON','RateMatchedBits'});
[attempt,~]=sixgr.report.collectLDPCRateMatchEvidence(coding,direction,"original_tx_coding_layout");
require(attempt.SelectionAvailable && attempt.SelectedPositions==g,'Actual rate-match selections must close.');
require(isfield(noiseReceipt,'Version') && ...
    string(noiseReceipt.Version)=="sixgr.phy.waveform.occupied_re_awgn/v1", ...
    'Only the original occupied-RE AWGN receipt is supported in this version.');
require(all(isfield(noiseReceipt,["NumTimeSamples","NumRxColumns","ConfiguredCyclicPrefix", ...
    "ConfiguredSubcarrierSpacing_kHz"])) && ...
    double(noiseReceipt.NumTimeSamples)==size(desiredWaveform,1) && ...
    double(noiseReceipt.NumRxColumns)==size(desiredWaveform,2) && ...
    string(noiseReceipt.ConfiguredCyclicPrefix)==string(carrier.CyclicPrefix) && ...
    double(noiseReceipt.ConfiguredSubcarrierSpacing_kHz)==double(carrier.SubcarrierSpacing), ...
    'Noise and reference must have the original matching sample shape/carrier operator.');
if isempty(fieldnames(measurement))
    [~,measurement]=sixgr.phy.waveform.measureReceivedOccupiedREEnergy( ...
        carrier,desiredWaveform,indices,'SignalFamily',family,'RetainEnergyReceipt',true);
end
require(all(isfield(measurement,["EnergySumPerReceiveBranch","DataIndicesSHA256", ...
    "UniqueTFSupportSHA256","ReferenceWaveformSHA256","ReferenceWaveformSize","GridSize"])) && ...
    string(measurement.DataIndicesSHA256)==string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(indices)) && ...
    string(measurement.UniqueTFSupportSHA256)==string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(tf)) && ...
    isequal(double(measurement.ReferenceWaveformSize),double(size(desiredWaveform))) && ...
    isequal(double(measurement.GridSize),[K L]),'Original compact energy receipt/support must match this execution.');
evidence.MeasurementReceipt=measurement;
evidence.NoiseReceipt=noiseReceipt;
evidence.DesiredWaveformSHA256=string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(desiredWaveform));
require(evidence.DesiredWaveformSHA256==string(measurement.ReferenceWaveformSHA256), ...
    'Do not transplant a measurement from another original desired waveform.');
evidence.TransmittedWaveformSHA256=string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(tx.Waveform));
evidence.DataIndicesSHA256=string(measurement.DataIndicesSHA256);
evidence.UniqueTFSupportSHA256=string(measurement.UniqueTFSupportSHA256);
evidence.GridSize=[K L]; evidence.UniqueTimeFrequencyRECount=numel(tf);
evidence.EnergySumPerReceiveBranch=measurement.EnergySumPerReceiveBranch;
evidence.Modulation=modulation; evidence.CanonicalModulation=canonical;
evidence.ModulationOrderQm=qm; evidence.ModulationSymbolCount=numel(symbols);
evidence.NumLayers=layers;
evidence.DataSymbolsSHA256=string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(symbols));
evidence.TransportBlockSHA256=string(sixgr.channel.ChannelFactory.runtimeNumericArraySHA256(bits));
evidence.CodedBitCount=g; evidence.TransportBlockBitCount=numel(bits);
evidence.RateMatchAccountingJSON=string(jsonencode({accounting}));
evidence.Available=true; evidence.Status="retained_original_single_codeword_SCH_operands";
% The collector is the single arithmetic/receipt-validation owner.
token=string(jsonencode(evidence));
probe=struct2table(identity,'AsArray',true);
probe.LinkEnergyEvidenceJSON=token;
probe.LinkEnergyEvidenceSHA256=string(sixgr.util.sha256Hex(char(token)));
sixgr.report.collectLinkEnergyRatioEvidence(probe,direction,"capture_validation");
end

function names=missingNumericIdentityFields(identity)
names=strings(0,1);
for name=string(fieldnames(identity))'
    value=identity.(name);
    if isnumeric(value)
        require(isreal(value) && isscalar(value) && ~isinf(value), ...
            "Original identity must be a finite or explicitly unavailable numeric scalar: "+name);
        if isnan(value), names(end+1,1)=name; end %#ok<AGROW>
    elseif islogical(value)
        require(isscalar(value),"Original logical identity must be scalar: "+name);
    elseif ischar(value)||isstring(value)
        require((isstring(value) || isrow(value) || isempty(value)) && ...
            isscalar(string(value)) && ~ismissing(string(value)), ...
            "Original text identity must be a nonmissing scalar (blank is retained): "+name);
    else
        require(false,"Unsupported original identity type: "+name);
    end
end
end

function require(tf,message)
assert(isscalar(tf) && tf,'sixgr:link:InvalidEnergyEvidence','%s',message);
end
