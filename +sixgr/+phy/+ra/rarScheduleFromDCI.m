function sched = rarScheduleFromDCI(raCfg, bits, context)
%RARSCHEDULEFROMDCI Materialize RAR scheduling from received/encoded bits.
dci = sixgr.phy.pdcch.DCIParser.parse(bits,context);
f = dci.Fields;
if f.vrb_to_prb_mapping ~= 0
    error("sixgr:pdsch:UnsupportedRARInterleaving", ...
        "Interleaved RAR VRB mapping requires a resource-plan implementation.");
end
mcs = sixgr.pdsch.PDSCHMCSResolver.resolve("qam64",f.mcs, ...
    struct("NumCodewords",1,"RNTIType","RA-RNTI","SelectionSource","ra_rnti_dci_bits"));
if mcs.Qm > 2
    error("sixgr:phy:ra:InvalidRARCommonPDSCH","TS 38.214 5.1.3.1 limits RA-RNTI PDSCH to QPSK.");
end
first = f.prb_start + f.reference_start - raCfg.NStartGrid;
if first < 0 || first+f.num_prb > raCfg.NSizeGrid
    error("sixgr:phy:ra:RARAllocationOutsideCarrier","Decoded RAR PRBs lie outside this waveform carrier.");
end
pdsch = nrPDSCHConfig;
pdsch.PRBSet = first+(0:f.num_prb-1);
pdsch.SymbolAllocation = [f.symbol_start f.num_symbols];
pdsch.MappingType = f.mapping_type;
pdsch.Modulation = mcs.Modulation;
pdsch.NumLayers = 1;
pdsch.RNTI = context.Data.RNTIValue;
pdsch.NID = raCfg.NCellID;
pdsch.DMRS.DMRSTypeAPosition = context.Data.DMRSTypeAPosition;
pdsch.DMRS.DMRSConfigurationType = 1;
pdsch.DMRS.DMRSAdditionalPosition = 2;
pdsch.DMRS.DMRSLength = 1;
pdsch.DMRS.NumCDMGroupsWithoutData = 2;
if f.num_symbols == 2, pdsch.DMRS.NumCDMGroupsWithoutData = 1; end
pdsch.DMRS.NIDNSCID = raCfg.NCellID;
pdsch.DMRS.NSCID = 0;
pdsch.DMRS.DMRSPortSet = 0;
% Common RA-RNTI has no PT-RS configuration/indication. Connected-data
% PT-RS configuration must not leak into this receiver's common procedure.
pdsch.EnablePTRS = false;
sched = struct("RNTI",context.Data.RNTIValue,"DCIFormat","1_0", ...
    "DCIBits",dci.Bits,"DCIContext",context,"DCIFieldTable",dci.FieldTable, ...
    "PDSCH",pdsch,"PRBStart",first,"NumPRB",f.num_prb, ...
    "SymbolStart",f.symbol_start,"NumSymbols",f.num_symbols, ...
    "MCS",f.mcs,"MCSTable","qam64","Modulation",mcs.Modulation, ...
    "TargetCodeRate",mcs.TargetCodeRate,"RV",0,"TBScaling",f.tb_scaling_factor);
end
