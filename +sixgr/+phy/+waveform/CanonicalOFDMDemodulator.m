classdef CanonicalOFDMDemodulator
    %CANONICALOFDMMODULATOR Canonical inverse OFDM engines.
    methods (Static)
        function [grid,info]=math(waveform,nfft,cpLengths,occupiedCount,varargin)
            cpLengths=double(cpLengths(:).');
            ports=size(waveform,2); offset=0;
            grid=complex(zeros(occupiedCount,numel(cpLengths),ports,"like",waveform));
            for symbol=1:numel(cpLengths)
                blockLength=nfft+cpLengths(symbol);
                if offset+blockLength>size(waveform,1)
                    error("WAVEFORM:InvalidOFDMParameters","Waveform is shorter than its symbol plan.");
                end
                useful=sixgr.phy.waveform.CPInsertionRemoval.remove( ...
                    waveform(offset+(1:blockLength),:),cpLengths(symbol),nfft);
                fftGrid=fft(useful,[],1)/sqrt(double(nfft));
                grid(:,symbol,:)=reshape( ...
                    sixgr.phy.waveform.SubcarrierMapper.extract( ...
                    fftGrid,occupiedCount,varargin{:}),occupiedCount,1,ports);
                offset=offset+blockLength;
            end
            info=struct("EngineUsed","canonical_unitary_math", ...
                "ConsumedSamples",offset,"GridSHA256", ...
                sixgr.phy.waveform.WaveformHash.numeric(grid));
        end

        function [grid,info]=toolbox(carrier,waveform,varargin)
            if mod(numel(varargin),2)~=0
                error("sixgr:phy:ofdmDemodulate:BadNameValueArguments", ...
                    "OFDM options must be name-value pairs.");
            end
            resolver={}; args={}; windowing=0;
            seen=strings(0,1);
            for i=1:2:numel(varargin)
                name=lower(strtrim(string(varargin{i}))); value=varargin{i+1};
                if any(seen==name)
                    error("sixgr:phy:ofdmDemodulate:DuplicateOption", ...
                        "OFDM option '%s' was supplied more than once.",char(name));
                end
                seen(end+1)=name; %#ok<AGROW>
                switch name
                    case "nfft"
                        resolver=[resolver {"Nfft",value}];args=[args varargin(i:i+1)]; %#ok<AGROW>
                    case "samplerate"
                        resolver=[resolver {"SampleRate",value}];args=[args varargin(i:i+1)]; %#ok<AGROW>
                    case "windowing"
                        windowing=value; resolver=[resolver {"WindowingSamples",value}]; %#ok<AGROW>
                    otherwise
                        args=[args varargin(i:i+1)]; %#ok<AGROW>
                end
            end
            resolution=sixgr.phy.waveform.OFDMParameterResolver.resolve(carrier,resolver{:});
            try
                grid=nrOFDMDemodulate(carrier,waveform,args{:});
            catch exception
                wrapped=MException("WAVEFORM:InvalidOFDMParameters", ...
                    "nrOFDMDemodulate rejected the resolved parameters: %s",exception.message);
                wrapped=addCause(wrapped,exception);throwAsCaller(wrapped);
            end
            info=nrOFDMInfo(carrier,"Windowing",double(windowing));
            calibration=sixgr.phy.waveform.calibrateOFDMNoiseTransform( ...
                carrier, ...
                "Nfft",double(resolution.Nfft), ...
                "SampleRate",double(resolution.SampleRate), ...
                "Windowing",double(resolution.WindowingSamples));
            info.NoiseTransform=calibration;
            info.SampleToGridNoiseVarianceGain=double(calibration.SampleToGridNoiseVarianceGain);
            info.GridToSampleNoiseVarianceGain=double(calibration.GridToSampleNoiseVarianceGain);
            info.TimeDomainSignalPowerReference=char(string(calibration.TimeDomainSignalPowerReference));
            info.FrequencyDomainSignalPowerReference=char(string(calibration.FrequencyDomainSignalPowerReference));
            info.OFDMNoiseTransformVersion=char(string(calibration.Version));
            info.OFDMSamplingResolution=resolution;
            info.OFDMWindowingSamples=double(resolution.WindowingSamples);
            info.OFDMWindowingSource="canonical_explicit";
            info.EngineUsed="canonical_nrOFDMDemodulate";
            info.WaveformSize=size(waveform);info.GridSize=size(grid);
            info.WaveformSHA256=sixgr.phy.waveform.WaveformHash.numeric(waveform);
            info.GridSHA256=sixgr.phy.waveform.WaveformHash.numeric(grid);
        end
    end
end
