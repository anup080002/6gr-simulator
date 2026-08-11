function result = runPuschResidualGrid(scenario,runDirectory)
%RUNPUSCHRESIDUALGRID Execute residual points through production PUSCH PHY.

[base,~]=sixgr.lls.loadConfig(string(scenario.physical_layer.pusch_config));
timing=double(scenario.residual_grid.timing_error_us(:))*1e-6;
frequency=double(scenario.residual_grid.frequency_error_khz(:))*1e3;
snr=double(scenario.physical_layer.residual_snr_db(:));
minTB=double(scenario.physical_layer.bler_blocks_min);
minErrors=double(scenario.physical_layer.block_errors_target);
maxTB=double(scenario.physical_layer.blocks_max);
folder=fullfile(char(runDirectory),'raw','campaign_d_pusch');
if exist(folder,'dir')~=7,mkdir(folder);end
summaryParts=cell(numel(timing)*numel(frequency)*numel(snr),1);
indexRows=cell(size(summaryParts));index=0;
for ti=1:numel(timing)
    for fi=1:numel(frequency)
        cfg=base;
        cfg.synchronizationResidual.enabled=true;
        cfg.synchronizationResidual.timingErrorSeconds=timing(ti);
        cfg.synchronizationResidual.frequencyErrorHz=frequency(fi);
        cfg.synchronizationResidual.source='ntn_resilient_sync_master_yaml_residual_grid';
        cfg.synchronizationResidual.receiverUsesOracle=false;
        cfg.simulation.snrDb=snr(:).';
        cfg.simulation.minTransportBlocks=minTB;
        cfg.simulation.minBlockErrors=minErrors;
        cfg.simulation.maxTransportBlocks=maxTB;
        if string(scenario.run_mode)=="quick"
            cfg.simulation.statisticalClass='diagnostic_only';
        else
            cfg.simulation.statisticalClass='publication_candidate';
        end
        cfg.scenario.id=sprintf('ntn_resilient_pusch_t%gus_f%gkhz',timing(ti)*1e6,frequency(fi)/1e3);
        cfg=sixgr.lls.validateConfig(cfg,"ConfigPath",scenario.ConfigPath);
        configHash=sixgr.util.sha256Hex(unicode2native(jsonencode(cfg),'UTF-8'));
        for si=1:numel(snr)
            index=index+1;
            [summary,trials]=sixgr.lls.runSNRPoint(cfg,configHash,si);
            summary.ResidualTimingError_s=timing(ti);
            summary.ResidualFrequencyError_Hz=frequency(fi);
            summary.Provenance="CALIBRATED_LLS";
            summaryParts{index}=summary;
            file=sprintf('pusch_t%+gus_f%+gkhz_snr%+gdb.csv', ...
                timing(ti)*1e6,frequency(fi)/1e3,snr(si));
            file=regexprep(file,'[^A-Za-z0-9_.-]','_');
            path=fullfile(folder,file);
            writetable(trials,path);
            indexRows{index}={replace(string(path),string(runDirectory)+filesep,""),height(trials), ...
                sum(trials.CRCError),localFileHash(path), ...
                timing(ti),frequency(fi),snr(si),"CALIBRATED_LLS"};
        end
    end
end
summaryTable=struct2table(vertcat(summaryParts{:}));
summaryTable.Properties.VariableUnits=repmat({''},1,width(summaryTable));
summaryTable.Properties.VariableUnits{strcmp(summaryTable.Properties.VariableNames,'ResidualTimingError_s')}='s';
summaryTable.Properties.VariableUnits{strcmp(summaryTable.Properties.VariableNames,'ResidualFrequencyError_Hz')}='Hz';
fileIndex=cell2table(vertcat(indexRows{:}),'VariableNames', ...
    {'RelativePath','Rows','BlockErrors','SHA256','ResidualTimingError_s', ...
    'ResidualFrequencyError_Hz','SNR_dB','Provenance'});
fileIndex.Properties.VariableUnits={'','','','','s','Hz','dB',''};
tables=struct('pusch_residual_summary',summaryTable,'pusch_trial_file_index',fileIndex);
evidence=table(["pusch_residual_summary";"pusch_trial_file_index"], ...
    repmat("CALIBRATED_LLS",2,1),true(2,1),repmat("PRODUCED",2,1), ...
    'VariableNames',{'Artifact','EvidenceClass','Measured','Status'});
result=struct('Status','COMPLETE','Tables',tables,'Evidence',evidence);
end

function digest=localFileHash(path)
fid=fopen(path,'rb');
if fid<0,error('sixgr:ntn:resilientsync:ArtifactReadFailed','Cannot hash %s.',path);end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
digest=sixgr.util.sha256Hex(fread(fid,Inf,'*uint8'));
end
