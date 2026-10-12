function Stage13a_test_fault_hooks()
model = 'Reformable_AI_2025';
tg = (0:0.1:30)';
pvCh = {'PV_Irradiance_Final','PV_Temperature_Final','PV_Voltage_Final','PV_Current_Final'};
bCh  = {'Battery_Voltage_Final','Battery_Current_Final','Battery_Temperature_Final'};
sigs = [pvCh bCh {'PV_Twin_Current','Battery_Twin_Voltage'}];
vals = {'PV_Irradiance_Valid','PV_Temperature_Valid','PV_Voltage_Valid','PV_Current_Valid', ...
        'Battery_Voltage_Valid','Battery_Current_Valid','Battery_Temperature_Valid'};

%      name            asset target type  fault parameter (workspace name)     value  kind
C = { 'PV I bias',     'pv', 3,    1,    'FaultBias_Value',                   0.10,  'bias'; ...
      'PV G stuck',    'pv', 0,    2,    'StuckAt_G',                         600,   'stuck'; ...
      'PV I noise',    'pv', 3,    6,    'ExcessiveNoise_Sigma',              0.15,  'noise'; ...
      'PV Tc drift',   'pv', 1,    7,    'ExtraDrift_Rate',                   0.04,  'drift'; ...
      'Batt V bias',   'b',  0,    1,    'FaultBias_Value_batt',              0.20,  'bias'; ...
      'Batt I stuck',  'b',  1,    2,    'StuckAt_I_batt',                    1.5,   'stuck'; ...
      'Batt T noise',  'b',  2,    6,    'ExcessiveNoise_Sigma_batt',         3,     'noise'; ...
      'Batt V drift',  'b',  0,    7,    'ExtraDrift_Rate_batt',              0.01,  'drift'};

base = runcase(model, tg, sigs, vals, '', 0, 0, '', 0);
L = cell(size(C,1), 1);                                                  % rows are collected, printed at the end
for i = 1:size(C,1)
    R = runcase(model, tg, sigs, vals, C{i,2}, C{i,3}, C{i,4}, C{i,5}, C{i,6});
    D = R.X - base.X;
    k = C{i,3} + 1 + 4*strcmp(C{i,2},'b');
    d = D(:,k);  v = C{i,6};
    switch C{i,7}
        case 'bias',  got = mean(d);              exp_ = v;      ok = abs(got-exp_) < 0.03*abs(exp_);
        case 'stuck', got = mean(R.X(:,k));       exp_ = v;      ok = abs(got-exp_) < 0.02*abs(exp_) && std(R.X(:,k)) < 1e-6;
        case 'noise', got = std(d);               exp_ = v;      ok = abs(got-exp_) < 0.15*exp_;
        case 'drift', got = d(end) - d(1);        exp_ = v*30;   ok = abs(got-exp_) < 0.05*exp_;
    end
    others = max(abs(D(:, setdiff(1:7, k))), [], 'all');
    twinMove = max(abs(D(:, 8:9)), [], 'all');
    okAll = ok && R.valid;
    L{i} = sprintf('%-13s %-8s %10.4g %10.4g  %-9s %-10.2g %-8d %-12.4g %s', C{i,1}, C{i,7}, exp_, got, ternary(ok), others, R.valid, twinMove, ternary(okAll));
end
fprintf('\n=================== FAULT HOOK TEST ===================\n');
fprintf('%-13s %-8s %10s %10s  %-9s %-10s %-8s %-12s %s\n', 'case','kind','expected','measured','target','others','valid','max dTwin','result');
fprintf('%s\n', L{:});
fprintf('"others" = largest change in any non-targeted sensor channel; "max dTwin" = largest change in the Twin outputs.\n');
end

function R = runcase(model, tg, sigs, vals, asset, target, type, pname, pval)
if bdIsLoaded(model), close_system(model, 0); end
evalin('base','reformable_AI;');                                         % reload every parameter first
load_system(model);
c = onCleanup(@() close_system(model, 0));
set_param(model,'FastRestart','off');
set_param(model,'DefaultParameterBehavior','Tunable');
set_param(model,'StopTime','30');
if strcmp(asset,'pv')                                                    % PV sensor-fault selectors
    set_param([model '/Constant7'], 'Value', num2str(target));
    set_param([model '/Constant8'], 'Value', num2str(type));
    set_param([model '/Constant9'], 'Value', '1');
elseif strcmp(asset,'b')                                                 % battery sensor-fault selectors
    set_param([model '/Constant10'], 'Value', num2str(target));
    set_param([model '/Constant11'], 'Value', num2str(type));
    set_param([model '/Constant12'], 'Value', '1');
end
if ~isempty(pname), assignin('base', pname, pval); end                   % fault size, set AFTER the reload
out = sim(model);
R.X = zeros(numel(tg), numel(sigs));
for i = 1:numel(sigs)
    s = out.get(sigs{i});  R.X(:,i) = interp1(s.Time, double(squeeze(s.Data)), tg);
end
R.valid = true;
for i = 1:numel(vals)
    s = out.get(vals{i});  R.valid = R.valid && all(double(s.Data(:)) == 1);
end
clear c
end

function s = ternary(ok)
if ok, s = 'PASS'; else, s = 'FAIL'; end
end