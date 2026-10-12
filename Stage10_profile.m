function p = Stage10_profile(asset, id, seed)
% Operating profile for one run.  asset: 'pv' or 'batt';  id: 1..4;  seed: any integer.
rng(seed);
U = @(a,b) a + (b-a)*rand;                           % uniform random number in [a,b]
t = (0:0.5:150)';
ramp = @(x) (min(max(x,0),1).^2) .* (3 - 2*min(max(x,0),1));   % smooth 0->1 step

if strcmp(asset,'pv')
    switch id
        case 1                                       % steady, moderate
            G = U(500,900)*ones(size(t));
        case 2                                       % one gradual ramp up or down
            g1 = U(250,500); g2 = U(700,1050);
            if rand < 0.5, [g1,g2] = deal(g2,g1); end
            G = g1 + (g2-g1)*ramp((t-U(10,40))/U(60,100));
        case 3                                       % clouds: 3-6 smooth dips
            base = U(700,1000); G = base*ones(size(t));
            for k = 1:randi([3 6])
                s = U(5,130); L = U(6,15); d = U(0.3,0.7);
                G = G - base*d*ramp((t-s)/3).*(1-ramp((t-(s+L))/3));
            end
        case 4                                       % plateaus: high / low levels
            lev = [U(250,1050) U(250,1050) U(250,1050)];
            sw  = sort([U(30,60) U(80,120)]);
            G = lev(1) + (lev(2)-lev(1))*ramp((t-sw(1))/3) + (lev(3)-lev(2))*ramp((t-sw(2))/3);
    end
    G = min(max(G,200),1100);
    switch id
        case {1,3}                                   % temperature follows irradiance through thermal lag
            Tc = lagf(U(10,35) + 0.02*G, 0.5, 40);
        case 2                                       % temperature on its own slow sinusoid
            Tc = U(20,32) + U(5,12)*sin(2*pi*t/U(100,250) + U(0,2*pi));
        case 4                                       % temperature on its own plateaus
            tl = [U(15,50) U(15,50) U(15,50)]; sw2 = sort([U(30,60) U(80,120)]);
            Tc = tl(1) + (tl(2)-tl(1))*ramp((t-sw2(1))/8) + (tl(3)-tl(2))*ramp((t-sw2(2))/8);
    end
    Tc = min(max(Tc,5),55);
    V  = min(max(U(16.4,17.6) + 0.3*sin(2*pi*t/U(60,200) + U(0,2*pi)), 16), 18);
    p = struct('t',t,'G',G,'Tc',Tc,'V',V);
else
    switch id
        case 1, I = U(0.3,1.0)*ones(size(t));        % low load
        case 2, I = U(1.5,2.5)*ones(size(t));        % moderate load
        case 3                                       % stepped load
            n = randi([3 5]); sw = sort(10 + 130*rand(1,n-1));
            lv = arrayfun(@(~) U(0.3,4.2), 1:n); I = lv(1)*ones(size(t));
            for k = 1:n-1, I = I + (lv(k+1)-lv(k))*ramp((t-sw(k))/2); end
        case 4                                       % low base + pulses
            I = U(0.3,1.0)*ones(size(t));
            for k = 1:randi([3 6])
                s = U(5,130); W = U(5,15); a = U(2.5,4.2) - I(1);
                I = I + a*ramp((t-s)/1.5).*(1-ramp((t-(s+W))/1.5));
            end
    end
    I = min(max(I,0.3),4.2);
    p = struct('t',t,'I',I,'Tbat',U(15,35),'soc0',U(60,100));
end
end

function y = lagf(x, dt, tau)
y = zeros(size(x)); y(1) = x(1);
for k = 2:numel(x), y(k) = y(k-1) + dt/tau*(x(k) - y(k-1)); end
end