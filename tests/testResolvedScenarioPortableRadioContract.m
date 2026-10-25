function ok=testResolvedScenarioPortableRadioContract()
% Reload the exact resolved-input formats from another directory.
% Config/native mapping qualification only; no waveform or performance claim.
setup6GRSimToolkit('Verbose',false,'RunToolboxChecks',false);
source='simulator/configs/scenarios/lls_tdd_n40_20mhz_64txru_4rx_cdlc100_reference_snr_sweep.yaml';
original=sixgr.lls6g.config.loadScenarioConfig(source);
root=fullfile(pwd,'logs','resolved_radio_portability',char(java.util.UUID.randomUUID()));
mkdir(root);
before=sixgr.lls6g.buildInternalConfig(original,fullfile(root,'original'));
nodes=["phy.carrier","phy.ssb","phy.csirs","phy.csi","phy.mimo", ...
    "phy.srs","phy.trs","phy.pdsch","phy.pusch"];
checks=table(strings(0,1),strings(0,1),false(0,1), ...
    'VariableNames',{'Format','RuntimeNode','Equal'});
data=original.toStruct();
assert(~isfield(data,'inherits'),'Resolved input must not retain executable inheritance.');
for format=["yaml","json"]
    file=fullfile(root,"scenario_config_resolved."+format);
    if format=="yaml"
        sixgr.lls6g.config.writeYAML(file,data);
    else
        sixgr.util.jsonWrite(file,data);
    end
    digest=sixgr.util.sha256File(file);
    restored=sixgr.lls6g.config.loadScenarioConfig(file);
    after=sixgr.lls6g.buildInternalConfig(restored,fullfile(root,format));
    assert(strcmpi(digest,sixgr.util.sha256File(file)), ...
        'test:ResolvedInputMutated','Reload must not rewrite the downloaded input.');
    for node=nodes
        left=sixgr.util.structGet(before,node,[]);
        right=sixgr.util.structGet(after,node,[]);
        assert(~isempty(left),'test:MissingRadioNode','Missing contract node %s.',node);
        same=isequaln(left,right);
        checks=[checks;table(format,node,same,'VariableNames',checks.Properties.VariableNames)]; %#ok<AGROW>
        writetable(checks,fullfile(root,'radio_contract_roundtrip.csv'));
        assert(same,'test:ResolvedRadioContractChanged', ...
            'Relocated %s input changed %s; see %s.',format,node,root);
    end
end
fprintf('RESOLVED_RADIO_PORTABILITY_PASS formats=YAML,JSON nodes=%d waveform_executed=0 evidence=%s\n',numel(nodes),root);
ok=true;
end
