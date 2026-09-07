function [pdcch,evidence] = resolveRARCommonControl(cfg,carrier)
%RESOLVERARCOMMONCONTROL Common-control layout, independent of a TX slot.
ue = sixgr.util.structGet(cfg,"UECommonCellConfiguration",struct());
if ~isempty(fieldnames(ue))
    if ~ue.PDCCHConfigCommonPresent
        error("sixgr:phy:ra:MissingRARCommonControl","Decoded SIB1 has no RAR common control configuration.");
    end
    common=ue.PDCCHConfigCommon; bwp=ue.InitialDLBWP;
    source="decoded_sib1_pdcch_config_common";
else
    common=sixgr.util.structGet(cfg,"initial_access.sib1.pdcch_config_common",struct());
    bwp=struct("StartRB",double(carrier.NStartGrid),"SizeRB",double(carrier.NSizeGrid), ...
        "SubcarrierSpacing_kHz",double(carrier.SubcarrierSpacing),"CyclicPrefix",string(carrier.CyclicPrefix));
    source="scenario_common_control_pending_sib1";
end
required=["commonControlResourceSet","commonSearchSpaceList","ra_SearchSpace"];
if ~all(isfield(common,required)) || common.ra_SearchSpace==0
    error("sixgr:phy:ra:UnsupportedRARCommonControl", ...
        "RAR requires its explicit common CORESET and nonzero Type1 search-space IE; SearchSpaceZero reuse is not implemented.");
end
core=common.commonControlResourceSet;
spaces=common.commonSearchSpaceList;
if iscell(spaces), spaces=[spaces{:}]; end
selection=find([spaces.searchSpaceId]==common.ra_SearchSpace);
if numel(selection)~=1
    error("sixgr:phy:ra:InvalidRARCommonControl","ra-SearchSpace must resolve to exactly one decoded IE.");
end
ss=spaces(selection);
if ss.controlResourceSetId~=core.controlResourceSetId || string(ss.searchSpaceType)~="common"
    error("sixgr:phy:ra:InvalidRARCommonControl","RAR search space must reference its common CORESET.");
end
if bwp.SubcarrierSpacing_kHz~=double(carrier.SubcarrierSpacing) || ...
        string(bwp.CyclicPrefix)~=string(carrier.CyclicPrefix)
    error("sixgr:phy:ra:UnsupportedRARControlNumerology","RAR control BWP requires an explicit cross-numerology waveform owner.");
end
frequency=char(string(core.frequencyDomainResources));
symbols=char(string(ss.monitoringSymbolsWithinSlot));
if numel(frequency)~=45 || any(~ismember(frequency,'01')) || ...
        numel(symbols)~=14 || any(~ismember(symbols,'01'))
    error("sixgr:phy:ra:InvalidRARCommonControl","Invalid common-control resource bitmap.");
end
starts=find(symbols=='1')-1;
if numel(starts)~=1
    error("sixgr:phy:ra:UnsupportedRARCommonControl", ...
        "Multiple in-slot RAR monitoring occasions need an explicit occasion iterator, not a truncated bitmap.");
end
crst=nrCORESETConfig;
crst.CORESETID=double(core.controlResourceSetId);
crst.Duration=double(core.duration);
crst.FrequencyResources=double(frequency-'0');
crst.CCEREGMapping=lower(string(core.cce_REG_MappingType));
crst.PrecoderGranularity=string(core.precoderGranularity);
if crst.CCEREGMapping=="interleaved"
    crst.REGBundleSize=str2double(extractAfter(string(core.reg_BundleSize),"n"));
    crst.InterleaverSize=str2double(extractAfter(string(core.interleaverSize),"n"));
    crst.ShiftIndex=double(sixgr.util.structGet(core,"shiftIndex",carrier.NCellID));
end
% Default RB grouping starts at the first complete group of six CRBs.
lastGroup=find(frequency=='1',1,'last');
if isempty(lastGroup) || mod(-bwp.StartRB,6)+lastGroup*6>bwp.SizeRB || ...
        bwp.StartRB<carrier.NStartGrid || bwp.StartRB+bwp.SizeRB>carrier.NStartGrid+carrier.NSizeGrid
    error("sixgr:phy:ra:InvalidRARCommonControl","Common CORESET/BWP lies outside the receiver carrier.");
end
search=nrSearchSpaceConfig;
search.SearchSpaceID=double(ss.searchSpaceId);
search.CORESETID=crst.CORESETID;
search.SearchSpaceType="common";
search.StartSymbolWithinSlot=starts;
period=str2double(extractAfter(string(ss.monitoringSlotPeriodicityAndOffset.periodicity),"sl"));
offset=double(ss.monitoringSlotPeriodicityAndOffset.offset);
search.SlotPeriodAndOffset=[period offset];
search.Duration=double(sixgr.util.structGet(ss,"duration",1));
search.NumCandidates=double(ss.nrofCandidates(:).');
levels=[1 2 4 8 16];
nCCE=sum(crst.FrequencyResources)*crst.Duration;
if any(search.NumCandidates>0 & levels>nCCE) || ~any(search.NumCandidates>0)
    error("sixgr:phy:ra:InvalidRARCommonControl","Advertised RAR candidate does not fit its CORESET.");
end
if starts+crst.Duration>carrier.SymbolsPerSlot
    error("sixgr:phy:ra:RAROutsideMonitoringOccasion","Scheduled Msg2 is outside the decoded Type1 monitoring occasion.");
end
pdcch=nrPDCCHConfig;
pdcch.NStartBWP=double(bwp.StartRB); pdcch.NSizeBWP=double(bwp.SizeRB);
pdcch.CORESET=crst; pdcch.SearchSpace=search;
pdcch.RNTI=0;
pdcch.DMRSScramblingID=double(sixgr.util.structGet(core,"pdcch_DMRS_ScramblingID",carrier.NCellID));
% Deterministic TX policy: first configured legal level/candidate. RX still
% monitors every configured candidate; it never receives this TX selection.
pdcch.AggregationLevel=levels(find(search.NumCandidates>0,1));
pdcch.AllocatedCandidate=1;
evidence=struct("Source",source,"SearchSpaceID",search.SearchSpaceID, ...
    "CORESETID",crst.CORESETID,"NCCE",nCCE, ...
    "SlotPeriodAndOffset",search.SlotPeriodAndOffset,"MonitoringDurationSlots",search.Duration, ...
    "StartSymbol",starts,"DurationSymbols",crst.Duration, ...
    "FrequencyResources",string(frequency),"NumCandidates",search.NumCandidates, ...
    "CCEREGMapping",string(crst.CCEREGMapping),"PhysicalScramblingRNTI",0);
end
