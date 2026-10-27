function [ok,fixture]=testNRRRCSetupAttemptState()
% Actual UPER/common installation; receive-clock flags are declared inputs.
% This tests the timer/request owner, not RF reception or reset execution.
source=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_tdd_n40_20mhz_64txru_4rx_cdlc100_impaired.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(source,tempname);
tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
[bits,encoded]=sixgr.rrc.asn1.encodeSIB1UPER(tree);
tree=sixgr.rrc.asn1.decodeSIB1UPER(bits);
[~,hash]=sixgr.rrc.asn1.compareSIB1Trees(tree,tree);
rx=struct('StrictOk',true,'DCICrcPass',true,'DLSCHCrcPass',true, ...
    'SIB1ASN1DecodeOk',true,'SIB1SemanticValid',true,'SIB1RxTree',tree, ...
    'SIB1PayloadHashRx',encoded.PayloadHash,'SIB1RxTreeHash',hash.RxTreeHash, ...
    'ReferenceConfigurationEpoch',2,'MeasurementClockEpoch',3,'OriginalServingCell',1, ...
    'ReceivedSIB1AvailableAtSample',100);
installed=sixgr.mac.ra.installDecodedSIB1RACHConfig(cfg,rx);
common=installed.UECommonCellConfiguration;common.ServingCell=1;common.ConfigurationEpoch=2;
policy=sixgr.lls6g.config.resolveNRAccessPolicy(struct( ...
    'encoding_profile',"nr_rrc_access_base_srb1_uper_v1", ...
    'require_setup_complete',true,'transaction_id',2,'srb1_lcid',1, ...
    'establishment_cause',"mo-Signalling",'selected_plmn_identity',1,'dedicated_nas_hex',"7E0041"));
context=struct('RunID',"declared_RRC_component",'UEIndex',1,'ServingCell',1, ...
    'ConfigurationEpoch',3,'SampleRateHz',30.72e6,'StartSample',1000);
before=rng;stream=RandStream('mt19937ar','Seed',41);
a=sixgr.mac.ra.NRRRCSetupAttemptState(policy,common,rx,context,stream);
assert(isequal(before,rng)&&a.Request.EncodingProfile==policy.EncodingProfile);
original=a.Request;deadline=a.ExpirySampleExclusive;
for attempt=1:3
    ra=struct('RunId',"MAC_attempt_"+attempt,'UEId',1,'ServingCell',1);
    a=a.bindMACAttempt(ra,1000+attempt);
    assert(isequaln(a.Request,original)&&a.ExpirySampleExclusive==deadline);
end
assert(numel(a.MACAttemptRunIDs)==3);
reject(@()a.bindMACAttempt(ra,1004));
reject(@()a.expire(deadline-1));
[expired,receipt]=a.expire(deadline);
assert(expired.Status=="t300_expired_pending_reset"&&receipt.Expired&& ...
    ~receipt.ResetExecuted&&receipt.ApplicationBytesDropped==0&& ...
    isequal(expired.Request,original));
reject(@()expired.expire(deadline));
bad=rx;bad.ReceivedSIB1AvailableAtSample=context.StartSample+1;
reject(@()sixgr.mac.ra.NRRRCSetupAttemptState(policy,common,bad,context,stream));
bad=common;bad.UETimersAndConstants.t300="ms2000";
if bad.UETimersAndConstants.t300==common.UETimersAndConstants.t300,bad.UETimersAndConstants.t300="ms100";end
reject(@()sixgr.mac.ra.NRRRCSetupAttemptState(policy,bad,rx,context,stream));
bad=rx;bad.OriginalServingCell=2;
reject(@()sixgr.mac.ra.NRRRCSetupAttemptState(policy,common,bad,context,stream));
new=sixgr.mac.ra.NRRRCSetupAttemptState(policy,common,rx,context,stream);
assert(new.Request.RRCSetupRequestSHA256~=original.RRCSetupRequestSHA256);
fixture=struct('Config',cfg,'OriginalCommon',common,'OriginalRecovery',rx, ...
    'WaitingAttempt',a,'ExpiredAttempt',expired,'Expiry',receipt);
ok=true;
fprintf('NR_RRC_ATTEMPT_STATE_PASS exact_T300=1 stable_request_across_MAC_retries=1 reset_execution=0 RF=0\n');
end
function reject(f)
try,f();catch e,assert(string(e.identifier)=="sixgr:rrc:InitialAttemptAuthority");return;end
error('test:NRInitialAttemptGuard','Invalid RRC attempt boundary accepted.');
end
