function ok = testPDSCHReceiverWithoutTXPrecoder()
% Component trust-boundary fixture, NOT actual received-DCI qualification.
setup6GRSimToolkit('Verbose',false);
fixture = StrictPDSCHChainFixture.create(2,'NPRB',6,'TransportBlockSize',384);
data = fixture.Assignment.toStruct();
data.AssignmentId = data.AssignmentId + "-RX-BOUNDARY-FIXTURE";
data.Profile = "connected_strict";
data.Source = "decoded_dci+ue_context";
data.DecodedDCIId = "TEST-ONLY-RECEIVED-ASSIGNMENT";
data.ScheduledDCIId = "";
data.ControlAuthority = "receiver_crc_valid_decode";
data.DCIFormat = "1_1";
data.DCICRCPass = true;
data.DecodedRNTI = data.RNTI;
data.DCIRNTIMatch = true;
data.PDCCHAbsoluteSlot = data.PDSCHAbsoluteSlot;
data.K0 = 0;
data.SearchSpaceId = "TEST-SS";
data.CORESETId = "TEST-CORESET";
data.TCIStateId = 3;
data.TransmissionConfigurationIndication = 3;
assignment = sixgr.pdsch.PDSCHSchedulingAssignment(data);
context = StrictPDSCHChainFixture.integrationContext(assignment,fixture.PrecoderBundle);
% Test only Type-A installed association, without asserting Type-D execution.
context.ActivatedTCIStates.QCLTypes = "A";
context.ActivatedTCIStates.Assumptions = "delay_doppler";
context.ActivatedTCIStates = rmfield(context.ActivatedTCIStates, ...
    {'PrecoderContextId','PrecoderBundleDigest','PrecoderAssignmentId', ...
    'PrecoderAssignmentValidationDigest','PrecoderConfigurationEpoch'});
tx = sixgr.pdsch.PDSCHTransmitter(fixture.TransportBlocks,fixture.Assignment, ...
    fixture.ResourcePlan,fixture.Carrier,fixture.ReferenceConfig, ...
    'PrecoderBundle',fixture.PrecoderBundle);
receiver = rmfield(fixture.ReceiverConfig,'ReferenceChannelGain');
receiver.ChannelModel = 'STATIC-MIMO';
plan = sixgr.pdsch.DLSCHCodingPlan.resolve( ...
    'TransportBlockSize',receiver.TransportBlockSizes, ...
    'TargetCodeRate',assignment.get('TargetCodeRatePerCodeword'), ...
    'RV',assignment.get('RVPerCodeword'), ...
    'Modulation',assignment.get('ModulationPerCodeword'), ...
    'NumLayers',assignment.get('LayerCountPerCodeword'), ...
    'RateMatchedBitCount',fixture.ResourcePlan.GPerCodeword);
waveform = tx.Waveform * [1 .15i; .1 .8*exp(.4i)];
args = {assignment,fixture.ResourcePlan,fixture.Carrier, ...
    fixture.ReferenceConfig,receiver,'CodingPlans',plan};
rx = sixgr.pdsch.PDSCHReceiver(waveform,args{:},'IntegrationContext',context);
assert(rx.CRCPass && isequal(rx.TransportBlock,vertcat(fixture.TransportBlocks{:})));
assert(rx.IntegrationBinding.Status == "PASS" && ...
    ~rx.IntegrationBinding.PrecoderBinding.Required && ...
    rx.IntegrationBinding.PrecoderBinding.Status == "NOT_EVALUATED" && ...
    rx.IntegrationBinding.PrecoderBinding.PrecoderBundleDigest == "");
assert(rx.IntegrationBinding.ReceiverQCL.QCLTypes == "A" && ...
    rx.IntegrationBinding.ReceiverQCL.TCIStateId == 3);
assert(isequal(size(rx.EffectiveLayerChannelEstimate),[72 14 2 2]) && ...
    all(isfinite(rx.EffectiveLayerChannelEstimate(:))) && ...
    isempty(rx.ChannelGainPerPhysicalPort) && ~rx.EstimatorUsesTrueChannel);

bad = context; bad.ConfigurationEpoch = bad.ConfigurationEpoch + 1;
localReject(@() sixgr.pdsch.PDSCHReceiver(waveform,args{:}, ...
    'IntegrationContext',bad),'sixgr:pdsch:StaleUEConfigurationEpoch');
bad = context; bad.ActiveBWPId = bad.ActiveBWPId + 1;
localReject(@() sixgr.pdsch.PDSCHReceiver(waveform,args{:}, ...
    'IntegrationContext',bad),'sixgr:pdsch:MissingActiveBWPContext');
bad = context; bad.ActivatedTCIStates.Activated = false;
localReject(@() sixgr.pdsch.PDSCHReceiver(waveform,args{:}, ...
    'IntegrationContext',bad),'sixgr:pdsch:TCIStateNotActivated');
localReject(@() sixgr.pdsch.PDSCHReceiver(waveform,args{:}), ...
    'sixgr:pdsch:MissingIntegrationContext');
% Supplying a TX matrix still requires its complete matching binding.
localReject(@() sixgr.pdsch.PDSCHReceiver(waveform,args{:}, ...
    'IntegrationContext',context,'PrecoderBundle',fixture.PrecoderBundle), ...
    'sixgr:pdsch:MissingPrecoderTCIBinding');
bound = StrictPDSCHChainFixture.integrationContext(assignment,fixture.PrecoderBundle);
bound.ActivatedTCIStates.PrecoderBundleDigest = "STALE";
localReject(@() sixgr.pdsch.PDSCHReceiver(waveform,args{:}, ...
    'IntegrationContext',bound,'PrecoderBundle',fixture.PrecoderBundle), ...
    'sixgr:pdsch:StalePrecoderTCIContext');
% The common validator's explicit third argument remains fail-closed.
localReject(@() sixgr.pdsch.PDSCHIntegrationValidator.bind(assignment,context,[]), ...
    'sixgr:pdsch:MissingPrecoderTCIBinding');
fprintf('PDSCH_RX_WITHOUT_TX_PRECODER_PASS bits=384 bit_errors=0 guards=7\n');
ok = true;
end

function localReject(fn,identifier)
try
    fn();
catch ME
    assert(string(ME.identifier)==string(identifier), ...
        'Expected %s, received %s: %s',identifier,ME.identifier,ME.message);
    return;
end
error('testPDSCHReceiverWithoutTXPrecoder:ExpectedFailure', ...
    'Expected %s.',identifier);
end
