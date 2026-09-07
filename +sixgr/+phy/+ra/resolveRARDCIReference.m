function reference = resolveRARDCIReference(cfg)
%RESOLVERARDCIREFERENCE Receiver-known common reference, never a TX grant.
decoded = sixgr.util.structGet(cfg,"UECommonCellConfiguration",struct());
mib = sixgr.util.structGet(cfg,"UECommonMIBConfiguration",struct());
if ~isempty(fieldnames(decoded))
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
end
