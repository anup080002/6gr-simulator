function sched = scheduleMsg2RAR(raCfg, varargin)
%SCHEDULEMSG2RAR Pack the RA-RNTI DCI 1_0 and derive its PDSCH allocation.
p = inputParser;
p.addParameter("RNTI", raCfg.RARNTI, @(x)isnumeric(x) && isscalar(x));
p.addParameter("DCIFormat", "1_0", @(x)ischar(x) || isstring(x));
p.parse(varargin{:});

if string(p.Results.DCIFormat) ~= "1_0"
    error("sixgr:phy:ra:InvalidRARDCIFormat","RAR uses RA-RNTI DCI 1_0.");
end
context = sixgr.phy.pdcch.RARDCIContext.create(raCfg.RARDCIReference,double(p.Results.RNTI));
[rows,~] = sixgr.phy.pdcch.RARDCIContext.defaultA( ...
    context.Data.CyclicPrefix,context.Data.DMRSTypeAPosition);
s = raCfg.Msg2PDSCH;
match = find(rows(:,2)==s.SymbolStart & rows(:,3)==s.NumSymbols & rows(:,4)==0);
if numel(match) ~= 1 || s.RV ~= 0
    error("sixgr:phy:ra:InvalidRARTDRA", ...
        "Msg2 allocation must match the installed common TDRA and RA-RNTI RV=0.");
end
% Scheduler PRBs are carrier-relative, whereas FDRA uses CORESET0 or the
% initial BWP, which can have a different start and width.
start = s.PRBStart + raCfg.NStartGrid - context.Data.FrequencyReferenceStart;
fields = struct("frequency_resource_assignment",sixgr.bwop.RIVFDRA.encode( ...
    context.Data.FrequencyReferenceSize,start,s.NumPRB), ...
    "time_resource_assignment",rows(match,1),"vrb_to_prb_mapping",0, ...
    "mcs",s.MCS,"tb_scaling",s.TBScaling,"reserved",0);
dci = sixgr.phy.pdcch.DCIPacker.pack(fields,context);
sched = sixgr.phy.ra.rarScheduleFromDCI(raCfg,dci.Bits,context);
if s.NLayers ~= 1 || s.EnablePTRS || string(s.MCSTable) ~= "qam64" || ...
        string(s.Modulation) ~= sched.Modulation || ...
        abs(s.TargetCodeRate-sched.TargetCodeRate) > 1e-12
    error("sixgr:phy:ra:InvalidRARCommonPDSCH", ...
        "RAR needs rank one, no PT-RS and the rate/modulation of its common DCI MCS.");
end
end
