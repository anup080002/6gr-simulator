function ok = testRAN1AI1032FWAPopulation()
%TESTRAN1AI1032FWAPOPULATION Verify exact profile quotas and O2I binding.

setup6GRSimToolkit("Verbose", false);
cfg = sixgr.studies.ran1ai1032.loadStudyConfig();
p1 = sixgr.studies.ran1ai1032.buildFWAPopulation(cfg, "Profile-1", 100, 311);
p1b = sixgr.studies.ran1ai1032.buildFWAPopulation(cfg, "Profile-1", 100, 311);
p3 = sixgr.studies.ran1ai1032.buildFWAPopulation(cfg, "Profile-3", 100, 312);

assert(isequaln(p1, p1b), "Population assignment must replay exactly from its paired seed.");
assert(nnz(p1.Indoor) == 80 && nnz(p1.Outdoor) == 20 && ...
    nnz(p1.O2IProfile == "low") == 40 && ...
    nnz(p1.O2IProfile == "high") == 40, ...
    "Profile-1 must be exactly 80%% indoor, 20%% rooftop and 50/50 indoor low/high O2I.");
assert(all(isnan(p1.FloorNumber(p1.Indoor))) && ...
    all(p1.FloorNumber(p1.Outdoor) >= 4 & p1.FloorNumber(p1.Outdoor) <= 8), ...
    "Only rooftop CPEs may carry configured floor numbers 4--8.");
assert(~any(p3.Indoor) && all(p3.Outdoor) && ...
    all(p3.O2IProfile == "not_applicable_outdoor"), ...
    "Profile-3 must contain only outdoor rooftop CPEs without O2I loss.");

ue = struct("K", 100, "id", (1:100).', "pos_m", zeros(100,3));
ue = sixgr.studies.ran1ai1032.applyFWAPopulation(ue, p1);
assert(isequal(ue.indoor, p1.Indoor) && ...
    isequal(ue.pos_m(:,3), p1.Height_m) && ...
    isequal(ue.o2i_model, p1.O2IProfile), ...
    "Applied population must preserve exact identity, height and O2I class.");

geometryCfg = sixgr.config.defaultConfig();
geometryCfg.phy.fc_Hz = 7e9;
geometryCfg.channel.pathlossEnabled = true;
geometryCfg.channel.shadowFadingEnabled = false;
geometryCfg.channel.losEnabled = false;
geometryCfg.channel.propagationScenario = "UMa";
geometryCfg.channel.o2i.indoorDistance_m = 10;
geometryCfg.channel.o2i.model = "low";
layout = struct("bs", struct("pos_m", [0 0 25]), ...
    "wraparoundEnabled", false, "area_m", [1000 1000]);
ue.pos_m(:,1) = (10:10:1000).';
model = sixgr.channel.TR38901Plus(geometryCfg, "Seed", 987);
state = sixgr.system.GeometryEngine.buildLargeScaleState(geometryCfg, layout, ue, model);
assert(all(state.O2I_dB(~p1.Indoor,1) == 0) && ...
    all(state.O2I_dB(p1.Indoor,1) > 0), ...
    "Only indoor receivers may receive strict O2I penetration loss.");
lowMean = mean(state.O2I_dB(p1.O2IProfile == "low",1));
highMean = mean(state.O2I_dB(p1.O2IProfile == "high",1));
assert(highMean > lowMean, ...
    "Configured high-loss O2I receivers must exceed low-loss receivers on this deterministic fixture.");
% A multicell state stores K-by-cell identities. Flattening that matrix
% previously passed K*cellCount values to a K-receiver pathloss call.
layout.bs.pos_m=[0 0 25;500 0 25;0 500 25];
multi=sixgr.system.GeometryEngine.buildLargeScaleState(geometryCfg,layout,ue,model);
assert(isequal(size(multi.O2I_dB),[100 3]));
assert(all(multi.O2I_dB(~p1.Indoor,:)==0,'all'));
assert(isequal(multi.O2IModelPerReceiver,repmat(p1.O2IProfile,1,3)));
multi.O2IModelPerReceiver(p1.Indoor,2)="high";
[~,~,e]=model.pathlossFromGeometryState(multi,2);
assert(isequal(e.o2iModelPerReceiver,multi.O2IModelPerReceiver(:,2)), ...
    'The requested cell must own the receiver model column; never use the first cell by default.');
bad=multi; bad.O2IModelPerReceiver=bad.O2IModelPerReceiver(:);
try
    model.pathlossFromGeometryState(bad,2);
    error('test:ExpectedError','Malformed flattened O2I identity must fail.');
catch ME
    assert(strcmp(ME.identifier,'TR38901Plus:pathlossFromGeometryState:BadO2IModelShape'));
end
ok = true;
end
