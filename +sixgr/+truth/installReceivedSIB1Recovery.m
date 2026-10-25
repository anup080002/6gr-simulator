function state = installReceivedSIB1Recovery(state, ueIdx, recovery, slotIdx, priorMIBBinding)
% Common production delivery owner; shared by coordinator and physical tests.
% Accept only original received SI evidence. No waveform or measurement synthesis.
if nargin<5, priorMIBBinding=[]; end
if ~(isstruct(recovery) && isscalar(recovery) && ~isempty(fieldnames(recovery)))
    return;
end
% Equality with a configured transmitter tree is an offline comparison,
% never an operational receiver admission condition.
strictFields = ["StrictOk","DCICrcPass","DLSCHCrcPass", ...
    "SIB1ASN1DecodeOk","SIB1SemanticValid"];
for i = 1:numel(strictFields)
    if ~localStructLogical(recovery, char(strictFields(i)), false)
        return;
    end
end
tree = sixgr.util.structGet(recovery, "SIB1RxTree", struct());
if ~(isstruct(tree) && ~isempty(fieldnames(tree)))
    return;
end
validateattributes(ueIdx,{'double'},{'real','scalar','finite','integer','positive'});
validateattributes(slotIdx,{'double'},{'real','scalar','finite','integer','positive'});
nUsers = max(0, round(double(sixgr.util.structGet(state, "NumUsers", 0))));
if ~(isfinite(ueIdx) && ueIdx >= 1 && ueIdx <= nUsers)
    return;
end
% Verify only the received semantic object and original decoded payload
% digest. Do not re-encode a configured TX tree or invent missing hashes.
[~,receivedHash]=sixgr.rrc.asn1.compareSIB1Trees(tree,tree);
assert(isfield(recovery,'SIB1RxTreeHash') && isfield(recovery,'SIB1PayloadHashRx') && ...
    string(recovery.SIB1RxTreeHash)==string(receivedHash.RxTreeHash) && ...
    strlength(string(recovery.SIB1PayloadHashRx))>0, ...
    'sixgr:truth:InvalidReceivedSIB1Identity','Retain the original decoded SIB1 tree and payload identities.');
if ~isempty(priorMIBBinding)
    sixgr.truth.ReceivedMIBDelivery.validate(priorMIBBinding,true);
    [valid,~,current]=sixgr.truth.ReceivedMIBDelivery.current(state,ueIdx);
    if ~valid || current.GenerationID~=priorMIBBinding.GenerationID, return; end
    assert(slotIdx==state.CurrentSlot && priorMIBBinding.UEIndex==ueIdx, ...
        'sixgr:truth:ReceivedSIB1DeliveryMismatch','Install only for the original receiver at the current delivery boundary.');
    if isfield(recovery,'PriorBCHContextSHA256')
        assert(string(recovery.PriorBCHContextSHA256)==priorMIBBinding.ContextSHA256 && ...
            isfield(recovery,'NewBCHReceptionAttempted') && ...
            isequal(recovery.NewBCHReceptionAttempted,false), ...
            'sixgr:truth:ReceivedSIB1DeliveryMismatch','SI-only decoding must use the frozen original MIB without a new BCH claim.');
    end
    recovery.ReceivedDLTimingReference=priorMIBBinding.ReceivedDLTimingReference;
    recovery.ReferenceConfigurationEpoch=priorMIBBinding.AcquisitionConfigurationEpoch;
    recovery.MeasurementClockEpoch=priorMIBBinding.PhysicalConfigurationEpoch;
    recovery.OriginalServingCell=priorMIBBinding.ServingCell;
    recovery.ReceivedMIBGenerationID=priorMIBBinding.GenerationID;
    recovery.ReceivedMIBDeliverySHA256=priorMIBBinding.DeliverySHA256;
    % Retain the actual earlier BCH owner, rather than adding false new-BCH
    % flags to the SI-only result. RA common-control projection consumes it.
    recovery.ReceivedMIBBinding=priorMIBBinding;
    recovery.ReceivedSIB1AvailableAtSample=sixgr.phy.frame.slotStartSample( ...
        sixgr.phy.grid.makeCarrier(state.CfgMobility),slotIdx-1,priorMIBBinding.SampleRateHz);
end
if ~isfield(state, "DecodedSIB1RecoveryByUE") || ...
        ~iscell(state.DecodedSIB1RecoveryByUE)
    state.DecodedSIB1RecoveryByUE = repmat({struct()}, nUsers, 1);
elseif numel(state.DecodedSIB1RecoveryByUE) < nUsers
    state.DecodedSIB1RecoveryByUE(end + 1:nUsers, 1) = {struct()};
end
if ~isfield(state, "DecodedSIB1RecoverySlotByUE") || ...
        numel(state.DecodedSIB1RecoverySlotByUE) < nUsers
    state.DecodedSIB1RecoverySlotByUE(end + 1:nUsers, 1) = NaN;
end
state.DecodedSIB1RecoveryByUE{ueIdx} = recovery;
state.DecodedSIB1RecoverySlotByUE(ueIdx) = double(slotIdx);
% Install only the received tree at the actual delivery boundary. Retain
% cell/epoch identity separately from the broadcast IEs; they are receiver
% context, not additional information claimed to have been in SIB1.
installCfg=struct();
if ~isempty(priorMIBBinding)
    installCfg=sixgr.truth.CoupledTruthRuntime.measurementConfigurationForUE(state,ueIdx);
end
installed = sixgr.mac.ra.installDecodedSIB1RACHConfig(installCfg,recovery);
common = installed.UECommonCellConfiguration;
common.ServingCell = state.CurrentServingIdx(ueIdx);
common.AvailableSlot = double(slotIdx);
common.ConfigurationEpoch = sixgr.util.structGet(state.CfgMobility, ...
    'initial_access.configuration_epoch',NaN);
if sixgr.phy.refsig.pathlossReferenceLifetime(state.CfgMobility)=="retained_filtered_reference"
    % Original receiver context is mandatory in the retained-state mode.
    common.ConfigurationEpoch=sixgr.util.structGet(recovery,'ReferenceConfigurationEpoch',NaN);
    common.MeasurementClockEpoch=sixgr.util.structGet(recovery,'MeasurementClockEpoch',NaN);
    common.ServingCell=sixgr.util.structGet(recovery,'OriginalServingCell',NaN);
end
% Resolve only after SIB1 has actually been delivered to this UE. The
% tuned carrier identifies FR1/FR2; the received IE (including absence),
% not the scenario's transmitter setting or duplex label, owns the offset.
range=sixgr.phy.frame.FrequencyRangeResolver.resolve( ...
    'CenterFrequencyHz',state.CfgMobility.phy.fc_Hz);
common.ULTimingAdvanceOffset=sixgr.phy.frame.resolveULTimingAdvanceOffset( ...
    common,range.FrequencyRange);
if isfield(recovery,'ReceivedDLTimingReference')
    common.ReceivedDLTimingReference=recovery.ReceivedDLTimingReference;
end
if ~isfield(state,'UECommonCellConfigurationByUE')
    state.UECommonCellConfigurationByUE = repmat({struct()},nUsers,1);
end
if sixgr.phy.refsig.pathlossReferenceLifetime(state.CfgMobility)=="retained_filtered_reference"
    [state,~]=sixgr.truth.SSBPowerReferenceLifecycle.install(state,ueIdx,common);
end
state.UECommonCellConfigurationByUE{ueIdx} = common;
if sixgr.truth.DLMeasurementInstallation.required(state)
    [measurementCfg,~]=sixgr.truth.CoupledTruthRuntime.applyUserContext(state.CfgMobility,state,ueIdx,'DL');
    state=sixgr.truth.DLMeasurementInstallation.install(state,ueIdx,measurementCfg);
end
end

function tf = localStructLogical(s, fieldName, defaultValue)
raw = defaultValue;
if isstruct(s) && isfield(s, fieldName)
    raw = s.(fieldName);
end
tf=(islogical(raw)||isnumeric(raw)) && isreal(raw) && isscalar(raw) && ...
    isfinite(raw) && raw==1;
end
