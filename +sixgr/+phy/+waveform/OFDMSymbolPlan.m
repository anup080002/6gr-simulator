classdef OFDMSymbolPlan
    %OFDMSYMBOLPLAN Immutable per-symbol waveform identity.
    properties (SetAccess=immutable)
        ProfileID string
        ServingCellID string
        ComponentCarrierID string
        BWPID string
        SCS_kHz double
        CyclicPrefix string
        Frame double
        Slot double
        Symbol double
        Nfft double
        SampleRate_Hz double
        CPLength double
        OccupiedSubcarriers double
        FFTBins double
        InputGridSHA256 string
        OutputSampleSHA256 string
    end
    methods
        function obj=OFDMSymbolPlan(context,inputGrid,outputSamples)
            required=["ProfileID","SCS_kHz","CyclicPrefix","Frame","Slot", ...
                "Symbol","Nfft","SampleRate_Hz","CPLength"];
            for field=required
                if ~isfield(context,field)
                    error("WAVEFORM:InvalidOFDMParameters", ...
                        "OFDMSymbolPlan requires %s.",field);
                end
            end
            obj.ProfileID=string(context.ProfileID);
            obj.ServingCellID=string(sixgr.util.structGet(context,"ServingCellID","CELL-0"));
            obj.ComponentCarrierID=string(sixgr.util.structGet(context,"ComponentCarrierID","CC-0"));
            obj.BWPID=string(sixgr.util.structGet(context,"BWPID","BWP-0"));
            obj.SCS_kHz=double(context.SCS_kHz);
            obj.CyclicPrefix=string(context.CyclicPrefix);
            obj.Frame=double(context.Frame); obj.Slot=double(context.Slot);
            obj.Symbol=double(context.Symbol); obj.Nfft=double(context.Nfft);
            obj.SampleRate_Hz=double(context.SampleRate_Hz);
            obj.CPLength=double(context.CPLength);
            map=sixgr.phy.waveform.SubcarrierMapper.build(obj.Nfft,size(inputGrid,1));
            obj.OccupiedSubcarriers=double(map.Subcarrier).';
            obj.FFTBins=double(map.FFTBin).';
            obj.InputGridSHA256=sixgr.phy.waveform.WaveformHash.numeric(inputGrid);
            obj.OutputSampleSHA256=sixgr.phy.waveform.WaveformHash.numeric(outputSamples);
        end
    end
end
