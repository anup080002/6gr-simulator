function tests=TestPublicFigureDefinitions
%TESTPUBLICFIGUREDEFINITIONS Focused production-component figure checks.
tests=functiontests(localfunctions);
end

function setupOnce(testCase)
root=string(tempname);mkdir(root);mkdir(fullfile(root,'raw'));mkdir(fullfile(root,'raw','campaign_a_reference_area'));
testCase.TestData.Root=root;
testCase.TestData.Scenario=sixgr.ntn.resilientsync.buildScenario('configs/ntn_resilient_sync/quick.yaml');
testCase.TestData.A=sixgr.ntn.resilientsync.runCampaign(testCase.TestData.Scenario,'A',root);
testCase.TestData.E=sixgr.ntn.resilientsync.runCampaign(testCase.TestData.Scenario,'E',root);
end

function teardownOnce(testCase)
root=char(testCase.TestData.Root);
if startsWith(string(root),string(tempdir))&&isfolder(root),rmdir(root,'s');end
end

function testHoldoverTdocRegression(testCase)
h=testCase.TestData.A.Tables.gnss_degraded_holdover;
h=h(h.CarrierId=="S_band"&h.Oscillator_ppm==min(h.Oscillator_ppm)&h.PositionAge_s==60,:);
[~,order]=sort(h.Speed_m_s);actual=abs(h.ULRPArrivalError_s(order))*1e6;
testCase.verifyEqual(actual,[.689152;3.289027;11.955276;24.473192],AbsTol=2e-6);
end

function testAbsoluteRTTKOffsetHierarchy(testCase)
k=testCase.TestData.E.Tables.k_offset_samples;k=k(k.SCS_kHz==120,:);
actual=[mean(k.UEExcessDelay_s),prctile(k.UEExcessDelay_s,95),max(k.UEExcessDelay_s); ...
    mean(k.BeamExcessDelay_s),prctile(k.BeamExcessDelay_s,95),max(k.BeamExcessDelay_s); ...
    mean(k.CellExcessDelay_s),prctile(k.CellExcessDelay_s,95),max(k.CellExcessDelay_s)]*1e3;
expected=[.070 .122 .125;.193 .344 .439;5.834 9.121 9.122];
testCase.verifyEqual(actual,expected,AbsTol=.0025);
testCase.verifyTrue(all(k.CellConfiguredDelay_s>=k.BeamConfiguredDelay_s));
testCase.verifyTrue(all(k.BeamConfiguredDelay_s>=k.UEConfiguredDelay_s));
end

function testAbsoluteRTTPipeline(testCase)
p=testCase.TestData.E.Tables.timing_pipeline;p=p(p.SCS_kHz==120,:);
actual=[mean(p.UEPipelineSlots),prctile(p.UEPipelineSlots,95),max(p.UEPipelineSlots); ...
    mean(p.BeamPipelineSlots),prctile(p.BeamPipelineSlots,95),max(p.BeamPipelineSlots); ...
    mean(p.CellPipelineSlots),prctile(p.CellPipelineSlots,95),max(p.CellPipelineSlots)];
expected=[66.9 112 113;67.9 113 113;113 113 113];
testCase.verifyEqual(actual,expected,AbsTol=.1);
end

function testRTTUpdateTimeScale(testCase)
t=testCase.TestData.E.Tables.rtt_update_timescale;
testCase.verifyEqual(unique(t.SCS_kHz).',[30 60 120]);
testCase.verifyTrue(all(t.TimeToOneSlot_s>0&isfinite(t.TimeToOneSlot_s)));
for scs=[30 60 120]
    row=t(t.SCS_kHz==scs,:);testCase.verifyGreaterThan(row.TimeToOneSlot_s(end),row.TimeToOneSlot_s(1));
end
end
