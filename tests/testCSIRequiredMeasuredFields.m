function ok=testCSIRequiredMeasuredFields()
% Explicit schema fixtures; these are not measured campaign CSI values.
for channel=["PUCCH","PUSCH"]
    request=struct('ReportConfigID',"required-fields-fixture",'Epoch',0, ...
        'CodebookType',"typeI-SinglePanel",'Ports',2,'Rank',1, ...
        'ReportQuantity',"cri-RI-PMI-CQI",'NumCSIResources',1, ...
        'FrequencyGranularity',"wideband",'UCIChannel',channel);
    config=sixgr.phy.mimo.CSIReportConfiguration(request,0);
    values=struct('RI',1,'CQI_CW0',9,'PMI',0);
    report=config.build(values); % Zero-width CRI/LI need no evidence bits.
    decoded=config.decode(report.Part1Bits,report.Part2Bits);
    assert(decoded.CQI_CW0==9 && decoded.PMI==0 && decoded.RI==1);
    for missing=["RI","CQI_CW0","PMI"]
        localReject(@()config.build(rmfield(values,missing)));
        absent=values; absent.(missing)=[];
        localReject(@()config.build(absent));
    end
    request.Ports=4; request.N1=2; request.N2=1;
    request.O1=4; request.O2=1; request.MaxRank=2; request.CodebookMode=1;
    config=sixgr.phy.mimo.CSIReportConfiguration(request,0);
    values=struct('RI',1,'CQI_CW0',9,'PMI_I11',3,'PMI_I2',2);
    report=config.build(values);
    decoded=config.decode(report.Part1Bits,report.Part2Bits);
    assert(decoded.PMI_I11==3 && decoded.PMI_I2==2);
    for missing=["PMI_I11","PMI_I2"]
        localReject(@()config.build(rmfield(values,missing)));
    end
end
ok=true;
end

function localReject(call)
try, call(); catch cause
    assert(strcmp(cause.identifier,'sixgr:mimo:MissingCSIReportMeasurement'), ...
        'Expected missing CSI evidence rejection, got %s: %s',cause.identifier,cause.message);
    return;
end
error('test:MissingError','Missing CSI fields were silently serialized.');
end
