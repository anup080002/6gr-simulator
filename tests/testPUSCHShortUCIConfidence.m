function ok=testPUSCHShortUCIConfidence()
% Codec/math regressions. NOT independent physical detector qualification.
setup6GRSimToolkit('Verbose',false);
prior=rng; cleanup=onCleanup(@()rng(prior)); %#ok<NASGU>
rng(92317,'twister');
policy=sixgr.phy.ul.pusch.resolveShortUCIDecisionPolicy();
cfg=sixgr.config.defaultConfig();
assert(isequal(policy.minimumPosterior,cfg.phy.pusch.shortUCIDecision.minimumPosterior));
assert(policy.minimumPosterior==0.99 && policy.Source=="core_catalog_component_default");
scenario=sixgr.lls6g.config.loadScenarioConfig( ...
    'simulator/configs/scenarios/lls_rejected_ul_due_harq_fixture.yaml');
data=scenario.Data;
data.pusch.short_uci_decision_algorithm='codeword_posterior';
data.pusch.short_uci_minimum_posterior=0.975;
sixgr.lls6g.config.validateScenarioConfig(data);
overridden=sixgr.lls6g.config.ScenarioConfig(data);
internal=sixgr.lls6g.buildInternalConfig(overridden,tempname(fullfile(pwd,'logs')));
assert(internal.phy.pusch.shortUCIDecision.minimumPosterior==0.975 && ...
    string(internal.phy.pusch.shortUCIDecision.algorithm)=="codeword_posterior");
for bad={[],struct(),struct('algorithm',"none",'minimumPosterior',0.99), ...
        struct('algorithm',"codeword_posterior",'minimumPosterior',NaN), ...
        struct('algorithm',"codeword_posterior",'minimumPosterior',0.5), ...
        struct('algorithm',"codeword_posterior",'minimumPosterior',1)}
    reject(@()sixgr.phy.ul.pusch.resolveShortUCIDecisionPolicy(bad{1}), ...
        'sixgr:pusch:InvalidShortUCIDecisionPolicy');
end
cases=0;
for modulation=["pi/2-BPSK","QPSK","16QAM","64QAM","256QAM"]
 for count=1:11
    E=120; if count>2, E=107; end % Include nonintegral small-block repetitions.
    bits=int8(randi([0 1],count,1));
    coded=wire(bits,E,modulation);
    [received,strong]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(10*(1-2*double(coded)),count,modulation);
    assert(isequal(received,bits) && strong.DecodeUsable && strong.DecoderWordUsable);
    assert(~strong.CRCApplicable && isnan(strong.CRCPass) && ~strong.ShortConfidence.SignalPresenceQualified);
    llr=randn(E,1);
    [received,e]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(llr,count,modulation);
    % Independent full-length enumeration, no rate folding, opposite message
    % order and log-sigmoid bit likelihoods instead of a linear score.
    messages=int8(dec2bin(0:2^count-1,count)-'0');
    logp=zeros(2^count,1);
    for k=1:2^count
        code=wire(messages(k,:).',E,modulation);
        signed=(1-2*double(code)).*llr;
        logp(k)=-sum(max(-signed,0)+log1p(exp(-abs(signed))));
    end
    probability=exp(logp-max(logp)); probability=probability/sum(probability);
    selected=find(all(messages==received.',2));
    c=e.ShortConfidence;
    assert(isscalar(selected) && abs(c.SelectedPosterior-probability(selected))<1e-11 && ...
        abs(c.MaximumPosterior-max(probability))<1e-11 && c.DecoderMatchesMaximum);
    [~,weak]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(llr*1e-4,count,modulation);
    assert(~weak.DecodeUsable && ~weak.ShortConfidence.Accepted);
    [zero,tie]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(zeros(E,1),count,modulation); %#ok<ASGLU>
    assert(~tie.DecodeUsable && ~tie.ShortConfidence.UniqueMaximum);
    cases=cases+1;
 end
end
% Captured physical false-ACK LLRs, unmodified from cc35e774's retained MAT:
% logs/tp1afe919f_cbd4_4726_88f8_c7167e14ef34/rejected_ul_receive_only.mat
% SHA256 7bcdbb3fd48febad4403aaf5ecfa4886007a1a1348a1e3496bbc1a9ffdecb9a3
llr=[-.0009921395169690342;.0005047353230345253;-.0004176035967614385; ...
    -.0001739014997941841;-.00018918525794994954;-.00006733420946632233; ...
    -.000018622313111793992;-.0006048624394470536;-.00005744605425176783; ...
    -.00023930409940662293;-.000012941247046657942;-.00010387026962408548; ...
    -.000009515686607756749;-.00026388529648432873;-.0000070158637105450885; ...
    -.00011624437222293308;-.0000008332742990705412;-.000054197617106658705; ...
    -.000008564072458078704;-.00019929517038305334;-.000050228981715212765; ...
    -.00005474283410394659;-.000013888303085711349;.000016145229280078266];
[raw,e]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(llr,1,"64QAM");
assert(isequal(raw,int8(1)) && e.DecoderWordUsable && ~e.DecodeUsable && ...
    e.ShortConfidence.SelectedPosterior<0.51,'Preserve the original raw ACK while rejecting its weak evidence.');
e.DecodeUsable=true;
[usable,crc]=sixgr.truth.puschUCIFieldUsable(e,raw,1);
assert(~usable && isnan(crc),'A stale usability flag must not override failed short-UCI confidence.');
e.ShortConfidence.Accepted=true;
assert(~sixgr.truth.puschUCIFieldUsable(e,raw,1),'A stale acceptance flag must not override actual posterior.');
% Configurable threshold changes acceptance only, never raw decoder bits.
len=24; llr=ones(len,1)*log(9)/len;
lo=struct('algorithm',"codeword_posterior",'minimumPosterior',0.8);
hi=struct('algorithm',"codeword_posterior",'minimumPosterior',0.95);
[a,ea]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(llr,1,"QPSK",lo);
[b,eb]=sixgr.phy.ul.pusch.decodeUCIWithEvidence(llr,1,"QPSK",hi);
assert(isequal(a,b) && ea.DecodeUsable && ~eb.DecodeUsable && ...
    abs(ea.ShortConfidence.SelectedPosterior-.9)<1e-12 && ea.ShortConfidence.PolicySource=="explicit_receiver_policy");
assert(~sixgr.truth.puschUCIFieldUsable(ea,1-a,1), ...
    'Confidence for a different decoded word must not authorize the supplied bits.');
c=sixgr.phy.ul.pusch.shortUCICodewordConfidence([Inf;-Inf],int8(0),1,"QPSK",policy);
assert(~c.Accepted && c.Reason=="nonfinite_informative_LLR");
% Infinite fixed filler terms cancel; they must not create confidence.
c=sixgr.phy.ul.pusch.shortUCICodewordConfidence([1;1;Inf;Inf],int8(0),1,"16QAM",policy);
assert(~c.Accepted && abs(c.SelectedPosterior-1/(1+exp(-2)))<1e-12);
fprintf('PUSCH_SHORT_UCI_CONFIDENCE_PASS math_cases=%d saved_false_ACK_rejected=1 physical_qualification=0\n',cases);
ok=true;
end

function coded=wire(bits,E,modulation)
coded=nrUCIEncode(bits,E,char(modulation)); coded(coded==-1)=1;
y=find(coded==-2); coded(y)=coded(y-1);
end

function reject(action,id)
try, action(); catch err
    assert(strcmp(err.identifier,id),'Expected %s, got %s: %s',id,err.identifier,err.message); return;
end
error('test:MissingRejection','Expected %s.',id);
end
