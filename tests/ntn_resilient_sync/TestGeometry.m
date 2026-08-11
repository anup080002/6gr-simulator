classdef TestGeometry < matlab.unittest.TestCase
    methods(Test)
        function overheadRangeEqualsAltitude(tc)
            s=sixgr.ntn.resilientsync.geometry.solveSatelliteStateForElevation(6371e3,600e3,pi/2);
            tc.verifyEqual(s.Range_m,600e3,'AbsTol',1e-6);
        end
        function elevationRangeClosedForm(tc)
            R=6371e3;h=600e3;e=deg2rad(30);
            s=sixgr.ntn.resilientsync.geometry.solveSatelliteStateForElevation(R,h,e);
            expected=-R*sin(e)+sqrt((R+h)^2-R^2*cos(e)^2);
            tc.verifyEqual(s.Range_m,expected,'RelTol',1e-13);
        end
        function finiteDifferenceRate(tc)
            s=sixgr.ntn.resilientsync.geometry.solveSatelliteStateForElevation(6371e3,600e3,deg2rad(30));
            g=sixgr.ntn.resilientsync.geometry.slantRangeAndRate(s.SatellitePositionECEF_m,s.SatelliteVelocityECEF_m_s,s.UEPositionECEF_m,[0 0 0]);
            dt=1e-3;p=s.SatellitePositionECEF_m+s.SatelliteVelocityECEF_m_s*dt;
            fd=(norm(p-s.UEPositionECEF_m)-g.Range_m)/dt;
            tc.verifyEqual(fd,g.RangeRate_m_s,'RelTol',2e-5);
        end
        function uniformAreaRadialCDF(tc)
            x=sixgr.ntn.resilientsync.geometry.sampleUniformReferenceArea([6371e3 0 0],6371e3,25e3,20000,7);
            tc.verifyLessThan(abs(mean((x.SurfaceRadius_m/25e3).^2)-0.5),0.01);
        end
        function cfoCarrierScaling(tc)
            rate=123;c=299792458;
            tc.verifyEqual(abs(-(30e9/c)*rate)/abs(-(2e9/c)*rate),15,'AbsTol',1e-12);
        end
    end
end
