classdef CanonicalOFDMModulator
    %CANONICALOFDMMODULATOR Unitary math oracle and strict Toolbox engine.

    methods (Static)
        function [waveform,info] = math(grid,nfft,cpLengths,varargin)
            if ismatrix(grid), grid=reshape(grid,size(grid,1),size(grid,2),1); end
            cpLengths=double(cpLengths(:).');
            if numel(cpLengths)==1, cpLengths=repmat(cpLengths,1,size(grid,2)); end
            if numel(cpLengths)~=size(grid,2)
                error("WAVEFORM:InvalidOFDMParameters", ...
                    "One CP length is required per OFDM symbol.");
            end
            fftGrid=sixgr.phy.waveform.SubcarrierMapper.place(grid,nfft,varargin{:});
            useful=ifft(fftGrid,[],1)*sqrt(double(nfft));
            blocks=cell(1,size(grid,2));
            for symbol=1:size(grid,2)
                blocks{symbol}=sixgr.phy.waveform.CPInsertionRemoval.insert( ...
                    reshape(useful(:,symbol,:),nfft,[]),cpLengths(symbol));
            end
            waveform=vertcat(blocks{:});
            if any(~isfinite(waveform),"all")
                error("WAVEFORM:NonFiniteSamples","OFDM modulation produced nonfinite samples.");
            end
            info=struct("EngineUsed","canonical_unitary_math", ...
                "Nfft",double(nfft),"CyclicPrefixLengths",cpLengths, ...
                "Symbols",double(size(grid,2)),"Ports",double(size(grid,3)), ...
                "ScaleFactor",sqrt(double(nfft)), ...
                "GridSHA256",sixgr.phy.waveform.WaveformHash.numeric(grid), ...
                "WaveformSHA256",sixgr.phy.waveform.WaveformHash.numeric(waveform), ...
                "IndexConvention","zero_based_waveform_indices");
        end

        function [waveform,info] = toolbox(carrier,grid,varargin)
            if ismatrix(grid), grid=reshape(grid,size(grid,1),size(grid,2),1); end
            [args,resolution,windowingSource]=sixgr.phy.waveform.CanonicalOFDMModulator.resolveArgs( ...
                carrier,varargin{:});
            try
                [waveform,info]=nrOFDMModulate(carrier,grid,args{:});
            catch exception
                wrapped=MException("WAVEFORM:InvalidOFDMParameters", ...
                    "nrOFDMModulate rejected the resolved parameters: %s", ...
                    exception.message);
                wrapped=addCause(wrapped,exception);throwAsCaller(wrapped);
            end
            applied=double(sixgr.util.structGet(info,"Windowing",NaN));
            if applied~=resolution.WindowingSamples
                error("WAVEFORM:InvalidOFDMParameters", ...
                    "The applied windowing differs from the resolved plan.");
            end
            calibration=sixgr.phy.waveform.calibrateOFDMNoiseTransform( ...
                carrier,args{:});
            info.NoiseTransform=calibration;
            info.SampleToGridNoiseVarianceGain=double(calibration.SampleToGridNoiseVarianceGain);
            info.GridToSampleNoiseVarianceGain=double(calibration.GridToSampleNoiseVarianceGain);
            info.TimeDomainSignalPowerReference=char(string(calibration.TimeDomainSignalPowerReference));
            info.FrequencyDomainSignalPowerReference=char(string(calibration.FrequencyDomainSignalPowerReference));
            info.OFDMNoiseTransformVersion=char(string(calibration.Version));
            info.OFDMSamplingResolution=resolution;
            info.OFDMWindowingSamples=double(resolution.WindowingSamples);
            info.OFDMWindowingSource=windowingSource;
            [gp,gpi]=sixgr.phy.waveform.ofdmReferencePower(grid,info,"Domain","occupied_re");
            [tp,tpi]=sixgr.phy.waveform.ofdmReferencePower(waveform,info,"Domain","active_samples");
            info.GridDomainSignalPower=gp; info.TimeDomainSignalPower=tp;
            info.GridDomainSignalPowerInfo=gpi; info.TimeDomainSignalPowerInfo=tpi;
            info.EngineUsed="canonical_nrOFDMModulate";
            info.GridSize=size(grid); info.WaveformSize=size(waveform);
            info.GridSHA256=sixgr.phy.waveform.WaveformHash.numeric(grid);
            info.WaveformSHA256=sixgr.phy.waveform.WaveformHash.numeric(waveform);
            info.DimensionContract=struct("GridSubcarriers",size(grid,1), ...
                "GridSymbols",size(grid,2),"GridPorts",size(grid,3), ...
                "WaveformSamples",size(waveform,1), ...
                "WaveformColumns",size(waveform,2), ...
                "Nfft",double(info.Nfft),"SampleRate",double(info.SampleRate));
        end
    end

    methods (Static,Access=private)
        function [args,resolution,windowingSource]=resolveArgs(carrier,varargin)
            if mod(numel(varargin),2)~=0
                error("sixgr:phy:ofdmModulate:BadNameValueArguments", ...
                    "OFDM options must be name-value pairs.");
            end
            args=varargin; resolver={}; hasWindow=false; seen=strings(0,1);
            for i=1:2:numel(varargin)
                name=lower(strtrim(string(varargin{i})));
                if any(seen==name)
                    error("sixgr:phy:ofdmModulate:DuplicateOption", ...
                        "OFDM option '%s' was supplied more than once.",char(name));
                end
                seen(end+1)=name; value=varargin{i+1}; %#ok<AGROW>
                switch name
                    case "nfft", resolver=[resolver {"Nfft",value}]; %#ok<AGROW>
                    case "samplerate", resolver=[resolver {"SampleRate",value}]; %#ok<AGROW>
                    case "windowing"
                        hasWindow=true; resolver=[resolver {"WindowingSamples",value}]; %#ok<AGROW>
                end
            end
            if ~hasWindow
                args=[args {"Windowing",0}];
                resolver=[resolver {"WindowingSamples",0}];
                windowingSource="standard_default_zero";
            else
                windowingSource="explicit_windowing_samples";
            end
            resolution=sixgr.phy.waveform.OFDMParameterResolver.resolve( ...
                carrier,resolver{:});
        end
    end
end
