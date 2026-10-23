function ok=testAntennaPanelGeometryConsistency()
% Geometry/ordering verification against the installed phased array, not
% an over-the-air beam-management or statistical performance qualification.
setup6GRSimToolkit('Verbose',false);
shapes={[2 3 2 2 2],[4 4 2 2 1],[1 2 2 1 1],[3 2 1 1 3]};
for k=1:numel(shapes)
    cfg=sixgr.config.defaultConfig();
    cfg.phy.bsArray=shapes{k}; cfg.phy.fc_Hz=4e9; cfg.channel.fc_Hz=4e9;
    cfg.antenna.bs.spacingLambda=[0.7 0.4];
    shape=shapes{k}; count=prod(shape);
    for explicit=[false true]
        if explicit, cfg.antenna.bs.panelCenterSpacingLambda=[4.1 3.3]; end
        a=sixgr.rf.AntennaArrayFactory.build(cfg,'bs','usePhased',true, ...
            'numPorts',1,'numRFChains',count);
        b=sixgr.rf.AntennaArrayFactory.build(cfg,'bs','usePhased',false, ...
            'numPorts',1,'numRFChains',count);
        assert(max(abs(a.ElementPositions_m-b.ElementPositions_m),[],'all')<1e-13, ...
            'Every numeric element coordinate must match its installed physical element.');
        assert(isequal(a.PolarizationIndexByElement,b.PolarizationIndexByElement));
        assert(isequal(a.PanelIndexByElement,b.PanelIndexByElement));
        if explicit
            assert(isequal(a.PanelCenterSpacing_lambda,[4.1 3.3]));
        else
            assert(isequal(a.PanelCenterSpacing_lambda, ...
                [(shape(2)+1)*0.7 (shape(1)+1)*0.4]));
        end
        assert(max(abs(a.ArrayObj.Spacing/a.Lambda_m- ...
            [0.4 0.7 a.PanelCenterSpacing_lambda([2 1])]))<1e-12);
        % Independent [row col polarization panelRow panelCol] coordinates.
        for q=1:count
            [r,c,p,pr,pc]=ind2sub(shape,q);
            expected=[0,(c-(shape(2)+1)/2)*0.7 + ...
                (pc-(shape(5)+1)/2)*a.PanelCenterSpacing_lambda(1), ...
                ((shape(1)+1)/2-r)*0.4 + ...
                ((shape(4)+1)/2-pr)*a.PanelCenterSpacing_lambda(2)];
            assert(max(abs(b.ElementPositions_m(q,:)/b.Lambda_m-expected))<1e-12);
            assert(b.PolarizationIndexByElement(q)==p && ...
                b.PanelIndexByElement(q)==pr+(pc-1)*shape(4));
        end
        % Geometry changes the phase factors, not unit-total precoder power.
        u=[cosd(17)*cosd(29);cosd(17)*sind(29);sind(17)];
        w=exp(2i*pi*b.ElementPositions_m*u/b.Lambda_m)/sqrt(count);
        assert(abs(sum(abs(w).^2)-1)<1e-12);
    end
end
cfg.phy.bsArray=[2 3 2 2 2];
for bad={[],[0 2],[1 NaN],[2 3 4],[1+1i 2]}
    if isempty(bad{1}), continue; end
    cfg.antenna.bs.panelCenterSpacingLambda=bad{1};
    localReject(@()sixgr.rf.AntennaArrayFactory.build(cfg,'bs','usePhased',false), ...
        'AntennaArrayFactory:InvalidPanelCenterSpacing');
end
cfg.antenna.bs.panelCenterSpacingLambda=[1.4 3];
localReject(@()sixgr.rf.AntennaArrayFactory.build(cfg,'bs','usePhased',false), ...
    'AntennaArrayFactory:OverlappingPanels');
% The numeric runtime adapter must preserve declared panel-center spacing
% on the actual CDL object, not silently restore factory defaults.
cfg.antenna.bs.panelCenterSpacingLambda=[4.1 3.3];
cfg.antenna.bs.polarizationAngles_deg=[0 90];
cfg.antenna.bs.element.polarizationModel=1;
cfg.phy.ueArray=[1 1 1 1 1];
bs=sixgr.rf.AntennaArrayFactory.build(cfg,'bs','usePhased',false,'numPorts',48,'numRFChains',48);
ue=sixgr.rf.AntennaArrayFactory.build(cfg,'ue','usePhased',false,'numPorts',1,'numRFChains',1);
[ch,~]=sixgr.channel.ChannelFactory.create(cfg,'Model','CDL-C', ...
    'NumTxAnt',48,'NumRxAnt',1,'SampleRate',7.68e6,'Fc_Hz',4e9, ...
    'TransmitAntennaRuntime',bs,'ReceiveAntennaRuntime',ue);
assert(max(abs(ch.Object.TransmitAntennaArray.ElementSpacing-[0.4 0.7 3.3 4.1]))<1e-12);
assert(isequal(ch.Object.TransmitAntennaArray.PolarizationAngles,[0 90]), ...
    'The numeric CDL adapter must not replace explicit H/V with default +/-45 degrees.');
assert(strcmp(ch.Object.TransmitAntennaArray.PolarizationModel,'Model-1'));
release(ch.Object);
bad=bs; bad.PolarizationAngles_deg=0;
localReject(@()sixgr.channel.ChannelFactory.create(cfg,'Model','CDL-C', ...
    'NumTxAnt',48,'NumRxAnt',1,'SampleRate',7.68e6,'Fc_Hz',4e9, ...
    'TransmitAntennaRuntime',bad,'ReceiveAntennaRuntime',ue), ...
    'ChannelFactory:InvalidRuntimePolarizationAngles');
bad=bs; bad.ElementPolarizationModel=3;
localReject(@()sixgr.channel.ChannelFactory.create(cfg,'Model','CDL-C', ...
    'NumTxAnt',48,'NumRxAnt',1,'SampleRate',7.68e6,'Fc_Hz',4e9, ...
    'TransmitAntennaRuntime',bad,'ReceiveAntennaRuntime',ue), ...
    'ChannelFactory:InvalidRuntimePolarizationModel');
ok=true; disp('ANTENNA_PANEL_GEOMETRY_CONSISTENCY_PASS');
end

function localReject(f,id)
try, f(); catch cause
    assert(strcmp(cause.identifier,id),'Expected %s, got %s: %s',id,cause.identifier,cause.message);
    return;
end
error('test:MissingError','Expected %s.',id);
end
