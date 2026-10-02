function out = runRFComponentQualification(study, cfg)
%RUNRFCOMPONENTQUALIFICATION Measure RF component execution on actual samples.
% No decoded BLER, RF mask approval, array approval or campaign PASS is
% inferred from these checks. All numerical tolerances are explicit inputs.
if nargin<2
    cfg=localQualificationConfig(study);
end
localValidateEVMAssumptions(study);
required=["SampleRateHz","SampleCount","Seed","Chains", ...
    "EVMRelativeTolerance","PowerToleranceDb","CFOToleranceHz"];
if ~all(isfield(cfg,required))
    error('sixgr:ran1ai1032:RFQualificationConfigMissing','Qualification requires sample rate/count, seeds/chains and explicit tolerances.');
end
validateattributes(cfg.SampleCount,{'numeric'},{'scalar','integer','>=',2});
validateattributes(cfg.Chains,{'numeric'},{'vector','integer','positive'});
validateattributes(cfg.SampleRateHz,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(cfg.EVMRelativeTolerance,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(cfg.PowerToleranceDb,{'numeric'},{'scalar','real','finite','positive'});
validateattributes(cfg.CFOToleranceHz,{'numeric'},{'scalar','real','finite','positive'});
rowTemplate=struct('CheckID',"",'Chains',NaN,'Expected',NaN, ...
    'Measured',NaN,'Units',"",'Pass',false, ...
    'MeasurementSource',"",'Seed',NaN, ...
    'SourceClassification',"executed_sample_domain_rf_component");
rows=repmat(rowTemplate,0,1); k=0;
for chains=double(cfg.Chains(:).')
    stream=RandStream('Threefry','Seed',double(cfg.Seed));
    % Independent QPSK diagnostic symbols are actual component stimulus.
    x=complex(2*randi(stream,[0 1],cfg.SampleCount,chains)-1, ...
        2*randi(stream,[0 1],cfg.SampleCount,chains)-1)/sqrt(2*chains);
    branch=struct('Endpoint',"rx",'SampleRateHz',cfg.SampleRateHz, ...
        'CarrierFrequencyHz',study.carrier.frequency_hz, ...
        'SCSHz',1000*study.carrier.scs_khz,'NormalizedCFO',0, ...
        'SampleOffset',0,'EVMPercent',0,'EVMCorrelation',eye(chains), ...
        'EVMReferencePowerPerChain',mean(abs(x).^2,1), ...
        'Seed',cfg.Seed,'PhaseNoiseEnabled',false);
    cases=study.rf.evm_cases;
    for i=1:numel(cases)
        c=localItem(cases,i);
        for endpoint=["tx","rx"]
            b=branch; b.Endpoint=endpoint;
            if endpoint=="tx"
                b.EVMPercent=c.tx_percent;
                b.RequestedPowerdBm=0; b.PowerClassMaxdBm=0; b.MPRdB=0;
            else
                b.EVMPercent=c.rx_percent;
            end
            [~,e]=sixgr.studies.ran1ai1032.applyRFStudyBranch(x,b);
            delta=abs(e.MeasuredAdditiveEVMPercent-b.EVMPercent)/b.EVMPercent;
            add("additive_evm_"+string(c.id)+"_"+endpoint,b.EVMPercent, ...
                e.MeasuredAdditiveEVMPercent,"percent", ...
                delta<=cfg.EVMRelativeTolerance,"independent_chain_diagnostic");
        end
    end
    for normalized=double(study.rf.residual_normalized_cfo(:).')
        b=branch; b.NormalizedCFO=normalized;
        y=sixgr.studies.ran1ai1032.applyRFStudyBranch(x,b);
        ratio=y./x;
        increments=ratio(2:end,:).*conj(ratio(1:end-1,:));
        measured=angle(sum(increments(:)))*cfg.SampleRateHz/(2*pi);
        expected=normalized*branch.SCSHz;
        add("cfo_"+string(normalized),expected,measured,"Hz", ...
            abs(measured-expected)<=cfg.CFOToleranceHz,"sample_phase_increment");
    end
    mprCases=study.rf.mpr_cases;
    for i=1:numel(mprCases)
        c=localItem(mprCases,i);
        for powerCase=1:numel(study.sls.ue_power_cases)
            p=localItem(study.sls.ue_power_cases,powerCase);
            maximum=p.tx_power_dbm-c.mpr_db;
            % Exercise both sides of the cap with a nonzero separation.
            for requested=[maximum-3 maximum+3]
                b=branch; b.Endpoint="tx"; b.RequestedPowerdBm=requested;
                b.PowerClassMaxdBm=p.tx_power_dbm; b.MPRdB=c.mpr_db;
                [~,e]=sixgr.studies.ran1ai1032.applyRFStudyBranch(x,b);
                measured=10*log10(e.OutputTotalPowerW)+30;
                expected=min(requested,maximum);
                pass=abs(measured-expected)<=cfg.PowerToleranceDb && ...
                    e.CapActive==(requested>maximum);
                add("mpr_"+string(c.modulation)+"_"+string(p.id)+ ...
                    "_request_"+string(requested),expected,measured,"dBm",pass, ...
                    "measured_sum_over_physical_chains");
            end
        end
    end
end
T=struct2table(rows);
out=struct('Checks',T,'ComponentChecksPassed',all(T.Pass), ...
    'QualificationConfig',cfg,'EVMAssumptions',study.rf.additive_evm, ...
    'DecodedPHYQualified',false,'ArrayPolarizationQualified',false, ...
    'PhaseNoiseAt7GHzQualified',false,'PrimaryResultEligible',false, ...
    'Status',"component_measurements_only", ...
    'SourceClassification',"executed_sample_domain_rf_component", ...
    'Pending', ["decoded_PUSCH_with_RF_branches"; ...
       "versioned_7GHz_oscillator_mask_and_independent_PSD_qualification"; ...
       "exact_7GHz_array_geometry_polarization_element_pattern_and_channel_binding"]);

    function add(id,expected,measured,units,pass,source)
        k=k+1;
        rows(k)=struct('CheckID',id,'Chains',chains,'Expected',expected, ...
            'Measured',measured,'Units',units,'Pass',logical(pass), ...
            'MeasurementSource',source,'Seed',double(cfg.Seed), ...
            'SourceClassification',"executed_sample_domain_rf_component");
    end
end

function value=localItem(values,i)
if iscell(values), value=values{i}; else, value=values(i); end
end

function cfg=localQualificationConfig(study)
if ~isfield(study,'rf') || ~isfield(study.rf,'component_qualification')
    error('sixgr:ran1ai1032:RFQualificationConfigMissing', ...
        'Study YAML must provide rf.component_qualification.');
end
raw=study.rf.component_qualification;
source=["sample_rate_hz","sample_count","seed","chains", ...
    "evm_relative_tolerance","power_tolerance_db","cfo_tolerance_hz"];
target=["SampleRateHz","SampleCount","Seed","Chains", ...
    "EVMRelativeTolerance","PowerToleranceDb","CFOToleranceHz"];
if ~all(isfield(raw,source))
    error('sixgr:ran1ai1032:RFQualificationConfigMissing', ...
        'Study YAML must explicitly configure all RF component measurement parameters and tolerances.');
end
cfg=struct();
for i=1:numel(source), cfg.(target(i))=raw.(source(i)); end
end

function localValidateEVMAssumptions(study)
if ~isfield(study.rf,'additive_evm')
    error('sixgr:ran1ai1032:RFQualificationConfigMissing', ...
        'Study YAML must declare rf.additive_evm injection and covariance assumptions.');
end
a=study.rf.additive_evm;
required=["tx_injection_plane","rx_injection_plane","covariance", ...
    "reference_power","tx_power_cap_includes_distortion","classification"];
if ~all(isfield(a,required)) || ...
        string(a.tx_injection_plane)~="post_ofdm_precoding_pre_channel" || ...
        string(a.rx_injection_plane)~="post_channel_pre_receiver" || ...
        string(a.covariance)~="independent_chains" || ...
        string(a.reference_power)~="clean_signal_per_chain" || ...
        ~isequal(a.tx_power_cap_includes_distortion,true) || ...
        strlength(string(a.classification))==0
    error('sixgr:ran1ai1032:RFQualificationAssumptionMismatch', ...
        'RF component qualification requires explicit supported EVM planes, independent chains, clean reference power and total composite TX power cap.');
end
end
