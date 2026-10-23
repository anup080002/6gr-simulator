function [ok,result]=testChannelNMSEReportingIntegrity(runExporters)
% Declared producer-contract fixtures. No PHY, archive replay or confidence claim.
if nargin<1, runExporters=true; end
before=rng;
dl=dataFixture("DL",false); ul=dataFixture("UL",true);
trs=trsFixture(); csi=csirsFixture();
original=dl;
meanDB=10*log10((0+.1+1)/3); pooledDB=10*log10(101/111);
for signal=["DL","UL","TRS","CSI-RS"]
    T=dl; if signal=="UL", T=ul; elseif signal=="TRS", T=trs; elseif signal=="CSI-RS", T=csi; end
    [s,o]=sixgr.report.summarizeChannelNMSEReport(T,signal);
    assert(height(s)==1 && height(o)==3 && all(o.MeasurementAvailable));
    assert(same(s.MeanNMSE_dB,meanDB) && s.P05NMSE_dB==-Inf && s.P95NMSE_dB==0 && s.MaxNMSE_dB==0);
    assert(s.MeasurementCount==3 && ~s.StatisticalIndependenceClaimed && ~s.ConfidenceIntervalAvailable);
    assert(~any(o.CountsTowardCoverage) && all(o.EvidenceValidationScope== ...
        "original_producer_row_contract_not_independent_archive_reaudit"));
    assert(~s.PooledEnergyAvailable && isnan(s.PooledNMSE_dB), ...
        'Count equality without exact retained support configuration cannot establish cross-observation pooling.');
    % Failed CRC/status are still independently scored channel measurements.
    assert(o.MeasurementAvailable(2) && T.CRCPass(2)==0 && T.Status(2)=="FAIL");
    zero=T(1,:); [z,~]=sixgr.report.summarizeChannelNMSEReport(zero,signal);
    assert(z.MeanNMSE_dB==-Inf && z.PooledEnergyAvailable && z.PooledNMSE_dB==-Inf);
end
assert(isequaln(dl,original) && isequaln(rng,before));

% Declared exact allocation fields demonstrate the DIFFERENT estimands.
% No claim that historical rows missing these fields can be backfilled.
complete=dl;
complete.PRBSet=repmat({0:3},3,1); complete.SymbolAllocation=repmat({[2 12]},3,1);
complete.DMRSPortSet=repmat({0},3,1); complete.NumRxAnt=ones(3,1);
complete.DMRSConfigType=ones(3,1); complete.DMRSLength=ones(3,1);
complete.DMRSAdditionalPosition=zeros(3,1); complete.DMRSTypeAPosition=repmat(2,3,1);
complete.NSizeGrid=repmat(4,3,1); complete.SubcarrierSpacing=repmat(30,3,1);
[s,~]=sixgr.report.summarizeChannelNMSEReport(complete,"DL");
assert(s.PooledEnergyAvailable && same(s.PooledNMSE_dB,pooledDB) && ...
    same(s.MeanNMSE_dB,meanDB) && abs(s.MeanNMSE_dB-s.PooledNMSE_dB)>1);
assert(s.ErrorEnergy==101 && s.ReferenceEnergy==111 && s.MeanDefinition~=s.PooledDefinition);

% Original point/seed/UE/support/RF-reference populations must not merge.
different=dl; different.RandomSeed(:)=19;
[s,~]=sixgr.report.summarizeChannelNMSEReport([dl;different],"DL"); assert(height(s)==2);
for field=["SourceRandomSeed","SourceChannelSeed","PreparedRandomSeed","PreparedChannelSeed"]
    seeded=dl; seeded.(field)=repmat(7,3,1); different=seeded; different.(field)(:)=19;
    [s,~]=sixgr.report.summarizeChannelNMSEReport([seeded;different],"DL"); assert(height(s)==2);
end
trialSeeds=dl; trialSeeds.Seed=(21:23).'; trialSeeds.NoiseStreamSeed=(121:123).';
[s,o]=sixgr.report.summarizeChannelNMSEReport(trialSeeds,"DL");
assert(height(s)==1 && s.MeasurementCount==3 && same(s.MeanNMSE_dB,meanDB));
for k=1:3
    identity=jsondecode(o.ObservationIdentityJSON(k));
    assert(identity.Seed==trialSeeds.Seed(k) && identity.NoiseStreamSeed==trialSeeds.NoiseStreamSeed(k));
end
different=dl; different.ConfiguredSNR_dB(:)=1e-10;
[s,~]=sixgr.report.summarizeChannelNMSEReport([dl;different],"DL");
assert(height(s)==2 && numel(unique(s.PopulationID))==2 && numel(unique(s.PopulationSeriesID))==1);
series=jsondecode(s.PopulationSeriesJSON(1)); seriesPopulation=jsondecode(series.PopulationJSON);
assert(~isfield(seriesPopulation,'ConfiguredSNR_dB') && seriesPopulation.RandomSeed==7);
configured=dl; configured.ConfigHash=repmat("original_config_a",3,1);
different=configured; different.ConfigHash(:)="original_config_b";
[s,~]=sixgr.report.summarizeChannelNMSEReport([configured;different],"DL");
assert(numel(unique(s.PopulationSeriesID))==2,'Do not infer equivalence of different original config hashes.');
different=dl; different.Layers(:)=2;
[s,~]=sixgr.report.summarizeChannelNMSEReport([dl;different],"DL"); assert(height(s)==2);
nominal=trs;
nominal.NMSEReferenceSource(:)="applied_identity_AWGN_operator_TRS_port_reference";
nominal.ChannelNMSEReferencePlane(:)="nominal_linear_TRS_port_response_with_executed_fading_loss_and_declared_TX_power";
nominal.ChannelNMSEReferenceIncludesRFImpairments(:)=0;
[s,~]=sixgr.report.summarizeChannelNMSEReport([trs;nominal],"TRS"); assert(height(s)==2);
piecewise=nominal;
piecewise.NMSEReferenceSource(:)="applied_piecewise_matrix_AWGN_operator_TRS_port_reference";
[s,o]=sixgr.report.summarizeChannelNMSEReport(piecewise,"TRS");
assert(height(s)==1 && all(o.MeasurementAvailable) && same(s.MeanNMSE_dB,meanDB));

% Bare numeric/PASS and pilot-fit/frequency-unmatched sources are excluded,
% not promoted or silently assigned the known producer's authority.
bare=table([-4;-2],["PASS";"PASS"],'VariableNames',{'NMSE_dB','Status'});
[s,o]=sixgr.report.summarizeChannelNMSEReport(bare,"UL");
assert(isempty(s) && height(o)==2 && ~any(o.MeasurementAvailable));
bad=dl; bad.NMSESource(:)="pilot_reconstruction_residual_not_independent_channel";
[s,o]=sixgr.report.summarizeChannelNMSEReport(bad,"DL"); assert(isempty(s)&&~any(o.MeasurementAvailable));
bad=dl; bad.ChannelEstimateReferencePlane(:)="pre_RX_oscillator_reference_with_receiver_correction_frequency_unmatched_diagnostic";
[s,~]=sixgr.report.summarizeChannelNMSEReport(bad,"DL"); assert(isempty(s));
bad=trs; bad.ChannelNMSEReferenceIncludesRFImpairments(:)=NaN;
[s,o]=sixgr.report.summarizeChannelNMSEReport(bad,"TRS"); assert(isempty(s)&&~any(o.MeasurementAvailable));
partial=csi; partial.ChannelNMSEConfiguredResourceCount(:)=2;
partial.ChannelNMSEAllResourcesMeasured(:)=false;
[s,o]=sixgr.report.summarizeChannelNMSEReport(partial,"CSI-RS");
assert(height(s)==1&&all(o.MeasurementAvailable)&&contains(s.PopulationJSON,'ChannelNMSEConfiguredResourceCount'));
bad=csi; bad.ChannelNMSEAllResourcesMeasured(:)=false;
reject(@()sixgr.report.summarizeChannelNMSEReport(bad,"CSI-RS"),'sixgr:report:NMSESupportCount');
bad=ul; bad.NMSEScoringAvailable(:)=0;
[s,~]=sixgr.report.summarizeChannelNMSEReport(bad,"UL"); assert(isempty(s));
bad=dl; bad=removevars(bad,'ChannelEstimateErrorEnergy');
[s,o]=sixgr.report.summarizeChannelNMSEReport(bad,"DL"); assert(isempty(s)&&~any(o.MeasurementAvailable));
bad=dl; bad.ChannelEstimateReferenceEnergy(1)=0;
reject(@()sixgr.report.summarizeChannelNMSEReport(bad,"DL"),'sixgr:report:NMSEEnergyContract');
bad=ul; bad.ChannelNMSEGainOrPhaseFitted(1)=1;
reject(@()sixgr.report.summarizeChannelNMSEReport(bad,"UL"),'sixgr:report:NMSEAuthorityConflict');
bad=dl; bad.ChannelEstimateGainOrPhaseFitted=[1;0;0];
reject(@()sixgr.report.summarizeChannelNMSEReport(bad,"DL"),'sixgr:report:NMSEAuthorityConflict');
bad=trs; bad.ChannelNMSEReferenceUsedByReceiver=[1;0;0];
reject(@()sixgr.report.summarizeChannelNMSEReport(bad,"TRS"),'sixgr:report:NMSEAuthorityConflict');
for signal=["DL","TRS","CSI-RS"]
    source=dl; if signal=="TRS", source=trs; elseif signal=="CSI-RS", source=csi; end
    for field=["ChannelNMSEGainFitted","ChannelNMSEPhaseAligned"]
        bad=source; bad.(field)=[1;0;NaN];
        reject(@()sixgr.report.summarizeChannelNMSEReport(bad,signal),'sixgr:report:NMSEAuthorityConflict');
        bad.(field)=[2;0;NaN];
        reject(@()sixgr.report.summarizeChannelNMSEReport(bad,signal),'sixgr:report:NMSEAuthorityValue');
    end
end
bad=ul; bad.ChannelEstimateComparedValues(1)=999;
reject(@()sixgr.report.summarizeChannelNMSEReport(bad,"UL"),'sixgr:report:NMSEAliasConflict');
bad=dl; bad.NMSE_dB(2)=-3;
reject(@()sixgr.report.summarizeChannelNMSEReport(bad,"DL"),'sixgr:report:NMSEEnergyClosure');
bad=dl; bad.NMSE_dB=[bad.NMSE_dB bad.NMSE_dB];
reject(@()sixgr.report.summarizeChannelNMSEReport(bad,"DL"),'sixgr:report:NMSEColumnShape');
bad=ul; bad.NMSEScoringAvailable=double(bad.NMSEScoringAvailable); bad.NMSEScoringAvailable(1)=2;
reject(@()sixgr.report.summarizeChannelNMSEReport(bad,"UL"),'sixgr:report:NMSEAuthorityValue');
text=dl; text.NMSE_dB=cellstr(string(text.NMSE_dB));
text.ChannelEstimateErrorEnergy=string(text.ChannelEstimateErrorEnergy);
[s,~]=sixgr.report.summarizeChannelNMSEReport(text,"DL"); assert(same(s.MeanNMSE_dB,meanDB));
inactive=dl; inactive.ChannelNMSEComparedComplexValues=zeros(3,1); inactive.NMSEScoringAvailable=false(3,1);
[s,~]=sixgr.report.summarizeChannelNMSEReport(inactive,"DL"); assert(same(s.MeanNMSE_dB,meanDB));
[s,o]=sixgr.report.summarizeChannelNMSEReport(table(),"TRS");
assert(isempty(s)&&isempty(o)&&isstring(s.ReferencePlane)&&islogical(o.MeasurementAvailable));

result=struct('Scope',"declared_report_contract_fixtures_no_PHY_no_archive_reaudit", ...
    'EvidenceRoot',"",'ExporterExercised',false,'PHYExecutions',0);
if runExporters
    root=fullfile(pwd,'results','validation','channel_nmse_reporting',char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
    assert(~isfolder(root),'Refuse to overwrite prior test evidence.');
    scfg=sixgr.lls6g.config.loadScenarioConfig('simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_0db.yaml');
    cfg=sixgr.lls6g.buildInternalConfig(scfg,root);
    % No executed lifecycle is manufactured for these declared row fixtures.
    cfg.run.runTag=''; cfg.run.executionID=''; cfg.meta.configHash='';
    layout=sixgr.report.resultLayout(root); sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
    % Exact-zero and close-but-distinct operating points reach the actual
    % publication entry points in the same bounded export, not only the helper.
    ulExport=[ul;zeroAt(ul,10)];
    trsExport=[trs;zeroAt(trs,10);zeroAt(trs,10+1e-10)];
    csiExport=[csi;zeroAt(csi,10);zeroAt(csi,10+1e-10)];
    csiExport.CQI=[3;3;3;7;11];
    inputs={dl,ulExport,trsExport,csiExport}; stems=["dl_pdsch_trials","ul_pusch_trials","trs_trials","csi_rs_trials"];
    signals=["DL","UL","TRS","CSI-RS"];
    hashes=strings(4,1);
    for k=1:4
        inputs{k}=exporterFixture(inputs{k},signals(k));
        file=fullfile(layout.AirInterfaceCSVDir,stems(k)+".csv");
        sixgr.util.csvWriteTable(file,inputs{k},'PreserveSchema',true,'RoundTripNumericText',true);
        hashes(k)=sixgr.util.sha256File(file);
    end
    live=sixgr.truth.exportLLSLiveDerivedTables(cfg,root, ...
        struct('DL',inputs{1},'UL',inputs{2},'TRS',inputs{3},'CSIRS',inputs{4}));
    assert(all(isnan(live.HARQ.TimelineTable.Frame)) && ...
        isequaln(live.HARQ.TimelineTable.CRCPass,[dl.CRCPass;ulExport.CRCPass]) && ...
        all(isnan(live.HARQ.TimelineTable.GoodBits)) && ...
        all(isnan(live.HARQ.TimelineTable.OfferedBits)), ...
        'Declared NMSE rows must not acquire executed frames or transport payloads.');
    C=live.ChannelEstimationStats; C=C(C.Metric=="NMSE_dB",:);
    ordinary=C(C.SNR_dB==0,:); zero=C(C.SNR_dB~=0,:);
    assert(height(C)==6 && height(ordinary)==3 && all(abs(ordinary.MeanValue-meanDB)<1e-12) && all(ordinary.SampleCount==3));
    assert(height(zero)==3 && all(zero.MeanValue==-Inf & zero.P05Value==-Inf & zero.P95Value==-Inf) && all(zero.SampleCount==1));
    F=live.CSIRSStats; F=F(ismember(F.TraceSource,["tracking_rs_path","csi_rs_runtime_trials"]),:);
    ordinary=F(F.SNR_dB==0,:); zero=F(F.SNR_dB~=0,:);
    assert(height(F)==6 && height(ordinary)==2 && all(abs(ordinary.MeanNMSE_dB-meanDB)<1e-12) && all(ordinary.NMSESampleCount==3));
    assert(height(zero)==4 && all(zero.MeanNMSE_dB==-Inf) && all(zero.NMSESampleCount==1) && all(zero.SampleCount==1));
    csiRows=zero(zero.TraceSource=="csi_rs_runtime_trials",:);
    assert(isequal(csiRows.SNR_dB,[10;10+1e-10]) && isequal(csiRows.MeanWidebandCQI,[7;11]), ...
        'Close distinct source operating points must not duplicate or mix practical feedback populations.');
    saved=sixgr.util.csvReadTable(live.ChannelNMSEPopulationSummaryPath,'TextType','string');
    assert(height(saved)==9 && nnz(saved.MeanNMSE_dB==-Inf)==5 && nnz(abs(saved.MeanNMSE_dB-meanDB)<1e-12)==4);
    manifest=struct('CodeVersion',"test",'CodeDetail',result.Scope,'RandomSeed',1, ...
        'GeneratedUTC',"test",'RunnerProfile',"test",'RunCompletion',"completed",'DeterministicMode',"test");
    report=sixgr.truth.exportLLSReportingBundle(root,scfg,cfg,struct('Ok',false),manifest, ...
        struct('StartedUTC',"test",'ElapsedSeconds',1),struct());
    for key=["ce_nmse","nmse","dmrs_estimation_quality"]
        expected="TRS"; if key=="dmrs_estimation_quality", expected="UL"; end
        rows=report.CategoryRows(report.CategoryRows.MetricKey==key & ...
            report.CategoryRows.Entity==expected,:);
        expectedGroups=3; if expected=="UL", expectedGroups=2; end
        assert(height(rows)==3+4*(expectedGroups-1) && all(rows.CountsTowardCoverage));
        assert(numel(unique(rows.PopulationID))==expectedGroups && all(strlength(rows.PopulationID)==64));
        assert(numel(unique(rows.PopulationSeriesID))==1 && all(strlength(rows.PopulationSeriesJSON)>0));
        means=rows(rows.Statistic=="mean",:);
        assert(height(means)==expectedGroups && nnz(abs(means.ValueNumeric-meanDB)<1e-12)==1 && nnz(means.ValueNumeric==-Inf)==expectedGroups-1);
        assert(all(string(rows.ValueText(rows.ValueNumeric==-Inf))=="-Inf"));
        assert(all(strlength(rows.PopulationJSON)>0 & strlength(rows.SupportConfigurationJSON)>0));
        assert(all(contains(rows.Notes,'equal_observation_mean_linear_normalized_error')));
    end
    audit=sixgr.util.csvReadTable(fullfile(layout.ReportCSVDir,'channel_nmse_source_audit.csv'),'TextType','string');
    assert(height(audit)==17 && all(audit.MeasurementAvailable) && ~any(audit.CountsTowardCoverage));
    persisted=sixgr.util.csvReadTable(fullfile(layout.ReportCSVDir,'lls_output_metric_rows.csv'),'TextType','string');
    nmseRows=persisted(strlength(string(persisted.PopulationID))==64,:);
    assert(any(nmseRows.ValueNumeric==-Inf) && all(string(nmseRows.ValueText(nmseRows.ValueNumeric==-Inf))=="-Inf"));
    for k=1:4
        assert(hashes(k)==string(sixgr.util.sha256File(fullfile(layout.AirInterfaceCSVDir,stems(k)+".csv"))));
    end
    result.ExporterExercised=true; result.EvidenceRoot=string(root);
end
ok=true;
fprintf('CHANNEL_NMSE_REPORTING_PASS declared_fixture=1 PHY_executions=0 exporter=%d root=%s\n', ...
    result.ExporterExercised,result.EvidenceRoot);
end

function T=zeroAt(source,snr)
T=source(1,:); T.ConfiguredSNR_dB=snr;
end

function T=exporterFixture(original,signal)
% The live exporter accepts raw receiver rows, not just NMSE operands.
% Its HARQ projection requires Frame/Slot; the local HARQ/user-summary
% schema owners handle the remaining optional fields as NaN/blank. These
% declared fixtures know only their original one-based Slot coordinates:
% there was no radio frame, crash, bit comparison or payload execution.
% Do not use full PHY normalization to populate configured antenna/allocation
% fields, since their presence could alter support/pooling eligibility.
T=original;
for name=["Frame","Crash","BitErrors","BitsCompared"]
    assert(~ismember(name,string(T.Properties.VariableNames)), ...
        'Do not overwrite an original producer field while completing this fixture.');
    T.(name)=nan(height(T),1);
end
T.SlotIndexBase=ones(height(T),1);
T.FixtureCoordinateSource=repmat( ...
    "declared_one_based_slot_frame_and_transport_execution_unavailable",height(T),1);
assert(isequaln(T(:,original.Properties.VariableNames),original), ...
    'Exporter schema completion must preserve every original value and authority field.');
[before,beforeRows]=sixgr.report.summarizeChannelNMSEReport(original,signal);
[after,afterRows]=sixgr.report.summarizeChannelNMSEReport(T,signal);
assert(isequaln(before,after) && ...
    isequaln(removevars(beforeRows,'ObservationIdentityJSON'), ...
    removevars(afterRows,'ObservationIdentityJSON')), ...
    'Unavailable reporting metadata must not change NMSE/reference/population/series/support semantics.');
end

function T=base()
T=table([-Inf;-10;0],[0;0;1],["PASS";"FAIL";"PASS"],zeros(3,1), ...
    ones(3,1),repmat(7,3,1),ones(3,1),(1:3).', ...
    'VariableNames',{'NMSE_dB','CRCPass','Status','ConfiguredSNR_dB','UEIndex','RandomSeed','Layers','Slot'});
T.FixtureScope=repmat("declared_producer_contract_not_executed_PHY",3,1);
end

function T=dataFixture(signal,shared)
T=base(); channel="PDSCH"; if signal=="UL", channel="PUSCH"; end
T.Direction=repmat(signal,3,1);
T.NMSESource=repmat("same_executed_desired_link_waveform_post_decode_"+channel+"_DMRS_LS",3,1);
T.ChannelEstimateReferencePlane=repmat("effective_"+channel+"_layer_channel_on_recorded_RX_clock_with_executed_RX_CFO_and_received_correction_before_other_RX_RF",3,1);
T.ChannelEstimateCaptureStatus=repmat("measured_and_independently_scored_after_reception",3,1);
T.ChannelEstimateReferenceUsedByReceiver=false(3,1);
T.ChannelEstimateReferenceRFImpairmentsIncluded=true(3,1);
T.ChannelEstimateComparedValues=repmat(40,3,1);
ids="isolated_hest_"+string(repmat('a',3,64));
ids(2)="isolated_hest_"+string(repmat('b',1,64)); ids(3)="isolated_hest_"+string(repmat('c',1,64));
T.ChannelEstimateObservationID=ids;
if shared
    T.ChannelObservationID="shared_fixture_"+string((1:3).');
    T.ChannelEstimateObservationID=T.ChannelObservationID;
    T.NMSEScoringAvailable=true(3,1);
    T.ChannelNMSEGainOrPhaseFitted=false(3,1); T.ChannelNMSEReferenceUsedByReceiver=false(3,1);
    T.ChannelNMSEErrorEnergy=[0;1;100]; T.ChannelNMSEReferenceEnergy=[1;10;100];
    T.ChannelNMSEComparedComplexValues=repmat(40,3,1); T.ChannelNMSEPilotResourceCount=repmat(20,3,1);
    T.ChannelNMSEReferencePlane=T.ChannelEstimateReferencePlane;
else
    T.ChannelEstimateErrorEnergy=[0;1;100]; T.ChannelEstimateReferenceEnergy=[1;10;100];
end
end

function T=trsFixture()
T=base(); T.NMSEScoringAvailable=true(3,1);
T.NMSEReferenceSource=repmat("same_executed_desired_link_waveform_post_decode_TRS_pilot_ratio",3,1);
T.ChannelNMSEQualificationMode=repmat("independent_complex_pilot_resources_no_gain_or_phase_fit",3,1);
T.ChannelNMSEReferencePlane=repmat("effective_TRS_port_channel_on_recorded_RX_timing_clock_with_executed_RX_CFO_and_received_frequency_correction_before_other_RX_RF",3,1);
T.ChannelNMSEReferenceIncludesRFImpairments=ones(3,1);
T.ChannelNMSEErrorEnergy=[0;1;100]; T.ChannelNMSEReferenceEnergy=[1;10;100];
T.ChannelNMSEComparedComplexValues=repmat(40,3,1); T.ChannelNMSEPilotResourceCount=repmat(20,3,1);
end

function T=csirsFixture()
T=trsFixture(); T=removevars(T,'NMSEReferenceSource');
T.ChannelNMSESource=repmat("executed_channel_coefficients_and_actual_resource_precoders_after_CSI_selection",3,1);
T.ChannelNMSEQualificationMode(:)="same_execution_nominal_linear_channel_no_gain_or_phase_fit";
T.ChannelNMSEReferencePlane(:)="nominal_linear_CSI_RS_port_channel_on_actual_RX_FFT_clock";
T.ChannelNMSEReferenceIncludesRFImpairments(:)=0;
T.ChannelNMSEGainOrPhaseFitted=false(3,1); T.ChannelNMSEReferenceUsedByReceiver=false(3,1);
T.ChannelNMSEScope=repmat("all_available_received_CSI_RS_resources_and_all_pilot_ports_RX_branches",3,1);
T.ChannelNMSEMeasuredResourceCount=ones(3,1); T.ChannelNMSEConfiguredResourceCount=ones(3,1);
T.ChannelNMSEAllResourcesMeasured=true(3,1);
end

function yes=same(a,b)
yes=isscalar(a)&&(isequaln(a,b)||(isfinite(a)&&isfinite(b)&&abs(a-b)<1e-12));
end

function reject(fn,id)
try, fn(); catch cause
    if ~strcmp(cause.identifier,id), rethrow(cause); end
    return;
end
error('testChannelNMSEReportingIntegrity:ExpectedRejection','Expected %s.',id);
end
