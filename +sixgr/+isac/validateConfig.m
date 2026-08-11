function validateConfig(cfg)
%VALIDATECONFIG Fail closed on the production communication-centric ISAC contract.

% Every execution-affecting value is required from the resolved YAML.  This
% validator deliberately supplies no scenario, sensing, channel, detector,
% acceptance, or publication defaults.

isac = sixgr.util.structGet(cfg,"isac",[]);
if ~(isstruct(isac) && isscalar(isac))
    error("sixgr:isac:MissingConfiguration", ...
        "The resolved scenario must contain a scalar isac section.");
end
required = [ ...
    "enabled"; "researchTaxonomy"; "approach"; "sensingMode"; ...
    "waveformAuthority"; "executionScope"; "channelModel"; "seed"; ...
    "coherentRepetitions"; "transmitPowerDbm"; ...
    "receiver.noiseFigureDb"; "receiver.referenceTemperatureK"; ...
    "receiver.gainDb"; "channel.simulateDirectPath"; "channel.warmupPulses"; ...
    "scene.nodePositionAuthority"; "scene.numberTargets"; ...
    "scene.targetPositionsM"; "scene.targetVelocitiesMps"; ...
    "scene.reflectionCoefficientReal"; "scene.reflectionCoefficientImag"; ...
    "processing.observationSource"; "processing.matchedFilterImplementation"; ...
    "processing.beamformer"; "processing.includeElementResponse"; ...
    "processing.backgroundRemoval"; ...
    "processing.maximumRangeM"; "processing.rangeFFTSize"; ...
    "processing.dopplerFFTSize"; "processing.azimuthGrid.minimumDeg"; ...
    "processing.azimuthGrid.maximumDeg"; "processing.azimuthGrid.stepDeg"; ...
    "detection.algorithm"; "detection.trainingCellsRange"; "detection.trainingCellsAngle"; ...
    "detection.guardCellsRange"; "detection.guardCellsAngle"; ...
    "detection.probabilityFalseAlarm"; "detection.maximumDetections"; ...
    "detection.nonMaximumSuppressionRangeBins"; ...
    "detection.nonMaximumSuppressionAngleBins"; ...
    "acceptance.minimumMatchedTargets"; "acceptance.maximumRangeErrorM"; ...
    "acceptance.maximumAzimuthErrorDeg"; "output.enabled"; ...
    "output.componentFolder"; "output.structuredComponentFolders"; ...
    "output.saveCSV"; "output.savePNG"; "output.imageFormat"; ...
    "output.imageResolutionDPI"; "output.prohibitSVG"];
for i = 1:numel(required)
    value = sixgr.util.structGet(isac,required(i),[]);
    if isempty(value)
        error("sixgr:isac:MissingConfigurationValue", ...
            "Resolved YAML is missing isac.%s.",char(required(i)));
    end
end

enabled = localLogical(isac,"enabled");
localLogical(isac,"channel.simulateDirectPath");
localLogical(isac,"processing.includeElementResponse");
localLogical(isac,"output.enabled");
localLogical(isac,"output.structuredComponentFolders");
localLogical(isac,"output.saveCSV");
localLogical(isac,"output.savePNG");
prohibitSVG = localLogical(isac,"output.prohibitSVG");

localToken(isac,"researchTaxonomy",["study_item_candidate","optional_research_experiment"]);
localToken(isac,"approach","communication_centric_nr_ofdm");
localToken(isac,"sensingMode",["monostatic_gnb","bistatic_gnb_ue"]);
localToken(isac,"waveformAuthority","exact_runtime_pdsch_waveform");
localToken(isac,"executionScope","first_committed_dl_grant");
localToken(isac,"channelModel","phased_scattering_mimo");
localToken(isac,"scene.nodePositionAuthority","coupled_runtime_topology");
localToken(isac,"processing.observationSource","known_runtime_waveform_matched_filter");
localToken(isac,"processing.matchedFilterImplementation","frequency_domain_exact_reference");
localToken(isac,"processing.beamformer","conventional_phase_shift");
localToken(isac,"processing.backgroundRemoval",["none","slow_time_mean"]);
localToken(isac,"detection.algorithm","ca_cfar_2d");
imageFormat = localToken(isac,"output.imageFormat",["png","jpeg"]);
if ~prohibitSVG || ~ismember(imageFormat,["png","jpeg"])
    error("sixgr:isac:InvalidRasterOutputPolicy", ...
        "Full-PHY ISAC output must prohibit SVG and use PNG or JPEG.");
end

nTargets = localInteger(isac,"scene.numberTargets",1,64);
localInteger(isac,"seed",0,2^32-1);
localInteger(isac,"coherentRepetitions",2,256);
localInteger(isac,"channel.warmupPulses",1,64);
localInteger(isac,"processing.rangeFFTSize",64,2^22);
localInteger(isac,"processing.dopplerFFTSize",2,4096);
localInteger(isac,"output.imageResolutionDPI",72,600);
localInteger(isac,"detection.trainingCellsRange",1,256);
localInteger(isac,"detection.trainingCellsAngle",1,256);
localInteger(isac,"detection.guardCellsRange",0,256);
localInteger(isac,"detection.guardCellsAngle",0,256);
localInteger(isac,"detection.maximumDetections",1,256);
localInteger(isac,"detection.nonMaximumSuppressionRangeBins",0,256);
localInteger(isac,"detection.nonMaximumSuppressionAngleBins",0,256);
minMatches = localInteger(isac,"acceptance.minimumMatchedTargets",0,nTargets);
if minMatches > nTargets
    error("sixgr:isac:InvalidAcceptanceTargetCount", ...
        "ISAC minimum matched targets cannot exceed the configured target count.");
end

localPositive(isac,"receiver.referenceTemperatureK");
localNonnegative(isac,"receiver.noiseFigureDb");
localFinite(isac,"receiver.gainDb");
localFinite(isac,"transmitPowerDbm");
localPositive(isac,"processing.maximumRangeM");
localPositive(isac,"processing.azimuthGrid.stepDeg");
localPositive(isac,"acceptance.maximumRangeErrorM");
localPositive(isac,"acceptance.maximumAzimuthErrorDeg");
pfa = localFinite(isac,"detection.probabilityFalseAlarm");
if ~(pfa > 0 && pfa < 1)
    error("sixgr:isac:InvalidFalseAlarmProbability", ...
        "isac.detection.probabilityFalseAlarm must lie strictly between zero and one.");
end
azMin = localFinite(isac,"processing.azimuthGrid.minimumDeg");
azMax = localFinite(isac,"processing.azimuthGrid.maximumDeg");
if ~(azMin < azMax)
    error("sixgr:isac:InvalidAzimuthGrid", ...
        "ISAC azimuth-grid minimum must be smaller than its maximum.");
end

localVectorLength(isac,"scene.targetPositionsM",3*nTargets);
localVectorLength(isac,"scene.targetVelocitiesMps",3*nTargets);
localVectorLength(isac,"scene.reflectionCoefficientReal",nTargets);
localVectorLength(isac,"scene.reflectionCoefficientImag",nTargets);

if enabled
    simulationMode = lower(strtrim(string(sixgr.util.structGet(cfg, ...
        "run.simulationMode",sixgr.util.structGet(cfg,"run_control.simulation_mode","")))));
    if simulationMode ~= "full_phy"
        error("sixgr:isac:RequiresFullPHY", ...
            "Enabled full-stack ISAC requires run.simulationMode=full_phy.");
    end
    if ~logical(sixgr.util.structGet(isac,"output.enabled",false))
        error("sixgr:isac:OutputDisabled", ...
            "Enabled ISAC requires isac.output.enabled=true.");
    end
    if ~logical(sixgr.util.structGet(isac,"output.saveCSV",false)) || ...
            ~logical(sixgr.util.structGet(isac,"output.savePNG",false))
        error("sixgr:isac:IncompleteOutputContract", ...
            "Enabled ISAC requires both measured CSV evidence and raster PNG/JPEG evidence.");
    end
end
end

function value = localToken(s,path,allowed)
value = lower(strtrim(string(sixgr.util.structGet(s,path,""))));
if ~isscalar(value) || strlength(value) == 0 || ~ismember(value,lower(string(allowed)))
    error("sixgr:isac:InvalidConfigurationValue", ...
        "isac.%s has unsupported value '%s'.",char(path),char(join(value,",")));
end
end

function value = localLogical(s,path)
value = sixgr.util.structGet(s,path,[]);
if ~(islogical(value) && isscalar(value))
    error("sixgr:isac:InvalidConfigurationValue", ...
        "isac.%s must be a scalar boolean.",char(path));
end
end

function value = localFinite(s,path)
value = sixgr.util.structGet(s,path,[]);
if ~(isnumeric(value) && isscalar(value) && isfinite(double(value)))
    error("sixgr:isac:InvalidConfigurationValue", ...
        "isac.%s must be a finite numeric scalar.",char(path));
end
value = double(value);
end

function value = localPositive(s,path)
value = localFinite(s,path);
if value <= 0
    error("sixgr:isac:InvalidConfigurationValue", ...
        "isac.%s must be positive.",char(path));
end
end

function value = localNonnegative(s,path)
value = localFinite(s,path);
if value < 0
    error("sixgr:isac:InvalidConfigurationValue", ...
        "isac.%s must be nonnegative.",char(path));
end
end

function value = localInteger(s,path,minimum,maximum)
value = localFinite(s,path);
if value ~= round(value) || value < minimum || value > maximum
    error("sixgr:isac:InvalidConfigurationValue", ...
        "isac.%s must be an integer in [%g,%g].",char(path),minimum,maximum);
end
end

function localVectorLength(s,path,expected)
value = sixgr.util.structGet(s,path,[]);
if ~isnumeric(value) || numel(value) ~= expected || ...
        any(~isfinite(real(value(:)))) || any(~isfinite(imag(value(:))))
    error("sixgr:isac:InvalidConfigurationValue", ...
        "isac.%s must contain exactly %d finite values.",char(path),expected);
end
end
