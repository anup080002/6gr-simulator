function out = buildPre6GExampleWaveform(cfg,seed)
%BUILDPRE6GEXAMPLEWAVEFORM Adapt the R2026a 6G ISAC example waveform APIs.
%
% This is a simulation-only adapter. It uses the installed 6G Exploration
% Library functions used by the NI-USRP example, but never claims that a radio
% was connected or that over-the-air evidence was captured.

arguments
    cfg (1,1) struct
    seed (1,1) double
end
adapter = cfg.pre6gExampleAdapter;
if ~logical(adapter.enabled)
    error("sixgr:isac:Pre6GAdapterDisabled", ...
        "pre6gExampleAdapter.enabled must be true.");
end
required = ["pre6GCarrierConfig","pre6GPhysicalChannelConfig", ...
    "pre6GReferenceSignalConfig","pre6GReferenceSignalIndices", ...
    "pre6GReferenceSignal","pre6GPhysicalChannelIndices", ...
    "pre6GPhysicalChannel","pre6GResourceGrid","pre6GOFDMModulate"];
for name=required
    if exist(name,"file") ~= 2
        error("sixgr:isac:MissingPre6GExplorationLibrary", ...
            "Required 6G Exploration Library function %s is unavailable.",name);
    end
end
carrier = pre6GCarrierConfig;
carrier.SubcarrierSpacing = double(adapter.subcarrierSpacingKHz);
carrier.NSizeGrid = double(adapter.nSizeGrid);
carrier.NCellID = double(adapter.nCellID);
carrier.NSlot = 0;
carrier.NFrame = 0;

dmrs = pre6GReferenceSignalConfig;
dmrs.PRBSet = 0:(carrier.NSizeGrid-1);
dmrs.SubcarrierLocations = double(adapter.dmrs.subcarrierLocations(:));
dmrs.SymbolLocations = double(adapter.dmrs.symbolLocations(:));
dmrs.FrequencyDomainCDM = double(adapter.dmrs.frequencyDomainCDM);
dmrs.TimeDomainCDM = double(adapter.dmrs.timeDomainCDM);
dmrs.PortSet = double(adapter.dmrs.portSet(:));
dmrsIndices = pre6GReferenceSignalIndices(carrier,dmrs);
dmrsSymbols = pre6GReferenceSignal(carrier,dmrs);

physical = pre6GPhysicalChannelConfig;
physical.PRBSet = 0:(carrier.NSizeGrid-1);
physical.Modulation = char(string(adapter.modulation));
physical.NumLayers = 1;
physical.SymbolAllocation = [0 carrier.SymbolsPerSlot];
physical.ReservedRE = dmrsIndices-1;
[dataIndices,dataInfo] = pre6GPhysicalChannelIndices(carrier,physical);
prior=rng; cleanup=onCleanup(@() rng(prior)); %#ok<NASGU>
rng(double(seed),"twister");
bits = randi([0 1],dataInfo.G,1);
dataSymbols = pre6GPhysicalChannel(carrier,physical,bits);
grid = pre6GResourceGrid(carrier,1);
grid(dataIndices) = dataSymbols;
grid(dmrsIndices) = dmrsSymbols;
waveform = pre6GOFDMModulate(carrier,grid);
info = pre6GOFDMInfo(carrier);
out = struct("Carrier",carrier,"PhysicalChannel",physical,"DMRS",dmrs, ...
    "Grid",grid,"Waveform",waveform,"Bits",bits, ...
    "DataIndices",dataIndices,"DMRSIndices",dmrsIndices, ...
    "SampleRateHz",double(info.SampleRate),"Nfft",double(info.Nfft), ...
    "WaveformSHA256",string(localHash(waveform)), ...
    "ExecutionBackend","6g_exploration_library_simulation", ...
    "HardwareValidated",false);
end

function digest=localHash(value)
digest=sixgr.util.sha256Hex(typecast([real(value(:));imag(value(:))],"uint8"));
end
