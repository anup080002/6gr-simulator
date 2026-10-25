function ok=testReceivedCommonMIBRACHAuthority(mode,cfg,recovery,binding)
% Original receiver evidence -> decoded common configuration -> RAR reference.
% No-argument entry reuses one actual shared BCH/later-SI monitoring test.
% The optional combined branch is called by testReceivedMIBDelivery with its
% original combined decoder result. No receiver rerun, PRACH/RAR waveform,
% on-air association qualification or fabricated decoded-MIB success here.
if nargin==0
    ok=testReceivedMIBSIMonitoring(); return;
end
assert(nargin==4 && any(string(mode)==["split","combined"]));
mode=string(mode);
original=recovery; beforeRNG=rng;
beforeCalls=sixgr.runtime.RuntimeCallLedger.snapshot();
sixgr.truth.ReceivedMIBDelivery.validate(binding,true);
assert(isfield(recovery,'ReceivedMIBBinding') && ...
    isequaln(recovery.ReceivedMIBBinding,binding));
[installed,~]=sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,recovery);
common=installed.UECommonMIBConfiguration;
reference=sixgr.phy.ra.resolveRARDCIReference(installed);
d=binding.Context.Data;
assert(common.Source=="decoded_mib_bch_transport_block" && ...
    common.ReceptionRelationship=="retained_original_delivered_BCH_for_received_SI" && ...
    common.ReceivedMIBContextSHA256==binding.ContextSHA256 && ...
    common.ReceivedMIBGenerationID==binding.GenerationID && ...
    common.ReceivedMIBDeliverySHA256==binding.DeliverySHA256 && ...
    common.BCHTransportBlockHash==string(d.MIB.TransportBlockHash) && ...
    common.MIBAvailableAtSample==binding.DeliveredAvailableSample && ...
    common.DMRSTypeAPosition==d.MIB.DMRSTypeAPosition && ...
    common.NCellID==d.NCellID && common.SSBIndex==d.SSBIndex && ...
    reference.FrequencyReferenceSource=="decoded_mib_coreset0" && ...
    reference.DMRSTypeAPosition==d.MIB.DMRSTypeAPosition && ...
    reference.FrequencyReferenceSize==recovery.CORESET0NumRB && ...
    reference.FrequencyReferenceStart==recovery.CORESET0RBStart);

% Configured MIB disagreement must not replace the actual received bits.
% These are semantic TX fields, not the frozen receiver tuning/geometry.
changed=cfg;
changed.phy.mib.dmrsTypeAPosition=5-double(d.MIB.DMRSTypeAPosition);
changed.phy.mib.pdcchConfigSIB1=mod(double(d.MIB.PDCCHConfigSIB1)+1,256);
changed=sixgr.mac.ra.installDecodedSIB1RACHConfig(changed,recovery);
assert(isequaln(changed.UECommonMIBConfiguration,common) && ...
    isequaln(sixgr.phy.ra.resolveRARDCIReference(changed),reference));

% No generation, PCI, tuning or Type0 change is rescued from YAML/defaults.
for name=["ReceivedMIBGenerationID","ReceivedMIBDeliverySHA256"]
    bad=recovery; bad.(name)="changed_original_identity";
    reject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,bad), ...
        'sixgr:mac:ra:ReceivedCommonMIBIdentityMismatch');
end
for name=["ReferenceConfigurationEpoch","MeasurementClockEpoch","OriginalServingCell"]
    bad=recovery; bad.(name)=bad.(name)+1;
    reject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,bad), ...
        'sixgr:mac:ra:ReceivedCommonMIBIdentityMismatch');
end
bad=recovery; bad.ReceivedMIBBinding.ContextSHA256="changed_context";
reject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,bad), ...
    'sixgr:truth:InvalidReceivedMIBDelivery');
bad=recovery; bad.ReceivedMIBBinding.DeliveredAvailableSample= ...
    bad.ReceivedMIBBinding.DeliveredAvailableSample+1;
reject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,bad), ...
    'sixgr:truth:InvalidReceivedMIBDelivery');
changed=cfg; changed.phy.carrier.NCellID=mod(d.NCellID+1,1008);
reject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(changed,recovery), ...
    'sixgr:phy:broadcast:ReceivedMIBCellMismatch');
changed=cfg; changed.initial_access.configuration_epoch= ...
    changed.initial_access.configuration_epoch+1;
reject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(changed,recovery), ...
    'sixgr:phy:broadcast:ReceivedMIBGeometryChanged');
changed=cfg; changed.initial_access.type0.note17_band= ...
    ~sixgr.util.structGet(changed,'initial_access.type0.note17_band',false);
reject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(changed,recovery), ...
    'sixgr:phy:broadcast:ReceivedMIBGeometryChanged');
for name=["CORESET0NumRB","CORESET0RBStart"]
    bad=recovery; bad.(name)=bad.(name)+1;
    reject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,bad), ...
        'sixgr:mac:ra:ReceivedCommonMIBType0Mismatch');
end
for name=["StrictOk","DCICrcPass","DLSCHCrcPass","SIB1ASN1DecodeOk","SIB1SemanticValid"]
    bad=recovery; bad.(name)=false;
    reject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,bad), ...
        'sixgr:mac:ra:InvalidReceivedCommonMIB');
end

if mode=="split"
    assert(isfield(recovery,'PriorBCHContextSHA256') && ...
        ~recovery.NewBCHReceptionAttempted && ...
        ~any(isfield(recovery,{'MIBDecoded','BCHCrcPass','BCHCRCValid'})), ...
        'A later SI-only result must not acquire a new BCH success claim.');
    for spoof=[false true]
        bad=rmfield(recovery,'ReceivedMIBBinding');
        if spoof
            bad.MIBDecoded=true; bad.BCHCrcPass=true;
            bad.MIBDMRSTypeAPosition=d.MIB.DMRSTypeAPosition;
        end
        reject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,bad), ...
            'sixgr:mac:ra:MissingReceivedMIBBinding');
    end
    for name=["PriorBCHContextSHA256","PriorReceivedNCellID","PriorReceivedSSBIndex"]
        bad=recovery;
        if name=="PriorBCHContextSHA256", bad.(name)="changed_prior_context";
        else, bad.(name)=bad.(name)+1; end
        reject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,bad), ...
            'sixgr:mac:ra:ReceivedCommonMIBIdentityMismatch');
    end
    bad=recovery; bad.PDCCHConfigSIB1=mod(bad.PDCCHConfigSIB1+1,256);
    reject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,bad), ...
        'sixgr:mac:ra:ReceivedCommonMIBType0Mismatch');
    assert(binding.DeliveredAvailableSample>0);
    bad=recovery; bad.SIB1CaptureStartSample=binding.DeliveredAvailableSample-1;
    reject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,bad), ...
        'sixgr:mac:ra:ReceivedCommonMIBAvailabilityMismatch');
    bad=recovery; bad.ReceivedSIB1AvailableAtSample= ...
        bad.SIB1CaptureStartSample+bad.SIB1AvailableCaptureSamples-1;
    reject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,bad), ...
        'sixgr:mac:ra:ReceivedCommonMIBAvailabilityMismatch');
    bad=recovery; bad.SampleRateHz=bad.SampleRateHz+1;
    reject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,bad), ...
        'sixgr:mac:ra:ReceivedCommonMIBAvailabilityMismatch');
else
    % Reuse actual combined BCH/SI outcomes, not a manufactured MIB fixture.
    legacy=rmfield(recovery,'ReceivedMIBBinding');
    old=sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,legacy);
    oldReference=sixgr.phy.ra.resolveRARDCIReference(old);
    assert(isequaln(oldReference,reference) && ...
        old.UECommonMIBConfiguration.ReceptionRelationship=="original_combined_BCH_and_SI_result");
    compact=legacy;
    for name=["BCHCRCValid","CandidateIdentityConsistent","SSBIdentityVerified"]
        if isfield(compact,name), compact=rmfield(compact,name); end
    end
    compact=sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,compact);
    assert(isequaln(sixgr.phy.ra.resolveRARDCIReference(compact),reference), ...
        'Original compact combined capsules retain their existing decoded-MIB authority.');
    for name=["BCHCRCValid","CandidateIdentityConsistent","SSBIdentityVerified"]
        bad=legacy; bad.(name)=false;
        reject(@()sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,bad), ...
            'sixgr:mac:ra:InvalidReceivedCommonMIB');
    end
end

% Declared legacy-API boundary only: explicit absent CORESET0 selects the
% decoded initial DL BWP. This is not another physical no-CORESET reception.
legacy=struct('MIBDecoded',true,'BCHCrcPass',true, ...
    'MIBDMRSTypeAPosition',double(d.MIB.DMRSTypeAPosition),'CORESET0Present',false);
absent=sixgr.mac.ra.resolveReceivedCommonMIBConfiguration(struct(),legacy);
boundary=installed; boundary.UECommonMIBConfiguration=absent;
fallback=sixgr.phy.ra.resolveRARDCIReference(boundary);
assert(~absent.CORESET0Present && ~isfield(absent,'CORESET0NumRB') && ...
    fallback.FrequencyReferenceSource=="decoded_sib1_initial_dl_bwp" && ...
    fallback.FrequencyReferenceSize==installed.UECommonCellConfiguration.InitialDLBWP.SizeRB && ...
    fallback.FrequencyReferenceStart==installed.UECommonCellConfiguration.InitialDLBWP.StartRB);
missing=rmfield(installed,'UECommonMIBConfiguration');
reject(@()sixgr.phy.ra.resolveRARDCIReference(missing),'sixgr:phy:ra:MissingDecodedCommonMIB');
assert(isequaln(recovery,original) && isequal(rng,beforeRNG) && ...
    isequaln(sixgr.runtime.RuntimeCallLedger.snapshot(),beforeCalls), ...
    'Retained receiver projection must not run PHY or mutate the source evidence.');
fprintf('RECEIVED_COMMON_MIB_RACH_AUTHORITY_PASS mode=%s receiver_reruns=0 PRACH_RAR_waveforms=0\n',mode);
ok=true;
end

function reject(action,id)
try, action(); catch ex
    assert(strcmp(ex.identifier,id),'Expected %s, got %s: %s',id,ex.identifier,ex.message); return;
end
error('test:ExpectedReceivedCommonMIBRejection','Expected %s.',id);
end
