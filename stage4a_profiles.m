% step4a_profiles.m -- what an "operating profile" is (no Simulink)
t = (0:0.5:150)';                 % time axis: 150 s, one point every 0.5 s
ramp = @(x) (min(max(x,0),1).^2) .* (3 - 2*min(max(x,0),1));  % smooth 0->1 transition

%% PV irradiance: 900 W/m2 with four cloud dips
G = 900*ones(size(t));
starts = [20 55 85 115];          % when each cloud arrives (s)
lens   = [10  8 12  6];           % how long it lasts (s)
depth  = [0.5 0.6 0.4 0.7];       % how much sunlight it blocks (fraction)
for k = 1:4
    dip = ramp((t - starts(k))/3) .* (1 - ramp((t - (starts(k)+lens(k)))/3));
    G = G - 900*depth(k)*dip;
end

%% Module temperature: ambient + sunlight heating, delayed (thermal lag)
Tamb = 20;  a = 0.02;  tau = 40;  dt = 0.5;
Tc = zeros(size(t));  Tc(1) = Tamb + a*G(1);
for k = 2:numel(t)
    Tc(k) = Tc(k-1) + dt/tau * ((Tamb + a*G(k)) - Tc(k-1));
end

%% Battery discharge current: 1 A, steps to 2.5 A at 40 s, down to 0.6 A at 90 s
I = 1.0*ones(size(t));
I = I + (2.5-1.0)*ramp((t-40)/2);
I = I + (0.6-2.5)*ramp((t-90)/2);

figure;
subplot(3,1,1); plot(t,G);  ylabel('G (W/m^2)');
subplot(3,1,2); plot(t,Tc); ylabel('T_c (°C)');
subplot(3,1,3); plot(t,I);  ylabel('I_{batt} (A)'); xlabel('time (s)');