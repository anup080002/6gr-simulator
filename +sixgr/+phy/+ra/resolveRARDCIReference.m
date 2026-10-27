function reference = resolveRARDCIReference(cfg)
%RESOLVERARDCIREFERENCE Receiver-known common reference, never a TX grant.
decoded = sixgr.util.structGet(cfg,"UECommonCellConfiguration",struct());
mib = sixgr.util.structGet(cfg,"UECommonMIBConfiguration",struct());
gnb=sixgr.util.structGet(cfg,"GNBCommonCellConfiguration",struct());
gnbMIB=sixgr.util.structGet(cfg,"GNBCommonMIBConfiguration",struct());
assert((isempty(fieldnames(decoded)) && isempty(fieldnames(mib))) || ...
    (isempty(fieldnames(gnb)) && isempty(fieldnames(gnbMIB))), ...
    'sixgr:phy:ra:MixedCommonControlAuthority','Retain either gNB configured or UE decoded authority.');
if ~isempty(fieldnames(gnb))
    assert(gnb.ConfigurationSource=="original_gNB_common_configuration" && ...
        ~isempty(fieldnames(gnbMIB)) && gnbMIB.Source=="original_gNB_configured_MIB", ...
        'sixgr:phy:ra:MissingConfiguredCommonMIB','The cell producer requires its original configured MIB.');
    if gnbMIB.CORESET0Present
        n=gnbMIB.CORESET0NumRB; first=gnbMIB.CORESET0RBStart;
        source="original_gNB_configured_mib_coreset0";
    else
        n=gnb.InitialDLBWP.SizeRB; first=gnb.InitialDLBWP.StartRB;
        source="original_gNB_configured_initial_dl_bwp";
    end
    dmrs=gnbMIB.DMRSTypeAPosition; cp=gnb.InitialDLBWP.CyclicPrefix;
    decoded=gnb; % Same common-list validation below; never stored as UE state.
elseif ~isempty(fieldnames(decoded))
    if isempty(fieldnames(mib))
        error("sixgr:phy:ra:MissingDecodedCommonMIB", ...
            "RAR DCI needs recovered MIB/CORESET0 authority as well as decoded SIB1.");
    end
    if logical(mib.CORESET0Present)
        n = mib.CORESET0NumRB; first = mib.CORESET0RBStart;
        source = "decoded_mib_coreset0";
    else
        n = decoded.InitialDLBWP.SizeRB; first = decoded.InitialDLBWP.StartRB;
        source = "decoded_sib1_initial_dl_bwp";
    end
    dmrs = mib.DMRSTypeAPosition;
    cp = decoded.InitialDLBWP.CyclicPrefix;
else
    % Offline component fixtures have an explicitly labelled scenario BWP;
    % they must not claim that an unexecuted MIB has been decoded.
    n = sixgr.util.structGet(cfg,"phy.carrier.NSizeGrid",NaN);
    first = sixgr.util.structGet(cfg,"phy.carrier.NStartGrid",0);
    dmrs = sixgr.util.structGet(cfg,"phy.mib.dmrsTypeAPosition",NaN);
    cp = sixgr.util.structGet(cfg,"phy.carrier.CyclicPrefix","normal");
    source = "scenario_initial_dl_bwp";
end
common = sixgr.util.structGet(decoded,"PDSCHConfigCommon",struct());
if ~isempty(fieldnames(common))
    error("sixgr:phy:ra:UnsupportedRARCommonTDRAList", ...
        "RAR must consume a configured PDSCH common list; it cannot replace it with default A.");
end
reference = struct("FrequencyReferenceSize",double(n), ...
    "FrequencyReferenceStart",double(first),"FrequencyReferenceSource",source, ...
    "DMRSTypeAPosition",double(dmrs),"CyclicPrefix",string(cp), ...
    "SharedSpectrum",logical(sixgr.util.structGet(cfg,"initial_access.shared_spectrum", ...
        sixgr.util.structGet(cfg,"frequency.shared_spectrum",false))), ...
    "FrequencyRange",string(sixgr.util.structGet(cfg,"frequency.range_name","")), ...
    "TimeAllocationSource","38.214_default_A", ...
    "ConfigurationEpoch",double(sixgr.util.structGet(cfg,"initial_access.configuration_epoch",0)));
if ~isempty(fieldnames(gnb))
    reference.AuthorityRole="original_gNB_transmitter_configuration";
end
end
