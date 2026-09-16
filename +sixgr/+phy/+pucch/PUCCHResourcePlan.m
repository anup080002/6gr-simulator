classdef PUCCHResourcePlan
    %PUCCHRESOURCEPLAN Pure RRC/UCI/PRI/timing selection, not a TX assignment.
    % No transmit power, waveform, reception, or eligibility is manufactured.
    properties (SetAccess=private)
        Data
        Resource
        ReportDigest
        RequestedReportDigest
        TransmittedReport
        RRCContextDigest
        Digest
    end
    properties (Dependent)
        Format
    end
    methods
        function obj=PUCCHResourcePlan(report,ue,rrc,frame,source)
            if ~isa(report,'sixgr.phy.pucch.UCIReport') || ...
                    ~isa(rrc,'sixgr.phy.pucch.PUCCHRRCContext')
                error('sixgr:phy:pucch:MissingUCIReportContext', ...
                    'Resource planning requires typed report and RRC configuration.');
            end
            sixgr.phy.pucch.UCIReport.requireFields(ue, ...
                ["UEID","RNTI","ServingCell","PUCCHCell", ...
                "ComponentCarrier","ActiveULBWP","ConfigurationEpoch"]);
            if report.ConfigurationEpoch~=double(ue.ConfigurationEpoch) || ...
                    report.ConfigurationEpoch~=rrc.ConfigurationEpoch
                error('sixgr:phy:pucch:StaleConfiguration','Report/UE/RRC epochs differ.');
            end
            if double(report.Data.ULBWP)~=double(ue.ActiveULBWP)
                error('sixgr:phy:pucch:StaleBWP','Report UL BWP differs from active UE BWP.');
            end
            if double(report.Data.RNTI)~=double(ue.RNTI)
                error('sixgr:phy:pucch:WrongRNTI','Report RNTI differs from active UE context.');
            end
            if double(report.Data.ServingCell)~=double(ue.ServingCell) || ...
                    double(report.Data.ComponentCarrier)~=double(ue.ComponentCarrier)
                error('sixgr:phy:pucch:WrongResource','Report serving cell/carrier differs from UE context.');
            end
            serialized=sixgr.phy.pucch.UCIReportSerializer.serialize(report);
            requestedReport=report;
            selection=localCSISelection(report,report);
            owners=string(serialized.Layout.BitOwner);
            csiOnly=any(owners=="CSI_PART1" | owners=="CSI_PART2") && ...
                ~any(owners=="HARQ_ACK");
            if csiOnly
                id=sixgr.phy.pucch.resolveConfiguredCSIResourceID(rrc.Data.CSIResources);
                resource=rrc.resourceByID(id);
                resourceSetID=NaN;
                priValue=NaN;
                priProvenance="configured_csi_report_resource";
            else
                set=sixgr.phy.pucch.PUCCHResourceSetResolver.resolve(report,rrc);
                priRow=struct('ResourceSetID',set.ID,'ResourceListSize',numel(set.ResourceIDs), ...
                    'PRIFieldWidth',sixgr.phy.pucch.PUCCHUtil.field(frame,'PRIFieldWidth', ...
                    ceil(log2(max(1,numel(set.ResourceIDs))))), ...
                    'PRIValue',sixgr.phy.pucch.PUCCHUtil.field(frame,'DecodedPRI',0), ...
                    'FirstCCE',sixgr.phy.pucch.PUCCHUtil.field(frame,'FirstCCE',NaN), ...
                    'NumCCE',sixgr.phy.pucch.PUCCHUtil.field(frame,'NumCCE',NaN), ...
                    'RequiresSet0CCEFormula',set.ID==0 && numel(set.ResourceIDs)>8);
                pri=sixgr.phy.pucch.PUCCHResourceIndicatorResolver.resolveVector(priRow);
                if ~pri.Valid
                    error(pri.ErrorID,'Invalid decoded PUCCH PRI: set=%g count=%g PRI=%g firstCCE=%g numCCE=%g.', ...
                        priRow.ResourceSetID,priRow.ResourceListSize,priRow.PRIValue, ...
                        priRow.FirstCCE,priRow.NumCCE);
                end
                resource=rrc.resourceByID(set.ResourceIDs(pri.Ordinal));
                resourceSetID=set.ID;
                priValue=priRow.PRIValue;
                priProvenance=sixgr.phy.pucch.PUCCHUtil.field(frame,'PRIProvenance','decoded_dci');
            end
            rrc.assertMultiplexingAllowed(resource.Format,sum(owners=="HARQ_ACK"), ...
                sum(owners=="CSI_PART1" | owners=="CSI_PART2"));
            k1=double(sixgr.phy.pucch.PUCCHUtil.field(frame,'K1',NaN));
            k1Source=string(sixgr.phy.pucch.PUCCHUtil.field(frame,'K1Source','decoded_dci'));
            pdschEnd=double(sixgr.phy.pucch.PUCCHUtil.field(frame,'PDSCHEndSlot',report.Data.TargetSlot-k1));
            ownership=string(sixgr.phy.pucch.PUCCHUtil.field(frame,'SlotSymbolOwnership','UUUUUUUUUUUUUU'));
            timing=sixgr.phy.pucch.PUCCHTimingResolver.resolve(pdschEnd,k1,k1Source, ...
                ownership,resource.Data.StartSymbol,resource.Data.NumSymbols, ...
                logical(sixgr.phy.pucch.PUCCHUtil.field(frame,'FlexibleResolutionProvided',false)));
            if timing.DueSlot~=double(report.Data.TargetSlot)
                error('sixgr:phy:pucch:InvalidK1','UCI target differs from the resolved feedback occasion.');
            end
            sixgr.phy.pucch.PUCCHFormatValidator.validateResource(resource.Data, ...
                numel(serialized.Sequence1.Bits)+numel(serialized.Sequence2.Bits), ...
                sixgr.phy.pucch.UCIReportContext.fromReport(report));
            allocationBudget=struct();
            if resource.Format>=2
                context=sixgr.phy.pucch.UCIReportContext.fromReport(report);
                procedure="dynamic_harq";
                if csiOnly
                    assert(numel(report.Data.CSIReports)==1, ...
                        'sixgr:phy:pucch:MultiCSIResourceSelectionRequired', ...
                        'Multiple CSI-only reports require their configured multi-CSI resource procedure.');
                    procedure="configured_csi";
                elseif context.CSIPart1Bits>0 || context.CSIPart2Bits>0
                    assert(string(source)~="sps_harq", ...
                        'sixgr:phy:pucch:SPSCSIResourceSelectionRequired', ...
                        'SPS/CSI cannot use the dynamic-HARQ resource procedure.');
                    procedure="dynamic_harq_csi";
                end
                [selected,allocationBudget]=rrc.allocateResource( ...
                    resource.ID,context,timing.DueSlot-1,procedure);
                if isempty(selected) && procedure=="dynamic_harq_csi"
                    [report,selected,allocationBudget]=localSelectCSIReports( ...
                        report,rrc,resource.ID,timing.DueSlot-1);
                    selection=localCSISelection(requestedReport,report);
                end
                assert(~isempty(selected),'sixgr:phy:pucch:CSIResourceCapacityExceeded', ...
                    ['CSI report selection is required before transmission: %s. ' ...
                     'No bits have been truncated and no resource or power increased.'], ...
                    allocationBudget.Disposition);
                resource=selected;
            end
            obj.Data=struct('AssignmentID',"PUCCH-"+report.ReportID+"-"+string(timing.DueSlot), ...
                'AssignmentSource',string(source),'UEID',ue.UEID,'RNTI',ue.RNTI, ...
                'ServingCell',ue.ServingCell,'PUCCHCell',ue.PUCCHCell, ...
                'ComponentCarrier',ue.ComponentCarrier,'ActiveULBWP',ue.ActiveULBWP, ...
                'ConfigurationEpoch',report.ConfigurationEpoch,'ReportID',report.ReportID, ...
                'K1',k1,'K1Source',k1Source,'DueSlot',timing.DueSlot, ...
                'ResourceSetID',resourceSetID,'ResourceID',resource.ID,'PRIValue',priValue, ...
                'PRIProvenance',priProvenance);
            obj.Data.AllocationBudget=allocationBudget;
            obj.Data.CSISelection=selection; % UE TX disposition, never RX evidence.
            obj.Resource=resource;
            obj.ReportDigest=report.Digest;
            obj.RequestedReportDigest=requestedReport.Digest;
            obj.TransmittedReport=report;
            obj.RRCContextDigest=rrc.Digest;
            obj.Digest=sixgr.phy.pucch.PUCCHUtil.hash(struct('Data',obj.Data, ...
                'ResourceDigest',resource.Digest,'ReportDigest',obj.ReportDigest, ...
                'RequestedReportDigest',obj.RequestedReportDigest, ...
                'RRCContextDigest',obj.RRCContextDigest));
        end
        function value=get.Format(obj), value=obj.Resource.Format; end
    end
end

function [report,resource,budget]=localSelectCSIReports(requested,rrc,id,slot0)
% TS 38.213 9.2.5.2: keep a prefix of whole CSI reports in priority order
% on the resource selected for the full UCI. Never truncate serialized bits.
reports=requested.Data.CSIReports;
if isa(reports,'sixgr.phy.pucch.CSIReportState'), reports=arrayfun(@(x)x.Data,reports); end
ids=[reports.ReportID]; priorities=[reports.Priority];
validateattributes(ids,{'numeric'},{'real','finite','integer','nonnegative','vector'});
validateattributes(priorities,{'numeric'},{'real','finite','integer','nonnegative','numel',numel(ids)});
assert(numel(unique(ids))==numel(ids),'sixgr:phy:pucch:DuplicateCSIReportIdentity', ...
    'Whole-report selection requires unique CSI report identities.');
[~,order]=sortrows([priorities(:) ids(:)],[1 2]);
reports=reports(order);
for count=numel(reports)-1:-1:0
    data=requested.Data; data.CSIReports=reports(1:count);
    report=sixgr.phy.pucch.UCIReport(data);
    context=sixgr.phy.pucch.UCIReportContext.fromReport(report);
    assert(context.Sequence1Length>=3,'sixgr:phy:pucch:CSIOmissionShortPayloadProcedureRequired', ...
        ['Omitting all CSI leaves fewer than three bits. The short-resource ' ...
         'transition must be resolved explicitly; do not pad or use a long-format shortcut.']);
    [resource,budget]=rrc.allocateResource(id,context,slot0,"dynamic_harq_csi_omission");
    if ~isempty(resource), return; end
end
end

function value=localCSISelection(requested,transmitted)
before=requested.Data.CSIReports; after=transmitted.Data.CSIReports;
if isa(before,'sixgr.phy.pucch.CSIReportState'), before=arrayfun(@(x)x.Data,before); end
if isa(after,'sixgr.phy.pucch.CSIReportState'), after=arrayfun(@(x)x.Data,after); end
beforeIDs=[]; afterIDs=[];
if ~isempty(before), beforeIDs=[before.ReportID]; end
if ~isempty(after), afterIDs=[after.ReportID]; end
omitted=setdiff(beforeIDs,afterIDs,'stable');
reason="all_requested_reports_selected";
if isempty(beforeIDs), reason="no_csi_requested";
elseif ~isempty(omitted), reason="whole_reports_omitted_by_capacity"; end
value=struct('RequestedReportIDs',beforeIDs,'TransmittedReportIDs',afterIDs, ...
    'OmittedReportIDs',omitted,'Reason',reason,'Authority',"UE_transmit_selection_not_receiver_evidence");
end
