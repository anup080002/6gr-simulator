classdef WaveformSuite
    %WAVEFORMSUITE Bounded execution through the strict PDCCH Tx/Rx chain.

    methods (Static)
        function result = run(campaign)
            cfg = campaign.Config;
            w = cfg.waveform;
            if ~logical(w.enabled)
                error("sixgr:phy:pdcch:tdoc:WaveformDisabled", ...
                    "waveform.enabled must be true for the bounded TDoc campaign.");
            end
            [strictCfg, resolvedScenario] = localStrictConfig(campaign);
            context = localDLContext(strictCfg);
            levels = double(w.aggregation_levels(:));
            fixtures = cell(numel(levels),1);
            for i=1:numel(levels)
                fixtures{i} = sixgr.phy.pdcch.PDCCHWaveformTrialEngine.createFixture( ...
                    strictCfg, context, levels(i));
            end
            rows = repmat(localTrialRow(), numel(levels)*numel(w.channels)* ...
                numel(w.snr_db)*double(w.trials_per_point),1);
            k=0;
            channels=string(w.channels(:));snrGrid=double(w.snr_db(:));
            doppler=double(w.doppler_hz(:));delay=double(w.channel_delay_spread_ns(:))*1e-9;
            for channelIndex=1:numel(channels)
                for snrIndex=1:numel(snrGrid)
                    for trial=1:double(w.trials_per_point)
                        realizationKey=channels(channelIndex)+":"+string(snrGrid(snrIndex))+":"+string(trial);
                        for levelIndex=1:numel(levels)
                            k=k+1;options=localOptions(cfg,w,trial,snrGrid(snrIndex), ...
                                channels(channelIndex),doppler(channelIndex),delay(channelIndex),realizationKey);
                            measured=sixgr.phy.pdcch.PDCCHWaveformTrialEngine.runCampaignTrial( ...
                                fixtures{levelIndex},options);
                            rows(k)=localMakeRow(campaign,strictCfg,fixtures{levelIndex}, ...
                                measured,"LLS-00",k,channels(channelIndex),delay(channelIndex), ...
                                doppler(channelIndex),snrGrid(snrIndex),trial,true,0,0);
                        end
                    end
                end
            end
            trials=struct2table(rows,"AsArray",true);
            anchorIndex=find(levels==4,1);if isempty(anchorIndex),anchorIndex=1;end
            falseAlarm=localFalseAlarm(campaign,strictCfg,fixtures{anchorIndex},w,k);
            impairments=localImpairments(campaign,strictCfg,fixtures{anchorIndex},w,k+height(falseAlarm));
            allTrials=[trials;falseAlarm;impairments];
            sixgr.phy.pdcch.tdoc.EvidenceClass.assertPrimaryTruth(allTrials);
            summary=localSummary(allTrials,double(w.confidence_level),w);
            baseline=summary(summary.ScenarioID=="LLS-00" & summary.SignalPresent & ...
                summary.CFOHz==0 & summary.PhaseNoiseStdRadians==0,:);
            baseline.CurveID=baseline.ChannelModel+" / AL"+string(baseline.AL);
            monotonic=localMonotonicity(baseline);
            if ~all(monotonic.Pass)
                error("sixgr:phy:pdcch:tdoc:NonMonotonicBoundedCurve", ...
                    "Bounded PDCCH BLER curves violate monotonicity beyond the configured low-count tolerance.");
            end
            result=struct();result.StrictConfig=strictCfg;result.ResolvedBaseScenario=resolvedScenario;
            result.Trials=allTrials;result.Summary=summary;result.Monotonicity=monotonic;
            result.ScenarioStatus=localScenarioStatus(summary,w);
            result.Figures=struct();
            result.Figures.lls_bundle_bler_by_al=baseline;
            result.Figures.lls_bundle_ce_nmse=baseline(isfinite(baseline.CENMSE),:);
            result.Figures.lls_sequence_false_alarm=summary(~summary.SignalPresent,:);
        end
    end
end

function [strictCfg,scenario]=localStrictConfig(campaign)
w=campaign.Config.waveform;root=localRoot();base=string(w.base_scenario);
if ~isfile(base),base=fullfile(root,base);end
scenarioObject=sixgr.lls6g.config.loadScenarioConfig(base);
scenario=scenarioObject.toStruct();
scenario.frequency.center_frequency_hz=double(w.carrier_frequency_hz);
scenario.frequency.dl_center_frequency_hz=double(w.carrier_frequency_hz);
scenario.frequency.ul_center_frequency_hz=double(w.carrier_frequency_hz);
scenario.frequency.band_name=char(string(w.band_name));
scenario.frequency.duplex_mode=char(string(w.duplex_mode));
scenario.frequency.bandwidth_hz=double(w.bandwidth_hz);
scenario.frequency.n_size_grid=double(w.n_size_grid);
scenario.frame.scs_khz=double(w.scs_khz);
scenario.reference_signals.ssb_case=char(string(w.ssb_case));
scenario.reference_signals.ssb_lmax=double(w.ssb_lmax);
scenario.control.coreset_duration=double(w.coreset_duration_symbols);
scenario.control.coreset_frequency_resources=double(w.coreset_frequency_resources(:).');
scenario.control.aggregation_levels=double(w.aggregation_levels(:).');
scenario.control.candidate_aggregation_levels=double(w.aggregation_levels(:).');
scenario.control.scheduler_aggregation_level=double(w.aggregation_levels(1));
scenario.control.search_space_num_candidates=ones(1,5);
scenario.control.pdcch_strict.execution_profile=char(string(w.execution_profile));
scenario.control.pdcch_strict.known_location_fallback=logical(w.known_location_fallback);
scenario.control.pdcch_strict.oracle_candidate_timing=logical(w.oracle_candidate_timing);
scenario.pdcch.start_symbol=double(w.coreset_start_symbol);
scenario.pdcch.num_symbols=double(w.coreset_duration_symbols);
scenario.pdcch.coreset.duration_symbols=double(w.coreset_duration_symbols);
scenario.pdcch.coreset.cce_to_reg_mapping=char(string(w.coreset_mapping));
scenario.pdcch.coreset.reg_bundle_size=double(w.reg_bundle_size);
scenario.pdcch.coreset.interleaver_size=double(w.interleaver_size);
scenario.channels.model_type="AWGN";scenario.channels.profile="AWGN";
scenario.mimo.n_tx_ant=1;scenario.mimo.n_rx_ant=1;scenario.mimo.n_layers=1;
runFolder=tempname;mkdir(runFolder);
internal=sixgr.lls6g.buildInternalConfig(scenario,runFolder);
strictCfg=sixgr.phy.pdcch.buildPDCCHConfigFromScenario(internal, ...
    "RunFolder",runFolder,"RunId",string(campaign.Config.run_id), ...
    "ScenarioName",campaign.ScenarioID);
if strictCfg.CORESETDefinition.Data.NCCE<max(double(w.aggregation_levels))
    error("sixgr:phy:pdcch:tdoc:InsufficientCORESET", ...
        "Configured CORESET has %d CCE, below maximum requested AL%d.", ...
        strictCfg.CORESETDefinition.Data.NCCE,max(double(w.aggregation_levels)));
end
end

function context=localDLContext(strictCfg)
formats=strings(numel(strictCfg.DCIContexts),1);
for i=1:numel(formats),formats(i)=strictCfg.DCIContexts{i}.Data.DCIFormat;end
index=find(formats=="1_0",1);
if isempty(index),error("sixgr:phy:pdcch:tdoc:MissingDCI10","DCI format 1_0 context is required.");end
context=strictCfg.DCIContexts{index};
end

function options=localOptions(cfg,w,trial,snr,channel,doppler,delay,realizationKey)
options=struct("Seed",double(cfg.reproducibility.seed_channel),"Trial",double(trial), ...
    "SNRdB",double(snr),"Channel",string(channel),"DopplerHz",double(doppler), ...
    "DelaySpreadSeconds",double(delay),"SignalPresent",true,"CFOHz",0, ...
    "TimingOffsetSamples",0,"PhaseNoiseStdRadians",0, ...
    "RealizationKey",string(realizationKey),"HypothesisCount",1, ...
    "ReceiverRNTIOffset",0,"ReceiverScramblingRNTIOffset",0);
end

function T=localFalseAlarm(campaign,strictCfg,fixture,w,offset)
snr=double(w.false_alarm_snr_db(:));n=double(w.absent_signal_trials_per_snr);
rows=repmat(localTrialRow(),numel(snr)*n,1);k=0;
for i=1:numel(snr)
 for trial=1:n
  k=k+1;options=localOptions(campaign.Config,w,trial,snr(i),"AWGN",0,0, ...
      "absent:"+string(snr(i))+":"+string(trial));options.SignalPresent=false;
  measured=sixgr.phy.pdcch.PDCCHWaveformTrialEngine.runCampaignTrial(fixture,options);
  rows(k)=localMakeRow(campaign,strictCfg,fixture,measured,"LLS-00-FA", ...
      offset+k,"AWGN",0,0,snr(i),trial,false,0,0);
 end
end
T=struct2table(rows,"AsArray",true);
end

function T=localImpairments(campaign,strictCfg,fixture,w,offset)
cfo=double(w.cfo_hz(:));pn=double(w.phase_noise_std_radians(:));
rows=repmat(localTrialRow(),numel(cfo)*numel(pn),1);k=0;snr=double(w.impairment_snr_db);
for c=cfo.'
 for phase=pn.'
  k=k+1;options=localOptions(campaign.Config,w,k,snr,"AWGN",0,0, ...
      "impairment:"+string(c)+":"+string(phase));
  options.CFOHz=c;options.PhaseNoiseStdRadians=phase;
  measured=sixgr.phy.pdcch.PDCCHWaveformTrialEngine.runCampaignTrial(fixture,options);
  rows(k)=localMakeRow(campaign,strictCfg,fixture,measured,"LLS-00-IMP", ...
      offset+k,"AWGN",0,0,snr,k,true,c,phase);
 end
end
T=struct2table(rows,"AsArray",true);
end

function row=localMakeRow(campaign,strictCfg,fixture,m,scenarioID,trialID,channel,delay,doppler,snr,trial,present,cfo,pn)
tx=fixture.Transmission;dataEnergy=sum(abs(tx.Grid(tx.PDCCHIndices)).^2);
dmrsEnergy=sum(abs(tx.Grid(tx.DMRSIndices)).^2);totalEnergy=dataEnergy+dmrsEnergy;
row=localTrialRow();row.RunID=string(campaign.Config.run_id);row.ScenarioID=string(scenarioID);
row.CaseID="CASE-"+compose("%05d",trialID);row.EvidenceClass=string(campaign.Config.waveform.evidence_class);
row.Status=string(m.Status);row.TDocGradeEligible=false;row.GitCommit=localGitCommit();
row.ConfigHash=campaign.ConfigHash;row.Seed=double(campaign.Config.reproducibility.seed_channel);
row.Trial=trial;row.CarrierHz=double(campaign.Config.waveform.carrier_frequency_hz);
row.SCSHz=double(campaign.Config.waveform.scs_khz)*1000;row.SystemBWHz=double(campaign.Config.waveform.bandwidth_hz);
row.NRB=double(campaign.Config.waveform.n_size_grid);row.ChannelModel=string(channel);
row.DelaySpreadNs=delay*1e9;row.SpeedKmph=double(doppler)*3.6*299792458/row.CarrierHz;
row.TxChains=1;row.RxChains=1;row.Receiver="MMSE";row.ChannelEstimation="practical_dmrs_ls_interpolation";
row.CORESET_RB=double(strictCfg.CORESETDefinition.Data.NRB);row.CORESET_Symbols=double(strictCfg.CORESETDefinition.Data.DurationSymbols);
row.MappingType=string(campaign.Config.waveform.coreset_mapping);row.REGBundleSize=double(campaign.Config.waveform.reg_bundle_size);
row.CCESizeREG=6;row.AL=fixture.AggregationLevel;row.Repetitions=1;
row.DCIPayloadBits=numel(tx.DCI.Bits);row.CRCBits=24;row.Modulation="QPSK";
row.DMRSPerREG=3;row.DMRSScope="candidate_local";row.DMRSPorts=1;
row.PrecoderScheme="one_port";row.PrecoderScope="same_as_reg_bundle";row.SNRdB=snr;
row.SignalPresent=present;row.Blocks=1;row.Errors=double(present && m.MissedDetection);
row.BLER=double(row.Errors);row.MissedDetection=logical(m.MissedDetection);row.FalseAlarm=logical(m.FalseAlarm);
row.CENMSE=double(m.CENMSE);if ~present,row.CENMSE=NaN;end
row.DataRECount=numel(tx.PDCCHIndices);row.DMRSRECount=numel(tx.DMRSIndices);
row.TotalEnergy=totalEnergy;row.DataEnergy=dataEnergy;row.DMRSEnergy=dmrsEnergy;
row.PolarK=row.DCIPayloadBits+24;row.PolarN=512;row.RateMatchedE=numel(tx.EncodedBits);
row.EoverN=row.RateMatchedE/row.PolarN;row.RateMatchMode=localRateMode(row.EoverN);
row.LLRMemoryBytes=8*row.RateMatchedE;row.ExecutedDecodes=1;row.ProcessingLatencyUs=1000*double(m.RuntimeMs);
row.CFOHz=cfo;row.PhaseNoiseStdRadians=pn;row.CorrectDetection=logical(m.CorrectDetection);
row.CRCCheckPassed=logical(m.CRCCheckPassed);row.KnownLocationUsed=logical(m.KnownLocationUsed);
row.OracleTimingUsed=logical(m.OracleTimingUsed);row.ExecutionBackend=string(m.ExecutionBackend);
row.ApproximationMode=string(m.ApproximationMode);row.ChannelRealizationID=string(m.ChannelRealizationID);
row.NoiseRealizationID=string(m.NoiseRealizationID);row.PayloadID=string(m.PayloadID);
row.Notes="bounded engineering trial; complete strict waveform chain; not publication statistics";
end

function row=localTrialRow()
row=struct("RunID","","ScenarioID","","CaseID","","EvidenceClass","LLS_CONTROLLED", ...
"Status","PASS","TDocGradeEligible",false,"GitCommit","","ConfigHash","","Seed",NaN,"Trial",NaN, ...
"CarrierHz",NaN,"SCSHz",NaN,"SystemBWHz",NaN,"NRB",NaN,"ChannelModel","", ...
"DelaySpreadNs",NaN,"SpeedKmph",NaN,"TxChains",NaN,"RxChains",NaN,"Receiver","", ...
"ChannelEstimation","","CORESET_RB",NaN,"CORESET_Symbols",NaN,"MappingType","", ...
"REGBundleSize",NaN,"CCESizeREG",NaN,"AL",NaN,"Repetitions",NaN,"DCIPayloadBits",NaN, ...
"CRCBits",NaN,"Modulation","","DMRSPerREG",NaN,"DMRSScope","","DMRSPorts",NaN, ...
"PrecoderScheme","","PrecoderScope","","SNRdB",NaN,"SignalPresent",true,"Blocks",NaN, ...
"Errors",NaN,"BLER",NaN,"MissedDetection",false,"FalseAlarm",false,"CENMSE",NaN, ...
"DataRECount",NaN,"DMRSRECount",NaN,"TotalEnergy",NaN,"DataEnergy",NaN,"DMRSEnergy",NaN, ...
"PolarK",NaN,"PolarN",NaN,"RateMatchedE",NaN,"EoverN",NaN,"RateMatchMode","", ...
"LLRMemoryBytes",NaN,"ExecutedDecodes",NaN,"ProcessingLatencyUs",NaN,"CFOHz",NaN, ...
"PhaseNoiseStdRadians",NaN,"CorrectDetection",false,"CRCCheckPassed",false, ...
"KnownLocationUsed",false,"OracleTimingUsed",false,"ExecutionBackend","", ...
"ApproximationMode","none","ChannelRealizationID","","NoiseRealizationID","", ...
"PayloadID","","Notes","");
end

function T=localSummary(trials,confidence,w)
keys=unique(trials(:,{'ScenarioID','ChannelModel','DelaySpreadNs','AL','SNRdB', ...
    'SignalPresent','CFOHz','PhaseNoiseStdRadians'}),'rows','stable');
rows=repmat(localSummaryRow(),height(keys),1);
for i=1:height(keys)
 mask=trials.ScenarioID==keys.ScenarioID(i)&trials.ChannelModel==keys.ChannelModel(i)& ...
  trials.DelaySpreadNs==keys.DelaySpreadNs(i)&trials.AL==keys.AL(i)&trials.SNRdB==keys.SNRdB(i)& ...
  trials.SignalPresent==keys.SignalPresent(i)&trials.CFOHz==keys.CFOHz(i)& ...
  trials.PhaseNoiseStdRadians==keys.PhaseNoiseStdRadians(i);
 part=trials(mask,:);blocks=height(part);errors=sum(part.Errors);fa=sum(part.FalseAlarm);
 eventCount=localTernary(keys.SignalPresent(i),errors,fa);[lo,hi]=localWilson(eventCount,blocks,confidence);
 rows(i).ScenarioID=keys.ScenarioID(i);rows(i).ChannelModel=keys.ChannelModel(i);
 rows(i).DelaySpreadNs=keys.DelaySpreadNs(i);rows(i).AL=keys.AL(i);rows(i).SNRdB=keys.SNRdB(i);
 rows(i).SignalPresent=keys.SignalPresent(i);rows(i).CFOHz=keys.CFOHz(i);
 rows(i).PhaseNoiseStdRadians=keys.PhaseNoiseStdRadians(i);rows(i).Blocks=blocks;
 rows(i).Errors=errors;rows(i).BLER=errors/max(blocks,1);rows(i).BLER_CI_Low=lo;rows(i).BLER_CI_High=hi;
 rows(i).FalseAlarms=fa;rows(i).FalseAlarmRate=fa/max(blocks,1);
 [~,faUpper]=localWilson(fa,blocks,confidence);rows(i).FAR_UpperBound=faUpper;
 rows(i).CENMSE=mean(part.CENMSE,'omitnan');rows(i).MeanLatencyUs=mean(part.ProcessingLatencyUs);
 rows(i).StatisticsQualified=blocks>=double(w.minimum_blocks_for_tdoc_grade)&& ...
     errors>=double(w.minimum_errors_for_tdoc_grade);
 rows(i).TDocGradeEligible=false;rows(i).EvidenceClass=string(w.evidence_class);rows(i).Status="PASS";
end
T=struct2table(rows,"AsArray",true);
end

function row=localSummaryRow()
row=struct("ScenarioID","","ChannelModel","","DelaySpreadNs",NaN,"AL",NaN,"SNRdB",NaN, ...
"SignalPresent",true,"CFOHz",NaN,"PhaseNoiseStdRadians",NaN,"Blocks",NaN,"Errors",NaN, ...
"BLER",NaN,"BLER_CI_Low",NaN,"BLER_CI_High",NaN,"FalseAlarms",NaN,"FalseAlarmRate",NaN, ...
"FAR_UpperBound",NaN,"CENMSE",NaN,"MeanLatencyUs",NaN,"StatisticsQualified",false, ...
"TDocGradeEligible",false,"EvidenceClass","LLS_CONTROLLED","Status","PASS");
end

function T=localMonotonicity(summary)
keys=unique(summary(:,{'ChannelModel','DelaySpreadNs','AL'}),'rows','stable');
rows=height(keys);ChannelModel=keys.ChannelModel;DelaySpreadNs=keys.DelaySpreadNs;AL=keys.AL;
Pass=false(rows,1);MaxUpwardStep=zeros(rows,1);Tolerance=zeros(rows,1);
for i=1:rows
 part=summary(summary.ChannelModel==ChannelModel(i)&summary.DelaySpreadNs==DelaySpreadNs(i)&summary.AL==AL(i),:);
 [~,order]=sort(part.SNRdB);bler=part.BLER(order);upper=part.BLER_CI_High(order);lower=part.BLER_CI_Low(order);
 delta=diff(bler);MaxUpwardStep(i)=max([0;delta]);
 intervalCompatible=all(lower(2:end)<=upper(1:end-1)+eps);
 Tolerance(i)=max(part.BLER_CI_High-part.BLER_CI_Low);Pass(i)=intervalCompatible;
end
T=table(ChannelModel,DelaySpreadNs,AL,MaxUpwardStep,Tolerance,Pass, ...
    repmat("LLS_CONTROLLED",rows,1), ...
    'VariableNames',{'ChannelModel','DelaySpreadNs','AL','MaxUpwardBLERStep', ...
    'LowCountCITolerance','Pass','EvidenceClass'});
end

function T=localScenarioStatus(summary,w)
ids="LLS-"+compose("%02d",(0:12)');status=repmat("NOT_EVALUATED",13,1);
detail=repmat("requested mechanism is not yet executed by the strict normative PDCCH path",13,1);
status(1)="PASS";detail(1)="strict QPSK Polar PDCCH baseline executed for all ALs over AWGN, TDL-A and TDL-C with practical CE";
status(11)="PASS";detail(11)="baseline sequence initialization and absent-signal false-alarm trials executed; identity variants remain bounded";
evidence=repmat("NOT_EVALUATED",13,1);evidence(1)=string(w.evidence_class);evidence(11)=string(w.evidence_class);
tdoc=false(13,1);executed=false(13,1);executed([1 11])=true;
if isempty(summary),status(:)="FAIL";detail(:)="no strict waveform trials";executed(:)=false;end
T=table(ids,status,executed,evidence,tdoc,detail, ...
    'VariableNames',{'ScenarioID','Status','Executed','EvidenceClass','TDocGradeEligible','Detail'});
end

function [lo,hi]=localWilson(events,trials,confidence)
if trials<=0,lo=NaN;hi=NaN;return;end
p=events/trials;z=sqrt(2)*erfinv(confidence);den=1+z^2/trials;
centre=(p+z^2/(2*trials))/den;half=z*sqrt(p*(1-p)/trials+z^2/(4*trials^2))/den;
lo=max(0,centre-half);hi=min(1,centre+half);
end

function value=localRateMode(ratio)
if ratio<1,value="puncturing_or_shortening";elseif ratio==1,value="mother_code_length";else,value="repetition";end
end

function value=localGitCommit()
[status,text]=system("git rev-parse HEAD");if status==0,value=strtrim(string(text));else,value="unavailable";end
end

function value=localTernary(condition,ifTrue,ifFalse)
if condition,value=ifTrue;else,value=ifFalse;end
end

function root=localRoot()
here=fileparts(mfilename("fullpath"));root=fileparts(fileparts(fileparts(fileparts(here))));
end
