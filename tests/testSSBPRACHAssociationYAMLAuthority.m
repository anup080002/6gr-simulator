function ok=testSSBPRACHAssociationYAMLAuthority()
% Actual resolved YAML -> internal config -> UPER -> association arithmetic.
% No received-SI waveform, runtime admission or Msg1 detector claim here.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml');
s=scenario.toStruct(); cfg=sixgr.lls6g.buildInternalConfig(s,tempname);
assert(string(s.random_access.ssb_per_rach_choice)=="four" && ...
    s.random_access.cb_preambles_per_ssb==16 && s.random_access.preamble_count==64);
assert(cfg.run.totalSlots==65 && cfg.run.numTTI==65 && ...
    s.run_control.total_time_ms==32.5 && s.simulation.n_slots==65 && ...
    s.simulation.n_subframes==33 && s.random_access.num_slots==65 && ...
    s.run_control.runtime_checkpoint_enable && s.run_control.checkpoint_first_slot==60 && ...
    string(cfg.rrc.sib1.ssb_per_rach_choice)=="four" && ...
    string(cfg.rrc.sib1.cb_preambles_per_ssb)=="16" && cfg.phy.prach.nPreambles==64);
overrides=s.scenario.sweep.overrides;
if iscell(overrides), overrides=[overrides{:}]; end
assert(numel(overrides)==2 && ...
    isequal(arrayfun(@(v)double(v.config.simulation.snr_db),overrides(:)).',[20 0]));
assert(string(s.random_access.cb_preamble_selection_policy)=="fixed_partition_offset" && ...
    s.random_access.cb_preamble_offset==1);
[r,tree]=wire(cfg); %#ok<ASGLU>
assert(string(r.ssbPerRACHChoice)=="four" && string(r.cbPreamblesPerSSB)=="16" && r.nPreambles==64);
n=sixgr.phy.frame.PRACHOccasionResolver.resolveFromConfig(cfg);
a=sixgr.mac.ra.resolveSSBPRACHAssociation(n,0:3,4,16,64,true(height(n.Occasions),1));
for beam=0:3
    rows=a.Mapping.SSBIndex0==beam;
    assert(any(rows) && all(a.Mapping.CBPreambleStart0(rows)==16*beam) && ...
        all(a.Mapping.CBPreambleCount(rows)==16));
end
% All ASN.1 CHOICE arms are driven through the generic config resolver and
% actual codec. Fractional cases use one declared active SSB for arithmetic.
tokens=["oneEighth","oneFourth","oneHalf","one","two","four","eight","sixteen"];
counts=[64 64 64 64 32 16 8 4]; ratios=[1/8 1/4 1/2 1 2 4 8 16];
for k=1:numel(tokens)
    authored=s.random_access; authored.ssb_per_rach_choice=tokens(k);
    authored.cb_preambles_per_ssb=counts(k);
    p=sixgr.lls6g.config.resolveSSBPRACHAssociationConfig(authored);
    c=cfg; c.rrc.sib1.ssb_per_rach_choice=p.Choice;
    c.rrc.sib1.cb_preambles_per_ssb=p.WireCBCount;
    received=wire(c);
    assert(string(received.ssbPerRACHChoice)==tokens(k) && ...
        str2double(erase(string(received.cbPreamblesPerSSB),"n"))==counts(k));
    mapped=sixgr.mac.ra.resolveSSBPRACHAssociation(n,0,ratios(k),counts(k),64,true(height(n.Occasions),1));
    assert(~isempty(mapped.Mapping) && all(mapped.Mapping.SSBIndex0==0));
end
% The last-authored resolved child values reach the builder, not a hidden
% hardcoded one/64 SIB1 default.
child=s; child.random_access.ssb_per_rach_choice='two'; child.random_access.cb_preambles_per_ssb=32;
c=sixgr.lls6g.buildInternalConfig(child,tempname); received=wire(c);
assert(string(received.ssbPerRACHChoice)=="two" && string(received.cbPreamblesPerSSB)=="n32");
for value={17,0,16.5,'16',true,NaN}
    bad=s.random_access; bad.cb_preambles_per_ssb=value{1};
    reject(@()sixgr.lls6g.config.resolveSSBPRACHAssociationConfig(bad));
end
bad=s.random_access; bad.preamble_count=63;
reject(@()sixgr.lls6g.config.resolveSSBPRACHAssociationConfig(bad));
bad=s.random_access; bad.ssb_per_rach_choice='unknown';
reject(@()sixgr.lls6g.config.resolveSSBPRACHAssociationConfig(bad));
fprintf('SSB_PRACH_YAML_AUTHORITY_PASS actual_UPER_choices=8 n40_four_16_65=1 checkpoint60=1 points_20_0=1 runtime_or_PHY_claim=0\n');
ok=true;
end
function [r,received]=wire(cfg)
tree=sixgr.rrc.asn1.buildBCCHDLSCHMessage(cfg);
bits=sixgr.rrc.asn1.encodeSIB1UPER(tree);
received=sixgr.rrc.asn1.decodeSIB1UPER(bits);
assert(sixgr.rrc.asn1.compareSIB1Trees(tree,received));
r=received.message.c1.systemInformationBlockType1.servingCellConfigCommon.uplinkConfigCommon.initialUplinkBWP.rach_ConfigCommon;
end
function reject(f)
try, f(); catch e
    assert(string(e.identifier)=="sixgr:lls6g:config:InvalidSSBPRACHAssociation",e.message); return;
end
error('sixgr:test:ExpectedFailure','Invalid SSB/RO policy was accepted.');
end
