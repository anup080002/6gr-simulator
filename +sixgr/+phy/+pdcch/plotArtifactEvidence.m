function plotArtifactEvidence(ax,imageName,sourceNames,tables)
%PLOTARTIFACTEVIDENCE Explicit data bindings for PDCCH figures.
% Never infer physical axes from arbitrary numeric columns, metadata hashes,
% category codes or a contract's requested number of series/points.
set(ax,'Color','white','XColor',[.15 .15 .15],'YColor',[.15 .15 .15]);
hold(ax,'on');
switch string(imageName)
    case "pdcch_beam_monitoring_timeline.png"
        t=localTable("pdcch_beam_monitoring.csv");
        localRequire(t,["AbsoluteSlot","TCIStateID","BeamID","QCLSourceID","QCLSourceType"]);
        x=localNumeric(t.AbsoluteSlot);
        for f=["TCIStateID","BeamID"]
            localPlot(x,localNumeric(t.(f)),f);
        end
        localGrouped(x,localNumeric(t.QCLSourceID),"QCLSourceID / "+string(t.QCLSourceType));
    case "pdcch_dmrs_sequence_correlation.png"
        t=localTable("pdcch_dmrs_matrix.csv");
        fields=["MatchedReferenceCorrelation","WrongNIDCorrelation","WrongSymbolCorrelation"];
        localRequire(t,["DMRSVectorIndex",fields,"EvidenceClass"]);
        if any(string(t.EvidenceClass)~="digital_sequence_component_not_receiver")
            error('sixgr:phy:pdcch:invalid_plot_evidence','DM-RS sequence evidence scope is missing or different.');
        end
        for f=fields
            y=localNumeric(t.(f));
            if any(y<0 | y>1+1e-12)
                error('sixgr:phy:pdcch:invalid_plot_evidence','Normalized sequence correlation is outside [0,1].');
            end
            localPlot(localNumeric(t.DMRSVectorIndex),y,f+" (sequence component)");
        end
    case "pdcch_candidate_map.png"
        t=localTable("pdcch_candidate_enumeration.csv");
        localRequire(t,["CandidateIndex","FirstCCE","AggregationLevel"]);
        localGrouped(localNumeric(t.CandidateIndex),localNumeric(t.FirstCCE), ...
            "AL="+string(t.AggregationLevel));
    case "pdcch_polar_rate_vs_al.png"
        t=localTable("pdcch_polar_coding.csv");
        localRequire(t,["AggregationLevel","CodeRate","KPayload"]);
        localGrouped(localNumeric(t.AggregationLevel),localNumeric(t.CodeRate), ...
            "K="+string(t.KPayload));
    case {"pdcch_detection_vs_snr.png","pdcch_false_alarm_bounds.png"}
        t=localTable("pdcch_detection_curve.csv");
        localRequire(t,["SNRdB","Trials","DetectionProbability","FalseAlarmCIUpper", ...
            "DCIFormat","AggregationLevel","Channel"]);
        group=string(t.DCIFormat)+" / AL="+string(t.AggregationLevel)+" / "+string(t.Channel);
        if string(imageName)=="pdcch_detection_vs_snr.png"
            x=localNumeric(t.SNRdB); y=localNumeric(t.DetectionProbability);
        else
            x=localNumeric(t.Trials); y=localNumeric(t.FalseAlarmCIUpper);
        end
        if any(y<0 | y>1), error('sixgr:phy:pdcch:invalid_plot_evidence','Invalid probability.'); end
        localGrouped(x,y,group);
    case "pdcch_search_space_timeline.png"
        t=localTable("pdcch_search_space_monitoring.csv");
        localRequire(t,["AbsoluteSlot","MonitoringSymbols","MonitoringOccasion","SearchSpaceID","CaseID"]);
        x=[]; y=[]; group=strings(0,1);
        for k=1:height(t)
            if ~localLogical(t.MonitoringOccasion(k)), continue; end
            symbols=localList(t.MonitoringSymbols(k));
            x=[x;repmat(localNumeric(t.AbsoluteSlot(k)),numel(symbols),1)]; %#ok<AGROW>
            y=[y;symbols]; %#ok<AGROW>
            group=[group;repmat(string(t.CaseID(k))+" / SS="+string(t.SearchSpaceID(k)),numel(symbols),1)]; %#ok<AGROW>
        end
        localGrouped(x,y,group);
    case "pdcch_coreset_reg_cce_map.png"
        t=localTable("pdcch_coreset_mapping.csv");
        localRequire(t,["REGIndices","CCEIndex","CaseID","MappingType"]);
        x=[]; y=[]; group=strings(0,1);
        for k=1:height(t)
            reg=localList(t.REGIndices(k));
            x=[x;reg]; %#ok<AGROW>
            y=[y;repmat(localNumeric(t.CCEIndex(k)),numel(reg),1)]; %#ok<AGROW>
            group=[group;repmat(string(t.CaseID(k))+" / "+string(t.MappingType(k)),numel(reg),1)]; %#ok<AGROW>
        end
        localGrouped(x,y,group);
    case "pdcch_dci_field_layout.png"
        t=localTable("pdcch_dci_field_layout.csv");
        localRequire(t,["BitStart","BitEnd","FieldName","Present","DCIFormat"]);
        t=t(localLogical(t.Present),:);
        [fieldIndex,fields]=localCategories(t.FieldName);
        % Two endpoints from each actual field's serialized bit interval.
        localGrouped([localNumeric(t.BitStart);localNumeric(t.BitEnd)], ...
            [fieldIndex;fieldIndex],[string(t.DCIFormat);string(t.DCIFormat)]);
        yticks(ax,1:numel(fields)); yticklabels(ax,fields);
    case "pdcch_bwp_crosscarrier_map.png"
        t=localTable("pdcch_bwp_crosscarrier.csv");
        localRequire(t,["ControlCarrier","ControlBWP","ScheduledCarrier","ScheduledBWP","ControlServingCell"]);
        [x,xnames]=localCategories(string(t.ControlCarrier)+"/"+string(t.ControlBWP));
        [y,ynames]=localCategories(string(t.ScheduledCarrier)+"/"+string(t.ScheduledBWP));
        localGrouped(x,y,"Control cell="+string(t.ControlServingCell));
        xticks(ax,1:numel(xnames)); xticklabels(ax,xnames);
        yticks(ax,1:numel(ynames)); yticklabels(ax,ynames);
    case "pdcch_type0_css_timeline.png"
        t=localTable("pdcch_type0_css.csv");
        localRequire(t,["MonitoringSlots","MonitoringFirstSymbols","SSBIndex","EvidenceClass"]);
        if any(string(t.EvidenceClass)~="resolved_configuration_not_receiver_detection")
            error('sixgr:phy:pdcch:invalid_plot_evidence','Type-0 evidence scope is missing or different.');
        end
        x=[]; y=[]; group=strings(0,1);
        for k=1:height(t)
            slots=localList(t.MonitoringSlots(k));
            symbols=localList(t.MonitoringFirstSymbols(k));
            if numel(slots)~=numel(symbols) || any(slots<0 | slots~=fix(slots)) || ...
                    any(symbols<0 | symbols>13 | symbols~=fix(symbols))
                error('sixgr:phy:pdcch:invalid_plot_evidence','Type-0 slot/symbol pairs are invalid.');
            end
            x=[x;slots]; y=[y;symbols]; %#ok<AGROW>
            group=[group;repmat("Resolved SSB="+string(t.SSBIndex(k)),numel(slots),1)]; %#ok<AGROW>
        end
        localGrouped(x,y,group);
    case "pdcch_rnti_confusion_matrix.png"
        t=localTable("pdcch_blind_trials.csv");
        localRequire(t,["RNTITypeTx","DecodedRNTIType","DCIFormatTx","Detected"]);
        detected=localLogical(t.Detected);
        outcome=string(t.DecodedRNTIType);
        if any(~detected & ~ismissing(outcome) & strlength(outcome)>0)
            error('sixgr:phy:pdcch:invalid_plot_evidence','Non-detection row claims a decoded RNTI identity.');
        end
        outcome(~detected)="Not detected";
        [x,xnames]=localCategories(t.RNTITypeTx);
        [y,ynames]=localCategories(outcome);
        localGrouped(x,y,string(t.DCIFormatTx));
        xticks(ax,1:numel(xnames)); xticklabels(ax,xnames);
        yticks(ax,1:numel(ynames)); yticklabels(ax,ynames);
    case "pdcch_grant_authority_trace.png"
        t=localTable("pdcch_grant_authority.csv");
        localRequire(t,["CaseID","CRCCheckPassed","AssignmentCreated","WaveformGenerated"]);
        [x,xnames]=localCategories(t.CaseID);
        for f=["CRCCheckPassed","AssignmentCreated","WaveformGenerated"]
            localPlot(x,double(localLogical(t.(f))),f);
        end
        ticks=unique(round(linspace(1,numel(xnames),min(12,numel(xnames)))));
        xticks(ax,ticks); xticklabels(ax,xnames(ticks)); xtickangle(ax,30);
    otherwise
        error('sixgr:phy:pdcch:missing_plot_binding', ...
            'No verified physical-data binding for %s. Metadata/counts cannot substitute for samples.',imageName);
end

    function t=localTable(name)
        idx=find(string(sourceNames)==name);
        if numel(idx)~=1 || isempty(tables{idx})
            error('sixgr:phy:pdcch:missing_plot_evidence','Missing nonempty source %s.',name);
        end
        t=tables{idx};
    end
    function localPlot(x,y,label)
        if isempty(x) || numel(x)~=numel(y) || any(~isfinite(x(:)) | ~isfinite(y(:)))
            error('sixgr:phy:pdcch:invalid_plot_evidence','Nonfinite, empty or mismatched series: %s.',label);
        end
        plot(ax,x,y,'o','LineStyle','none','DisplayName',label,'Tag','PDCCHSourceEvidence');
    end
    function localGrouped(x,y,g)
        if isempty(g), error('sixgr:phy:pdcch:missing_plot_evidence','No executed observations.'); end
        for name=reshape(unique(string(g),'stable'),1,[])
            selected=string(g)==name;
            localPlot(x(selected),y(selected),name);
        end
    end
end

function localRequire(t,fields)
if ~all(ismember(fields,string(t.Properties.VariableNames)))
    error('sixgr:phy:pdcch:missing_plot_evidence','Required named CSV fields are absent.');
end
end
function x=localNumeric(raw)
if isnumeric(raw) || islogical(raw), x=double(raw(:)); else, x=str2double(string(raw(:))); end
if any(~isfinite(x)), error('sixgr:phy:pdcch:invalid_plot_evidence','Required numeric field is invalid.'); end
end
function x=localLogical(raw)
if isnumeric(raw) || islogical(raw)
    x=localNumeric(raw);
    if any(x~=0 & x~=1), error('sixgr:phy:pdcch:invalid_plot_evidence','Invalid logical evidence.'); end
    x=logical(x);
else
    s=lower(string(raw(:)));
    if any(~ismember(s,["true","false","1","0"]))
        error('sixgr:phy:pdcch:invalid_plot_evidence','Invalid logical evidence.');
    end
    x=ismember(s,["true","1"]);
end
end
function x=localList(raw)
x=localNumeric(split(string(raw),'|'));
end
function [x,names]=localCategories(raw)
s=string(raw(:));
if any(ismissing(s) | strlength(s)==0)
    error('sixgr:phy:pdcch:missing_plot_evidence','Category identity is missing.');
end
names=unique(s,'stable'); [~,x]=ismember(s,names);
end
