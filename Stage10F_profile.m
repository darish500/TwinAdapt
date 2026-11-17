function p = Stage10F_profile(asset, id, seed)
% Operating profile for Dataset F.  asset: 'pv' or 'batt';  id: 1..5;  seed: any integer.
% ids 1..4 call the original Stage10_profile unchanged (same code, same seeds -> same profile).
% id 5 is a NEW profile family, added only for the untouched final test (Regime B-F):
%   PV   5 : irradiance oscillates continuously (sinusoid), cell temperature follows through thermal lag
%   batt 5 : periodic duty-cycle load (square-ish wave between a low and a high current)
% Neither shape exists in Dataset A (A has: steady, one ramp, clouds, plateaus / low, moderate, stepped, pulses).
if id <= 4
    p = Stage10_profile(asset, id, seed);
    return
end
rng(seed);
U = @(a,b) a + (b-a)*rand;
t = (0:0.5:150)';
ramp = @(x) (min(max(x,0),1).^2) .* (3 - 2*min(max(x,0),1));
if strcmp(asset,'pv')
    base = U(500,850);  amp = U(120,250);  per = U(25,70);  ph = U(0,2*pi);
    G  = base + amp*sin(2*pi*t/per + ph);
    G  = min(max(G,200),1100);
    Tc = lagf(U(10,35) + 0.02*G, 0.5, 40);
    Tc = min(max(Tc,5),55);
    V  = min(max(U(16.4,17.6) + 0.3*sin(2*pi*t/U(60,200) + U(0,2*pi)), 16), 18);
    p = struct('t',t,'G',G,'Tc',Tc,'V',V);
else
    lo = U(0.3,1.0);  hi = U(2.5,4.2);  P = U(15,30);  duty = U(0.3,0.6);  s0 = U(0,P);
    I = lo*ones(size(t));
    for s = (s0 - P):P:150
        I = I + (hi-lo)*ramp((t-s)/1.5).*(1-ramp((t-(s+duty*P))/1.5));
    end
    I = min(max(I,0.3),4.2);
    p = struct('t',t,'I',I,'Tbat',U(15,35),'soc0',U(60,100));
end
end

function y = lagf(x, dt, tau)
y = zeros(size(x)); y(1) = x(1);
for k = 2:numel(x), y(k) = y(k-1) + dt/tau*(x(k) - y(k-1)); end
end