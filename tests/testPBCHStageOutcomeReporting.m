function [ok,result]=testPBCHStageOutcomeReporting()
% Declared stage outcomes through the REAL CSV reader/public report writer.
% No PHY execution, empirical detection qualification or independent trials.
setup6GRSimToolkit('Verbose',false);
folder=fullfile(pwd,'results','validation','pbch_stage_outcome_reporting', ...
    char(datetime('now','Format','yyyyMMdd_HHmmss_SSS')));
assert(~isfolder(folder),'Never replace retained evidence.');
layout=sixgr.report.resultLayout(folder);
sixgr.util.ensureFolder(layout.AirInterfaceCSVDir);
scfg=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_5mhz_rank2_4tx2rx_awgn_0db.yaml');
data=scfg.toStruct(); data.output.artifact_contract_engine.enabled=false;
scfg=sixgr.lls6g.config.ScenarioConfig(data);
cfg=sixgr.lls6g.buildInternalConfig(scfg,folder);
template=sixgr.truth.makeLinkTrialRow(cfg,"DL",0,1);
assert(islogical(template.PBCHStrictReceiverEvidenceOk) && ...
    isscalar(template.PBCHStrictReceiverEvidenceOk) && ~template.PBCHStrictReceiverEvidenceOk);
% The ordinary collector preallocates an array of this exact schema.
sameSchema=repmat(template,2,1); completed=template;
completed.PBCHStrictReceiverEvidenceOk=true; sameSchema(2)=completed;
assert(~sameSchema(1).PBCHStrictReceiverEvidenceOk && sameSchema(2).PBCHStrictReceiverEvidenceOk);

n=257;
source=table((1:n).',repmat("PASS",n,1),zeros(n,1), ...
    'VariableNames',{'Slot','Status','Crash'});
flags=["DetectionAttempted","PSSDetected","SSSDetected","NCellIDRecovered", ...
    "DecodeAttempted","BCHCRCValid","BCHCrcPass","CRCPass","MIBDecoded", ...
    "CandidateIdentityConsistent","SSBIdentityVerified","PBCHStrictReceiverEvidenceOk", ...
    "PSSDetectionDecisionAvailable","SSSDetectionDecisionAvailable", ...
    "PSSDetectionMetricValid","SSSDetectionMetricValid"];
for field=flags, source.(field)=nan(n,1); end
for field=["PSSNormalizedMetric","SSSNormalizedMetric","PSSDetectionThreshold", ...
        "SSSDetectionThreshold","PSSDetectionHypothesisCount","SSSDetectionHypothesisCount", ...
        "BCHTransportBlockNumBits"]
    source.(field)=nan(n,1);
end
source.BCHTransportBlockHash=strings(n,1);
source.DetectionMetricSource=strings(n,1);
source.KSSBContractVersion=strings(n,1);
source.DecodedKSSB=nan(n,1); source.MIBKSSBSubcarrierOffset=nan(n,1);
source.MIBKSSBLow4=nan(n,1); source.PBCHKSSBMSB=nan(n,1);
source.PBCHKSSBHighContribution=nan(n,1); source.KSSBHighBitApplicable=nan(n,1);
source.k_SSB=nan(n,1); source.Lmax=nan(n,1);
source.ReceiverID=repmat("declared_receiver",n,1);
source.ObservationStartSample=(0:n-1).'*100;
source.ObservationEndSampleExclusive=source.ObservationStartSample+100;
source.ObservationSampleRateHz=repmat(1e6,n,1);
source.SourceClassification=repmat("declared_stage_metadata_not_PHY",n,1);
for k=[1:4 11 12 257]
    for field=flags, source.(field)(k)=1; end
    source.PSSNormalizedMetric(k)=0.75; source.SSSNormalizedMetric(k)=0.75;
    source.PSSDetectionThreshold(k)=0.5; source.SSSDetectionThreshold(k)=0.5;
    source.PSSDetectionHypothesisCount(k)=3; source.SSSDetectionHypothesisCount(k)=336;
    source.DetectionMetricSource(k)="SSS:normalized_correlation_independent_branch_gamma_bound";
end
for k=1:4
    source.BCHTransportBlockNumBits(k)=24;
    source.BCHTransportBlockHash(k)=string(sixgr.util.sha256Hex(sprintf('declared_block_%d',k)));
    source.KSSBContractVersion(k)="sixgr_decoded_kssb/v2";
    source.Lmax(k)=8; source.MIBKSSBLow4(k)=0; source.PBCHKSSBMSB(k)=1;
    source.PBCHKSSBHighContribution(k)=16; source.KSSBHighBitApplicable(k)=1;
    source.DecodedKSSB(k)=16; source.MIBKSSBSubcarrierOffset(k)=16; source.k_SSB(k)=16;
end
% Real stage semantics declared here: SI fails AFTER original successful BCH.
source.Status(1)="FAIL"; source.Status(2)="CRASH"; source.Crash(2)=1;
% Raw CRC success does not prove accepted MIB identity.
source.CandidateIdentityConsistent(3)=0; source.MIBDecoded(3)=0;
source.BCHCRCValid(4)=0; source.BCHCrcPass(4)=0; source.CRCPass(4)=0;
source.MIBDecoded(4)=0; source.CandidateIdentityConsistent(4)=0;
source.PBCHStrictReceiverEvidenceOk(4)=0;
% Original terminal PSS miss (no SSS execution) and terminal SSS miss.
for k=5:7
    source.DetectionAttempted(k)=1; source.PSSDetectionDecisionAvailable(k)=1;
    source.PSSDetectionMetricValid(k)=1; source.PSSDetectionThreshold(k)=0.5;
    source.PSSDetectionHypothesisCount(k)=3; source.PSSNormalizedMetric(k)=0.75;
    source.PSSDetected(k)=1; source.NCellIDRecovered(k)=0;
end
source.PSSDetected(5)=0; source.PSSNormalizedMetric(5)=0.25;
source.DetectionMetricSource(5)="PSS:normalized_correlation_independent_branch_gamma_bound";
source.SSSDetectionDecisionAvailable(6)=1; source.SSSDetectionMetricValid(6)=1;
source.SSSDetected(6)=0; source.SSSNormalizedMetric(6)=0.25;
source.SSSDetectionThreshold(6)=0.5; source.SSSDetectionHypothesisCount(6)=336;
source.DetectionMetricSource(6)="SSS:normalized_correlation_independent_branch_gamma_bound";
% Row7 has no terminal SSS decision: exclude, do not invent a missed trial.
source.DecodeAttempted(8)=1; source.BCHCRCValid(8)=0; % No returned block.
source.NCellIDRecovered(11)=0; % Detection does not imply PCI recovery.
source.PSSDetected(12)=2; % Malformed flag, never logical(2)==true.
source.PSSNormalizedMetric(257)=0.25; % Contradicts original positive decision.
source.BCHTransportBlockNumBits(257)=24;
source.BCHTransportBlockHash(257)="not_a_returned_block_hash";
original=source;
path=fullfile(layout.AirInterfaceCSVDir,'pbch_trials.csv');
sixgr.util.csvWriteTable(path,source,'PreserveSchema',true,'RoundTripNumericText',true);
digest=string(sixgr.util.sha256File(path));
readback=sixgr.util.csvReadTable(path,'TextType','string');
localPublicChecks(readback);
manifest=struct('CodeVersion',"test",'CodeDetail',"declared_metadata_no_PHY", ...
    'RandomSeed',1,'GeneratedUTC',"test",'RunnerProfile',"test", ...
    'RunCompletion',"completed",'DeterministicMode',"test");
out=sixgr.truth.exportLLSReportingBundle(folder,scfg,cfg,struct('Ok',false),manifest, ...
    struct('StartedUTC',"test",'ElapsedSeconds',1),struct());
for rows={out.CategoryRows,sixgr.util.csvReadTable(out.DetailCSV,'TextType','string')}
    localCheckMetric(rows{1},"one_shot_ssb_detection_probability",5,7,[1:6 11],[1:4 11],digest);
    localCheckMetric(rows{1},"cell_id_detection_success",4,7,[1:6 11],1:4,digest);
    localCheckMetric(rows{1},"pbch_decode_success",3,4,1:4,1:3,digest);
    selected=rows{1}; selected=selected(selected.MetricKey=="pbch_decode_success",:);
    assert(selected.ValueNumeric(selected.Statistic=="accepted_mib_count")==2);
    assert(selected.ValueNumeric(selected.Statistic=="accepted_mib_evaluable_attempt_count")==4);
end
assert(isequaln(source,original) && digest==string(sixgr.util.sha256File(path)), ...
    'Original rows/bytes/Status/CRC must remain unchanged.');
result=struct('EvidenceRoot',string(folder),'OriginalSourceSHA256',digest, ...
    'SourceRows',n,'Scope',"declared_stage_operands_to_real_CSV_and_public_reporting", ...
    'PHYExecutions',0,'StatisticallyQualified',false);
ok=true;
fprintf('PBCH_STAGE_OUTCOME_REPORTING_PASS original_rows=257 writer_calls=1 PHY_calls=0 root=%s\n',folder);
end

function localPublicChecks(source)
contract=struct('Outputs',table(),'Metrics',table());
meta=struct('logical_run_id',"declared_pbch_stage_projection",'run_id',1);
tables=sixgr.truth.buildLLSPublicOutputTables(struct('ssb_pbch_table',source),contract,meta);
pub=tables.ssb_pbch_cell_search_table;
for field=["Status","Crash","CRCPass","BCHCRCValid","BCHCrcPass","MIBDecoded", ...
        "CandidateIdentityConsistent","SSBIdentityVerified","PBCHStrictReceiverEvidenceOk", ...
        "KSSBContractVersion","Lmax","DecodedKSSB","MIBKSSBSubcarrierOffset", ...
        "MIBKSSBLow4","PBCHKSSBMSB","PBCHKSSBHighContribution", ...
        "KSSBHighBitApplicable","k_SSB","NCellIDRecovered","PSSDetected", ...
        "PSSDetectionDecisionAvailable","PSSNormalizedMetric","BCHTransportBlockHash"]
    assert(isequaln(pub.(field),source.(field)),'Changed original %s.',field);
end
assert(all(pub.MIBAcquisitionAccepted(1:2)) && ~any(pub.MIBAcquisitionAccepted(3:4)));
assert(all(pub.MIBAcquisitionEvidenceComplete(1:4)) && ...
    ~pub.MIBAcquisitionEvidenceComplete(9));
assert(~pub.MIBRecovered(9) && pub.PBCHCRC(9)=="unavailable", ...
    'NaN original flags cannot become a successful MIB/CRC by logical casting.');
assert(pub.PBCHCRC(3)=="pass" && ~pub.MIBAcquisitionAccepted(3));
legacy=table("PASS",1,'VariableNames',{'Status','CRCPass'});
tables=sixgr.truth.buildLLSPublicOutputTables(struct('ssb_pbch_table',legacy),contract,meta);
pub=tables.ssb_pbch_cell_search_table;
assert(~pub.MIBAcquisitionAccepted && ~pub.MIBAcquisitionEvidenceComplete && ...
    ~pub.MIBRecovered && pub.PBCHCRC=="unavailable" && ...
    ~ismember('PBCHStrictReceiverEvidenceOk',pub.Properties.VariableNames) && ...
    ~ismember('BCHCRCValid',pub.Properties.VariableNames));
end

function localCheckMetric(rows,key,numerator,denominator,included,success,digest)
rows=rows(rows.MetricKey==key,:);
rate=rows(rows.Statistic=="rate",:);
% The public writer normalizes available air-interface evidence to observed.
% This is its availability vocabulary, not a PHY claim for this fixture.
assert(height(rate)==1 && rate.Availability=="observed" && ...
    abs(rate.ValueNumeric-numerator/denominator)<1e-12);
assert(rows.ValueNumeric(rows.Statistic=="count")==numerator && ...
    rows.ValueNumeric(rows.Statistic=="attempt_count")==denominator && ...
    rows.ValueNumeric(rows.Statistic=="excluded_row_count")==257-denominator);
p=jsondecode(char(rate.PopulationJSON));
assert(string(p.SourceSHA256)==digest && p.SourceRowCount==257 && ...
    isequal(p.IncludedSourceRows(:),double(included(:))) && ...
    isequal(p.SuccessSourceRows(:),double(success(:))) && ...
    ismember(257,p.ExcludedSourceRows) && ismember(9,p.ExcludedSourceRows) && ...
    ~p.StatisticallyQualified && ~p.StandardizedAccuracyQualified);
assert(string(sixgr.util.sha256Hex(char(rate.PopulationJSON)))==rate.PopulationID);
operands=jsondecode(p.OriginalOperandsJSON);
assert(string(operands.Status{1})=="FAIL" && string(operands.Status{2})=="CRASH");
assert(contains(rate.Notes,"Status is unchanged") && contains(rate.Notes,"No independent-trial"));
end
