function validateConfig(cfg)
%VALIDATECONFIG Validate the complete YAML-owned NTN configuration.

ntn = sixgr.util.structGet(cfg,"ntn",[]);
if ~(isstruct(ntn) && isscalar(ntn))
    error("sixgr:ntn:MissingConfiguration", ...
        "The resolved scenario must contain a scalar ntn section.");
end
required = [ ...
    "enabled"; "standardReference"; "researchTaxonomy"; "channelProfile"; ...
    "orbit.type"; "orbit.model"; "orbit.satelliteAltitudeM"; ...
    "orbit.groundAltitudeM"; "orbit.elevationAngleDeg"; "orbit.epochSeconds"; ...
    "payload.architecture"; "doppler.satelliteMotionEnabled"; ...
    "doppler.mobileMotionEnabled"; "doppler.compensationMode"; ...
    "doppler.mobileDirectionAzimuthDeg"; "doppler.mobileDirectionZenithDeg"; ...
    "propagationDelay.enabled"; "propagationDelay.model"; ...
    "propagationDelay.compensationMode"; "tdl.mimoCorrelation"; ...
    "tdl.polarization"; "cdl.autoOrientSatelliteArray"; ...
    "atmosphericLoss.enabled"; "atmosphericLoss.model"; ...
    "output.enabled"; "output.componentFolder"; ...
    "output.structuredComponentFolders"; "output.saveCSV"; ...
    "output.savePNG"; "output.imageFormat"; "output.imageResolutionDPI"; ...
    "output.prohibitSVG"];
for i = 1:numel(required)
    if isempty(sixgr.util.structGet(ntn,required(i),[]))
        error("sixgr:ntn:MissingConfigurationValue", ...
            "Resolved YAML is missing ntn.%s.",char(required(i)));
    end
end

enabled = localLogical(ntn,"enabled");
localLogical(ntn,"doppler.satelliteMotionEnabled");
localLogical(ntn,"doppler.mobileMotionEnabled");
delayEnabled = localLogical(ntn,"propagationDelay.enabled");
localLogical(ntn,"cdl.autoOrientSatelliteArray");
atmosphericEnabled = localLogical(ntn,"atmosphericLoss.enabled");
localLogical(ntn,"output.enabled");
localLogical(ntn,"output.structuredComponentFolders");
localLogical(ntn,"output.saveCSV");
localLogical(ntn,"output.savePNG");
prohibitSVG = localLogical(ntn,"output.prohibitSVG");

localToken(ntn,"standardReference","3gpp tr 38.811");
localToken(ntn,"researchTaxonomy",["agreed_starting_point","study_item_candidate","optional_research_experiment"]);
profile = upper(localToken(ntn,"channelProfile",["ntn-tdl-a","ntn-tdl-b","ntn-tdl-c","ntn-tdl-d","ntn-cdl-a","ntn-cdl-b","ntn-cdl-c","ntn-cdl-d"]));
localToken(ntn,"orbit.type",["leo","meo","geo"]);
localToken(ntn,"orbit.model","circular");
localToken(ntn,"payload.architecture","regenerative_service_link");
localToken(ntn,"doppler.compensationMode",["none","ideal_transmitter_geometry","ideal_receiver_geometry"]);
localToken(ntn,"propagationDelay.model","static_slant_range");
delayMode = localToken(ntn,"propagationDelay.compensationMode",["disabled","perfect_geometry_timing_advance"]);
localToken(ntn,"tdl.mimoCorrelation",["low","medium","medium-a","high","custom"]);
localToken(ntn,"tdl.polarization",["co-polar","cross-polar","custom"]);
localToken(ntn,"atmosphericLoss.model","itu-r p.618");
imageFormat = localToken(ntn,"output.imageFormat",["png","jpeg"]);
localInteger(ntn,"output.imageResolutionDPI",72,600);

satelliteAltitude = localPositive(ntn,"orbit.satelliteAltitudeM");
groundAltitude = localNonnegative(ntn,"orbit.groundAltitudeM");
if groundAltitude >= satelliteAltitude
    error("sixgr:ntn:InvalidAltitude", ...
        "NTN ground altitude must be below satellite altitude.");
end
elevation = localFinite(ntn,"orbit.elevationAngleDeg");
if ~(elevation > 0 && elevation <= 90)
    error("sixgr:ntn:InvalidElevation", ...
        "NTN elevation angle must lie in (0,90] degrees.");
end
localFinite(ntn,"orbit.epochSeconds");
azimuth = localFinite(ntn,"doppler.mobileDirectionAzimuthDeg");
zenith = localFinite(ntn,"doppler.mobileDirectionZenithDeg");
if azimuth < 0 || azimuth > 360 || zenith < 0 || zenith > 180
    error("sixgr:ntn:InvalidMobileDirection", ...
        "NTN mobile direction requires azimuth [0,360] and zenith [0,180].");
end
if delayEnabled ~= (delayMode == "perfect_geometry_timing_advance")
    error("sixgr:ntn:InvalidDelayCompensation", ...
        "Enabled delay requires perfect_geometry_timing_advance; disabled delay requires disabled compensation.");
end
if ~prohibitSVG || ~ismember(imageFormat,["png","jpeg"])
    error("sixgr:ntn:InvalidRasterOutputPolicy", ...
        "NTN output must prohibit SVG and use PNG or JPEG.");
end

if enabled
    channelModel = upper(strtrim(string(sixgr.util.structGet(cfg,"channel.model", ...
        sixgr.util.structGet(cfg,"channels.profile","")))));
    if channelModel ~= profile
        error("sixgr:ntn:ChannelProfileMismatch", ...
            "Enabled NTN channelProfile=%s must exactly match runtime channel profile=%s.", ...
            char(profile),char(channelModel));
    end
    if atmosphericEnabled
        error("sixgr:ntn:AtmosphericLossRequiresPowerBudgetMode", ...
            "P.618 loss cannot be applied to a configured-SNR reference plane.");
    end
    if ~logical(ntn.output.enabled) || ~logical(ntn.output.saveCSV) || ...
            ~logical(ntn.output.savePNG)
        error("sixgr:ntn:IncompleteOutputContract", ...
            "Enabled NTN requires measured CSV evidence and raster PNG/JPEG evidence.");
    end
    if exist("slantRangeCircularOrbit","file") ~= 2 || ...
            exist("dopplerShiftCircularOrbit","file") ~= 2
        error("sixgr:ntn:MissingSatelliteCommunicationsToolbox", ...
            "Enabled NTN requires Satellite Communications Toolbox orbit geometry functions.");
    end
end
end

function value = localToken(s,path,allowed)
value = lower(strtrim(string(sixgr.util.structGet(s,path,""))));
if ~isscalar(value) || strlength(value) == 0 || ~ismember(value,lower(string(allowed)))
    error("sixgr:ntn:InvalidConfigurationValue", ...
        "ntn.%s has unsupported value '%s'.",char(path),char(join(value,",")));
end
end

function value = localLogical(s,path)
value = sixgr.util.structGet(s,path,[]);
if ~(islogical(value) && isscalar(value))
    error("sixgr:ntn:InvalidConfigurationValue", ...
        "ntn.%s must be a scalar boolean.",char(path));
end
end

function value = localFinite(s,path)
value = sixgr.util.structGet(s,path,[]);
if ~(isnumeric(value) && isscalar(value) && isfinite(double(value)))
    error("sixgr:ntn:InvalidConfigurationValue", ...
        "ntn.%s must be a finite numeric scalar.",char(path));
end
value = double(value);
end

function value = localPositive(s,path)
value = localFinite(s,path);
if value <= 0
    error("sixgr:ntn:InvalidConfigurationValue", ...
        "ntn.%s must be positive.",char(path));
end
end

function value = localNonnegative(s,path)
value = localFinite(s,path);
if value < 0
    error("sixgr:ntn:InvalidConfigurationValue", ...
        "ntn.%s must be nonnegative.",char(path));
end
end

function value = localInteger(s,path,minimum,maximum)
value = localFinite(s,path);
if value ~= round(value) || value < minimum || value > maximum
    error("sixgr:ntn:InvalidConfigurationValue", ...
        "ntn.%s must be an integer in [%g,%g].",char(path),minimum,maximum);
end
end
