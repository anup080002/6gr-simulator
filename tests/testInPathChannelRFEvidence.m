function ok = testInPathChannelRFEvidence()
%TESTINPATHCHANNELRFEVIDENCE Guard actual-row Channel/RF evidence binding.

setup6GRSimToolkit("Verbose",false);
cfg = struct();
cfg.channel = struct("model","CDL","cdlProfile","CDL-C", ...
    "pathlossEnabled",false,"shadowFadingEnabled",false, ...
    "o2i",struct("enabled",false), ...
    "fading",struct("profile","CDL-C","delaySpread_s",100e-9));
cfg.run = struct("interferenceExecutionMode","none");
cfg.rf = struct("enable",false);
cfg.phy = struct("waveform",struct("sampleRate_Hz",122.88e6));
cfg.waveform = struct("sample_rate_hz",122.88e6);

identity = struct("RunID","runtime_test_run", ...
    "ExecutionID","execution_runtime_test", ...
    "ScenarioID","runtime_channel_rf_test", ...
    "ConfigHash",repmat('a',1,64));
inHash = string(repmat('1',1,64)); outHash = string(repmat('2',1,64));
pathHash = string(repmat('3',1,64)); rxHash = string(repmat('4',1,64));

T = table();
T.SFN = 0; T.Slot = 0; T.UEIndex = 1; T.Seed = 11; T.BaseStationID = 1;
T.ChannelRealizationId = "ch_0123456789abcdef";
T.RuntimeChannelLinkKey = "DL:cell1:ue1";
T.RuntimeChannelStartSample = 0; T.RuntimeChannelEndSample = 1024;
T.RuntimeChannelInputWaveformSHA256 = inHash;
T.RuntimeChannelOutputWaveformSHA256 = outHash;
T.RuntimeChannelPathGainsSHA256 = pathHash;
T.RuntimeChannelPathGainElementCount = 4096;
T.RuntimeChannelPathGainDimensions = "1024x4";
T.ChannelModelApplied = "CDL-C"; T.ChannelFadingApplied = true;
T.ChannelFadingObjectClass = "nrCDLChannel";
T.PhysicalTxAntennas = 2; T.PhysicalRxAntennas = 2;
T.RxWaveformBranches = 2; T.SampleRate_Hz = 122.88e6;
T.DopplerHz = 30; T.PropagationDistance_m = 100;
T.RuntimeGeometryDistance2D_m=80; T.RuntimeGeometryDistance3D_m=100;
T.RuntimeGeometrySource="explicit_3_4_5_geometry_adapter_fixture";
T.AppliedPathloss_dB = 0; T.AppliedShadowFading_dB = 0;
T.AppliedO2I_dB = 0; T.AppliedLargeScaleLoss_dB = 0;
% Explicit analytic adapter fixture; physical sample capture is tested by
% testSharedWaveformPhysicalRuntime, not claimed by these authored rows.
T.LargeScaleInputEnergy_mWsample=2048;
T.LargeScaleOutputEnergy_mWsample=2048;
T.LargeScaleExpectedOutputEnergy_mWsample=2048;
T.LargeScaleSampleElementCount=2048;
T.LargeScalePowerClosureRelativeTolerance=64*eps+8*2048*eps;
T.LargeScaleMeasurementStartSample=0;
T.LargeScaleMeasurementEndSampleExclusive=1024;
T.LargeScaleMeasurementSource="analytic_adapter_fixture_not_runtime_sample_capture";
T.PathlossModelSource = "disabled_by_yaml"; T.O2IModelSource = "disabled_by_yaml";
T.InterferenceMode = "none"; T.InterferenceContributorCount = 0;
T.InterferenceAggregatedRxPower_dBm = NaN; T.InterferencePowerSource = "";
T.DesiredSignalPowerBeforeNoise = 1; T.ReplaySampleNoiseVariance = 0.01;
T.MeasuredTrialSINR_dB = 20; T.NoiseBandwidth_Hz = 100e6;
T.NoiseFigure_dB = 7; T.NoiseOperatingMode = "configured_awgn_reference_snr";
T.NoiseVarianceSource = "configured_snr_exact_sample_variance";
T.RFImpairmentChainId = "rfpath_0123456789abcdef";
T.RxRFImpairmentChainId = "rf_0123456789ab";
T.RxRFInputWaveformSHA256 = rxHash;
T.RxRFOutputWaveformSHA256 = rxHash;
T.TxRFStageOrder = ""; T.RxRFStageOrder = "";
T.TxRFConfiguredStageCount = 0; T.RxRFConfiguredStageCount = 0;
T.RFStrictOk = true; T.EVM_rms = 0.02;

anchor = struct();
anchor.ConfigValidation = struct("Ok",true);
anchor.ConfigStrict = table("runtime_test_run","runtime_channel_rf_test",true, ...
    'VariableNames',{'RunId','ScenarioName','ConfigValidationOk'});
anchor.ToolboxCapabilities = struct("MATLABVersion",string(version));
anchor.Geometry = localGeometry();

% Actual retained RF execution, combined with the explicit analytic channel
% adapter fixture above. This is not an end-to-end fading/access trial.
cfgRF=cfg; cfgRF.rf.tx.cfo_Hz=125;
txOnly=localRFExecutionFixture(T,cfgRF,false);
txOnlyResult=sixgr.channel.buildInPathChannelRFResult(cfgRF,anchor,struct('DL',txOnly),identity);
rf=txOnlyResult.RFImpairmentChain;
assert(txOnlyResult.StrictOk && rf.RFExecuted && ~rf.WaveformChanged && ...
    rf.TXSegmentWaveformChanged && ~rf.RXSegmentWaveformChanged, ...
    'Actual TX-only RF must not fail merely because the RX front end is an identity.');
idle=localRFExecutionFixture(T,cfgRF,true);
idle.LargeScaleInputEnergy_mWsample=0; idle.LargeScaleOutputEnergy_mWsample=0;
idle.LargeScaleExpectedOutputEnergy_mWsample=0;
idleResult=sixgr.channel.buildInPathChannelRFResult(cfgRF,anchor,struct('DL',idle),identity);
rf=idleResult.RFImpairmentChain;
assert(rf.StrictOk && rf.RFExecuted && ~rf.WaveformChanged && ~rf.TXSegmentWaveformChanged, ...
    'An actually executed oscillator on idle samples is not a skipped RF stage.');
assert(~idleResult.StrictOk,'Idle data does not provide nonzero power-measurement qualification.');
missingRF=removevars(txOnly,'RFExecutionManifestJSON');
missingRFResult=sixgr.channel.buildInPathChannelRFResult(cfgRF,anchor,struct('DL',missingRF),identity);
assert(~missingRFResult.StrictOk && ~missingRFResult.RFImpairmentChain.StrictOk, ...
    'Missing retained execution evidence must not fall back to a mutation-only claim.');
skipped=txOnly; m=jsondecode(skipped.RFExecutionManifestJSON);
m.TX.ExecutedSegments.RFExecutedStageCount=0;
skipped.TxRFExecutedStageCount=0;
skipped.RFExecutionManifestJSON=string(jsonencode(m));
skipped.RFExecutionManifestSHA256=string(sixgr.util.sha256Hex( ...
    uint8(unicode2native(char(skipped.RFExecutionManifestJSON),'UTF-8'))));
skipped.RFImpairmentChainId="rfpath_"+skipped.RFExecutionManifestSHA256;
skippedResult=sixgr.channel.buildInPathChannelRFResult(cfgRF,anchor,struct('DL',skipped),identity);
assert(~skippedResult.StrictOk && ~skippedResult.RFImpairmentChain.StrictOk && ...
    contains(skippedResult.RFImpairmentChain.FailureReason,'RF:ManifestExecutionMissing'), ...
    'A correctly hashed manifest cannot validate a configured stage that did not execute.');

result = sixgr.channel.buildInPathChannelRFResult( ...
    cfg,anchor,struct("DL",T),identity);
legacyColumns=T; legacyColumns.TxRFExecutedStageCount=NaN;
legacyColumns.RxRFExecutedStageCount=NaN; legacyColumns.RFExecutionManifestJSON="";
legacyColumns.RFExecutionEvidenceSource="";
legacyResult=sixgr.channel.buildInPathChannelRFResult(cfg,anchor,struct('DL',legacyColumns),identity);
assert(legacyResult.StrictOk && startsWith(legacyResult.RFImpairmentChain.RFExecutionEvidenceSource,'legacy_'), ...
    'Empty compatibility columns must not relabel a legacy row as retained execution.');
assert(result.StrictOk && height(result.ChannelRealizations)==1 && ...
    all(string(result.ChannelRealizations.EvidenceScope)=="in_path") && ...
    all(logical(result.ChannelRealizations.SameScenarioInPathEligible)), ...
    "Executed Channel/RF rows must pass with exact in-path identity. %s", ...
    char(string(result.FailureReason)));
assert(result.InPathRuntimeValidationComplete && ...
    string(result.ValidationAuthority)=="sixgr.channel.buildInPathChannelRFResult/v1" && ...
    string(result.ValidationComponent)=="channel_rf" && ...
    string(result.RuntimeEvidenceSource)=="CoupledTruthRuntime.RawTrials" && ...
    ~result.LaunchedSupplementalWaveform && strlength(string(result.SourceTableSHA256))==64, ...
    "Channel/RF evidence must carry the exact specialized runtime-validation seal.");
assert(isempty(result.ChannelSnapshots) && ...
    ~result.ChannelRealizations.ChannelSnapshotExported && ~result.ChannelRealizations.PathGainsExported && ...
    result.ChannelRealizations.ChannelSnapshotHash=="" && ...
    isnan(result.ChannelRealizations.ChannelMatrixRows) && isnan(result.ChannelRealizations.ChannelMatrixColumns) && ...
    result.ChannelPathGains.SampleTimeHash=="" && isnan(result.ChannelPathGains.SampleTimeCount), ...
    'Waveform hashes and interval descriptors cannot prove a tensor snapshot, matrix dimensions or a sample-time array hash.');
assert(result.ChannelRealizations.SampleTimeSec==0 && ...
    result.ChannelRealizations.SampleRateHz==122.88e6 && ...
    string(result.ChannelRealizations.SampleRateSource)=="runtime_trial.SampleRate_Hz", ...
    "Channel execution time must use and identify the exact runtime sample clock.");
emptyCaptureColumns=T; emptyCaptureColumns.ChannelObservationID=NaN;
emptyCaptureColumns.ChannelObservationManifestJSON="";
emptyCaptureColumns.ChannelObservationSegmentCount=NaN;
emptyCaptureResult=sixgr.channel.buildInPathChannelRFResult(cfg,anchor,struct('DL',emptyCaptureColumns),identity);
assert(isempty(emptyCaptureResult.ChannelSnapshots) && ~emptyCaptureResult.ChannelRealizations.PathGainsExported, ...
    'Blank compatibility columns must not promote legacy rows to verified coefficient artifacts.');

assert(result.LargeScaleParameters.PowerMeasurementAvailable && ...
    result.LargeScaleParameters.PowerClosureOk && result.LargeScaleParameters.MeasuredDeltaDb==0);
assert(result.LargeScaleParameters.Distance2Dm==80 && ...
    result.LargeScaleParameters.Distance3Dm==100 && ...
    result.LargeScaleParameters.GeometrySource==T.RuntimeGeometrySource);
missingGeometry=removevars(T,{'RuntimeGeometryDistance2D_m','RuntimeGeometryDistance3D_m','RuntimeGeometrySource'});
missingGeometryResult=sixgr.channel.buildInPathChannelRFResult(cfg,anchor,struct('DL',missingGeometry),identity);
assert(isnan(missingGeometryResult.LargeScaleParameters.Distance2Dm) && ...
    isnan(missingGeometryResult.LargeScaleParameters.Distance3Dm), ...
    'Legacy propagation range must not manufacture an executed 2-D/3-D geometry pair.');
missingEnergy=removevars(T,'LargeScaleOutputEnergy_mWsample');
missingResult=sixgr.channel.buildInPathChannelRFResult(cfg,anchor,struct('DL',missingEnergy),identity);
assert(~missingResult.StrictOk && isnan(missingResult.LargeScaleParameters.MeasuredDeltaDb) && ...
    missingResult.LargeScaleParameters.FailureReason=="runtime_large_scale_independent_energy_missing", ...
    'Expected loss must never substitute for missing measured energy.');
wrongClock=T;
wrongClock.LargeScaleMeasurementStartSample=1024;
wrongClock.LargeScaleMeasurementEndSampleExclusive=2048;
wrongClockResult=sixgr.channel.buildInPathChannelRFResult(cfg,anchor,struct('DL',wrongClock),identity);
assert(~wrongClockResult.StrictOk && ~wrongClockResult.LargeScaleParameters.PowerMeasurementAvailable, ...
    'Energy from another sample interval must not validate the current receive capture.');
wrongEnergy=T; wrongEnergy.LargeScaleOutputEnergy_mWsample=1024;
wrongResult=sixgr.channel.buildInPathChannelRFResult(cfg,anchor,struct('DL',wrongEnergy),identity);
assert(~wrongResult.StrictOk && ~wrongResult.LargeScaleParameters.PowerClosureOk && ...
    abs(wrongResult.LargeScaleParameters.MeasuredDeltaDb-10*log10(2))<1e-12, ...
    'Wrong executed gain must fail even when all configured/applied ledger fields agree.');
netGain=T; netGain.LargeScaleExpectedOutputEnergy_mWsample=2048*10^(-30/10);
netGain.LargeScaleOutputEnergy_mWsample=netGain.LargeScaleExpectedOutputEnergy_mWsample;
netGain.AppliedLargeScaleLoss_dB=40;
gainResult=sixgr.channel.buildInPathChannelRFResult(cfg,anchor,struct('DL',netGain),identity);
assert(gainResult.LargeScaleParameters.PowerClosureOk && ...
    abs(gainResult.LargeScaleParameters.ExpectedDeltaDb-30)<1e-12 && ...
    abs(gainResult.LargeScaleParameters.MeasuredDeltaDb-30)<1e-12, ...
    'Net waveform attenuation must not be incorrectly equated with pathloss alone.');

% Production runtime rows may omit a duplicate sample-rate column because
% buildInternalConfig already owns the resolved waveform clock.  In that
% case the snapshot must bind to config authority, never eps or a guessed
% denominator.
TConfigRate=T;
TConfigRate.SampleRate_Hz=[];
TConfigRate.RuntimeChannelStartSample=61440;
TConfigRate.RuntimeChannelEndSample=62464;
TConfigRate.LargeScaleMeasurementStartSample=61440;
TConfigRate.LargeScaleMeasurementEndSampleExclusive=62464;
resultConfigRate=sixgr.channel.buildInPathChannelRFResult( ...
    cfg,anchor,struct("DL",TConfigRate),identity);
assert(abs(resultConfigRate.ChannelRealizations.SampleTimeSec-5e-4)<1e-15 && ...
    resultConfigRate.ChannelRealizations.SampleRateHz==122.88e6 && ...
    string(resultConfigRate.ChannelRealizations.SampleRateSource)== ...
        "resolved_config.phy.waveform.sampleRate_Hz", ...
    "Config-resolved runtime sample rate must produce the physical snapshot time.");

cfgNoRate=rmfield(cfg,"phy");
cfgNoRate=rmfield(cfgNoRate,"waveform");
try
    sixgr.channel.buildInPathChannelRFResult( ...
        cfgNoRate,anchor,struct("DL",TConfigRate),identity);
    error("testInPathChannelRFEvidence:MissingExpectedFailure", ...
        "Missing sample-rate authority must fail closed.");
catch ME
    assert(string(ME.identifier)=="sixgr:channel:RuntimeSampleRateUnavailable", ...
        "Missing sample-rate authority must raise the typed production error, got %s.", ...
        string(ME.identifier));
end
positive = logical(result.ConfiguredVsApplied.ExpectedOk);
assert(all(string(result.ConfiguredVsApplied.EvidenceScope(positive))=="in_path") && ...
    all(string(result.ConfiguredVsApplied.EvidenceScope(~positive))=="component_anchor") && ...
    all(string(result.ConfiguredVsApplied.TruthStatus(~positive))== ...
        "executed_negative_contract_evidence") && ...
    all(logical(result.NegativeTrials.NegativeExpectedOk)), ...
    "Executed negative contracts must remain component-anchor evidence.");

% The canonical YAML interference section is authoritative. A shared-slot
% contributor must not be mislabeled disabled merely because the legacy
% run.interferenceExecutionMode alias is absent.
cfgInterference=cfg;
cfgInterference.interference=struct( ...
    "intra_cell_interference_flag",true, ...
    "intra_cell_execution_mode","shared_slot_waveform_superposition");
TI=T;
TI.InterferenceMode="shared_slot_waveform_superposition";
TI.InterferenceContributorCount=1;
TI.InterferenceAggregatedRxPower_dBm=-80;
TI.InterferencePowerSource="same_slot_runtime_contribution";
resultInterference=sixgr.channel.buildInPathChannelRFResult( ...
    cfgInterference,anchor,struct("DL",TI),identity);
assert(resultInterference.StrictOk && ...
    all(logical(resultInterference.InterferenceTopology.InterferenceConfigured)) && ...
    all(logical(resultInterference.InterferenceTopology.InterferenceApplied)), ...
    "Configured same-slot interference must match its actual runtime contributor evidence.");

% buildInternalConfig publishes normalized camel-case authority fields.
% These must be equivalent to the canonical YAML names above.
cfgNormalized=cfg;
cfgNormalized.run.intraCellInterferenceExecutionMode= ...
    "shared_slot_waveform_superposition";
cfgNormalized.interference=struct("intraCellEnabled",true, ...
    "interCellEnabled",false);
cfgNormalized.channel.interference=struct("intraCellEnabled",true, ...
    "interCellEnabled",false);
resultNormalized=sixgr.channel.buildInPathChannelRFResult( ...
    cfgNormalized,anchor,struct("DL",TI),identity);
assert(resultNormalized.StrictOk && ...
    all(logical(resultNormalized.InterferenceTopology.InterferenceConfigured)) && ...
    all(logical(resultNormalized.InterferenceTopology.InterferenceApplied)), ...
    "Normalized internal interference authority must match runtime contributors.");

scopeStats=struct("ChannelRFRequired",true,"ChannelRFStrictOk",false, ...
    "ChannelRFStatus","missing");
classified=sixgr.truth.classifySupplementalEvidenceScope(scopeStats, ...
    struct("StrictSupplemental",struct("ChannelRF",resultInterference)), ...
    "ChannelRF","ChannelRFStatus");
assert(classified.ChannelRFStrictOk && classified.InPathRuntimeEvidenceValidated && ...
    string(classified.ComponentAnchorStatus)=="PASS_IN_PATH_RUNTIME_VALIDATED", ...
    "Only the specialized Channel/RF runtime validator seal may promote in-path evidence.");

tmp=tempname; mkdir(tmp); cleanup=onCleanup(@() rmdir(tmp,"s")); %#ok<NASGU>
artifacts=sixgr.channel.exportStrictChannelRFArtifacts(result,tmp);
reported=readtable(fullfile(tmp,"reports","csv","channel_rf_configured_applied.csv"), ...
    "TextType","string");
disabled=~logical(reported.FeatureConfigured);
assert(any(disabled) && all(~logical(reported.FeatureApplied(disabled))) && ...
    all(logical(reported.ConfiguredAppliedOk)), ...
    "Explicitly disabled, unexecuted features must not become false report failures.");
assert(isfile(artifacts.ConfiguredVsAppliedCSV) && ...
    isfile(artifacts.ChannelRealizationsCSV) && ...
    isfile(artifacts.ConfiguredVsAppliedPNG) && isfile(artifacts.RFImpairmentPNG), ...
    "In-path Channel/RF evidence must export its CSV and PNG contract.");
for p=[string(artifacts.ConfiguredVsAppliedPNG),string(artifacts.RFImpairmentPNG)]
    info=imfinfo(p);
    assert(info.Width>=640 && info.Height>=360 && strcmpi(info.Format,"png"), ...
        "Channel/RF visual evidence must be a readable publication-size PNG.");
end
ok=true;
end

function geometry=localGeometry()
geometry=struct();
geometry.LinkTable=table("link1",1,1,1,"0 0 25","100 0 1.5",100,100,false,false,0, ...
    'VariableNames',{'LinkId','CellId','SectorId','UEId','SitePositionXYZm', ...
    'UEPositionXYZm','Distance2Dm','Distance3Dm','LOSState','O2IState','IndoorDistance2Dm'});
geometry.SiteTable=table(1,"site1",'VariableNames',{'SiteId','SiteName'});
geometry.SectorTable=table(1,1,'VariableNames',{'SectorId','SiteId'});
geometry.UETable=table(1,"ue1",'VariableNames',{'UEId','UEName'});
end

function T=localRFExecutionFixture(T,cfg,idle)
fs=T.SampleRate_Hz; n=T.RuntimeChannelEndSample-T.RuntimeChannelStartSample;
x=complex(ones(n,2)); if idle, x(:)=0; end
tx=sixgr.rf.runtime.RFImpairmentStream(cfg,'tx','DL',fs,2,0,1,false);
rx=sixgr.rf.runtime.RFImpairmentStream(cfg,'rx','DL',fs,2,0,1,false);
a=tx.apply(sixgr.phy.waveform.WaveformChunk(x,0),1);
b=rx.apply(sixgr.phy.waveform.WaveformChunk(a.Waveform,0),1);
execution=struct('StartSample',0,'EndSampleExclusive',n, ...
    'TX',struct('ID',"gnb",'Replay',a.Replay), ...
    'RX',struct('ID',"ue",'Replay',b.Replay));
names=["gnb:tx","ue:pre_rf","ue:post_rf"]; samples={a.Waveform,a.Waveform,b.Waveform};
planes=struct([]);
for k=1:3
    d=sixgr.phy.waveform.WaveformReceiveDispatcher(fs,2,0);
    d.register(names(k),0,n);
    done=d.dispatch(sixgr.phy.waveform.WaveformChunk(samples{k},0),fs);
    plane=struct('ReceiverID',names(k),'Observation',done.Observation, ...
        'Segments',{{struct('StartSample',0,'EndSampleExclusive',n,'Execution',execution)}});
    if k==1, planes=plane; else, planes(k)=plane; end %#ok<AGROW>
end
T=sixgr.truth.bindSharedRFExecutionEvidence(T,planes);
end
