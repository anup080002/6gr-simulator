function slot=periodicCSIReferenceSlot(cfg,reportSlot)
% TS 38.214 V18.8.0 5.2.2.5: reference resource, not AMC feedback delay.
% This installed same-cell/equal-numerology procedure has no CA/NTN offset.
validateattributes(reportSlot,{'numeric'},{'scalar','real','finite','integer','positive'});
identity=cfg.phy.frame.DefaultIdentity;
carriers=cfg.phy.frame.ComponentCarriers;
cc=carriers([carriers.CCID]==identity.ScheduledCCID);
assert(isscalar(cc),'sixgr:truth:CSIReferenceCarrierUnresolved','Resolve exactly one reporting carrier.');
bwp=cc.BWPs;
dl=bwp([bwp.BWPID]==identity.DLBWPID & upper(string({bwp.Direction}))=="DL");
ul=bwp([bwp.BWPID]==identity.ULBWPID & upper(string({bwp.Direction}))=="UL");
assert(isscalar(dl) && isscalar(ul) && dl.Mu==ul.Mu && ...
    dl.SCSKHz==cfg.phy.carrier.SubcarrierSpacing && dl.CyclicPrefix==ul.CyclicPrefix, ...
    'sixgr:truth:CSIReferenceNumerologyUnresolved', ...
    'The current CSI reference procedure requires resolved same-cell DL/UL numerology; do not reuse this slot calendar across BWPs.');
resources=cfg.phy.csi.reportConfiguration.NumCSIResources;
validateattributes(resources,{'numeric'},{'scalar','real','finite','integer','positive'});
delay=(4+double(resources>1))*2^dl.Mu;
slot=NaN;
for candidate=reportSlot-delay:-1:1
    [dlAllowed,~,~,partition]=sixgr.truth.CoupledTruthRuntime.resolveSlotPartition(cfg,candidate);
    % The installed runtime resolves flexible symbols into concrete slot
    % ownership; its DL allocation is the valid reference-resource authority.
    valid=dlAllowed && partition.DLSymbolAllocation(2)>0;
    if valid && ~sixgr.truth.isCSIReportingMeasurementGap(cfg,candidate)
        slot=candidate; return;
    end
end
end
