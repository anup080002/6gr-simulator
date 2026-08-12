function out=buildReferenceGrid(cfg,carrier,waveformId,seed,coherentSymbols,sequenceVariant)
%BUILDREFERENCEGRID Build W0-W3 RS on an existing production NR carrier.
%
% This is the adapter used to place the same 10.8.3 profile into the coded
% PDSCH resource plan. It returns only physical grid resources; OFDM remains
% owned by the production PDSCH transmitter.
arguments
    cfg (1,1) struct
    carrier (1,1) nrCarrierConfig
    waveformId (1,1) string
    seed (1,1) double
    coherentSymbols (1,1) double = 0
    sequenceVariant (1,1) string = ""
end
waveformId=upper(strtrim(waveformId));
profile=sixgr.util.structGet(cfg,"waveform.profiles."+waveformId,[]);
if ~(isstruct(profile)&&isscalar(profile))
    error("sixgr:isac:UnknownWaveformProfile","Unknown waveform profile %s.",waveformId);
end
if coherentSymbols<=0, coherentSymbols=double(cfg.waveform.defaultCoherentSymbols); end
symbolSet=double(sixgr.util.structGet(cfg, ...
    "waveform.coherentSymbolSets.M"+string(round(coherentSymbols)),[]));
if isempty(symbolSet)
    error("sixgr:isac:UnsupportedCoherentSymbolCount", ...
        "No coherent symbol set M%d is configured.",round(coherentSymbols));
end
nSC=carrier.NSizeGrid*12; nSymbols=carrier.SymbolsPerSlot;
if any(symbolSet<0|symbolSet>=nSymbols)
    error("sixgr:isac:SensingSymbolOutsideCarrier", ...
        "The sensing symbol set exceeds the production carrier slot.");
end
ofdmInfo=nrOFDMInfo(carrier,"Windowing",double(cfg.waveform.ofdmWindowingSamples));
cp=double(ofdmInfo.CyclicPrefixLengths(1:nSymbols)); cp=cp(:);
q=sixgr.isac.cumulativeCPState(cp,double(ofdmInfo.Nfft), ...
    double(cfg.waveform.w3ResetSymbolIndices(:)));
subcarrier0=(double(cfg.waveform.frequencyCombOffset): ...
    double(cfg.waveform.frequencyComb):nSC-1).';
physicalK=subcarrier0+12*double(carrier.NStartGrid)-floor(nSC/2);
grid=complex(zeros(nSC,nSymbols)); mask=false(nSC,nSymbols);
base=localGold(seed+double(carrier.NCellID),numel(subcarrier0));
for occasion=1:numel(symbolSet)
    symbol0=symbolSet(occasion); symbol=symbol0+1;
    switch lower(string(profile.sequenceRule))
        case "reused_nr_gold"
            sequence=localGold(seed+104729*symbol0+1009*occasion+double(carrier.NCellID),numel(subcarrier0));
        case "randomized_nr_gold"
            variant=lower(strtrim(sequenceVariant));
            if variant=="", variant=lower(string(profile.resetRule)); end
            if variant=="reset_aligned_interval"
                intervalIndex=floor((occasion-1)/double(cfg.waveform.w1ResetAlignedIntervalOccasions));
                sequence=localGold(seed+65537*intervalIndex+double(carrier.NCellID),numel(subcarrier0));
            elseif ismember(variant,["per_occasion","per_occasion_randomization"])
                sequence=localGold(seed+65537*occasion+4099*symbol0+double(carrier.NCellID),numel(subcarrier0));
            else
                error("sixgr:isac:UnsupportedW1SequenceVariant", ...
                    "Unsupported W1 sequence variant %s.",variant);
            end
        otherwise
            sequence=base;
    end
    if logical(profile.cumulativeCPPhase)
        sequence=sequence.*exp(1i*2*pi*physicalK*q(symbol)/double(ofdmInfo.Nfft));
    end
    grid(subcarrier0+1,symbol)=sqrt(double(cfg.waveform.sensingRSPower))*sequence;
    mask(subcarrier0+1,symbol)=true;
end
out=struct("ProfileId",waveformId,"Grid",grid,"Mask",mask, ...
    "CumulativeCPState",q,"PhysicalSubcarrierIndices",physicalK, ...
    "CPLengths",cp,"Nfft",double(ofdmInfo.Nfft),"Seed",seed, ...
    "SHA256",string(localHash(grid)));
end

function sequence=localGold(seed,n)
bits=nrPRBS(mod(round(seed),2^31),2*n);
sequence=nrSymbolModulate(bits,"QPSK"); sequence=sequence/sqrt(mean(abs(sequence).^2));
end

function digest=localHash(value)
digest=sixgr.util.sha256Hex(typecast([real(value(:));imag(value(:))],"uint8"));
end
