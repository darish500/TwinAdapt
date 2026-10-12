function step4c_noise_test()
model = 'Reformable_AI_2025';
seeds = [1 2 1];                          % run 3 repeats run 1
tg = (0:0.1:60)';                         % common time grid
R  = zeros(numel(tg), numel(seeds));      % PV residual of each run
B  = zeros(numel(tg), numel(seeds));      % battery residual of each run

if bdIsLoaded(model), close_system(model, 0); end
evalin('base','reformable_AI;');
load_system(model);
c = onCleanup(@() close_system(model, 0));
set_param(model,'FastRestart','off');
set_param(model,'StopTime','60');

for k = 1:numel(seeds)
    rng(seeds(k));                        % set the random generator BEFORE the run
    out = sim(model);
    r = out.PV_Residual_Current;
    b = out.Battery_Residual_Voltage;
    R(:,k) = interp1(r.Time, squeeze(r.Data), tg);
    B(:,k) = interp1(b.Time, squeeze(b.Data), tg);
end

hp = @(x) x - movmean(x, 21);             % remove the slow trend, keep the noise
for name = ["PV","Battery"]
    if name == "PV", X = R; else, X = B; end
    N = hp(X);
    c12 = corr(N(:,1), N(:,2));
    c13 = corr(N(:,1), N(:,3));
    fprintf('%-8s noise corr  seed1 vs seed2 = %6.3f   seed1 vs seed1 = %6.3f\n', name, c12, c13);
end
end