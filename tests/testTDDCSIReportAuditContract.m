function ok=testTDDCSIReportAuditContract()
% Validate the actual TDD audit policy using explicitly artificial unit rows.
% Does not alter or requalify historical run artifacts.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
s=sixgr.lls6g.config.readConfigFile( ...
    'simulator/configs/scenarios/lls_causal_access_to_data_wiring_tdd.yaml');
allStages=s.validation.causal_phy_chain_audit.stages;
stages=cell(1,2); ids=["csi_rs_measurement","csi_feedback_cqi_ri_pmi_cri"];
for k=1:numel(allStages)
    if iscell(allStages), item=allStages{k}; else, item=allStages(k); end
    index=find(ids==string(item.stage_id));
    if isempty(index), continue; end
    item.always_required=true;
    item=rmfield(item,'feature_authority');
    item.consumer_source_files="tests/testTDDCSIReportAuditContract.m";
    if index==1, item.dependency_stages={}; end
    stages{index}=item;
end
assert(all(~cellfun(@isempty,stages)));
folder=tempname; mkdir(folder);
cleanup=onCleanup(@()rmdir(folder,'s')); %#ok<NASGU>
mkdir(fullfile(folder,'reports','csv'));
mkdir(fullfile(folder,'air_interface','csv'));
mkdir(fullfile(folder,'control','csv'));
profile=table(string(mfilename('fullpath')+".m"),1,0, ...
    'VariableNames',{'FileName','NumCalls','TotalTime_s'});
sixgr.util.csvWriteTable(fullfile(folder,'reports','csv','runtime_function_profile.csv'),profile);
measured=table(true,true,true,true,true,17,18,"runtime_measured_csi_complete", ...
    'VariableNames',{'Scheduled','Transmitted','Observed','Consumed', ...
    'ChannelEstimateAvailable','ReferenceMeasuredSINR_dB','SINR_dB','CSIComputationStatus'});
received=table(12,1,3,0,"unit_report",40,7,true,NaN, ...
    'VariableNames',{'CQI','RI','PMI','CRI','ReportIdentity','DeliveredSlot', ...
    'CSIUCIDecodedBitCount','CSIUCIDecodeOk','SINR_dB'});
writeRows();
audit=struct('enabled',true,'required',true,'fail_on_enabled_bypass',true, ...
    'require_config_mapping_match',true,'require_runtime_consumer',true, ...
    'require_measurement_evidence',true,'stages',{stages},'parameter_bindings',struct([]));
cfg=struct('validation',struct('causal_phy_chain_audit',audit));
out=check(); assert(out.Ok,'Decoded CSI must not require an unreported SINR field.');
received.CSIUCIDecodeOk=false; writeRows();
out=check(); assert(~out.Ok && out.DetailTable.StageOutcome(2)=="FAILED_MEASUREMENT");
received.CSIUCIDecodeOk=true; measured.SINR_dB=NaN; writeRows();
out=check(); assert(~out.Ok && out.DetailTable.StageOutcome(1)=="CALLED_NO_MEASUREMENT" && ...
    out.DetailTable.StageOutcome(2)=="BLOCKED_BY_DEPENDENCY");
ok=true; fprintf('TDD_CSI_REPORT_AUDIT_CONTRACT_PASS received_fields_and_source_SINR_separate=1 integrated_run=0\n');

    function writeRows()
        sixgr.util.csvWriteTable(fullfile(folder,'air_interface','csv','csi_rs_trials.csv'),measured,'PreserveSchema',true);
        sixgr.util.csvWriteTable(fullfile(folder,'control','csv','csi_feedback_reports.csv'),received,'PreserveSchema',true);
    end
    function out=check()
        out=sixgr.truth.exportCausalPHYChainAudit(folder,cfg,cfg, ...
            'RunId','explicit_unit_fixture','WriteArtifacts',false);
    end
end
