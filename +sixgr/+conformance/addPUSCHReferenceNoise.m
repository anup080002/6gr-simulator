function [rxWaveform, provenance] = addPUSCHReferenceNoise( ...
        txWaveform, carrier, pusch, standardSNR_dB, varargin)
%ADDPUSCHREFERENCENOISE Add AWGN using the TS 38.104 PUSCH SNR definition.
%
%   [Y, INFO] = sixgr.conformance.addPUSCHReferenceNoise( ...
%       X, CARRIER, PUSCH, SNR_DB, "DMRSPowerScale", BETA2)
%   converts the TS 38.104 slot-energy SNR into the occupied-data-RE Es/N0
%   consumed by sixgr.phy.waveform.addOccupiedREAWGN. For codebook PUSCH,
%   the accounting uses the actual TS 38.211 TPMI matrix energy and the
%   native precoded DM-RS symbols rather than counting zero-valued port
%   entries as signal energy.
%
%   TS 38.104 clauses 8.1.1 and 11.1.1 define SNR as total wanted-signal
%   energy in the slot on one connector/RIB divided by the noise energy in
%   the transmission bandwidth over the duration in which signal energy
%   exists. For CP-OFDM FRCs,
%
%       S = NdataRows * trace(W*W') * Edata + E{DM-RS} * beta^2
%       N = N0 * (12 * NSizeGrid * NallocatedSymbols)
%
%   and Edmrs/Edata is supplied explicitly as DMRSPowerScale. The Release
%   18 FRC token "PUSCH EPRE to DM-RS EPRE = -3 dB" is realized by the
%   truth transmitter as the exact linear power ratio 2.
%
%   This helper deliberately does not change addReferenceNoise: the latter
%   remains the downlink/occupied-grid Es/N0 primitive.

ip = inputParser;
ip.FunctionName = "sixgr.conformance.addPUSCHReferenceNoise";
ip.addRequired("txWaveform", @localValidWaveform);
ip.addRequired("carrier");
ip.addRequired("pusch");
ip.addRequired("standardSNR_dB", ...
    @(v) isnumeric(v) && isreal(v) && isscalar(v) && isfinite(v));
ip.addParameter("DMRSPowerScale", [], @localOptionalPositiveScalar);
ip.addParameter("DataEPRE", 1, @localPositiveScalar);
ip.addParameter("PrecodeInfo", struct(), ...
    @(v) isstruct(v) && isscalar(v));
ip.addParameter("Seed", [], @localValidSeed);
ip.parse(txWaveform, carrier, pusch, standardSNR_dB, varargin{:});
opt = ip.Results;

dmrsPowerScale = opt.DMRSPowerScale;
if isempty(dmrsPowerScale)
    error("sixgr:conformance:PUSCHDMRSPowerScaleRequired", ...
        ("TS 38.104 PUSCH SNR conversion requires the realized linear " + ...
        "DM-RS/data EPRE ratio; pass DMRSPowerScale from PUSCH_Tx."));
end
dmrsPowerScale = double(dmrsPowerScale);
dataEPRE = double(opt.DataEPRE);

numLayers = localObjectNumeric(pusch, "NumLayers", NaN);
numPorts = localObjectNumeric(pusch, "NumAntennaPorts", NaN);
if ~(isfinite(numLayers) && numLayers >= 1 && numLayers == fix(numLayers) && ...
        isfinite(numPorts) && numPorts >= numLayers && numPorts == fix(numPorts))
    error("sixgr:conformance:UnsupportedPUSCHSNREnergyMapping", ...
        "Invalid PUSCH layer/port tuple NumLayers=%g, NumAntennaPorts=%g.", ...
        numLayers, numPorts);
end
if logical(localObjectNumeric(pusch, "EnablePTRS", false))
    error("sixgr:conformance:UnsupportedPUSCHSNREnergyMapping", ...
        ("Exact TS 38.104 connector-energy accounting does not yet include " + ...
        "PT-RS energy. Disable PT-RS or extend the accounting explicitly."));
end

symbolAllocation = double(localObjectValue(pusch, "SymbolAllocation", []));
if numel(symbolAllocation) ~= 2 || ...
        any(~isfinite(symbolAllocation), "all") || ...
        any(symbolAllocation ~= fix(symbolAllocation), "all") || ...
        symbolAllocation(1) < 0 || symbolAllocation(2) < 1
    error("sixgr:conformance:InvalidPUSCHSymbolAllocation", ...
        "PUSCH.SymbolAllocation must be [zeroBasedStart positiveLength].");
end
symbolAllocation = reshape(symbolAllocation, 1, 2);

nSizeGrid = localObjectNumeric(carrier, "NSizeGrid", NaN);
symbolsPerSlot = localObjectNumeric(carrier, "SymbolsPerSlot", NaN);
if ~(isfinite(nSizeGrid) && nSizeGrid == fix(nSizeGrid) && nSizeGrid > 0 && ...
        isfinite(symbolsPerSlot) && symbolsPerSlot == fix(symbolsPerSlot) && ...
        symbolsPerSlot > 0 && ...
        sum(symbolAllocation) <= symbolsPerSlot)
    error("sixgr:conformance:InvalidPUSCHNoiseBandwidth", ...
        ("Carrier grid dimensions and PUSCH.SymbolAllocation must define a " + ...
        "valid in-slot TS 38.104 noise-energy interval."));
end

try
    dataIndices = nrPUSCHIndices(carrier, pusch, ...
        "IndexStyle", "index", "IndexBase", "1based");
catch
    dataIndices = nrPUSCHIndices(carrier, pusch);
end
try
    dmrsIndices = nrPUSCHDMRSIndices(carrier, pusch, ...
        "IndexStyle", "index", "IndexBase", "1based");
catch
    dmrsIndices = nrPUSCHDMRSIndices(carrier, pusch);
end
dataIndexShape = size(dataIndices);
dataIndices = double(dataIndices(:));
dmrsIndices = double(dmrsIndices(:));
if isempty(dataIndices) || isempty(dmrsIndices)
    error("sixgr:conformance:EmptyPUSCHSNREnergyMapping", ...
        "The selected PUSCH must contain both data and DM-RS resource elements.");
end

transmissionScheme = lower(strtrim(string(localObjectValue( ...
    pusch, "TransmissionScheme", "nonCodebook"))));
transformPrecoding = logical(localObjectNumeric( ...
    pusch, "TransformPrecoding", false));
tpmi = localObjectNumeric(pusch, "TPMI", NaN);
if transmissionScheme == "codebook"
    if isempty(fieldnames(opt.PrecodeInfo))
        error("sixgr:conformance:PUSCHPrecodeEvidenceRequired", ...
            ("Exact codebook-PUSCH SNR accounting requires the runtime " + ...
            "PrecodeInfo emitted by PUSCH_Tx."));
    end
    [~, codebookStatus, Wtx] = ...
        sixgr.phy.ul.puschCodebookProjectionMatrix( ...
        numLayers, numPorts, tpmi, transformPrecoding);
    localAssertRuntimeCodebook(opt.PrecodeInfo, Wtx, tpmi, codebookStatus);
elseif transmissionScheme == "noncodebook"
    Wtx = eye(numLayers);
    codebookStatus = "not_applicable_noncodebook";
    tpmi = NaN;
else
    error("sixgr:conformance:UnsupportedPUSCHSNREnergyMapping", ...
        "Unsupported PUSCH TransmissionScheme '%s'.", transmissionScheme);
end

try
    nativeDMRSSymbols = nrPUSCHDMRS(carrier, pusch);
catch cause
    failure = MException("sixgr:conformance:PUSCHDMRSEnergyUnavailable", ...
        "Unable to materialize native PUSCH DM-RS energy: %s", cause.message);
    failure = addCause(failure, cause);
    throw(failure);
end
if isempty(nativeDMRSSymbols) || any(~isfinite(nativeDMRSSymbols), "all")
    error("sixgr:conformance:PUSCHDMRSEnergyUnavailable", ...
        "Native PUSCH DM-RS symbols must be nonempty and finite.");
end

subcarriersInTransmissionBandwidth = 12 * nSizeGrid;
signalDurationSymbols = symbolAllocation(2);
noiseEnergyRECount = ...
    subcarriersInTransmissionBandwidth * signalDurationSymbols;
dataRowsPerPort = double(dataIndexShape(1));
precoderTrace = real(trace(double(Wtx) * double(Wtx)'));
if ~(isfinite(precoderTrace) && precoderTrace > 0)
    error("sixgr:conformance:InvalidPUSCHPrecoderEnergy", ...
        "The effective PUSCH precoder trace must be positive and finite.");
end
dataEnergyEquivalentRECount = dataRowsPerPort * precoderTrace;
dmrsEnergyEquivalentRECount = sum(abs(double(nativeDMRSSymbols(:))).^2);
dataRECount = dataEnergyEquivalentRECount;
dmrsRECount = dmrsEnergyEquivalentRECount;
dataSignalEnergy = dataEnergyEquivalentRECount * dataEPRE;
dmrsSignalEnergy = ...
    dmrsEnergyEquivalentRECount * dataEPRE * dmrsPowerScale;
totalSignalEnergy = dataSignalEnergy + dmrsSignalEnergy;
if ~(isfinite(totalSignalEnergy) && totalSignalEnergy > 0 && ...
        isfinite(noiseEnergyRECount) && noiseEnergyRECount > 0)
    error("sixgr:conformance:InvalidPUSCHSNREnergyMapping", ...
        "The derived PUSCH signal/noise energy accounting must be positive and finite.");
end

standardToDataEsN0Offset_dB = 10 * log10( ...
    totalSignalEnergy / (noiseEnergyRECount * dataEPRE));
equivalentDataEsN0_dB = ...
    double(standardSNR_dB) - standardToDataEsN0Offset_dB;

[rxWaveform, base] = sixgr.phy.waveform.addOccupiedREAWGN( ...
    txWaveform, carrier, equivalentDataEsN0_dB, "Seed", opt.Seed, ...
    "SignalEnergyPerOccupiedRE", dataEPRE);

dataSymbolIndices = localZeroBasedSymbolIndices( ...
    dataIndices, subcarriersInTransmissionBandwidth, symbolsPerSlot);
dmrsSymbolIndices = localZeroBasedSymbolIndices( ...
    dmrsIndices, subcarriersInTransmissionBandwidth, symbolsPerSlot);
expectedStandardSNR_dB = 10 * log10(totalSignalEnergy / ...
    (noiseEnergyRECount * double(base.GridNoiseVariance)));

provenance = base;
provenance.Version = "ts38104_pusch_reference_noise/v2";
provenance.Source = "sixgr.conformance.addPUSCHReferenceNoise";
provenance.BaseNoiseContractVersion = string(base.Version);
provenance.BaseNoiseSource = string(base.Source);
provenance.Direction = "uplink";
provenance.PhysicalChannel = "PUSCH";
provenance.Standard = "3GPP TS 38.104 V18.13.0";
provenance.StandardClauses = ["8.1.1", "11.1.1"];
provenance.SNRDefinition = ...
    "total PUSCH signal energy in the slot on one connector/RIB divided by noise energy in the transmission bandwidth over the same signal duration";
provenance.RequestedStandardSNR_dB = double(standardSNR_dB);
provenance.EquivalentOccupiedDataREEsN0_dB = ...
    double(equivalentDataEsN0_dB);
provenance.StandardSNRToOccupiedDataREEsN0Offset_dB = ...
    double(standardToDataEsN0Offset_dB);
provenance.ExpectedStandardSNRFromAppliedVariance_dB = ...
    double(expectedStandardSNR_dB);
provenance.MappingType = string(localObjectValue(pusch, "MappingType", ""));
provenance.SignalDurationStartSymbol = symbolAllocation(1);
provenance.SignalDurationSymbolCount = signalDurationSymbols;
provenance.DataBearingSymbolIndices = dataSymbolIndices;
provenance.DataBearingSymbolCount = numel(dataSymbolIndices);
provenance.DMRSSymbolIndices = dmrsSymbolIndices;
provenance.DMRSSymbolCount = numel(dmrsSymbolIndices);
provenance.TransmissionBandwidthPRB = nSizeGrid;
provenance.TransmissionBandwidthSubcarriers = ...
    subcarriersInTransmissionBandwidth;
provenance.TransmissionBandwidthNoiseEnergyRECount = ...
    noiseEnergyRECount;
provenance.PUSCHDataRECount = dataRECount;
provenance.PUSCHDMRSRECount = dmrsRECount;
provenance.PUSCHRawDataPortIndexCount = numel(dataIndices);
provenance.PUSCHRawDMRSPortIndexCount = numel(dmrsIndices);
provenance.PUSCHDataRowsPerPort = dataRowsPerPort;
provenance.PUSCHDataEnergyEquivalentRECount = ...
    dataEnergyEquivalentRECount;
provenance.PUSCHDMRSEnergyEquivalentRECount = ...
    dmrsEnergyEquivalentRECount;
provenance.NumLayers = numLayers;
provenance.NumAntennaPorts = numPorts;
provenance.TransmissionScheme = transmissionScheme;
provenance.TransformPrecoding = transformPrecoding;
provenance.TPMI = tpmi;
provenance.PrecoderTraceWWH = precoderTrace;
provenance.PrecoderSource = string(sixgr.util.structGet( ...
    opt.PrecodeInfo, "Source", codebookStatus));
provenance.PrecoderStatus = string(codebookStatus);
provenance.DataEPRE = dataEPRE;
provenance.DMRSPowerScaleRelativeToData = dmrsPowerScale;
provenance.DMRSEPRESameUnits = dataEPRE * dmrsPowerScale;
provenance.NominalDataSignalEnergy = dataSignalEnergy;
provenance.NominalDMRSSignalEnergy = dmrsSignalEnergy;
provenance.NominalTotalSlotSignalEnergy = totalSignalEnergy;
provenance.StandardNoiseEnergyAtAppliedVariance = ...
    noiseEnergyRECount * double(base.GridNoiseVariance);
provenance.SignalEnergyEquation = ...
    "S = PUSCHDataRowsPerPort*trace(W*W')*DataEPRE + sum(abs(nativeDMRS).^2)*DMRSPowerScaleRelativeToData*DataEPRE";
provenance.NoiseEnergyEquation = ...
    "N = TransmissionBandwidthNoiseEnergyRECount*GridNoiseVariance";
provenance.ConversionEquation = ...
    "EquivalentOccupiedDataREEsN0_dB = RequestedStandardSNR_dB - 10*log10(NominalTotalSlotSignalEnergy/(TransmissionBandwidthNoiseEnergyRECount*DataEPRE))";
provenance.WaveformPowerUsed = false;
provenance.InstantaneousFadingPowerUsed = false;
provenance.PTRSEnergyIncluded = false;
end

function indices = localZeroBasedSymbolIndices( ...
        linearIndices, subcarriersPerSymbol, symbolsPerSlot)
indices = mod(floor((double(linearIndices(:)) - 1) ./ ...
    double(subcarriersPerSymbol)), double(symbolsPerSlot));
indices = reshape(unique(indices, "sorted"), 1, []);
end

function localAssertRuntimeCodebook(precodeInfo, expectedWtx, expectedTPMI, expectedStatus)
if ~logical(sixgr.util.structGet(precodeInfo, "NativeCodebookApplied", false))
    error("sixgr:conformance:PUSCHRuntimeCodebookMismatch", ...
        "PUSCH_Tx did not report native codebook precoding as applied.");
end
actualTPMI = double(sixgr.util.structGet(precodeInfo, "PMI", NaN));
if ~(isscalar(actualTPMI) && isfinite(actualTPMI) && ...
        actualTPMI == double(expectedTPMI))
    error("sixgr:conformance:PUSCHRuntimeCodebookMismatch", ...
        "Runtime TPMI %.15g does not match configured TPMI %.15g.", ...
        actualTPMI, double(expectedTPMI));
end
actualWtx = double(sixgr.util.structGet(precodeInfo, "MatrixNR", []));
if ~isequal(size(actualWtx), size(expectedWtx)) || ...
        max(abs(actualWtx(:) - double(expectedWtx(:))), [], "omitnan") > 1e-12
    error("sixgr:conformance:PUSCHRuntimeCodebookMismatch", ...
        "Runtime native codebook matrix does not match nrPUSCHCodebook for TPMI %d.", ...
        round(double(expectedTPMI)));
end
actualStatus = string(sixgr.util.structGet(precodeInfo, "CodebookStatus", ""));
if actualStatus ~= string(expectedStatus)
    error("sixgr:conformance:PUSCHRuntimeCodebookMismatch", ...
        "Runtime codebook status '%s' does not match '%s'.", ...
        actualStatus, string(expectedStatus));
end
end

function value = localObjectNumeric(object, name, fallback)
value = localObjectValue(object, name, fallback);
if isempty(value)
    value = fallback;
end
value = double(value);
if ~isscalar(value)
    value = fallback;
end
end

function value = localObjectValue(object, name, fallback)
value = fallback;
try
    if isobject(object) && isprop(object, name)
        value = object.(name);
    elseif isstruct(object) && isfield(object, name)
        value = object.(name);
    end
catch
    value = fallback;
end
end

function tf = localValidWaveform(value)
tf = isnumeric(value) && isfloat(value) && ismatrix(value) && ...
    ~isempty(value) && size(value, 1) > 0 && all(isfinite(value), "all");
end

function tf = localOptionalPositiveScalar(value)
tf = isempty(value) || localPositiveScalar(value);
end

function tf = localPositiveScalar(value)
tf = isnumeric(value) && isreal(value) && isscalar(value) && ...
    isfinite(value) && value > 0;
end

function tf = localValidSeed(value)
tf = isempty(value) || (isnumeric(value) && isreal(value) && ...
    isscalar(value) && isfinite(value) && value == fix(value) && ...
    value >= 0 && value <= 2^32 - 1);
end
