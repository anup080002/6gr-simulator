function out=measurePhysicalChainPower(x,plane)
% Actual sample-domain statistics; units must be bound by the power owner.
% Retain no IQ and consume no RNG. Fixed-size temporaries bound memory.
assert(isfloat(x)&&ismatrix(x)&&~isempty(x), ...
    'RF:ChainPowerSamples','Require actual nonempty sample-by-physical-chain IQ.');
plane=string(plane);
assert(isscalar(plane)&&ismember(plane,["rf_input","post_tx_pa","rf_output"]), ...
    'RF:ChainPowerPlane','Declare the actual RF measurement boundary.');
n=size(x,1); ports=size(x,2); energy=zeros(1,ports);
for port=1:ports
    for first=1:65536:n
        z=double(x(first:min(n,first+65535),port));
        assert(all(isfinite(z)),'RF:ChainPowerSamples','RF IQ must be finite.');
        energy(port)=energy(port)+sum(real(z).^2+imag(z).^2);
    end
end
assert(all(isfinite(energy)),'RF:ChainPowerOverflow','Sample energy overflowed.');
out=struct('Contract',"physical_chain_sample_power/v1",'Plane',plane, ...
    'SampleCount',double(n),'PhysicalChainCount',double(ports), ...
    'SquaredMagnitudeSumPerChain',energy,'MeanSquarePerChain',energy/n, ...
    'TotalMeanSquare',sum(energy)/n, ...
    'Population',"all_supplied_samples_including_cp_and_idle_not_active_RE_EPRE", ...
    'Source',"actual_RF_operator_boundary_samples");
end
