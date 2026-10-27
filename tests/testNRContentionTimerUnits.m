function ok=testNRContentionTimerUnits()
% Literal ASN.1 subframes and exact common clock.
for mu=0:2
    t=sixgr.mac.ra.resolveContentionResolutionTimer(struct(),15*2^mu,"sf64");
    assert(t.Subframes==64&&t.Slots==64*2^mu&&t.DurationSeconds==.064 && ...
        t.DurationTicks==int64(64)*idivide(sixgr.phy.frame.AbsoluteTime.TicksPerFrame,int64(10)) && ...
        t.OriginalEnum=="sf64"&&t.Source=="original_received_RACH_ContentionResolutionTimer");
end
legacy=sixgr.mac.ra.resolveContentionResolutionTimer(struct('ra_contention_resolution_timer_slots',64),30);
assert(legacy.Slots==64&&legacy.Subframes==32&&legacy.OriginalEnum=="sf32");
same=sixgr.mac.ra.resolveContentionResolutionTimer(struct( ...
    'ra_contention_resolution_timer_subframes',64,'ra_contention_resolution_timer_slots',128),30);
assert(same.OriginalEnum=="sf64"&&same.Slots==128);
bad=struct('ra_contention_resolution_timer_subframes',64,'ra_contention_resolution_timer_slots',64);
reject(@()sixgr.mac.ra.resolveContentionResolutionTimer(bad,30));
reject(@()sixgr.mac.ra.resolveContentionResolutionTimer(struct(),30,""));
reject(@()sixgr.mac.ra.resolveContentionResolutionTimer(struct(),30,"sl64"));
reject(@()sixgr.mac.ra.resolveContentionResolutionTimer(struct(),30,"sf7"));
reject(@()sixgr.mac.ra.resolveContentionResolutionTimer(struct(),30));
short=sixgr.mac.ra.resolveContentionResolutionTimer(struct('ra_contention_resolution_timer_slots',1),30);
assert(~short.WireRepresentable&&short.Subframes==.5&&short.Slots==1);
% Actual selected n40 authoring -> UPER decode -> installation. A stale host
% value cannot replace the original received sf64, and a missing IE fails.
source=sixgr.lls6g.config.loadScenarioConfig(fullfile('simulator','configs','scenarios', ...
    'lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml'));
cfg=sixgr.lls6g.buildInternalConfig(source,tempdir);
tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
rach=tree.message.c1.systemInformationBlockType1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon;
assert(rach.contentionResolutionTimer=="sf64");
rx=sixgr.rrc.asn1.decodeSIB1UPER(sixgr.rrc.asn1.encodeSIB1UPER(tree));
host=cfg;host.random_access.ra_contention_resolution_timer_slots=3;
host.random_access.ra_contention_resolution_timer_subframes=8;
[installed,evidence]=sixgr.mac.ra.installDecodedSIB1RACHConfig(host,rx);
assert(installed.random_access.ra_contention_resolution_timer_slots==128 && ...
    installed.random_access.ra_contention_resolution_timer_subframes==64 && ...
    installed.UECommonCellConfiguration.RACHConfigCommon.ContentionResolutionTimer.DurationSeconds==.064);
row=evidence(evidence.Parameter=="ra_contention_resolution_timer_slots",:);
assert(height(row)==1&&row.ValueBefore=="3"&&row.ValueAfter=="128"&&row.Units=="slots");
bad=rx;bad.message.c1.systemInformationBlockType1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon= ...
    rmfield(bad.message.c1.systemInformationBlockType1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon,'contentionResolutionTimer');
failure="";try,sixgr.mac.ra.installDecodedSIB1RACHConfig(host,bad);catch e,failure=string(e.identifier);end
assert(failure=="sixgr:mac:ra:MissingDecodedRACHOperand");
ok=true;fprintf('NR_CONTENTION_TIMER_UNITS_PASS received_sf64=64ms mu0_1_2_slots64_128_256=1 conflicts_rejected=1 RF=0\n');
end
function reject(f)
try,f();catch e,assert(string(e.identifier)=="sixgr:mac:ra:ContentionTimerAuthority",e.message);return;end
error('test:MissingTimerRejection','Expected exact timer authority rejection.');
end
