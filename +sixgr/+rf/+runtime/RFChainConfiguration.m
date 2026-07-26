classdef RFChainConfiguration
%RFCHAINCONFIGURATION Strict RF planning validation.

    methods(Static)
        function result=validate(config)
            if ~isstruct(config)
                error("RF:UnsupportedCombination","RF chain configuration must be a structure.");
            end
            profileId=string(sixgr.util.structGet(config,"ProfileID",""));
            profile=sixgr.rf.runtime.RFSpecificationProfile.resolve(profileId);
            if logical(sixgr.util.structGet(config,"SCOEnabled",false)) && ...
                    ~isstruct(sixgr.util.structGet(config,"SCOProfile",[]))
                error("RF:SampleClockProfileMissing", ...
                    "SCO is enabled without a stateful resampler profile.");
            end
            if logical(sixgr.util.structGet(config,"PhaseNoiseEnabled",false))
                sixgr.rf.runtime.PhaseNoiseProfile.validate( ...
                    sixgr.util.structGet(config,"PhaseNoiseProfile",struct()));
            end
            if logical(sixgr.util.structGet(config,"PAEnabled",false)) && ...
                    ~isstruct(sixgr.util.structGet(config,"PAProfile",[]))
                error("RF:PAProfileMissing","PA is enabled without a calibrated profile.");
            elseif logical(sixgr.util.structGet(config,"PAEnabled",false))
                sixgr.rf.runtime.PAProfile.apply(0.1,config.PAProfile);
            end
            if logical(sixgr.util.structGet(config,"DPDEnabled",false)) && ...
                    ~isstruct(sixgr.util.structGet(config,"DPDProfile",[]))
                error("RF:DPDProfileMissing","DPD is enabled without coefficients.");
            elseif logical(sixgr.util.structGet(config,"DPDEnabled",false))
                sixgr.rf.runtime.DPDProfile.validate(config.DPDProfile);
            end
            if logical(sixgr.util.structGet(config,"ADCEnabled",false)) && ...
                    ~isstruct(sixgr.util.structGet(config,"ADCProfile",[]))
                error("RF:ADCProfileMissing","ADC is enabled without a profile.");
            elseif logical(sixgr.util.structGet(config,"ADCEnabled",false))
                sixgr.rf.runtime.ADCModel.quantize(0,config.ADCProfile);
            end
            if logical(sixgr.util.structGet(config,"AGCEnabled",false)) && ...
                    ~isstruct(sixgr.util.structGet(config,"AGCProfile",[]))
                error("RF:ImplicitAGCForbidden","AGC profile is not explicit.");
            elseif logical(sixgr.util.structGet(config,"AGCEnabled",false))
                sixgr.rf.runtime.AGCState(config.AGCProfile, ...
                    sixgr.util.structGet(config,"ConfigurationEpoch",1));
            end
            epoch=double(sixgr.util.structGet(config,"ConfigurationEpoch",NaN));
            if ~(isscalar(epoch)&&isfinite(epoch)&&epoch==round(epoch)&&epoch>=1)
                error("RF:StateEpochMismatch", ...
                    "Strict RF configuration requires an explicit positive integer epoch.");
            end
            if any([logical(sixgr.util.structGet(config,"PAEnabled",false)), ...
                    logical(sixgr.util.structGet(config,"ADCEnabled",false)), ...
                    logical(sixgr.util.structGet(config,"AGCEnabled",false)), ...
                    logical(sixgr.util.structGet(config,"SCOEnabled",false)), ...
                    logical(sixgr.util.structGet(config,"PhaseNoiseEnabled",false))])
                inputPlane=sixgr.util.structGet(config,"InputReferencePlane","");
                outputPlane=sixgr.util.structGet(config,"OutputReferencePlane","");
                sixgr.rf.runtime.RFReferencePlane.validate(inputPlane);
                sixgr.rf.runtime.RFReferencePlane.validate(outputPlane);
                impedance=double(sixgr.util.structGet(config, ...
                    "ReferenceImpedance_Ohm",NaN));
                if ~(isscalar(impedance)&&isfinite(impedance)&&impedance>0)
                    error("RF:MissingPowerParameter", ...
                        "Strict RF execution requires reference impedance.");
                end
            end
            plan=sixgr.rf.runtime.RFPlanningResult.executable(profile,config);
            result=struct("Profile",profile,"Passed",true, ...
                "ConfigurationEpoch",epoch,"Plan",plan);
        end
    end
end
