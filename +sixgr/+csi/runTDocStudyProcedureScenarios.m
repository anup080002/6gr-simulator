function out=runTDocStudyProcedureScenarios(cfg)
%RUNPROCEDURESCENARIOS Deterministic/stochastic procedure evidence only.
state=sixgr.csi.CSITDocStudyStateTimelineEngine.run(cfg);

variants=string(cfg.early_csi.variants(:)); candidates=double(cfg.early_csi.monitored_candidates(:));
early=[];
for v=variants.'
    for c=candidates.'
        firstInformed=double(any(v==["E1","E2"]));
        refinementStart=localIf(v=="E3",2,localIf(v=="E4",1,Inf));
        early=[early;table(v,c,firstInformed,refinementStart,c*double(cfg.carrier.n_rb), ...
            c*double(cfg.arrays.rx_antennas(1))*double(cfg.carrier.n_rb), ...
            "PROCEDURE","PASS",'VariableNames',{'Variant','Candidates', ...
            'FirstPDSCHCSIInformed','DMRSRefinementStartsAtTransmission', ...
            'MeasurementREUnits','EstimatorOperationUnits','EvidenceClass','Status'})]; %#ok<AGROW>
    end
end

rho=double(cfg.event_csi.gauss_markov_rho); slots=double(cfg.event_csi.sanity_slots);
periods=double(cfg.event_csi.periodic_periods(:)); thresholds=double(cfg.event_csi.thresholds(:));
old=rng; cleanup=onCleanup(@() rng(old)); %#ok<NASGU>
eventSeed=double(cfg.reproducibility.base_seed)+31;
rng(eventSeed,"twister");
x=zeros(slots,1); innovation=randn(slots,1);
for t=2:slots, x(t)=rho*x(t-1)+sqrt(1-rho^2)*innovation(t); end
event=[];
for period=periods.'
    sample=1:period:slots; held=zeros(slots,1);
    for k=1:numel(sample), held(sample(k):min(slots,sample(k)+period-1))=x(sample(k)); end
    absError=abs(x-held); [ciLow,ciHigh]=localMeanCI(absError,.95);
    event=[event;table("periodic",period,NaN,100*numel(sample)/slots, ...
        mean(absError),ciLow,ciHigh,slots,eventSeed,"SANITY","PASS", ...
        'VariableNames',{'Policy','PeriodSlots','Threshold', ...
        'ReportsPer100Slots','MeanAbsoluteStateError','MAECI95Low', ...
        'MAECI95High','N','Seed','EvidenceClass','Status'})]; %#ok<AGROW>
end
for threshold=thresholds.'
    last=x(1); reports=1; absError=zeros(slots,1);
    for t=1:slots
        if abs(x(t)-last)>=threshold, last=x(t); reports=reports+1; end
        absError(t)=abs(x(t)-last);
    end
    [ciLow,ciHigh]=localMeanCI(absError,.95);
    event=[event;table("event",NaN,threshold,100*reports/slots,mean(absError), ...
        ciLow,ciHigh,slots,eventSeed,"SANITY","PASS", ...
        'VariableNames',{'Policy','PeriodSlots','Threshold', ...
        'ReportsPer100Slots','MeanAbsoluteStateError','MAECI95Low', ...
        'MAECI95High','N','Seed','EvidenceClass','Status'})]; %#ok<AGROW>
end

hyp=string(cfg.energy_hypotheses.names(:)); energy=[];
for h=1:numel(hyp)
    ports=double(cfg.energy_hypotheses.active_port_counts(:)).';
    trps=double(cfg.energy_hypotheses.active_trp_counts(:)).';
    pDb=double(cfg.energy_hypotheses.per_hypothesis_power_offset_db(:)).';
    qBits=double(cfg.energy_hypotheses.differential_quantizer_bits(2));
    reportBits=localIf(h==1,12,12+(h-1)*qBits+ceil(log2(numel(hyp))));
    txEnergy=trps(h)*ports(h)*10^(pDb(h)/10);
    energy=[energy;table(hyp(h),ports(h),trps(h),pDb(h),reportBits, ...
        txEnergy,ports(h)*trps(h),ports(h)*16, ...
        "PROCEDURE","PASS",'VariableNames',{'Hypothesis','ActivePorts', ...
        'ActiveTRPs','PowerOffsetDb','ReportBits','PhysicalTxEnergyUnits', ...
        'ChannelSearches','MemoryBytes','EvidenceClass','Status'})]; %#ok<AGROW>
end

labels=string(cfg.sharing.pair_labels(:)); sharing=[];
for pair=1:numel(labels)
    periodA=double(cfg.sharing.period_a_slots(pair));
    periodB=double(cfg.sharing.period_b_slots(pair));
    firstB=double(cfg.sharing.initial_b_slots(pair));
    horizon=double(cfg.sharing.horizon_slots);
    occasionsA=0:periodA:horizon-1;
    typeB=string(cfg.sharing.type_b(pair));
    if typeB=="aperiodic"
        occasionsB=firstB;
    else
        occasionsB=firstB:periodB:horizon-1;
        if typeB=="semipersistent"
            occasionsB=occasionsB(occasionsB< ...
                firstB+double(cfg.sharing.semipersistent_active_slots));
        end
    end
    for slot=occasionsA
        prior=occasionsB(occasionsB<=slot);
        if isempty(prior), age=NaN; available=false;
        else, age=slot-prior(end); available=true; end
        common=any(occasionsB==slot);
        stale=~available || age>double(cfg.sharing.maximum_state_age_slots);
        sharing=[sharing;table(labels(pair),string(cfg.sharing.type_a(pair)), ...
            typeB,slot,localLast(prior),age,common,available,stale, ...
            "PROCEDURE","PASS",'VariableNames',{'PairLabel','TypeA', ...
            'TypeB','ConsumerSlot','ProducerSlot','StateAgeSlots', ...
            'CommonOccasion','StateAvailable','StateStale','EvidenceClass', ...
            'Status'})]; %#ok<AGROW>
    end
end

out=struct("StateSummary",state.Summary,"StateEvents",state.Events, ...
    "EarlyCSI",early,"EventPareto",event,"Energy",energy, ...
    "SharingTimeAge",sharing);
end

function value=localIf(tf,a,b)
if tf, value=a; else, value=b; end
end

function value=localLast(values)
if isempty(values), value=NaN; else, value=values(end); end
end

function [low,high]=localMeanCI(samples,confidence)
samples=double(samples(:)); n=numel(samples); meanValue=mean(samples);
if n<2, low=meanValue; high=meanValue; return; end
z=-sqrt(2)*erfcinv(2*(.5+confidence/2));
half=z*std(samples,0)/sqrt(n); low=meanValue-half; high=meanValue+half;
end
