function ok=testCSIWireQualification()
% Wire/metadata fixtures only; no measured RF or complete CSI conformance claim.
setup6GRSimToolkit('Verbose',false);
for channel=["PUCCH","PUSCH"]
    request=struct('ReportConfigID',"qualified-wire",'Epoch',3, ...
        'CodebookType',"typeI-SinglePanel",'Ports',2,'Rank',2,'MaxRank',2, ...
        'ReportQuantity',"cri-RI-PMI-CQI",'NumCSIResources',2, ...
        'FrequencyGranularity',"wideband",'UCIChannel',channel);
    config=sixgr.phy.mimo.CSIReportConfiguration(request,3);
    report=config.build(struct('CRI',1,'RI',2,'PMI',1,'CQI_CW0',9));
    csi=struct('TypedReport',report,'CSIReportConfiguration',config);
    payload=sixgr.phy.dl.packCSIFeedbackPayload(csi,struct('Strict',true));
    assert(payload.BitExactSupported && ~payload.CustomContainerUsed && ...
        isequal(payload.Bits,uint8([report.Part1Bits;report.Part2Bits])));
    assert(payload.SeparateEncoding==(channel=="PUSCH"));
    localReject(@()sixgr.phy.dl.packCSIFeedbackPayload(rmfield(csi,'CSIReportConfiguration'),struct()), ...
        'sixgr:mimo:MissingCSIReportConfig');
    for field=["ReportConfigID","ConfigurationEpoch","Part1Owners"]
        bad=csi;
        if field=="ReportConfigID", bad.TypedReport.(field)="wrong-report";
        elseif field=="ConfigurationEpoch", bad.TypedReport.(field)=4;
        else, bad.TypedReport.(field)(1)="forged_owner";
        end
        localReject(@()sixgr.phy.dl.packCSIFeedbackPayload(bad,struct()), ...
            'sixgr:mimo:CSISerializationMismatch');
    end
    bad=csi; bad.TypedReport.Part1Bits=double(report.Part1Bits);
    bad.TypedReport.Part1Bits(1)=.5;
    localReject(@()sixgr.phy.dl.packCSIFeedbackPayload(bad,struct()), ...
        'sixgr:mimo:CSIDeserializationMismatch');
    % Caller-supplied CSI object must not override active runtime authority.
    active=request; active.ReportConfigID="new-active-report";
    localReject(@()sixgr.phy.dl.packCSIFeedbackPayload(csi,struct('ReportConfiguration',active)), ...
        'sixgr:mimo:CSISerializationMismatch');
    % A stale prior rank is not used to size a supplied received-rank report.
    active=request; active.Rank=1;
    payload=sixgr.phy.dl.packCSIFeedbackPayload(csi,struct('ReportConfiguration',active));
    assert(isequal(payload.Bits,uint8([report.Part1Bits;report.Part2Bits])));
end
% Multiport strict packing without a prebuilt TypedReport must retain the
% measured component tuple, not replace it with a scalar/custom PMI token.
request.Ports=4; request.N1=2; request.N2=1; request.O1=4; request.O2=1;
request.CodebookMode=1;
config=sixgr.phy.mimo.CSIReportConfiguration(request,3);
csi=struct('CRI',1,'RI',2,'CQI',9,'PMI_I11',3,'PMI_I13',1,'PMI_I2',1);
payload=sixgr.phy.dl.packCSIFeedbackPayload(csi,struct('Strict',true,'ReportConfigurationObject',config));
decoded=config.decode(payload.Part1Bits,payload.Part2Bits);
assert(decoded.PMI_I11==3 && decoded.PMI_I13==1 && decoded.PMI_I2==1);
% Every legacy advanced family may be inspected but may not generate or
% consume a made-up NR payload through the production serializer/decoder.
for cb=["typeI-MultiPanel","typeII","typeII-PortSelection","enhancedTypeII","enhancedTypeII-CJT"]
    request.CodebookType=cb; request.FrequencyGranularity="subband";
    config=sixgr.phy.mimo.CSIReportConfiguration(request,3);
    localReject(@()config.build(struct()),'sixgr:mimo:UnqualifiedCSIWireLayout');
    localReject(@()config.decode(zeros(config.part1BitCount(),1),zeros(config.part2BitCount(),1)), ...
        'sixgr:mimo:UnqualifiedCSIWireLayout');
    localReject(@()sixgr.phy.dl.packCSIFeedbackPayload(struct(), ...
        struct('Strict',true,'ReportConfigurationObject',config)), ...
        'sixgr:mimo:UnqualifiedCSIWireLayout');
end
legacy=struct('ChannelStateInformationMode',"CQI",'ReportCQI',true,'CQI',9);
for alias=["Strict","mimo","phy"]
    strictCfg=struct('Strict',false);
    if alias=="Strict", strictCfg.Strict=true;
    elseif alias=="mimo", strictCfg.mimo.strict=true;
    else, strictCfg.phy.mimo.strict=true;
    end
    localReject(@()sixgr.phy.dl.packCSIFeedbackPayload(legacy,strictCfg), ...
        'sixgr:mimo:MissingCSIReportConfig');
end
payload=sixgr.phy.dl.packCSIFeedbackPayload(legacy,struct());
assert(~payload.BitExactSupported && payload.CustomContainerUsed && ...
    string(payload.StandardProfile)=="legacy_custom_csi_container_not_3gpp_wire_format");
ok=true; disp('CSI_WIRE_QUALIFICATION_AND_REPORT_BINDING_PASS');
end

function localReject(fn,id)
try, fn(); catch err
    assert(strcmp(err.identifier,id),'Expected %s, got %s: %s',id,err.identifier,err.message); return;
end
error('test:ExpectedFailure','Expected %s.',id);
end
