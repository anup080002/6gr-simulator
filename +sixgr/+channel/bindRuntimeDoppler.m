function cfg = bindRuntimeDoppler(cfg, user)
%BINDRUNTIMEDOPPLER Keep fading maximum distinct from geometric ray shift.
% nrCDL/TDL MaximumDopplerShift is a maximum, not the LOS radial projection.
% This binds a channel-model parameter only; it is not a receiver estimate.
if nargin < 2
    user = sixgr.util.structGet(cfg,'lls6g.userContext',struct());
end
mode = lower(string(sixgr.util.structGet(cfg,'channel.dopplerSourceMode','configured')));
switch mode
    case "configured"
        value = sixgr.util.structGet(cfg,'channel.dopplerConfigured_Hz', ...
            sixgr.util.structGet(cfg,'channel.doppler_Hz', ...
            sixgr.util.structGet(cfg,'channel.dopplerHz', ...
            sixgr.util.structGet(cfg,'channel.fading.maxDoppler_Hz',30))));
        source = "configured_maximum_doppler";
    case "derive_from_ue_speed"
        velocity = sixgr.util.structGet(user,'RuntimeUEVelocity_mps',[]);
        if isempty(velocity)
            % Before a runtime UE is bound, use the builder's resolved value.
            value = sixgr.util.structGet(cfg,'channel.doppler_Hz',NaN);
            source = "configured_speed_resolved_by_builder";
        else
            validateattributes(velocity,{'numeric'},{'real','finite','vector','numel',3});
            fc = sixgr.channel.ChannelFactory.resolveCarrierFrequency(cfg);
            value = norm(double(velocity))*double(fc)/299792458;
            source = "runtime_ue_speed_norm_times_carrier_over_c";
        end
    otherwise
        error('sixgr:channel:InvalidDopplerSourceMode', ...
            'Unsupported maximum-Doppler source mode: %s.',mode);
end
validateattributes(value,{'numeric'},{'real','finite','scalar','nonnegative'}, ...
    mfilename,'maximumDopplerHz');
for name = ["doppler_Hz","dopplerHz","maxDoppler_Hz","maxDopplerHz"]
    cfg.channel.(name) = double(value);
end
cfg = sixgr.util.structSet(cfg,'channel.fading.maxDoppler_Hz',double(value));
cfg.channel.maximumDopplerSource = source;
cfg.channel.runtimeProjectedRadialDoppler_Hz = double(sixgr.util.structGet( ...
    user,'RuntimeServingDopplerHz',NaN));
cfg.channel.runtimeSignedDoppler_Hz = double(sixgr.util.structGet( ...
    user,'RuntimeServingSignedDopplerHz',NaN));
end
