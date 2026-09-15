function ok=testNormalizedSSBPowerAuthority()
% Declared selector/codec inputs, not additional physical RF episodes.
s=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_pucch_baseline_signal_fixture.yaml');
cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
cfg.lls6g.userContext=struct();
assert(strcmpi(cfg.integration.run_mode,'FIXED_SNR_SWEEP') && ...
    cfg.integration.configured_snr_is_link_authority);
% The same received-power label transformation is used by full-burst and
% per-occasion SSB completion; it does not change RF samples or SINR.
raw=struct('SS_RSRP_dBm',-5,'SS_RSRPPerReceiveAntenna_dBm',"-5;-6", ...
    'SS_RSRPRawObserved_dBm',-4,'ReferenceSignalTxEPRE_dBm',0, ...
    'SS_SINR_dB',12,'BCHCrcPass',true,'SSBWindowPowerMeasurementJSON','{"dBm":-5}');
raw.SSPhysicalMeasurementStatus="available_rsrp_and_sinr";
raw.SSMeasurementFFTSize=512; raw.SSMeasurementGridScaleToSqrtW=512*sqrt(1000);
raw.ReferenceSignalTxMeasurementFFTSize=1024;
raw.ReferenceSignalTxMeasurementGridScaleToSqrtW=1024*sqrt(1000);
raw.ReferenceSignalTxMeasurementSource="declared_power_unit_fixture";
rxOffset=20*log10(512); txOffset=20*log10(1024);
relative=sixgr.link.normalizeReceivedSSBPowerReference(raw,cfg);
branches=str2double(split(relative.SS_RSRPPerReceiveAntenna_dB_re_UnitOccupiedRE_Es,';'));
assert(relative.SS_RSRP_dB_re_UnitOccupiedRE_Es==-5+rxOffset && ...
    max(abs(branches-([-5;-6]+rxOffset)))<1e-10 && ...
    relative.MeasuredReferenceSignalChannelGain_dB==(-5+rxOffset)-txOffset && isnan(relative.SS_RSRP_dBm) && ...
    relative.SS_SINR_dB==raw.SS_SINR_dB && relative.BCHCrcPass==raw.BCHCrcPass && ...
    relative.SSBWindowPowerMeasurementJSON=="" && isnan(relative.MeasuredReferenceSignalPathloss_dB));
localReject(@()sixgr.link.normalizeReceivedSSBPowerReference(relative,cfg), ...
    'sixgr:link:SSBPowerReferenceAlreadyNormalized');
absolute=cfg; absolute.integration.configured_snr_is_link_authority=false;
assert(isequaln(raw,sixgr.link.normalizeReceivedSSBPowerReference(raw,absolute)));
missing=struct('SSPhysicalMeasurementStatus',"unavailable_sss_measurement",'SS_RSRP_dBm',NaN);
unchanged=sixgr.link.normalizeReceivedSSBPowerReference(missing,cfg);
assert(unchanged.SSPhysicalMeasurementStatus==missing.SSPhysicalMeasurementStatus && ...
    isnan(unchanged.SS_RSRP_dB_re_UnitOccupiedRE_Es) && ...
    ~isfield(unchanged,'ReferenceSignalTxMeasurementSource'));
localReject(@()sixgr.link.normalizeReceivedSSBPowerReference(unchanged,cfg), ...
    'sixgr:link:SSBPowerReferenceAlreadyNormalized');
bad=raw; bad.SS_RSRP_dBm=NaN;
localReject(@()sixgr.link.normalizeReceivedSSBPowerReference(bad,cfg),'sixgr:link:MissingSSBPowerMeasurement');
bad=rmfield(raw,'SSMeasurementFFTSize');
localReject(@()sixgr.link.normalizeReceivedSSBPowerReference(bad,cfg),'sixgr:link:MissingSSBPowerScale');
bad=raw; bad.ReferenceSignalTxMeasurementGridScaleToSqrtW=1;
localReject(@()sixgr.link.normalizeReceivedSSBPowerReference(bad,cfg),'sixgr:link:MissingSSBPowerScale');
bad=raw; bad.SS_RSRPPerReceiveAntenna_dBm="1||2";
localReject(@()sixgr.link.normalizeReceivedSSBPowerReference(bad,cfg),'sixgr:link:InvalidSSBPowerToken');
multi=struct('Enabled',true,'NumUsers',1,'RNTIStart',1,'ExecutionModel','slot_coupled_truth');
state=sixgr.truth.CoupledTruthRuntime.initialize(cfg,tempname,multi,struct(),10);
state.CurrentSlot=1; state.CurrentServingIdx(:)=1;
state.UECommonCellConfigurationByUE={decodedSSBPowerCodecFixture(cfg,-55,1,1)};
% Exercise the old failure even when a caller supplies a numeric reference
% row. Mode authority must not turn that relative value into physical loss.
measurement=table(0,1,-54.38924037,12, ...
    'VariableNames',{'ReferenceSignalId','ServingCell','SS_RSRP_dBm','SS_SINR_dB'});
state=sixgr.truth.CoupledTruthRuntime.publishReferenceSignalMeasurementRuntime( ...
    state,'SSB','UE',1,measurement,'ProducerSlot',1,'AvailableSlot',1,'Valid',true, ...
    'Direction','DL','SourceSignal','SSB','MeasurementSource','declared_mode_boundary_fixture');
state.CurrentSlot=5;
[bound,decision]=sixgr.truth.bindSharedSSBPowerReference(cfg,state,1,5,0);
assert(~decision.ReferenceUsable && ~decision.AbsolutePowerReferenceApplicable && ...
    decision.Status=="not_applicable_normalized_fixed_esn0" && ...
    decision.OperatingPointAuthority=="configured_occupied_re_esn0" && ...
    isnan(decision.Pathloss_dB) && isnan(decision.MeasuredRSRP_dBm) && ...
    isnan(bound.lls6g.userContext.RuntimeServingPathloss_dB));
[bound,boundState]=sixgr.truth.CoupledTruthRuntime.applyUserContext(cfg,state,1,'UL');
assert(isnan(bound.lls6g.userContext.RuntimeServingPathloss_dB));
assert(bound.lls6g.userContext.RuntimePropagationPathloss_dB== ...
    boundState.LargeScaleState.Pathloss_dB(1,boundState.CurrentServingIdx(1)), ...
    'Mode-boundary binding must not modify the physical propagation ledger.');
% A stale physical value from an earlier mode cannot survive the switch.
stale=cfg; stale.lls6g.userContext.RuntimeServingPathloss_dB=123;
[bound,~]=sixgr.truth.bindSharedSSBPowerReference(stale,state,1,5,0);
assert(isnan(bound.lls6g.userContext.RuntimeServingPathloss_dB));
% The RA wrapper must reach its normalized-mode decision before an unrelated
% physical loss guard; it must still require real received common authority.
cfg.random_access.associated_ssb_index=0;
[bound,ra]=sixgr.truth.bindSharedRAPowerReference(cfg,state,1,5);
assert(ra.ReferenceUsable && isnan(ra.Pathloss_dB) && ...
    isnan(bound.lls6g.userContext.RuntimeServingPathloss_dB));
missing=state; missing.UECommonCellConfigurationByUE={struct()};
[~,ra]=sixgr.truth.bindSharedRAPowerReference(cfg,missing,1,5);
assert(~ra.ReferenceUsable && ra.Status=="no_available_decoded_sib1");
future=state; future.RuntimeViewMode="future_ul_grant_planning";
future.PlanningDecisionSlot=3; future.UECommonCellConfigurationByUE{1}.AvailableSlot=4;
[~,ra]=sixgr.truth.bindSharedRAPowerReference(cfg,future,1,5);
assert(~ra.ReferenceUsable,'Normalized operation cannot consume future SIB1.');
localReject(@()sixgr.truth.bindSharedSSBPowerReference(cfg,state,1,6,0), ...
    'sixgr:truth:SSBPowerReferenceKnowledgeClock');
% Preserve the original physical-mode negative-loss rejection, including
% either missing half of the explicit normalized-mode authority pair.
physical=cfg; physical.integration.configured_snr_is_link_authority=false;
localReject(@()sixgr.truth.bindSharedSSBPowerReference(physical,state,1,5,0), ...
    'sixgr:truth:InvalidSSBPowerReference');
physical=cfg; physical.integration.run_mode='GEOMETRY_NETWORK';
localReject(@()sixgr.truth.bindSharedSSBPowerReference(physical,state,1,5,0), ...
    'sixgr:truth:InvalidSSBPowerReference');
ok=true;
disp('NORMALIZED_SSB_POWER_AUTHORITY_PASS: no absolute pathloss, unchanged physical/knowledge guards; no RF episodes.');
end
function localReject(f,id)
try, f(); catch e, assert(string(e.identifier)==id,e.message); return; end
error('testNormalizedSSBPowerAuthority:MissingRejection','Expected %s.',id);
end
