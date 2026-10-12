function step4c2_noise_patch()
model = 'Reformable_AI_2025';
seeds = [1 2 1];
tg = (0:0.1:60)';
R = zeros(numel(tg), numel(seeds));
B = R;

for k = 1:numel(seeds)
    if bdIsLoaded(model), close_system(model, 0); end
    evalin('base','reformable_AI;');
    load_system(model);
    c = onCleanup(@() close_system(model, 0));
    set_param(model,'FastRestart','off');
    set_param(model,'StopTime','60');

    n = patch_noise(model, seeds(k));            % edit the sensor blocks (memory only)
    if k == 1, fprintf('patched %d blocks that use randn\n', n); end

    out = sim(model);
    r = out.PV_Residual_Current;
    b = out.Battery_Residual_Voltage;
    R(:,k) = interp1(r.Time, squeeze(r.Data), tg);
    B(:,k) = interp1(b.Time, squeeze(b.Data), tg);
    clear c                                      % closes the model without saving
end

hp = @(x) x - movmean(x, 21);
for name = ["PV","Battery"]
    if name == "PV", X = R; else, X = B; end
    N = hp(X);
    fprintf('%-8s noise corr  seed1 vs seed2 = %6.3f   seed1 vs seed1 = %6.3f\n', ...
        name, corr(N(:,1),N(:,2)), corr(N(:,1),N(:,3)));
end
end

function n = patch_noise(model, seed)
charts = sfroot().find('-isa','Stateflow.EMChart');   % every MATLAB Function block
n = 0;
for i = 1:numel(charts)
    ch = charts(i);
    if ~startsWith(ch.Path, model), continue; end     % only blocks of our model
    s = ch.Script;                                    % the block's code as text
    if isempty(regexp(s, '\<randn\>', 'once')), continue; end   % skip blocks with no noise
    n = n + 1;
    skip = seed*20000 + n*10007;                      % draws to throw away: differs per run AND per block
    s = regexprep(s, '\<randn\>', 's10_randn()');     % every randn becomes s10_randn()
    s = [s newline newline ...
        'function r = s10_randn()' newline ...
        'persistent started;' newline ...
        'if isempty(started)' newline ...
        '    started = true;' newline ...
        '    for kk = 1:' num2str(skip) newline ...
        '        r0 = randn; %#ok<NASGU>' newline ...
        '    end' newline ...
        'end' newline ...
        'r = randn;' newline ...
        'end' newline];
    ch.Script = s;                                    % write the edited code back
end
end