function ok=testCSIReportQuantityAuthority()
% Declared component measurements exercise the actual strict CSI facade
% and typed codec. No waveform, received UCI, spatial-choice reliability or
% standardized measurement-accuracy claim is made by this policy test.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
checks={@singletonPolicy,@zeroWidthRI,@quantityPolicyMismatch, ...
    @()legacyAlias("cri-cqi"),@()legacyAlias("cqi"),@multiportAliases,@partialPMIPolicy};
names=["singleton_implicit_RI","configured_zero_width_RI","policy_guard", ...
    "CRI_CQI_inspection_only","CQI_inspection_only","multiport_alias_guard", ...
    "partial_PMI_i1_policy_inspection"];
passed=false(size(checks));
for k=1:numel(checks)
    try
        checks{k}(); passed(k)=true;
        fprintf('CSI_REPORT_QUANTITY_PASS %s\n',names(k));
    catch cause
        fprintf(2,'CSI_REPORT_QUANTITY_FAIL %s %s: %s\n', ...
            names(k),cause.identifier,cause.message);
    end
end
assert(all(passed),'test:CSIReportQuantityAuthority', ...
    'CSI report quantity checks passed %d/%d.',nnz(passed),numel(passed));
fprintf('CSI_REPORT_QUANTITY_AUTHORITY_PASS groups=%d waveform=0 received_UCI=0\n',numel(checks));
ok=true;
end

function singletonPolicy()
[cfg,measurement,request]=fixture(1,"cri-ri-cqi");
typed=sixgr.phy.mimo.CSIReportConfiguration(request,request.Epoch);
policy=typed.reportingPolicy();
assert(policy.ReportRI&&policy.ReportCRI&&policy.ReportCQI&&~policy.ReportPMI);
assert(~any([typed.Part1Fields typed.Part2Fields]=="RI")&& ...
    typed.part1BitCount()==4&&typed.part2BitCount()==0);
[csi,info]=sixgr.phy.dl.CSI_Feedback(measurement.ChannelEstimate, ...
    measurement.NoiseVariance,cfg,'MeasurementState',measurement);
assert(csi.ReportRI&&csi.RI==1&&csi.ReportCRI&&csi.ReportCQI&&~csi.ReportPMI&& ...
    numel(csi.CSIPart1Bits)==4&&isempty(csi.CSIPart2Bits)&& ...
    ~any(csi.TypedReport.Part1Owners=="RI")&& ...
    ~any(startsWith(csi.TypedReport.Part1Owners,"PMI"))&& ...
    csi.CSIPayloadBitExactSupported&&~csi.ConfiguredOracleUsed&& ...
    ~info.ConfiguredSNRUsed&&csi.MeasurementID==measurement.MeasurementID);
decoded=csi.CSIReportConfiguration.decode(csi.CSIPart1Bits,csi.CSIPart2Bits);
assert(decoded.RI==1&&decoded.CQI_CW0==csi.CQI);
end

function zeroWidthRI()
[cfg,measurement,request]=fixture(2,"cri-ri-pmi-cqi");
typed=sixgr.phy.mimo.CSIReportConfiguration(request,request.Epoch);
ri=find(typed.Part1Fields=="RI");
policy=typed.reportingPolicy();
assert(isscalar(ri)&&typed.Part1Widths(ri)==0&&policy.ReportRI);
csi=sixgr.phy.dl.CSI_Feedback(measurement.ChannelEstimate, ...
    measurement.NoiseVariance,cfg,'MeasurementState',measurement);
assert(csi.ReportRI&&csi.RI==1&&csi.ReportPMI&& ...
    ~any(csi.TypedReport.Part1Owners=="RI")&& ...
    any(csi.TypedReport.Part1Owners=="PMI")&&csi.CSIPayloadBitExactSupported);
assert(csi.PrecoderMatrixSHA256==sixgr.phy.mimo.MatrixContract.digest( ...
    cfg.phy.csi.candidateMatricesByRank{1}));
end

function quantityPolicyMismatch()
[cfg,measurement]=fixture(1,"cri-ri-cqi");
% A consistent disabled flag/authority still contradicts the installed
% quantity. The strict post-selection guard must reject, not hide RI.
cfg.phy.csi.reportRI=false;
cfg.runtime.features.ri_reporting.Enabled=false;
reject(@()sixgr.phy.dl.CSI_Feedback(measurement.ChannelEstimate, ...
    measurement.NoiseVariance,cfg,'MeasurementState',measurement), ...
    'sixgr:config:YAMLFeatureExecutionMismatch');
end

function legacyAlias(quantity)
[~,~,request]=fixture(1,quantity);
typed=sixgr.phy.mimo.CSIReportConfiguration(request,request.Epoch);
policy=typed.reportingPolicy();
assert(policy.ReportCQI&&~policy.ReportRI&&~policy.ReportPMI&& ...
    policy.ReportCRI==(quantity=="cri-cqi"));
assert(~any([typed.Part1Fields typed.Part2Fields]=="RI")&&typed.part1BitCount()==4);
reject(@()typed.assertQualifiedWireLayout(),'sixgr:mimo:UnqualifiedCSIWireLayout');
values=struct('CRI',0,'RI',1,'CQI_CW0',7,'PMI',0);
reject(@()typed.build(values),'sixgr:mimo:UnqualifiedCSIWireLayout');
csi=struct('CSIReportConfiguration',typed,'ChannelStateInformationMode',quantity);
reject(@()sixgr.phy.dl.packCSIFeedbackPayload(csi,struct('Strict',true)), ...
    'sixgr:mimo:UnqualifiedCSIWireLayout');
end

function multiportAliases()
for quantity=["cri-cqi","cqi"]
    [~,~,request]=fixture(2,quantity);
    reject(@()sixgr.phy.mimo.CSIReportConfiguration(request,request.Epoch), ...
        'sixgr:mimo:UnsupportedCSIReportLayout');
end
end

function partialPMIPolicy()
% Report-quantity/schema inspection only, not a received four-port i1
% report or qualification of its physical transmission/decoding.
for quantity=["cri-ri-i1","cri-ri-i1-cqi"]
    [~,~,request]=fixture(2,quantity);
    request.Ports=4; request.N1=2; request.O1=4; request.CodebookMode=1;
    typed=sixgr.phy.mimo.CSIReportConfiguration(request,request.Epoch);
    policy=typed.reportingPolicy();
    fields=[typed.Part1Fields typed.Part2Fields];
    assert(policy.ReportPMI&&policy.ReportRI&&policy.ReportCRI&& ...
        policy.ReportCQI==endsWith(quantity,"-cqi")&& ...
        any(fields=="PMI_I11")&&~any(fields=="PMI_I2"));
end
end

function [cfg,measurement,request]=fixture(ports,quantity)
request=struct('ReportConfigID',"declared-quantity-component",'Epoch',0, ...
    'CodebookType',"typeI-SinglePanel",'Ports',ports,'Rank',1, ...
    'MaxRank',1,'AllowedRanks',1,'ReportQuantity',quantity, ...
    'NumCSIResources',1,'FrequencyGranularity',"wideband", ...
    'UCIChannel',"PUCCH",'ConfiguredUCIChannel',"PUCCH", ...
    'N1',1,'N2',1,'O1',1,'O2',1);
cfg=struct();
cfg.phy.mimo=struct('strict',true,'N1',1,'N2',1,'O1',1,'O2',1);
cfg.phy.linkAdaptation.rankPolicy='measured_ri';
cfg.phy.csi=struct('maxRank',1,'rankDomain',1,'reportCSI',true, ...
    'reportCQI',true,'reportPMI',contains(quantity,'pmi'), ...
    'reportRI',true,'reportCRI',true,'reportConfiguration',request, ...
    'reportConfigurationEpoch',0);
if ports==1
    H=[1;.3i]; candidate=1;
else
    H=[1 .2;.1 .85];
    candidate=sixgr.phy.mimo.TypeI2PortCodebook.matrix(1,0);
end
cfg.phy.csi.candidateMatricesByRank={candidate};
cfg.runtime.currentSlot=3;
% Explicit declared feature-authority boundary, not an authored claim of
% actual received control or a substituted resolved scenario.
for pair=["csi_reporting","cqi_reporting","pmi_reporting","ri_reporting","cri_reporting"; ...
        "reportCSI","reportCQI","reportPMI","reportRI","reportCRI"]
    cfg.runtime.features.(pair(1))=struct('Enabled',cfg.phy.csi.(pair(2)), ...
        'SourceYAMLPath',"declared_component."+pair(1));
end
measurement=sixgr.phy.mimo.CSIMeasurementState( ...
    MeasurementID="declared-quantity-measurement",UEID="UE1", ...
    ResourceType="NZP-CSI-RS",ResourceID="CSI-RS-0",ResourceOrdinal=0, ...
    Slot=3,MaxAgeSlots=0,ChannelEstimate=H,NoiseVariance=.02, ...
    Provenance="measured_declared_component_policy_fixture");
end

function reject(fn,identifier)
try
    fn();
catch cause
    assert(strcmp(cause.identifier,identifier),'test:CSIQuantityWrongRejection', ...
        'Expected %s, got %s: %s',identifier,cause.identifier,cause.message);
    return;
end
error('test:CSIQuantityMissingRejection','Expected %s.',identifier);
end
