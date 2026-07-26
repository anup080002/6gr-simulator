classdef PAProfile
%PAPROFILE Calibrated bounded PA models with no output-power restoration.

    methods(Static)
        function [profile,canonical]=fromConfiguration(config)
            canonical=false;
            profile=struct();
            profileId=string(sixgr.util.structGet(config, ...
                "rf.specification.profile_id",""));
            if strlength(strtrim(profileId))==0
                return;
            end
            sixgr.rf.runtime.RFSpecificationProfile.resolve(profileId);
            raw=sixgr.util.structGet(config,"rf.frontend.pa",struct());
            if ~isstruct(raw)||isempty(fieldnames(raw))
                error("RF:PAProfileMissing", ...
                    "Canonical RF execution requires rf_frontend.pa.");
            end
            profile=struct( ...
                "ProfileID",string(sixgr.util.structGet(raw,"profile_id","")), ...
                "Model",string(sixgr.util.structGet(raw,"model","")), ...
                "InputBackoff_dB",double(sixgr.util.structGet( ...
                raw,"input_backoff_db",NaN)), ...
                "Version",string(sixgr.util.structGet(raw,"version","")));
            model=lower(strtrim(profile.Model));
            if model=="rapp"
                profile.Smoothness=double(sixgr.util.structGet( ...
                    raw,"smoothness",NaN));
                profile.SaturationAmplitude=double(sixgr.util.structGet( ...
                    raw,"saturation_amplitude",NaN));
            elseif model=="saleh"
                profile.AlphaAM=double(sixgr.util.structGet(raw,"alpha_am",NaN));
                profile.BetaAM=double(sixgr.util.structGet(raw,"beta_am",NaN));
                profile.AlphaPM=double(sixgr.util.structGet(raw,"alpha_pm",NaN));
                profile.BetaPM=double(sixgr.util.structGet(raw,"beta_pm",NaN));
            elseif model=="memory_polynomial"
                profile.Coefficients=double(sixgr.util.structGet( ...
                    raw,"coefficients",[]));
                profile.Orders=double(sixgr.util.structGet(raw,"orders",[]));
                profile.MemoryDepth=double(sixgr.util.structGet( ...
                    raw,"memory_depth",NaN));
            end
            if strlength(strtrim(profile.ProfileID))==0 || ...
                    strlength(strtrim(profile.Version))==0 || ...
                    strlength(strtrim(profile.Model))==0 || ...
                    ~isfinite(profile.InputBackoff_dB)
                error("RF:PAProfileMissing", ...
                    "Canonical PA profile identity/version/backoff is incomplete.");
            end
            canonical=true;
        end

        function [y, evidence] = apply(x, profile)
            required = ["ProfileID","Model","InputBackoff_dB","Version"];
            if ~isstruct(profile) || ~all(isfield(profile,required))
                error("RF:PAProfileMissing", ...
                    "PA execution requires an explicit calibrated profile.");
            end
            if any(~isfinite(x(:)))
                error("RF:NonFiniteSamples", ...
                    "PA input samples must be finite.");
            end
            model = lower(strtrim(string(profile.Model)));
            xin = x;
            switch model
                case "rapp"
                    smoothness = sixgr.rf.runtime.PAProfile.requiredField( ...
                        profile,"Smoothness");
                    saturation = sixgr.rf.runtime.PAProfile.requiredField( ...
                        profile,"SaturationAmplitude");
                    y = xin ./ (1+(abs(xin)./saturation).^(2*smoothness)).^(1/(2*smoothness));
                case "saleh"
                    alphaAM = sixgr.rf.runtime.PAProfile.requiredField(profile,"AlphaAM");
                    betaAM = sixgr.rf.runtime.PAProfile.requiredField(profile,"BetaAM");
                    alphaPM = sixgr.rf.runtime.PAProfile.requiredField(profile,"AlphaPM");
                    betaPM = sixgr.rf.runtime.PAProfile.requiredField(profile,"BetaPM");
                    r = abs(xin);
                    am = alphaAM.*r./(1+betaAM.*r.^2);
                    pm = alphaPM.*r.^2./(1+betaPM.*r.^2);
                    y = am.*exp(1j*(angle(xin)+pm));
                case "memory_polynomial"
                    coefficients = sixgr.rf.runtime.PAProfile.requiredField( ...
                        profile,"Coefficients");
                    orders = sixgr.rf.runtime.PAProfile.requiredField( ...
                        profile,"Orders");
                    memoryDepth = sixgr.rf.runtime.PAProfile.requiredField( ...
                        profile,"MemoryDepth");
                    orders = double(orders(:));
                    coefficients = double(coefficients);
                    if isvector(coefficients) && memoryDepth == 1 && ...
                            numel(coefficients) == numel(orders)
                        coefficients = coefficients(:);
                    end
                    if memoryDepth < 1 || memoryDepth ~= round(memoryDepth) || ...
                            size(coefficients,1) ~= numel(orders) || ...
                            size(coefficients,2) ~= memoryDepth
                        error("RF:PAProfileDimensionMismatch", ...
                            "Memory-polynomial PA coefficient dimensions are invalid.");
                    end
                    [y,~]=sixgr.rf.runtime.MemoryPolynomialPA.apply( ...
                        xin,coefficients,orders,[]);
                case {"gmp","generalized_memory_polynomial"}
                    y=sixgr.rf.runtime.GeneralizedMemoryPolynomialPA.apply( ...
                        xin,profile);
                otherwise
                    error("RF:PAProfileMissing", ...
                        "Unsupported or uncalibrated PA model '%s'.",model);
            end
            y = y.*10.^(-double(profile.InputBackoff_dB)/20);
            pin = mean(abs(double(x(:))).^2);
            pout = mean(abs(double(y(:))).^2);
            evidence = struct( ...
                "ProfileID",string(profile.ProfileID), ...
                "Model",model, ...
                "Version",string(profile.Version), ...
                "InputPower_dB",10*log10(max(pin,realmin)), ...
                "OutputPower_dB",10*log10(max(pout,realmin)), ...
                "PowerChange_dB",10*log10(max(pout,realmin)/max(pin,realmin)), ...
                "PowerRestorationApplied",false, ...
                "CoefficientSHA256",string(sixgr.util.sha256Hex( ...
                    uint8(unicode2native(jsonencode(orderfields(profile)),"UTF-8")))));
        end
    end

    methods(Static,Access=private)
        function value = requiredField(s,name)
            if ~isfield(s,name)
                error("RF:PAProfileMissing", ...
                    "PA profile field '%s' is required.",name);
            end
            value = s.(name);
            if ~isnumeric(value) || any(~isfinite(value(:)))
                error("RF:PAProfileMissing", ...
                    "PA profile field '%s' must be finite numeric data.",name);
            end
        end
    end
end
