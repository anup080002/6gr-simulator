function ok=testLinkTrialReceiverStageAuthority()
% Declared receiver-row contract regression: no waveform or decoder runs.
% The stopped row follows PUSCH_Rx.localBuildUnavailableNoiseVarianceRx:
% Hest may exist, but extraction/equalization/UL-SCH decoding did not run.
% runULPUSCHThroughput retains the transmitted TB size on this NA outcome.
% Finite allocation/diagnostic values cannot override explicit stage flags.
% Incomplete primary rows and unattempted TB decoding are not coverage.
setup6GRSimToolkit('Verbose',false);
cfg=sixgr.config.defaultConfig();
cfg.channel.model='AWGN'; cfg.channel.awgnOnly=true;
stageFields=["ReceiverUsable","DecodeAttempted","DecodeUsable", ...
    "ChannelEstimateAttempted","ChannelEstimateAvailable", ...
    "ResourceExtractionAttempted","ResourceExtractionAvailable", ...
    "EqualizationAttempted","EqualizationAvailable", ...
    "DLSCHDecodeAttempted","DLSCHDecodeAvailable", ...
    "ULSCHDecodeAttempted","ULSCHDecodeAvailable","LLRAvailable","LLRFinite", ...
    "DetectionAttempted","DetectionUsable","MeasurementAttempted","MeasurementUsable"];
preserved=[stageFields,"CRCApplicable","CRCPass","TBSize_bits", ...
    "NoiseVarStrictFailure","NoiseVariance","FailureReason","Status","Crash"];
changed=strings(0,1);
count=0;
for direction=["DL","UL"]
    rows=localDeclaredCases(direction,stageFields,cfg);
    for k=1:numel(rows)
        row=struct2table(rows{k},'AsArray',true);
        beforeRNG=rng;
        out=sixgr.truth.SharedDataCompletionRuntime.ensureLinkTrialTable(row,direction,40,cfg);
        assert(isequal(rng,beforeRNG),'test:RowAdapterExecutedRandomness', ...
            'Row finalization must not execute a new channel or receiver realization.');
        assert(height(out)==height(row),'test:RowAdapterManufacturedTrial', ...
            'Normalization must retain the original trial population.');
        for field=preserved
            if ~isequaln(out.(field),row.(field))
                changed(end+1,1)=direction+"/"+row.TestCase+"/"+field; %#ok<AGROW>
            end
        end
        for field=["RuntimeMaterializationStatus","RuntimeEvidenceSource"]
            supplied=ismember(field,string(row.Properties.VariableNames));
            retained=ismember(field,string(out.Properties.VariableNames));
            if supplied
                if ~retained || ~isequaln(out.(field),row.(field))
                    changed(end+1,1)=direction+"/"+row.TestCase+"/"+field; %#ok<AGROW>
                end
            elseif retained && any(strlength(strtrim(string(out.(field))))>0)
                changed(end+1,1)=direction+"/"+row.TestCase+"/invented_"+field; %#ok<AGROW>
            end
        end
        assert(all(ismember({'CountsTowardCoverage','PartialRowFlag','FinalizedFlag'}, ...
            out.Properties.VariableNames)), 'test:MissingRowCoverageEvidence', ...
            'Finalized trial rows must retain explicit lifecycle and coverage evidence.');
        schAttempted=row.DLSCHDecodeAttempted || row.ULSCHDecodeAttempted;
        noCoverage=out.PartialRowFlag || ~out.FinalizedFlag || ...
            row.Status=="NA" || ~row.DecodeAttempted || ~schAttempted;
        if noCoverage && out.CountsTowardCoverage
            changed(end+1,1)=direction+"/"+row.TestCase+"/CountsTowardCoverage"; %#ok<AGROW>
        end
        if row.TestCompletePrimary && (~out.FinalizedFlag || out.PartialRowFlag || ~out.CountsTowardCoverage)
            changed(end+1,1)=direction+"/"+row.TestCase+"/complete_decode_not_counted"; %#ok<AGROW>
        end
        % Only the separately declared complete cases assert coverage true.
        % A finite CRC alone cannot qualify the incomplete CRC0/CRC1 cases.
        count=count+1;
    end
end
assert(isempty(changed),'test:ReceiverStageAuthorityOverwritten', ...
    'Explicit receiver evidence changed during table normalization: %s', ...
    char(strjoin(changed,', ')));
fprintf('LINK_TRIAL_RECEIVER_STAGE_AUTHORITY_PASS cases=%d DL_UL=1 no_new_CRC_or_TBS=1 partial_coverage_excluded=1 complete_CRC0_CRC1_counted=1 provenance_preserved=1 physical_qualification=0\n',count);
ok=true;
end

function rows=localDeclaredCases(direction,stageFields,cfg)
base=struct('Direction',direction,'Frame',2,'Slot',17,'Seed',43, ...
    'Status',"NA",'Crash',false,'TBSize_bits',1024,'CRCPass',NaN, ...
    'CRCApplicable',false,'NoiseVariance',NaN,'NoiseVarStrictFailure',true, ...
    'FailureReason',"declared_noise_variance_unavailable", ...
    'TestCase',"stopped_before_noise_gate",'TestCompletePrimary',false);
for field=stageFields, base.(field)=false; end
base.ChannelEstimateAttempted=true;
base.ChannelEstimateAvailable=true;

% Partial reception may expose measured symbols and UCI evidence without a
% usable transport-block decision. Preserve both true and false stages.
partial=base;
partial.TestCase="partial_receiver_no_usable_TB";
partial.NoiseVarStrictFailure=false;
partial.NoiseVariance=0.125;
partial.FailureReason="declared_TB_mapping_unresolved";
partial.ReceiverUsable=true;
partial.DecodeAttempted=true;
partial.ResourceExtractionAttempted=true;
partial.ResourceExtractionAvailable=true;
partial.EqualizationAttempted=true;
partial.EqualizationAvailable=true;
partial.LLRAvailable=true;
partial.LLRFinite=true;
partial.DetectionAttempted=true;
partial.DetectionUsable=true;
partial.MeasurementAttempted=true;
partial.MeasurementUsable=true;
partial.EVM_rms=0.03;
partial.RuntimeMaterializationStatus="";
partial.RuntimeEvidenceSource="";

% CRC failure is an actual attempted decode, not an unavailable stage.
failed=partial;
failed.TestCase="attempted_TB_CRC_failure";
failed.Status="FAIL";
failed.FailureReason="declared_TB_CRC_failure";
failed.DecodeUsable=true;
failed.CRCApplicable=true;
failed.CRCPass=0;
failed.BitErrors=1;
failed.BitsCompared=1024;
failed.DecoderIterations=2;
% These are supplied producer tokens in a declared fixture, not a claim
% that this test executes the waveform owner named by the tokens.
if direction=="DL"
    failed.RuntimeMaterializationStatus="active_waveform_pdsch_runtime";
else
    failed.RuntimeMaterializationStatus="active_waveform_pusch_runtime";
end
failed.RuntimeEvidenceSource="sixgr.truth.runWaveformLinkBundle";
if direction=="DL"
    failed.DLSCHDecodeAttempted=true; failed.DLSCHDecodeAvailable=true;
else
    failed.ULSCHDecodeAttempted=true; failed.ULSCHDecodeAvailable=true;
end
passed=failed;
passed.TestCase="attempted_TB_CRC_success";
passed.Status="PASS"; passed.FailureReason="";
passed.CRCPass=1; passed.BitErrors=0;

% Primary-field-complete declared records exercise positive decode coverage,
% including CRC failure. Allocation fields are fixture inputs, not outputs
% of a waveform/TBS calculation. Goodput follows the declared decoded bits
% over one configured slot, and is zero for the failed transport block.
completeFailed=failed;
completeFailed.TestCase="complete_declared_TB_CRC_failure";
completeFailed.TestCompletePrimary=true;
completeFailed.AllocatedPRBCount=6;
completeFailed.PRBStart=0;
completeFailed.MCSIndex=0;
completeFailed.Modulation="QPSK";
completeFailed.TargetCodeRate=120/1024;
completeFailed.GoodBits=0;
completeFailed.Goodput_Mbps=0;
completeFailed.IsWarmupFrame=false;
completePassed=completeFailed;
completePassed.TestCase="complete_declared_TB_CRC_success";
completePassed.Status="PASS"; completePassed.FailureReason="";
completePassed.CRCPass=1; completePassed.BitErrors=0;
completePassed.GoodBits=completePassed.BitsCompared;
completePassed.Goodput_Mbps=completePassed.GoodBits/sixgr.time.slotDurationSec(cfg)/1e6;

% Deliberately unqualified numerical metadata cannot manufacture detection,
% measurement usability or a receiver decision against explicit false flags.
metadata=base;
metadata.TestCase="unqualified_numeric_metadata";
metadata.ReceiverHestSINR_dB=8;
metadata.ReceiverHestSINRSource="declared_negative_fixture_not_receiver_evidence";
metadata.MeasuredTrialSINR_dB=7;
metadata.MeasuredTrialSINRSource="declared_negative_fixture_not_receiver_evidence";
metadata.NoiseVariance=0.25;
metadata.EVM_rms=0.1;
metadata.WidebandCQI=10;
metadata.ChannelGain_dB=-5;
metadata.ConditionNumber_dB=3;
rows={base,partial,failed,passed,metadata,completeFailed,completePassed};
end
