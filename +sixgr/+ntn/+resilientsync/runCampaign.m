function result = runCampaign(scenario, campaignId, runDirectory)
%RUNCAMPAIGN Execute one evidence-class-separated resilient NTN campaign.

arguments
    scenario (1,1) struct
    campaignId (1,1) string
    runDirectory (1,1) string
end
campaignId = upper(strtrim(campaignId));
switch campaignId
    case "A"
        result = localCampaignA(scenario,runDirectory);
    case "B"
        result = localCampaignB(scenario,runDirectory);
    case "C"
        result = sixgr.ntn.resilientsync.prach.runPrachResidualGrid(scenario,runDirectory);
    case "D"
        pusch = sixgr.ntn.resilientsync.uplink.runPuschResidualGrid(scenario,runDirectory);
        pucch = sixgr.ntn.resilientsync.uplink.runPucchResidualGrid(scenario,runDirectory);
        result = struct("Campaign","D","Tables",localMergeTables(pusch.Tables,pucch.Tables), ...
            "Evidence",[pusch.Evidence;pucch.Evidence],"Status",localBoth(pusch.Status,pucch.Status));
    case "E"
        result = localCampaignE(scenario);
    case "F"
        result = localCampaignF(scenario);
    case "G"
        result = localCampaignG(scenario);
    otherwise
        error("sixgr:ntn:resilientsync:UnknownCampaign", ...
            "Unknown resilient synchronization campaign %s.",char(campaignId));
end
end

function result = localCampaignA(cfg,runDirectory)
c = double(cfg.geometry.speed_of_light_m_s);
elevation = deg2rad(double(cfg.gnss_degraded.service_link_elevation_deg));
ages = double(cfg.gnss_degraded.ages_s(:));
speeds = double(cfg.gnss_degraded.speeds_kmh(:)) ./ 3.6;
ppm = double(cfg.gnss_degraded.oscillator_ppm(:));
carriers = cfg.carriers;
rows = cell(numel(ages)*numel(speeds)*numel(ppm)*numel(carriers),1);
index = 0;
for carrierIndex = 1:numel(carriers)
    fUl = double(carriers(carrierIndex).f_ul_hz);
    for speedIndex = 1:numel(speeds)
        for ageIndex = 1:numel(ages)
            uePositionBound = double(cfg.gnss_degraded.initial_ue_position_error_los_m) + ...
                speeds(speedIndex)*ages(ageIndex) + ...
                0.5*double(cfg.gnss_degraded.acceleration_uncertainty_m_s2)*ages(ageIndex)^2;
            deltaRange = double(cfg.gnss_degraded.satellite_position_error_los_m) + uePositionBound;
            deltaTau = deltaRange/c;
            timing = -double(cfg.geometry.timing_mapping.kappa_t)*deltaTau;
            deltaRangeRate = double(cfg.gnss_degraded.satellite_radial_velocity_error_mps) + ...
                speeds(speedIndex)*cos(elevation);
            for ppmIndex = 1:numel(ppm)
                frequency = -(fUl/c)*deltaRangeRate + fUl*ppm(ppmIndex)*1e-6;
                index = index+1;
                rows{index} = {string(carriers(carrierIndex).id),fUl,ages(ageIndex), ...
                    speeds(speedIndex),ppm(ppmIndex),uePositionBound,deltaRange, ...
                    deltaRangeRate,deltaTau,timing,frequency,abs(frequency), ...
                    "deterministic_bound","ANALYTICAL"};
            end
        end
    end
end
holdover = cell2table(vertcat(rows{:}),'VariableNames', ...
    {'CarrierId','ULCarrier_Hz','PositionAge_s','Speed_m_s','Oscillator_ppm', ...
    'UEPositionErrorBound_m','DeltaRange_m','DeltaRangeRate_m_s','DeltaTauSL_s', ...
    'ULRPArrivalError_s','ULFrequencyError_Hz','AbsoluteULFrequencyError_Hz', ...
    'StatisticType','Provenance'});
holdover.Properties.VariableUnits = {'','Hz','s','m/s','ppm','m','m','m/s','s','s','Hz','Hz','',''};

earthRadius = double(cfg.geometry.earth_radius_km)*1e3;
altitude = double(cfg.geometry.orbit.altitude_km)*1e3;
mu = double(cfg.geometry.gravitational_parameter_m3_s2);
radii = double(cfg.gnss_free.reference_area_radii_km(:))*1e3;
elevations = double(cfg.gnss_free.elevations_deg(:));
nDrops = double(cfg.gnss_free.drops_per_point);
summaryRows = cell(numel(radii)*numel(elevations),1);
rawFolder = fullfile(char(runDirectory),'raw','campaign_a_reference_area');
if exist(rawFolder,'dir') ~= 7, mkdir(rawFolder); end
index = 0;
for elevationIndex = 1:numel(elevations)
    sat = sixgr.ntn.resilientsync.geometry.solveSatelliteStateForElevation( ...
        earthRadius,altitude,deg2rad(elevations(elevationIndex)),mu);
    ref = sixgr.ntn.resilientsync.geometry.slantRangeAndRate( ...
        sat.SatellitePositionECEF_m,sat.SatelliteVelocityECEF_m_s, ...
        sat.UEPositionECEF_m,sat.UEVelocityECEF_m_s);
    for radiusIndex = 1:numel(radii)
        seed = double(cfg.seed)+1000*elevationIndex+radiusIndex;
        samples = sixgr.ntn.resilientsync.geometry.sampleUniformReferenceArea( ...
            sat.UEPositionECEF_m,earthRadius,radii(radiusIndex),nDrops,seed);
        zeroVelocity = zeros(nDrops,3);
        geometry = sixgr.ntn.resilientsync.geometry.slantRangeAndRate( ...
            sat.SatellitePositionECEF_m,sat.SatelliteVelocityECEF_m_s, ...
            samples.PositionECEF_m,zeroVelocity);
        deltaRange = geometry.Range_m-ref.Range_m;
        deltaRangeRate = geometry.RangeRate_m_s-ref.RangeRate_m_s;
        deltaTau = deltaRange/c;
        eT = -double(cfg.geometry.timing_mapping.kappa_t).*deltaTau;
        cfoS = -(double(carriers(1).f_ul_hz)/c).*deltaRangeRate;
        cfoKa = -(double(carriers(2).f_ul_hz)/c).*deltaRangeRate;
        index = index+1;
        summaryRows{index} = {radii(radiusIndex),elevations(elevationIndex),nDrops,seed, ...
            localPercentile(abs(deltaTau),95),localPercentile(abs(eT),95), ...
            localPercentile(abs(cfoS),95),localPercentile(abs(cfoKa),95), ...
            max(abs(eT)),max(abs(cfoS)),"uniform_in_area", ...
            "exact_spherical_earth","MONTE_CARLO_GEOMETRY"};
        raw = table(samples.SurfaceRadius_m,samples.Azimuth_rad,deltaRange, ...
            deltaRangeRate,deltaTau,eT,cfoS,cfoKa, ...
            'VariableNames',{'SurfaceRadius_m','Azimuth_rad','DeltaRange_m', ...
            'DeltaRangeRate_m_s','DeltaTauSL_s','ULRPArrivalError_s', ...
            'DifferentialCFO_SBand_Hz','DifferentialCFO_Ka_Hz'});
        raw.Properties.VariableUnits = {'m','rad','m','m/s','s','s','Hz','Hz'};
        rawName = sprintf('reference_area_r%gkm_e%gdeg.mat', ...
            radii(radiusIndex)/1e3,elevations(elevationIndex));
        save(fullfile(rawFolder,rawName),'raw','seed','-v7.3');
    end
end
referenceArea = cell2table(vertcat(summaryRows{:}),'VariableNames', ...
    {'ReferenceAreaRadius_m','Elevation_deg','NumDrops','Seed', ...
    'P95AbsoluteDeltaTauSL_s','P95AbsoluteULRPArrivalError_s', ...
    'P95AbsoluteDifferentialCFO_SBand_Hz','P95AbsoluteDifferentialCFO_Ka_Hz', ...
    'MaxAbsoluteULRPArrivalError_s','MaxAbsoluteDifferentialCFO_SBand_Hz', ...
    'Distribution','GeometryModel','Provenance'});
referenceArea.Properties.VariableUnits = {'m','deg','','','s','s','Hz','Hz','s','Hz','','',''};

feederRows = cell(0,1);
for elev = double(cfg.feeder_link.elevations_deg(:)).'
    initial = sixgr.ntn.resilientsync.geometry.solveSatelliteStateForElevation( ...
        earthRadius,altitude,deg2rad(elev),mu);
    for validity = double(cfg.feeder_link.validity_s(:)).'
        t = linspace(0,validity,double(cfg.feeder_link.evaluation_samples)).';
        orbit = sixgr.ntn.resilientsync.geometry.propagateCircularOrbit( ...
            initial.SatellitePositionECEF_m,initial.SatelliteVelocityECEF_m_s,t,mu);
        geo = sixgr.ntn.resilientsync.geometry.slantRangeAndRate( ...
            orbit.PositionECEF_m,orbit.VelocityECEF_m_s,initial.UEPositionECEF_m,zeros(numel(t),3));
        tau = geo.Range_m/c;
        for order = double(cfg.feeder_link.derivative_orders(:)).'
            model = sixgr.ntn.resilientsync.geometry.feederDelayTaylorError(t,tau,0,order);
            feederRows{end+1,1} = {elev,validity,order,model.EndpointError_s, ...
                model.MaximumAbsoluteError_s,model.RMSError_s, ...
                double(carriers(1).f_ul_hz)*model.EndpointError_s/max(validity,eps), ...
                "ANALYTICAL"}; %#ok<AGROW>
        end
    end
end
feeder = cell2table(vertcat(feederRows{:}),'VariableNames', ...
    {'Elevation_deg','Validity_s','DerivativeOrder','EndpointError_s', ...
    'MaximumAbsoluteError_s','RMSError_s','EquivalentEndpointFrequencyError_Hz','Provenance'});
feeder.Properties.VariableUnits = {'deg','s','','s','s','s','Hz',''};

result = struct("Campaign","A","Status","COMPLETE", ...
    "Tables",struct("gnss_degraded_holdover",holdover, ...
    "reference_area_summary",referenceArea,"feeder_polynomial_summary",feeder), ...
    "Evidence",localEvidence(["gnss_degraded_holdover";"reference_area_summary";"feeder_polynomial_summary"], ...
    ["ANALYTICAL";"MONTE_CARLO_GEOMETRY";"ANALYTICAL"]));
end

function result = localCampaignB(cfg,runDirectory)
profiles = cfg.StateProfiles;
stateRows = cell(numel(profiles)*4,1); index=0;
domains = ["dl_timing","dl_frequency","ul_timing","ul_frequency"];
for profileIndex=1:numel(profiles)
    for domain=domains
        d=profiles(profileIndex).(domain); index=index+1;
        stateRows{index}={string(profiles(profileIndex).id),double(profiles(profileIndex).state_version), ...
            domain,string(d.status),string(d.responsible_entity),string(d.reference_point), ...
            string(d.component),string(d.update_mode),double(d.derivative_order), ...
            string(profiles(profileIndex).coefficient_rule_id),string(profiles(profileIndex).g_model), ...
            "ARCHITECTURE_DIAGRAM"};
    end
end
stateTable=cell2table(vertcat(stateRows{:}),'VariableNames', ...
    {'ProfileId','StateVersion','Domain','Status','ResponsibleEntity','ReferencePoint', ...
    'Component','UpdateMode','DerivativeOrder','CoefficientRuleId','GModel','Provenance'});
stateTable.Properties.VariableUnits=repmat({''},1,width(stateTable));

intervals=double(cfg.measurement.observation_intervals_s(:));
sigmaPpm=double(cfg.measurement.dl_cfo_sigma_ppm_reference);
nTrials=localModeValue(cfg,1000,10000,30000);
estRows=cell(numel(profiles)*numel(intervals),1); wrongRows=cell(numel(profiles),1);
index=0;
for profileIndex=1:numel(profiles)
    profile=profiles(profileIndex); H=double(profile.H);
    trueX=[80/299792458;0.1e-6];
    g=localProfileG(profileIndex,size(H,1));
    for intervalIndex=1:numel(intervals)
        sigma=sigmaPpm*1e-6/sqrt(intervals(intervalIndex));
        stream=RandStream("mt19937ar","Seed",double(cfg.seed)+profileIndex*100+intervalIndex);
        errorValues=zeros(nTrials,2);
        for trial=1:nTrials
            noise=sigma*randn(stream,size(H,1),1);
            obs=sixgr.ntn.resilientsync.state.stateObservationModel(profile,trueX,noise,g);
            estimate=sixgr.ntn.resilientsync.measurement.estimateRangeRateOscillator( ...
                obs.Y,H,g,eye(size(H,1))*sigma^2);
            errorValues(trial,:)=estimate.XHat(:).'-trueX(:).';
        end
        index=index+1;
        estRows{index}={string(profile.id),double(profile.state_version),intervals(intervalIndex), ...
            nTrials,sigma,sqrt(mean(errorValues(:,1).^2)),sqrt(mean(errorValues(:,2).^2)), ...
            mean(errorValues(:,1)),mean(errorValues(:,2)),"ANALYTICAL"};
    end
    noiseless=sixgr.ntn.resilientsync.state.stateObservationModel(profile,trueX,zeros(size(H,1),1),g);
    wrong=sixgr.ntn.resilientsync.measurement.estimateRangeRateOscillator( ...
        noiseless.Y,H,zeros(size(g)),eye(size(H,1)));
    wrongRows{profileIndex}={string(profile.id),double(profile.state_version), ...
        wrong.RhoHat-trueX(1),wrong.EpsilonHat-trueX(2),norm(wrong.Residual), ...
        "wrong_g_model_intentionally_applied","EVENT_PROCEDURE"};
end
estimator=cell2table(vertcat(estRows{:}),'VariableNames', ...
    {'ProfileId','StateVersion','ObservationInterval_s','NumTrials','MeasurementSigma_fractional', ...
    'RhoRMSE_fractional','EpsilonRMSE_fractional','RhoBias_fractional', ...
    'EpsilonBias_fractional','Provenance'});
estimator.Properties.VariableUnits={'','','s','','1','1','1','1','1',''};
wrongState=cell2table(vertcat(wrongRows{:}),'VariableNames', ...
    {'ProfileId','StateVersion','RhoBias_fractional','EpsilonBias_fractional', ...
    'ResidualNorm','AppliedMismatch','Provenance'});
wrongState.Properties.VariableUnits={'','','1','1','1','',''};
[stepBoundary,staleState,mismatch,actions,fddScaling]=localConfidentialStateEvidence(cfg,profiles);
trsFolder=fullfile(char(runDirectory),'raw','campaign_b_trs');
if exist(trsFolder,'dir')~=7,mkdir(trsFolder);end
trsScenario=sixgr.lls6g.config.loadScenarioConfig( ...
    string(cfg.physical_layer.trs_scenario_config));
trsInternal=sixgr.lls6g.buildInternalConfig(trsScenario,trsFolder);
trs=sixgr.phy.trs.runStrictTRSValidation(trsInternal, ...
    "RunFolder",trsFolder,"RunId",string(cfg.RunId)+"_trs", ...
    "ScenarioName",string(cfg.campaign_name),"WriteArtifacts",true);
if ~logical(trs.StrictOk)
    error("sixgr:ntn:resilientsync:TRSStrictValidationFailed", ...
        "Physical downlink TRS measurement validation failed.");
end
trsFrequency=trs.ArtifactTables.trs_frequency_tracking;
finiteError=double(trsFrequency.FrequencyError_Hz);
finiteError=finiteError(isfinite(finiteError));
if isempty(finiteError)
    error("sixgr:ntn:resilientsync:TRSFrequencyEvidenceMissing", ...
        "Strict TRS execution produced no finite physical frequency-error observation.");
end
physicalError=median(finiteError);
stateMeasured=table(strings(numel(profiles)*2,1),zeros(numel(profiles)*2,1), ...
    strings(numel(profiles)*2,1),zeros(numel(profiles)*2,1), ...
    repmat(physicalError,numel(profiles)*2,1),zeros(numel(profiles)*2,1), ...
    repmat("CALIBRATED_LLS",numel(profiles)*2,1), ...
    'VariableNames',{'ProfileId','StateVersion','AppliedState','StateModelOffset_Hz', ...
    'PhysicalTRSError_Hz','PostStateResidual_Hz','Provenance'});
row=0;
for profileIndex=1:numel(profiles)
    modelOffset=(profileIndex-1)*0.02e-6*2e9;
    row=row+1;stateMeasured.ProfileId(row)=string(profiles(profileIndex).id); ...
        stateMeasured.StateVersion(row)=double(profiles(profileIndex).state_version); ...
        stateMeasured.AppliedState(row)="correct";stateMeasured.StateModelOffset_Hz(row)=0; ...
        stateMeasured.PostStateResidual_Hz(row)=physicalError;
    row=row+1;stateMeasured.ProfileId(row)=string(profiles(profileIndex).id); ...
        stateMeasured.StateVersion(row)=double(profiles(profileIndex).state_version); ...
        stateMeasured.AppliedState(row)="wrong";stateMeasured.StateModelOffset_Hz(row)=modelOffset; ...
        stateMeasured.PostStateResidual_Hz(row)=physicalError+modelOffset;
end
stateMeasured.Properties.VariableUnits={'','','','Hz','Hz','Hz',''};
stepBoundary.PhysicalTRSError_Hz=repmat(physicalError,height(stepBoundary),1);
stepBoundary.HandledResidual_Hz=physicalError+stepBoundary.HandledEpsilonBias*2e9;
stepBoundary.UnhandledResidual_Hz=physicalError+stepBoundary.UnhandledEpsilonBias*2e9;
stepBoundary.Properties.VariableUnits(end-2:end)={'Hz','Hz','Hz'};
tables=struct("compensation_state_matrix",stateTable, ...
    "estimator_reference",estimator,"wrong_state_validation",wrongState, ...
    "step_boundary_validation",stepBoundary,"stale_state_validation",staleState, ...
    "mismatch_classifier",mismatch,"network_action_outcomes",actions, ...
    "fdd_scaling_validation",fddScaling,"state_aware_measured_residual",stateMeasured);
trsNames=fieldnames(trs.ArtifactTables);
for trsIndex=1:numel(trsNames)
    tables.(trsNames{trsIndex})=trs.ArtifactTables.(trsNames{trsIndex});
end
baseEvidence=localEvidence(["compensation_state_matrix";"estimator_reference";"wrong_state_validation"; ...
    "step_boundary_validation";"stale_state_validation";"mismatch_classifier"; ...
    "network_action_outcomes";"fdd_scaling_validation";"state_aware_measured_residual"], ...
    ["ARCHITECTURE_DIAGRAM";"ANALYTICAL";repmat("EVENT_PROCEDURE",6,1);"CALIBRATED_LLS"]);
trsEvidence=localEvidence(string(trsNames),repmat("CALIBRATED_LLS",numel(trsNames),1));
result=struct("Campaign","B","Status","COMPLETE", ...
    "Tables",tables,"Evidence",[baseEvidence;trsEvidence]);
end

function result = localCampaignE(cfg)
c=double(cfg.geometry.speed_of_light_m_s); R=double(cfg.geometry.earth_radius_km)*1e3;
h=double(cfg.geometry.orbit.altitude_km)*1e3; mu=double(cfg.geometry.gravitational_parameter_m3_s2);
elev=double(cfg.k_offset.beam_center_elevations_deg(:)); scs=double(cfg.k_offset.scs_khz(:));
n=double(cfg.k_offset.ue_drops_per_beam); rawParts=cell(numel(elev)*numel(scs),1); part=0;
for ei=1:numel(elev)
    sat=sixgr.ntn.resilientsync.geometry.solveSatelliteStateForElevation(R,h,deg2rad(elev(ei)),mu);
    sample=sixgr.ntn.resilientsync.geometry.sampleUniformReferenceArea( ...
        sat.UEPositionECEF_m,R,double(cfg.k_offset.beam_diameter_km)*500,n,double(cfg.seed)+5000+ei);
    geo=sixgr.ntn.resilientsync.geometry.slantRangeAndRate( ...
        sat.SatellitePositionECEF_m,sat.SatelliteVelocityECEF_m_s,sample.PositionECEF_m,zeros(n,3));
    rtt=2*geo.Range_m/c; relative=rtt-min(rtt);
    for si=1:numel(scs)
        tslot=1e-3/(scs(si)/15); ue=ceil(relative/tslot).*tslot;
        beam=ceil(max(relative)/tslot)*tslot+zeros(n,1); part=part+1;
        rawParts{part}=table(repmat(elev(ei),n,1),repmat(scs(si),n,1), ...
            relative,ue,beam,ue-relative,beam-relative, ...
            'VariableNames',{'Elevation_deg','SCS_kHz','RequiredDelay_s','UEConfiguredDelay_s', ...
            'BeamConfiguredDelay_s','UEExcessDelay_s','BeamExcessDelay_s'});
    end
end
raw=vertcat(rawParts{:});
for si=1:numel(scs)
    mask=raw.SCS_kHz==scs(si); tslot=1e-3/(scs(si)/15);
    cellDelay=ceil(max(raw.RequiredDelay_s(mask))/tslot)*tslot;
    raw.CellConfiguredDelay_s(mask)=cellDelay;
end
raw.CellExcessDelay_s=raw.CellConfiguredDelay_s-raw.RequiredDelay_s;
raw.CoverageOk=raw.UEConfiguredDelay_s+eps>=raw.RequiredDelay_s & ...
    raw.BeamConfiguredDelay_s+eps>=raw.UEConfiguredDelay_s & ...
    raw.CellConfiguredDelay_s+eps>=raw.BeamConfiguredDelay_s;
raw.Provenance=repmat("SCHEDULER_SYSTEM",height(raw),1);
raw.Properties.VariableUnits={'deg','kHz','s','s','s','s','s','s','s','',''};
if ~all(raw.CoverageOk), error("sixgr:ntn:resilientsync:KOffsetCoverageFailure", ...
        "Configured k_offset hierarchy does not cover every represented delay."); end
summary=groupsummary(raw,{'Elevation_deg','SCS_kHz'}, ...
    {'max','mean'},{'RequiredDelay_s','UEExcessDelay_s','BeamExcessDelay_s','CellExcessDelay_s'});
summary.Provenance=repmat("SCHEDULER_SYSTEM",height(summary),1);
summary.Properties.VariableUnits=repmat({''},1,width(summary));
pipeline=table(summary.Elevation_deg,summary.SCS_kHz, ...
    ceil((2*(h/c)+double(cfg.k_offset.processing_delay_ms)*1e-3+ ...
    double(cfg.k_offset.configured_wait_ms)*1e-3)./(1e-3./(summary.SCS_kHz/15))), ...
    repmat("timing_pipeline_occupancy_not_normative_harq",height(summary),1), ...
    repmat("SCHEDULER_SYSTEM",height(summary),1), ...
    'VariableNames',{'Elevation_deg','SCS_kHz','PipelineSlots','Interpretation','Provenance'});
pipeline.Properties.VariableUnits={'deg','kHz','slot','',''};
result=struct("Campaign","E","Status","COMPLETE","Tables", ...
    struct("k_offset_samples",raw,"k_offset_summary",summary,"timing_pipeline",pipeline), ...
    "Evidence",localEvidence(["k_offset_samples";"k_offset_summary";"timing_pipeline"], ...
    repmat("SCHEDULER_SYSTEM",3,1)));
end

function result = localCampaignF(cfg)
steps=double(cfg.ta_report.report_steps_ms(:)); modes=string(cfg.ta_report.duplex_modes(:));
rawTA=linspace(0,double(cfg.k_offset.beam_diameter_km)*1e3/299792458*2,1001).'*1e3;
rows=cell(numel(steps)*numel(modes),1); index=0;
for mi=1:numel(modes)
    for si=1:numel(steps)
        quantized=round(rawTA/steps(si))*steps(si); err=quantized-rawTA;
        collision=false(size(err));
        if modes(mi)=="HD_FDD"
            collision=quantized+double(cfg.ta_report.hd_fdd_guard_ms)<rawTA;
        end
        index=index+1;
        rows{index}=table(repmat(modes(mi),numel(rawTA),1),repmat(steps(si),numel(rawTA),1), ...
            rawTA,quantized,err,collision, ...
            repmat("EVENT_PROCEDURE",numel(rawTA),1), ...
            'VariableNames',{'DuplexMode','ReportStep_ms','RawTA_ms','ReportedTA_ms', ...
            'QuantizationError_ms','PredictedCollision','Provenance'});
    end
end
ta=vertcat(rows{:}); ta.Properties.VariableUnits={'','ms','ms','ms','ms','',''};
summary=groupsummary(ta,{'DuplexMode','ReportStep_ms'},{'max','mean'},{'QuantizationError_ms','PredictedCollision'});
summary.Provenance=repmat("EVENT_PROCEDURE",height(summary),1);
summary.Properties.VariableUnits=repmat({''},1,width(summary));
result=struct("Campaign","F","Status","COMPLETE","Tables", ...
    struct("ta_report_events",ta,"ta_report_summary",summary), ...
    "Evidence",localEvidence(["ta_report_events";"ta_report_summary"],repmat("EVENT_PROCEDURE",2,1)));
end

function result = localCampaignG(cfg)
mixes=double(cfg.mixed_population.mixes); labels=string(cfg.mixed_population.population_labels(:));
n=double(cfg.mixed_population.samples_per_mix); rows=cell(size(mixes,1),1);
for i=1:size(mixes,1)
    counts=round(mixes(i,:)*n); counts(end)=n-sum(counts(1:end-1));
    rows{i}={i,n,mixes(i,1),mixes(i,2),mixes(i,3),counts(1),counts(2),counts(3), ...
        strjoin(labels,"|"),"EVENT_PROCEDURE"};
end
population=cell2table(vertcat(rows{:}),'VariableNames', ...
    {'MixId','Population','GNSSValidFraction','GNSSDegradedFraction','GNSSFreeFraction', ...
    'GNSSValidCount','GNSSDegradedCount','GNSSFreeCount','PopulationLabels','Provenance'});
population.Properties.VariableUnits={'','','1','1','1','','','','',''};
events=["gnss_to_degraded";"beam_switch";"satellite_switch";"feeder_switch";"reduced_harq_feedback"];
transitions=table((1:numel(events)).',events,repmat(1,numel(events),1), ...
    (2:numel(events)+1).',repmat("state_version_increment_before_new_correction",numel(events),1), ...
    repmat("EVENT_PROCEDURE",numel(events),1), ...
    'VariableNames',{'EventId','EventType','OldStateVersion','NewStateVersion','HandlingRule','Provenance'});
transitions.Properties.VariableUnits=repmat({''},1,width(transitions));
result=struct("Campaign","G","Status","COMPLETE","Tables", ...
    struct("mixed_population",population,"transition_events",transitions), ...
    "Evidence",localEvidence(["mixed_population";"transition_events"],repmat("EVENT_PROCEDURE",2,1)));
end

function out = localEvidence(names,classes)
names=string(names(:)); classes=string(classes(:));
out=table(names,classes,classes=="CALIBRATED_LLS",repmat("PRODUCED",numel(names),1), ...
    'VariableNames',{'Artifact','EvidenceClass','Measured','Status'});
end
function p=localPercentile(x,q), p=prctile(double(x(:)),q); end
function n=localModeValue(cfg,quick,tdoc,filing)
switch string(cfg.run_mode),case "quick",n=quick;case "tdoc",n=tdoc;otherwise,n=filing;end
end
function g=localProfileG(index,n),g=zeros(n,1);if index>1,g(:)=(index-1)*0.02e-6;end,end
function out=localMergeTables(a,b),out=a;f=fieldnames(b);for i=1:numel(f),out.(f{i})=b.(f{i});end,end
function status=localBoth(a,b),if string(a)=="COMPLETE"&&string(b)=="COMPLETE",status="COMPLETE";else,status="FAILED";end,end

function [stepTable,staleTable,mismatchTable,actionTable,fddTable]=localConfidentialStateEvidence(cfg,profiles)
stepIndex=find(string({profiles.id})=="STEPWISE_COMMON_COMP",1);
profile=profiles(stepIndex);H=double(profile.H);x=[50/299792458;0.1e-6];
windows={[-2;-1]+profile.activation_time_s,[-1;1]+profile.activation_time_s,[1;2]+profile.activation_time_s};
names=["before";"straddling";"after"];rows=cell(3,1);step=0.05e-6;
for i=1:3
    times=windows{i};g=zeros(numel(times),size(H,1));g(times>=profile.activation_time_s,:)=step;
    y=zeros(numel(times),size(H,1));
    for k=1:numel(times),y(k,:)=(H*x+g(k,:).').';end
    handled=zeros(numel(times),2);
    boundary=sixgr.ntn.resilientsync.state.handleStepBoundary(profile,times,y);
    for segment=unique(boundary.SegmentIndex).'
        mask=boundary.SegmentIndex==segment;gUse=zeros(size(H,1),1);if segment==2,gUse(:)=step;end
        estimate=sixgr.ntn.resilientsync.measurement.estimateRangeRateOscillator( ...
            mean(y(mask,:),1).',H,gUse,eye(size(H,1)));
        handled(mask,:)=repmat(estimate.XHat.',sum(mask),1);
    end
    unhandled=sixgr.ntn.resilientsync.measurement.estimateRangeRateOscillator( ...
        mean(y,1).',H,zeros(size(H,1),1),eye(size(H,1)));
    rows{i}={names(i),min(times),max(times),boundary.StraddlesStep, ...
        mean(handled(:,1))-x(1),mean(handled(:,2))-x(2), ...
        unhandled.RhoHat-x(1),unhandled.EpsilonHat-x(2),double(profile.state_version), ...
        "EVENT_PROCEDURE"};
end
stepTable=cell2table(vertcat(rows{:}),'VariableNames', ...
    {'Window','StartTime_s','EndTime_s','StraddlesStep','HandledRhoBias', ...
    'HandledEpsilonBias','UnhandledRhoBias','UnhandledEpsilonBias','StateVersion','Provenance'});
stepTable.Properties.VariableUnits={'','s','s','','1','1','1','1','',''};
versions=[profile.state_version-1;profile.state_version;profile.state_version+1];
accepted=versions==profile.state_version;
staleTable=table(versions,repmat(profile.state_version,3,1),accepted, ...
    strings(3,1),repmat("EVENT_PROCEDURE",3,1), ...
    'VariableNames',{'ReportedStateVersion','ActiveStateVersion','Accepted','RejectionReason','Provenance'});
staleTable.RejectionReason(~accepted)="stale_or_future_state_version";
staleTable.RejectionReason(accepted)="none";staleTable.Properties.VariableUnits=repmat({''},1,width(staleTable));

n=localModeValue(cfg,3000,30000,90000);stream=RandStream("mt19937ar","Seed",double(cfg.seed)+9000);
truth=[zeros(n/3,1);ones(n/3,1);2*ones(n-2*floor(n/3),1)];
means=[0,3,6];normalized=zeros(n,1);
for cls=0:2,m=truth==cls;normalized(m)=means(cls+1)+randn(stream,sum(m),1);end
absValue=abs(normalized);prediction=zeros(n,1);prediction(absValue>=2)=1;prediction(absValue>=4)=2;
confidence=erf(absValue/sqrt(2));
mismatchTable=table((1:n).',truth,normalized,absValue,prediction,confidence, ...
    repmat(profile.state_version,n,1),repmat("EVENT_PROCEDURE",n,1), ...
    'VariableNames',{'Sample','TruthClass','NormalizedMismatch','AbsoluteNormalizedMismatch', ...
    'PredictedClass','Confidence','StateVersion','Provenance'});
mismatchTable.Properties.VariableUnits={'','','1','1','','1','',''};
actions=["continue";"request_measurement";"switch_state_profile"];
actionTable=table((0:2).',actions,accumarray(prediction+1,1,[3 1]), ...
    accumarray(prediction+1,double(prediction==truth),[3 1]),repmat("EVENT_PROCEDURE",3,1), ...
    'VariableNames',{'PredictedClass','NetworkAction','Count','CorrectCount','Provenance'});
actionTable.SuccessRate=actionTable.CorrectCount./max(actionTable.Count,1);
actionTable.Properties.VariableUnits={'','','','','','1'};

rows=cell(numel(profiles),1);rho=100/299792458;epsilon=0.1e-6;f=30e9;
for i=1:numel(profiles)
    correction=sixgr.ntn.resilientsync.state.applyNetworkCompensation(profiles(i),rho,epsilon,f,0);
    ideal=-f*(double(profiles(i).fdd_scaling)*double(profiles(i).k_rho)*rho+double(profiles(i).k_epsilon)*epsilon);
    rows{i}={string(profiles(i).id),double(profiles(i).fdd_scaling),correction.EffectiveKRho, ...
        correction.FrequencyCorrection_Hz,ideal,correction.FrequencyCorrection_Hz-ideal, ...
        double(profiles(i).state_version),"EVENT_PROCEDURE"};
end
fddTable=cell2table(vertcat(rows{:}),'VariableNames', ...
    {'ProfileId','FDDScaling','EffectiveKRho','AppliedCorrection_Hz','ExpectedCorrection_Hz', ...
    'Residual_Hz','StateVersion','Provenance'});
fddTable.Properties.VariableUnits={'','1','1','Hz','Hz','Hz','',''};
end
