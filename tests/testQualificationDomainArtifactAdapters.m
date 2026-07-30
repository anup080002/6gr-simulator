function tests=testQualificationDomainArtifactAdapters
tests=functiontests(localfunctions);
end

function testFrameGridObservedFieldsMapWithoutConfiguredBackfill(testCase)
source=table(["GRID-1";"GRID-2"],[100;50],[30;15],[273;270], ...
    [845000;425000],[845000;425000], ...
    'VariableNames',{'TestID','ChannelBandwidth_MHz', ...
    'CarrierSCS_kHz','ResolvedNRB','GuardbandLow_Hz', ...
    'GuardbandHigh_Hz'});
required=["CaseID","Bandwidth_MHz","SCS_kHz","NSizeGrid", ...
    "Guardband_kHz"];
hash=string(repmat('b',1,64));
[adapted,trace]=sixgr.integration.qualification. ...
    QualificationDomainArtifactAdapter.adapt( ...
    "carrier_grid_matrix.csv",source,required,hash);
verifyEqual(testCase,adapted.CaseID,source.TestID);
verifyEqual(testCase,adapted.Bandwidth_MHz, ...
    source.ChannelBandwidth_MHz);
verifyEqual(testCase,adapted.Guardband_kHz,[845;425]);
verifyEqual(testCase,height(adapted),height(source));
verifyTrue(testCase,all(trace.Lossless));
verifyTrue(testCase,all(trace.RowsIn==height(source)));
verifyTrue(testCase,all(trace.RowsOut==height(source)));
verifyFalse(testCase,contains(lower(strjoin( ...
    trace.TransformationFormula,"|")),"config"));
end

function testObservedRenameIsLosslessAndProvenanced(testCase)
source=table([0.01;0.02],'VariableNames',{'NMSE'});
hash=string(repmat('a',1,64));
[adapted,trace]=sixgr.integration.qualification. ...
    QualificationDomainArtifactAdapter.adapt( ...
    "waveform_ofdm_roundtrip.csv",source,"GridNMSE",hash);
verifyEqual(testCase,adapted.GridNMSE,source.NMSE);
verifyTrue(testCase,all(trace.Lossless));
verifyEqual(testCase,trace.SourceArtifactSHA256,hash);
verifyEqual(testCase,trace.TransformationFormula, ...
    "lossless_rename(NMSE)");
end
