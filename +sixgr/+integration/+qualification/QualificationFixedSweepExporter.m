classdef QualificationFixedSweepExporter
    %QUALIFICATIONFIXEDSWEEPEXPORTER Publish exact Wave-C runtime evidence.
    %
    % The exporter adapts production fixed-link campaign trials. It never
    % substitutes configured SNR for a receiver measurement and refuses
    % incomplete operating points.
    methods (Static)
        function summary = export(campaign, outputDir, runID, cfg)
            arguments
                campaign (1,1) struct
                outputDir (1,1) string
                runID (1,1) string
                cfg (1,1) struct
            end
            dlTrials = localRequiredTable(campaign,"DLTrials");
            ulTrials = localRequiredTable(campaign,"ULTrials");
            dlSource = localRequiredTable(campaign,"DLBlerCurve");
            ulSource = localRequiredTable(campaign,"ULBlerCurve");
            localRequireFiveActualPoints(dlSource,"DL");
            localRequireFiveActualPoints(ulSource,"UL");

            pdschMetrics = localReceiverMetrics(dlTrials,"DL");
            puschMetrics = localReceiverMetrics(ulTrials,"UL");
            pdschCurve = localBLERCurve(dlSource,dlTrials,runID,"DL",cfg);
            puschCurve = localBLERCurve(ulSource,ulTrials,runID,"UL",cfg);

            tables = struct( ...
                "pdsch_receiver_metrics",pdschMetrics, ...
                "pusch_receiver_metrics",puschMetrics, ...
                "pdsch_bler_curve",pdschCurve, ...
                "pusch_bler_curve",puschCurve);
            names = string(fieldnames(tables));
            for index = 1:numel(names)
                sixgr.integration.qualification.QualificationAtomicWriter. ...
                    writeTable(fullfile(outputDir,names(index)+".csv"), ...
                    tables.(names(index)));
            end

            images = [ ...
                localPlotCurve(pdschCurve,outputDir, ...
                    "pdsch_bler_vs_snr.png","PDSCH BLER","SNR (dB)","BLER"); ...
                localPlotCurve(puschCurve,outputDir, ...
                    "pusch_bler_vs_snr.png","PUSCH BLER","SNR (dB)","BLER"); ...
                localPlotSINR(pdschMetrics,outputDir, ...
                    "pdsch_per_layer_sinr.png","Per-layer SINR", ...
                    "Layer","Measured SINR (dB)"); ...
                localPlotSINR(puschMetrics,outputDir, ...
                    "pusch_per_layer_sinr.png","PUSCH per-layer SINR", ...
                    "Layer / operating point","Measured SINR (dB)")];
            summary = struct("Passed",true,"Tables",tables, ...
                "Images",images,"DLTrialCount",height(dlTrials), ...
                "ULTrialCount",height(ulTrials));
        end
    end
end

function T=localRequiredTable(value,field)
T=sixgr.util.structGet(value,field,table());
if ~(istable(T) && ~isempty(T))
    error("FULLSTACK:FixedSweepRuntimeEvidenceMissing", ...
        "Fixed-link campaign field %s contains no runtime rows.",field);
end
end

function localRequireFiveActualPoints(T,direction)
snr=localNumeric(T,["SNR_dB"]);
trials=localNumeric(T,["TrialCount"]);
value=localNumeric(T,["Value"]);
incomplete=localLogical(T,["Incomplete"],false);
expected=[-8 -4 0 4 10];
if height(T)~=5 || ~isequal(sort(snr(:)).',expected) || ...
        any(~isfinite(value) | value<0 | value>1 | trials<1 | incomplete)
    error("FULLSTACK:FixedSweepPointContractFailed", ...
        "%s must contain five complete measured BLER points at %s dB.", ...
        direction,mat2str(expected));
end
end

function T=localReceiverMetrics(source,direction)
n=height(source);
configuredSNR=localNumeric(source,["ConfiguredSNR_dB","SNR_dB"]);
measured=localNumeric(source,["PostEqSINR_dB","MeasuredTrialSINR_dB"]);
measuredSource=localText(source, ...
    ["PostEqSINRSource","MeasuredTrialSINRSource"]);
receiverDerived=localLogical(source,["PostEqSINRReceiverDerived"],false);
if any(~isfinite(measured)) || any(~receiverDerived) || ...
        any(contains(lower(measuredSource), ...
        ["configured","requested","nominal","fallback","proxy"]))
    error("FULLSTACK:FixedSweepReceiverSINRInvalid", ...
        "%s fixed-sweep SINR must be finite and receiver-derived.",direction);
end
rank=localNumeric(source,["FixedLinkConfiguredRank","ConfiguredRank","Layers"]);
layers=localNumeric(source,["FixedLinkConfiguredLayers","ConfiguredLayers","Layers"]);
if any(rank~=1 | layers~=1)
    error("FULLSTACK:FixedSweepReceiverRankUnsupported", ...
        "Wave-C receiver metric adapter currently requires executed rank one.");
end
dataRE=localNumeric(source,["DataRECount"]);
llrCount=localNumeric(source,["RateMatchedBits"]);
rateRecovered=localNumeric(source,["EncodedBits","RateMatchedBits"]);
evm=100*localNumeric(source,["EVM_rms"]);
bitErrors=localNumeric(source,["BitErrors"]);
bitsCompared=localNumeric(source,["BitsCompared"]);
crc=localLogical(source,["CRCPass"],false);
nmse=localNumeric(source,["NMSE_dB"]);
iterations=localNumeric(source,["DecoderIterations"]);
ber=bitErrors./max(bitsCompared,1);
bler=double(~crc);
if any(~isfinite([configuredSNR,rank,dataRE,llrCount, ...
        rateRecovered,evm,ber,bler,nmse,iterations]),"all") || ...
        any(dataRE<1 | llrCount<1 | rateRecovered<1 | ...
        bitsCompared<1 | ber<0 | ber>1)
    error("FULLSTACK:FixedSweepReceiverMetricInvalid", ...
        "%s fixed-sweep receiver metrics are missing runtime values.",direction);
end
caseID=direction+"-P"+string(localNumeric(source, ...
    ["FixedLinkPointIndex"]))+"-T"+string(localNumeric(source, ...
    ["FixedLinkTrialIndex"]));
channel=localText(source, ...
    ["FixedLinkConfiguredChannelModel","ChannelModel"]);
codeword=zeros(n,1);
layer=zeros(n,1);
status=repmat("PASS",n,1);
if direction=="DL"
    T=table(caseID,configuredSNR,channel,rank,codeword,layer, ...
        dataRE,llrCount,rateRecovered,measured,evm,ber,bler,crc, ...
        nmse,iterations,status,'VariableNames', ...
        {'CaseID','SNRdB','ChannelModel','Rank','Codeword','Layer', ...
        'DataRECount','LLRCount','RateRecoveredBitCount', ...
        'MeasuredSINRdB','EVMPercent','BER','BLER','TBCRCOK', ...
        'ChannelEstimateNMSEdB','LDPCIterations','Status'});
else
    ueIndex=localNumeric(source,["UEIndex"]);
    ueID="UE"+string(ueIndex);
    hop=zeros(n,1);
    covariance=localLogical(source, ...
        ["InterferenceCovarianceAvailable"],false);
    T=table(caseID,configuredSNR,channel,ueID,rank,codeword, ...
        layer,hop,dataRE,llrCount,rateRecovered,measured, ...
        measuredSource,receiverDerived,evm,ber,bler,crc,nmse, ...
        iterations,covariance,status,'VariableNames', ...
        {'CaseID','SNRdB','ChannelModel','UEID','Rank','Codeword', ...
        'Layer','Hop','DataRECount','LLRCount', ...
        'RateRecoveredBitCount','MeasuredSINRdB', ...
        'MeasuredSINRSource','ReceiverDerived','EVMPercent','BER', ...
        'BLER','TBCRCOK','ChannelEstimateNMSEdB','LDPCIterations', ...
        'InterferenceCovarianceUsed','Status'});
end
end

function T=localBLERCurve(curve,trials,runID,direction,cfg)
n=height(curve);
snr=localNumeric(curve,["SNR_dB"]);
mcs=localNumeric(curve,["MCSIndex"]);
rank=localNumeric(curve,["ConfiguredRank"]);
trialCount=localNumeric(curve,["TrialCount"]);
failures=localNumeric(curve,["FailureCount"]);
bler=localNumeric(curve,["Value"]);
ciLow=localNumeric(curve,["CI_Low"]);
ciHigh=localNumeric(curve,["CI_High"]);
ciHalf=localNumeric(curve,["CI_HalfWidth"]);
stopReason=localText(curve,["StopReason"]);
incomplete=localLogical(curve,["Incomplete"],false);
confidence=double(sixgr.util.structGet(cfg, ...
    "validation.fixed_link_campaign.confidence_level",NaN));
minErrors=double(sixgr.util.structGet(cfg, ...
    "validation.fixed_link_campaign.min_errors_for_ci",NaN));
channel=localText(curve,["ConfiguredChannelModel"]);
modulation=strings(n,1);
for index=1:n
    mask=localNumeric(trials,["ConfiguredSNR_dB","SNR_dB"])==snr(index);
    values=unique(localText(trials(mask,:),["Modulation"]),"stable");
    if numel(values)~=1 || strlength(strtrim(values))==0
        error("FULLSTACK:FixedSweepModulationEvidenceInvalid", ...
            "%s %.6g dB has no unique executed modulation.", ...
            direction,snr(index));
    end
    modulation(index)=values;
end
campaignID=repmat(runID+"-"+direction+"-FIXED",n,1);
operatingPointID=direction+"-SNR-"+string(snr);
status=repmat("PASS",n,1);
status(incomplete | ~isfinite(bler) | ~isfinite(ciLow) | ...
    ~isfinite(ciHigh) | trialCount<1)="FAIL";
if any(status~="PASS")
    error("FULLSTACK:FixedSweepCurveIncomplete", ...
        "%s fixed-sweep curve contains incomplete runtime points.",direction);
end
if direction=="DL"
    T=table(campaignID,operatingPointID,snr,channel,rank,mcs, ...
        modulation,trialCount,failures,bler,repmat(confidence,n,1), ...
        ciLow,ciHigh,ciHalf,repmat(minErrors,n,1),stopReason,status, ...
        'VariableNames',{'CampaignID','OperatingPointID','SNRdB', ...
        'ChannelModel','Rank','MCSIndex','Modulation','Trials', ...
        'TBErrors','BLER','ConfidenceLevel','CILower','CIUpper', ...
        'CIHalfWidth','MinErrorsRequired','StopReason','Status'});
else
    if ~ismember("TransformPrecodingApplied", ...
            string(trials.Properties.VariableNames))
        error("FULLSTACK:FixedSweepTransformPrecodingEvidenceMissing", ...
            "UL trial rows do not record applied transform precoding.");
    end
    transform=localLogical(trials,["TransformPrecodingApplied"],false);
    transform=double(any(transform));
    hopping=string(sixgr.util.structGet(cfg, ...
        "phy.pusch.frequencyHopping.mode","none"));
    T=table(campaignID,operatingPointID,snr,channel,rank,mcs, ...
        modulation,repmat(transform,n,1),repmat(hopping,n,1), ...
        trialCount,failures,bler,repmat(confidence,n,1),ciLow, ...
        ciHigh,ciHalf,repmat(minErrors,n,1),stopReason,incomplete, ...
        status,'VariableNames',{'CampaignID','OperatingPointID', ...
        'SNRdB','ChannelModel','Rank','MCSIndex','Modulation', ...
        'TransformPrecoding','FrequencyHopping','Trials','TBErrors', ...
        'BLER','ConfidenceLevel','CILower','CIUpper','CIHalfWidth', ...
        'MinErrorsRequired','StopReason','Incomplete','Status'});
end
end

function info=localPlotCurve(T,outputDir,fileName,titleText,xText,yText)
[snr,order]=sort(double(T.SNRdB));
bler=double(T.BLER(order));
fig=localFigure();
cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
ax=axes(fig); hold(ax,"on"); grid(ax,"on"); box(ax,"on");
semilogy(ax,snr,max(bler,eps),"-o","LineWidth",1.8, ...
    "DisplayName","Measured waveform BLER");
xlabel(ax,xText); ylabel(ax,yText); title(ax,titleText);
legend(ax,"Location","best"); hold(ax,"off");
info=localSaveFigure(fig,outputDir,fileName);
end

function info=localPlotSINR(T,outputDir,fileName,titleText,xText,yText)
fig=localFigure();
cleanup=onCleanup(@()close(fig)); %#ok<NASGU>
ax=axes(fig); hold(ax,"on"); grid(ax,"on"); box(ax,"on");
x=(1:height(T)).';
scatter(ax,x,double(T.MeasuredSINRdB),24,double(T.SNRdB),"filled", ...
    "DisplayName","Receiver-derived SINR");
xlabel(ax,xText); ylabel(ax,yText); title(ax,titleText);
colorbar(ax); hold(ax,"off");
info=localSaveFigure(fig,outputDir,fileName);
end

function fig=localFigure()
fig=figure("Visible","off","Color","white","Units","inches", ...
    "Position",[1 1 12 8],"Renderer","painters");
end

function info=localSaveFigure(fig,outputDir,fileName)
sixgr.util.ensureFolder(outputDir);
temporary=fullfile(outputDir,"."+erase(fileName,".png")+"."+ ...
    string(java.util.UUID.randomUUID())+".tmp.png");
cleanup=onCleanup(@()localDelete(temporary)); %#ok<NASGU>
drawnow;
exportgraphics(fig,temporary,"Resolution",100, ...
    "BackgroundColor","white");
metadata=imfinfo(temporary);
if metadata.Width<900 || metadata.Height<600
    error("FULLSTACK:FixedSweepImageDimensionInvalid", ...
        "%s is only %dx%d.",fileName,metadata.Width,metadata.Height);
end
target=fullfile(outputDir,fileName);
if isfile(target)
    error("FULLSTACK:FixedSweepArtifactAlreadyExists", ...
        "Refusing to overwrite %s.",target);
end
[ok,message]=movefile(temporary,target,"f");
if ~ok
    error("FULLSTACK:FixedSweepImagePublishFailed","%s",message);
end
info=struct("FileName",string(fileName), ...
    "Width",double(metadata.Width),"Height",double(metadata.Height), ...
    "SHA256",localHash(target));
end

function value=localNumeric(T,names)
for name=names
    if ismember(name,string(T.Properties.VariableNames))
        value=double(T.(char(name)));
        return;
    end
end
error("FULLSTACK:FixedSweepColumnMissing", ...
    "Runtime evidence lacks numeric column %s.",strjoin(names,"|"));
end

function value=localText(T,names)
for name=names
    if ismember(name,string(T.Properties.VariableNames))
        value=string(T.(char(name)));
        return;
    end
end
error("FULLSTACK:FixedSweepColumnMissing", ...
    "Runtime evidence lacks text column %s.",strjoin(names,"|"));
end

function value=localLogical(T,names,default)
for name=names
    if ismember(name,string(T.Properties.VariableNames))
        raw=T.(char(name));
        if islogical(raw)
            value=logical(raw);
        elseif isnumeric(raw)
            value=logical(raw);
        else
            value=ismember(upper(strtrim(string(raw))), ...
                ["1","TRUE","YES","PASS"]);
        end
        return;
    end
end
value=repmat(logical(default),height(T),1);
end

function hash=localHash(path)
fid=fopen(path,"rb");
if fid<0,error("FULLSTACK:FixedSweepArtifactReadFailed","%s",path);end
cleanup=onCleanup(@()fclose(fid)); %#ok<NASGU>
hash=string(sixgr.util.sha256Hex(fread(fid,Inf,"*uint8")));
end

function localDelete(path)
if isfile(path),delete(path);end
end
