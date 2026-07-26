classdef ADCModel
%ADCMODEL Explicit signed-midtread complex quantizer.

    methods(Static)
        function result = quantize(input, profile)
            if ~isstruct(profile) || ~all(isfield(profile, ...
                    ["Bits","FullScale","Convention"]))
                error("RF:ADCProfileMissing", ...
                    "ADC quantization requires bits, full scale and convention.");
            end
            bits = double(profile.Bits);
            fullScale = double(profile.FullScale);
            convention=lower(strtrim(string(profile.Convention)));
            if ~(isscalar(bits) && isfinite(bits) && bits==round(bits) && ...
                    bits>=2 && bits<=24 && isscalar(fullScale) && ...
                    isfinite(fullScale) && fullScale>0 && ...
                    any(convention==["signed_midtread","signed_midrise"]))
                error("RF:ADCProfileMissing", ...
                    "ADC profile is invalid or unsupported.");
            end
            if any(~isfinite(input(:)))
                error("RF:NonFiniteSamples", ...
                    "ADC input samples must be finite.");
            end
            ditherRMS=double(sixgr.util.structGet(profile,"DitherRMS",0));
            apertureJitter=double(sixgr.util.structGet( ...
                profile,"ApertureJitter_s",0));
            inl=double(sixgr.util.structGet(profile,"INL_LSB",0));
            dnl=double(sixgr.util.structGet(profile,"DNL_LSB",0));
            seed=double(sixgr.util.structGet(profile,"Seed",1));
            if any(~isfinite([ditherRMS apertureJitter inl dnl seed]))|| ...
                    ditherRMS<0||apertureJitter<0||inl<0||dnl<0
                error("RF:ADCProfileMissing", ...
                    "ADC dither, jitter, INL/DNL and seed must be explicit finite values.");
            end
            stream=RandStream("Threefry","Seed",seed);
            working=double(input);
            dither=ditherRMS/sqrt(2).*(randn(stream,size(working))+ ...
                1j*randn(stream,size(working)));
            if isreal(input),dither=real(dither)*sqrt(2);end
            working=working+dither;
            apertureError=zeros(size(working));
            sampleRate=double(sixgr.util.structGet(profile,"SampleRate_Hz",NaN));
            if apertureJitter>0
                if ~(isscalar(sampleRate)&&isfinite(sampleRate)&&sampleRate>0)
                    error("RF:ADCProfileMissing", ...
                        "ADC aperture jitter requires an explicit sample rate.");
                end
                derivative=[zeros(1,size(working,2));diff(double(input),1,1)]*sampleRate;
                timeError=apertureJitter.*randn(stream,size(working,1),1);
                apertureError=derivative.*timeError;
                working=working+apertureError;
            end
            maxCode = 2^(bits-1)-1;
            [realOut,realCode,realClip,step] = ...
                sixgr.rf.runtime.ADCModel.quantizeReal(real(working), ...
                fullScale,maxCode,convention);
            if isreal(input)
                output = realOut;
                code = realCode;
                clipped = realClip;
            else
                [imagOut,imagCode,imagClip] = ...
                    sixgr.rf.runtime.ADCModel.quantizeReal(imag(working), ...
                    fullScale,maxCode,convention);
                output = complex(realOut,imagOut);
                code = complex(realCode,imagCode);
                clipped = realClip|imagClip;
            end
            if inl>0||dnl>0
                output=output+inl*step.*sin(pi*double(code)/max(maxCode,1))+ ...
                    dnl*step/2.*(-1).^round(real(double(code)));
            end
            errorSamples = output-double(input);
            result = struct( ...
                "Output",cast(output,"like",input), ...
                "Code",code, ...
                "Clipped",clipped, ...
                "QuantizationError",errorSamples, ...
                "Dither",dither, ...
                "ApertureError",apertureError, ...
                "ErrorVariance",mean(abs(errorSamples(:)).^2), ...
                "ClippingRatio",mean(double(clipped(:))), ...
                "Bits",bits, ...
                "FullScale",fullScale, ...
                "Step",step, ...
                "Convention",convention, ...
                "INL_LSB",inl,"DNL_LSB",dnl, ...
                "ApertureJitter_s",apertureJitter);
        end
    end

    methods(Static,Access=private)
        function [output,code,clipped,step] = ...
                quantizeReal(input,fullScale,maxCode,convention)
            clipped = abs(input)>=fullScale;
            limited = min(max(input,-fullScale),fullScale);
            if convention=="signed_midtread"
                code = round(limited/fullScale*maxCode);
                code = min(max(code,-maxCode),maxCode);
                step=fullScale/maxCode;
                output = code*step;
            else
                levelCount=2*(maxCode+1);
                step=2*fullScale/levelCount;
                index=floor((limited+fullScale)/step);
                index=min(max(index,0),levelCount-1);
                code=index-(maxCode+1);
                output=-fullScale+(index+0.5)*step;
            end
        end
    end
end
