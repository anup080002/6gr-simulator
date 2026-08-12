function bundle = buildJointWaveform(cfg,waveformId,seed,omittedSensingSymbols,coherentSymbols,sequenceVariant,nFFTOverride)
%BUILDJOINTWAVEFORM Build the common data+sensing CP-OFDM waveform.
%
% W3 modifies sensing RE phases only. OFDM modulation and communication CP
% insertion are the ordinary 5G Toolbox operations for all profiles.

arguments
    cfg (1,1) struct
    waveformId (1,1) string
    seed (1,1) double
    omittedSensingSymbols double = zeros(0,1)
    coherentSymbols (1,1) double = 0
    sequenceVariant (1,1) string = ""
    nFFTOverride (1,1) double {mustBeInteger,mustBeNonnegative} = 0
end
waveformId = upper(strtrim(waveformId));
profile = sixgr.util.structGet(cfg,"waveform.profiles."+waveformId,[]);
if ~(isstruct(profile) && isscalar(profile))
    error("sixgr:isac:UnknownWaveformProfile","Unknown waveform profile %s.",waveformId);
end
[carrier,carrierProfile,ofdmInfo] = sixgr.isac.carrierConfig(cfg);
ofdmOptions={"Windowing",double(cfg.waveform.ofdmWindowingSamples)};
if nFFTOverride>0
    ofdmOptions=[ofdmOptions,{"Nfft",nFFTOverride}];
    ofdmInfo=nrOFDMInfo(carrier,ofdmOptions{:});
end
nSC = carrier.NSizeGrid*12;
nSymbols = carrier.SymbolsPerSlot;
grid = complex(zeros(nSC,nSymbols,1));
prior = rng;
cleanup = onCleanup(@() rng(prior)); %#ok<NASGU>
rng(double(seed)+double(cfg.waveform.dataSeedOffset),"twister");
dataBits = randi([0 1],2*nSC*nSymbols,1);
dataSymbols = nrSymbolModulate(dataBits,char(string(cfg.waveform.modulation)));
dataGrid = reshape(dataSymbols,nSC,nSymbols);
if logical(cfg.waveform.communicationDataEnabled)
    grid(:,:,1) = sqrt(double(cfg.waveform.communicationDataPower))*dataGrid;
end

if coherentSymbols<=0
    coherentSymbols=double(cfg.waveform.defaultCoherentSymbols);
end
symbolSet=sixgr.util.structGet(cfg,"waveform.coherentSymbolSets.M"+string(round(coherentSymbols)),[]);
if isempty(symbolSet)
    error("sixgr:isac:UnsupportedCoherentSymbolCount", ...
        "No waveform.coherentSymbolSets.M%d entry exists.",round(coherentSymbols));
end
sensingSymbols0=double(symbolSet(:));
comb = double(cfg.waveform.frequencyComb);
combOffset = double(cfg.waveform.frequencyCombOffset);
subcarrier0 = (combOffset:comb:nSC-1).';
nREPerSymbol = numel(subcarrier0);
physicalK = subcarrier0 + 12*double(carrier.NStartGrid) - floor(nSC/2);
cpLengths = double(ofdmInfo.CyclicPrefixLengths(:));
if numel(cpLengths) < nSymbols
    error("sixgr:isac:InvalidOFDMMeta", ...
        "nrOFDMInfo returned fewer CP lengths than symbols in the slot.");
end
resetSymbols0=double(sixgr.util.structGet(cfg,"waveform.w3ResetSymbolIndices",0));
qBySymbol=sixgr.isac.cumulativeCPState(cpLengths(1:nSymbols), ...
    double(ofdmInfo.Nfft),resetSymbols0(:));

sensingGrid = complex(zeros(nSC,nSymbols));
sensingMaskConfigured = false(nSC,nSymbols);
sensingMaskTransmitted = false(nSC,nSymbols);
baseSequence = localGoldQPSK(double(seed)+double(carrier.NCellID),nREPerSymbol);
for occasion = 1:numel(sensingSymbols0)
    symbol0 = sensingSymbols0(occasion);
    symbol = symbol0+1;
    sensingMaskConfigured(subcarrier0+1,symbol) = true;
    sequenceRule = lower(string(profile.sequenceRule));
    switch sequenceRule
        case "reused_nr_gold"
            % Communication RS initialization is symbol/occasion dependent.
            % W0 therefore remains distinct from the deliberately repeated
            % W2 base sequence.
            sequence = localGoldQPSK(double(seed)+104729*symbol0+ ...
                1009*occasion+double(carrier.NCellID),nREPerSymbol);
        case "randomized_nr_gold"
            variant=lower(strtrim(sequenceVariant));
            if strlength(variant)==0, variant=lower(string(profile.resetRule)); end
            if variant=="reset_aligned_interval"
                interval=double(cfg.waveform.w1ResetAlignedIntervalOccasions);
                intervalIndex=floor((occasion-1)/interval);
                sequence=localGoldQPSK(double(seed)+65537*intervalIndex+ ...
                    double(carrier.NCellID),nREPerSymbol);
            elseif ismember(variant,["per_occasion","per_occasion_randomization"])
                sequence = localGoldQPSK(double(seed)+65537*occasion+ ...
                    4099*symbol0+double(carrier.NCellID),nREPerSymbol);
            else
                error("sixgr:isac:UnsupportedW1SequenceVariant", ...
                    "Unsupported W1 sequence variant %s.",variant);
            end
        otherwise
            sequence = baseSequence;
    end
    if logical(profile.cumulativeCPPhase)
        sequence = sequence.*exp(1i*2*pi*physicalK*qBySymbol(symbol)/double(ofdmInfo.Nfft));
    end
    if ~ismember(symbol0,double(omittedSensingSymbols(:)))
        sensingGrid(subcarrier0+1,symbol) = sequence;
        sensingMaskTransmitted(subcarrier0+1,symbol) = true;
    end
end

activeCount = nnz(sensingMaskTransmitted);
if activeCount == 0
    error("sixgr:isac:NoSensingResources", ...
        "All configured sensing symbols were omitted.");
end
sensingScale = sqrt(double(cfg.waveform.sensingRSPower)* ...
    nnz(sensingMaskConfigured)/activeCount);
sensingGrid = sensingGrid*sensingScale;
grid(sensingMaskTransmitted) = sensingGrid(sensingMaskTransmitted);
sensingWaveform = nrOFDMModulate(carrier,sensingGrid,ofdmOptions{:});
waveform = nrOFDMModulate(carrier,grid,ofdmOptions{:});

power = mean(abs(waveform).^2);
paprDb = 10*log10(max(abs(waveform).^2)/power);
bundle = struct( ...
    "ProfileId",waveformId,"Profile",profile,"Carrier",carrier, ...
    "CarrierProfile",carrierProfile,"OFDMInfo",ofdmInfo, ...
    "Grid",grid,"DataGrid",dataGrid,"SensingGrid",sensingGrid, ...
    "ConfiguredMask",sensingMaskConfigured, ...
    "TransmittedMask",sensingMaskTransmitted, ...
    "Waveform",waveform,"SensingWaveform",sensingWaveform, ...
    "SensingSymbolIndices",sensingSymbols0,"PhysicalSubcarrierIndices",physicalK, ...
    "CumulativeCPState",qBySymbol,"CPLengths",cpLengths(1:nSymbols), ...
    "PAPRDb",paprDb,"Seed",seed,"CoherentSymbols",coherentSymbols, ...
    "SequenceVariant",sequenceVariant, ...
    "NfftOverride",nFFTOverride, ...
    "WaveformSHA256",string(localComplexHash(waveform)), ...
    "SensingWaveformSHA256",string(localComplexHash(sensingWaveform)));
end

function sequence = localGoldQPSK(cinit,nSymbols)
bits = nrPRBS(mod(round(cinit),2^31),2*nSymbols);
sequence = nrSymbolModulate(bits,"QPSK");
sequence = sequence/sqrt(mean(abs(sequence).^2));
end

function digest = localComplexHash(value)
bytes = typecast([real(value(:));imag(value(:))],"uint8");
digest = sixgr.util.sha256Hex(bytes);
end
