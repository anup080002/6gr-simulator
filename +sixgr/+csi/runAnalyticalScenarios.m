function out=runAnalyticalScenarios(cfg)
%RUNANALYTICALSCENARIOS Exact/sanity evaluations for groups C,E,G-I,J.
ports=double(cfg.csirs.port_counts(:)); modes=string(cfg.power.normalization_modes(:));
pRows=[]; nRows=[];
for p=ports.'
    for mode=modes.'
        if mode=="fixed_total_csirs"
            total=10^(double(cfg.power.total_csirs_power_dbm)/10); per=total/p;
        else
            per=10^(double(cfg.power.per_port_epre_dbm)/10); total=p*per;
        end
        pRows=[pRows;table(p,mode,10*log10(per),10*log10(total), ...
            "ANALYTICAL","PASS",'VariableNames',{'TxPorts','PowerNormalization', ...
            'PerPortEPREdBm','TotalCSIRSPowerdBm','EvidenceClass','Status'})]; %#ok<AGROW>
        snr=double(cfg.simulation.bounded_snr_points_db(:));
        nmse=10.^(-snr/10)./per;
        nRows=[nRows;table(repmat(p,numel(snr),1),repmat(mode,numel(snr),1), ...
            snr,nmse,10*log10(nmse),repmat("ANALYTICAL",numel(snr),1), ...
            repmat("PASS",numel(snr),1),'VariableNames',{'TxPorts', ...
            'PowerNormalization','SNRdB','NMSELinear','NMSEdB', ...
            'EvidenceClass','Status'})]; %#ok<AGROW>
    end
end

lengths=double(cfg.occ.lengths(:)); families=string(cfg.occ.families(:));
phases=double(cfg.occ.phase_sweep_deg_per_chip(:)); occRows=[];
for L=lengths.'
    for family=families.'
        for phase=phases.'
            c=sixgr.phy.refsig.OCCFactory.coupling(family,L,phase);
            occRows=[occRows;table(L,family,phase,c.WorstLeakage,c.MeanLeakage, ...
                c.P95Leakage,c.TotalOffDiagonalEnergy,c.DiagonalPower, ...
                "ANALYTICAL","PASS",'VariableNames',{'CDMSize','OCCFamily', ...
                'PhaseDegPerChip','WorstLeakage','MeanLeakage','P95Leakage', ...
                'TotalOffDiagonalEnergy','DiagonalPower','EvidenceClass','Status'})]; %#ok<AGROW>
        end
    end
end

m1=double(cfg.multislot.m1(:)); increments=double(cfg.multislot.phase_increment_deg(:));
cfoRows=[];
for M=m1.'
    for phase=increments.'
        z=exp(1j*deg2rad(phase)*(0:M-1)); direct=abs(mean(z))^2;
        x=deg2rad(phase)/2;
        if abs(sin(x))<eps, closed=1; else, closed=(sin(M*x)/(M*sin(x)))^2; end
        cfoRows=[cfoRows;table(M,phase,direct,closed,abs(direct-closed), ...
            "ANALYTICAL","PASS",'VariableNames',{'M1','PhaseIncrementDeg', ...
            'DirectGain','ClosedFormGain','AbsoluteError','EvidenceClass','Status'})]; %#ok<AGROW>
    end
end
stds=double(cfg.multislot.iid_phase_std_deg(:)); iidRows=[];
trials=double(cfg.multislot.monte_carlo_trials);
old=rng; cleanup=onCleanup(@() rng(old)); %#ok<NASGU>
iidSeed=double(cfg.reproducibility.base_seed)+11;
rng(iidSeed,"twister");
for M=m1.'
    for sd=stds.'
        sigma=deg2rad(sd); theoretical=1/M+(1-1/M)*exp(-sigma^2);
        phi=sigma*randn(trials,M); samples=abs(mean(exp(1j*phi),2)).^2;
        empirical=mean(samples); [ciLow,ciHigh]=localMeanCI(samples,.95);
        iidRows=[iidRows;table(M,sd,theoretical,empirical,abs(theoretical-empirical), ...
            ciLow,ciHigh,trials,iidSeed,"ANALYTICAL","PASS", ...
            'VariableNames',{'M1','PhaseStdDeg','TheoreticalGain', ...
            'MonteCarloGain','AbsoluteError','GainCI95Low','GainCI95High', ...
            'N','Seed','EvidenceClass','Status'})]; %#ok<AGROW>
    end
end
speeds=double(cfg.multislot.speed_kmph(:)); agingRows=[];
fc=double(cfg.carrier.center_frequency_hz); slot=double(cfg.multislot.slot_duration_s);
for M=m1.'
    for speed=speeds.'
        fd=(speed/3.6)*fc/299792458;
        idx=(0:M-1).'; R=besselj(0,2*pi*fd*abs(idx-idx.')*slot);
        gain=sum(R,"all")/M^2;
        eigMin=min(real(eig((R+R')/2)));
        agingRows=[agingRows;table(M,speed,fd,gain,eigMin, ...
            "ANALYTICAL","PASS",'VariableNames',{'M1','SpeedKmph', ...
            'MaximumDopplerHz','ChannelAgingGain','MinimumEigenvalue', ...
            'EvidenceClass','Status'})]; %#ok<AGROW>
    end
end

% Exact shared-RE sequence identity counterexample.
density=double(cfg.csirs.density(:)); shareRows=[];
for d=density.'
    absolute=(0:round(1/d):63).'; compact=(0:numel(absolute)-1).';
    base=exp(1j*2*pi*mod(17*absolute+3,127)/127);
    compactBase=exp(1j*2*pi*mod(17*compact+3,127)/127);
    shareRows=[shareRows;table(repmat(d,numel(absolute),1),absolute,compact, ...
        real(base),imag(base),real(compactBase),imag(compactBase), ...
        abs(base-compactBase)<1e-12,repmat("ANALYTICAL",numel(absolute),1), ...
        repmat("PASS",numel(absolute),1),'VariableNames',{'Density', ...
        'AbsoluteCoordinate','CompactedIndex','AbsoluteSequenceReal', ...
        'AbsoluteSequenceImag','CompactedSequenceReal','CompactedSequenceImag', ...
        'CompactedMatchesAbsolute','EvidenceClass','Status'})]; %#ok<AGROW>
end

% Prescribed interference-age stochastic sanity model.
ages=double(cfg.interference_age.sanity_ages_slots(:)); probs=double( ...
    cfg.interference_age.pairing_change_probability(:)); trials=double( ...
    cfg.interference_age.sanity_trials); ageRows=[];
ageSeed=double(cfg.reproducibility.base_seed)+19;
rng(ageSeed,"twister");
for prob=probs.'
    for age=ages.'
        retained=rand(trials,1)>(1-(1-prob)^age);
        oldInterference=-log(max(rand(trials,1),realmin));
        newInterference=-log(max(rand(trials,1),realmin));
        actual=retained.*oldInterference+(~retained).*newInterference;
        desired=double(cfg.interference_age.desired_power); noise=double(cfg.interference_age.noise_power);
        err=10*log10(desired./(noise+oldInterference))-10*log10(desired./(noise+actual));
        squared=err.^2; mse=mean(squared); rmse=sqrt(mse);
        seMSE=std(squared,0)/sqrt(trials); z=1.95996398454005;
        rmseLow=sqrt(max(0,mse-z*seMSE)); rmseHigh=sqrt(max(0,mse+z*seMSE));
        exactRetention=(1-prob)^age;
        [retLow,retHigh]=sixgr.lls.stats.wilsonInterval(sum(retained),trials,.95);
        ageRows=[ageRows;table(age,prob,mean(retained),exactRetention, ...
            retLow,retHigh,rmse,rmseLow,rmseHigh,trials,ageSeed, ...
            "SANITY","PASS",'VariableNames',{'InterferenceAgeSlots', ...
            'ChangeProbabilityPerSlot','HypothesisRetentionProbability', ...
            'ExactRetentionProbability','RetentionCI95Low','RetentionCI95High', ...
            'EffectiveSINRRMSEdB','RMSECI95LowdB','RMSECI95HighdB', ...
            'N','Seed','EvidenceClass','Status'})]; %#ok<AGROW>
    end
end

out=struct("PortPower",pRows,"PortNMSE",nRows,"OCC",occRows, ...
    "MultislotCFO",cfoRows,"MultislotIID",iidRows,"MultislotAging",agingRows, ...
    "Sharing",shareRows,"InterferenceAge",ageRows);
end

function [low,high]=localMeanCI(samples,confidence)
samples=double(samples(:)); n=numel(samples); meanValue=mean(samples);
if n<2, low=meanValue; high=meanValue; return; end
z=-sqrt(2)*erfcinv(2*(.5+confidence/2));
half=z*std(samples,0)/sqrt(n); low=meanValue-half; high=meanValue+half;
end
