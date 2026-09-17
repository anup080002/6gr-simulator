% Read-only allocation/coding audit; no waveform or new success observation.
captureRoot=['C:/Users/anup0/OneDrive/Documents/Simulator/6GR Simulator_v2_clean_main/' ...
    'logs/research_selected_iq_6be2985f_20260917/execution/lls/' ...
    'lls_7ghz_400mhz_1024qam_tdd_30db_rate082_iq/committed_source'];
negativeRoot=['C:/Users/anup0/OneDrive/Documents/Simulator/6GR Simulator_v2_clean_main/' ...
    'logs/research_rate_matrix_91046b23_20260917/execution/lls/' ...
    'research_400mhz_rate_matrix/committed_source/runs/lls/research_400mhz_rate085/candidate_3'];
s=jsondecode(fileread(fullfile(captureRoot,'meta','resolved_config.json')));
pass=readtable(fullfile(captureRoot,'reports','csv','trials.csv'),'Delimiter',',','ReadVariableNames',true,'TextType','string');
negative=readtable(fullfile(negativeRoot,'reports','csv','trials.csv'),'Delimiter',',','ReadVariableNames',true,'TextType','string');
assert(all(pass.CRCPass & pass.TBExact) && ~all(negative.CRCPass & negative.TBExact));
for direction=["DL","UL"]
    ch=s.("research_"+lower(direction));
    a=pass(find(pass.Direction==direction,1),:);
    b=negative(find(negative.Direction==direction,1),:);
    assert(a.CodedBits==b.CodedBits && a.Qm==b.Qm && a.Layers==b.Layers);
    rePerPRB=a.CodedBits/(a.Qm*a.Layers*ch.num_prbs);
    assert(rePerPRB==fix(rePerPRB));
    % A diagnostic grid between two actually executed candidate rates.
    rates=linspace(a.TargetCodeRate,b.TargetCodeRate,301);
    sizes=arrayfun(@(r)nrTBS(char(ch.modulation),ch.num_layers,ch.num_prbs,rePerPRB,r,0),rates);
    distinct=unique(sizes);
    assert(isequal(distinct,sort([a.TBSBits,b.TBSBits])));
    labels=linspace(-1,1,a.CodedBits).'; % synthetic position probe, not received LLRs
    for tbs=distinct
        members=find(sizes==tbs);
        low=rates(members(1)); high=rates(members(end));
        first=nrRateRecoverLDPC(labels,tbs,low,ch.rv,char(ch.modulation),ch.num_layers);
        last=nrRateRecoverLDPC(labels,tbs,high,ch.rv,char(ch.modulation),ch.num_layers);
        assert(isequaln(first,last),'Rate recovery differs within sampled equal-TBS band.');
        fprintf('RATE_QUANTIZATION direction=%s low=%.4f high=%.4f TBS=%d sampled_rates=%d equal_endpoint_rate_recovery=1\n',direction,low,high,tbs,numel(members));
    end
end
fprintf('RATE_QUANTIZATION_AUDIT_PASS rates_per_direction=301 new_waveform_trials=0 no_global_optimum_claim=1\n');
