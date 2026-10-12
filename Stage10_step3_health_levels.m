function T = Stage10_step3_health_levels()
% Stage10_step3_health_levels  STEP 3 ONLY: hold health at D = 0, .25, .5, .75, 1
% and compare what the model LOGS with what the aging equations predict.
%
% No profiles, no seeds, no datasets -- just the health override.
% Run from the project folder:   T = Stage10_step3_health_levels
%
% Method: the Clock -> t branch of PV_Degradation_Model and
% Battery_Degradation_Model is replaced (in memory only) by a Constant
% t = D*T_life, so D = min(1, t/T_life) = D for the whole run.
% The model is closed WITHOUT saving after every level.

model  = 'Reformable_AI_2025';
levels = [0 0.25 0.5 0.75 1.0];
Tstop  = 30;                       % short: health is constant, we only need steady values
rows   = zeros(numel(levels), 14);

for i = 1:numel(levels)
    D = levels(i);
    if bdIsLoaded(model), close_system(model, 0); end
    evalin('base', 'reformable_AI;');                 % same workspace setup as Stage 9
    load_system(model);
    c = onCleanup(@() close_system(model, 0));        %#ok<NASGU>  never save
    set_param(model, 'FastRestart', 'off');
    set_param(model, 'StopTime', num2str(Tstop));

    TlifePV = evalin('base', 'T_life');
    TlifeB  = evalin('base', 'T_life_batt');
    const_time(model, 'PV_Degradation_Model',      D * TlifePV);
    const_time(model, 'Battery_Degradation_Model', D * TlifeB);

    out = sim(model);
    m = @(sig) mean(sig.Data(sig.Time >= 5));          % steady value after the first 5 s
    rows(i,:) = [D, m(out.D_index), m(out.Rs_aged), m(out.Rsh_aged), m(out.Iph_ref_aged), ...
                 m(out.PV_Current_Final), m(out.D_batt), m(out.R0_aged), m(out.R1_aged), ...
                 m(out.Capacity_aged), m(out.OCV_deltaV), m(out.PV_Residual_Current), ...
                 m(out.Battery_Residual_Voltage), m(out.PV_Voltage_Final)];
    clear c
end

T = array2table(rows, 'VariableNames', {'D_set','D_index','Rs_aged','Rsh_aged','Iph_aged', ...
    'PV_I_meas','D_batt','R0_aged','R1_aged','Capacity','OCV_shift','PV_ResI','Batt_ResV','PV_V_meas'});
disp(T);

% ---- compare with the model's own equations ----
Rs0 = 0.012837780207248; Rsh0 = 500; Iph0 = 1.8200467301198948;   % from PV_Params_Stage1.mat
D = T.D_set;
exp_ok = [ ...
  all(abs(T.D_index  - D)                < 1e-9), ...
  all(abs(T.Rs_aged  - Rs0*(1+0.5*D))    < 1e-9), ...
  all(abs(T.Rsh_aged - Rsh0*(1-0.6*D))   < 1e-6), ...
  all(abs(T.Iph_aged - Iph0*(1-0.2*D))   < 1e-9), ...
  all(abs(T.D_batt   - D)                < 1e-9), ...
  all(abs(T.R0_aged  - 0.03*(1+0.5*D))   < 1e-9), ...
  all(abs(T.R1_aged  - 0.015*(1+0.6*D))  < 1e-9), ...
  all(abs(T.Capacity - 7*(1-0.2*D))      < 1e-9), ...
  all(abs(T.OCV_shift- 0.05*D)           < 1e-9)];
names = {'D_index','Rs','Rsh','Iph','D_batt','R0','R1','Capacity','OCV shift'};
for k = 1:numel(names)
    fprintf('%-10s %s\n', names{k}, ternary(exp_ok(k), 'PASS  logged == model equation', 'FAIL  logged differs from equation'));
end
fprintf('\nPV current should fall as D rises: %s\n', mat2str(round(T.PV_I_meas', 3)));
end

function const_time(model, subName, tval)
sub = [model '/' subName];
ph  = get_param(sub, 'PortHandles');  inP = ph.Inport(1);
ln  = get_param(inP, 'Line');         assert(ln > 0, 'no line into %s/t', subName);
srcP = get_param(ln, 'SrcPortHandle');
assert(strcmp(get_param(get_param(srcP, 'Parent'), 'BlockType'), 'Clock'), '%s/t is not driven by the Clock', subName);
delete_line(model, srcP, inP);                        % removes only this branch
cb = [model '/S10_time_' subName];
add_block('simulink/Sources/Constant', cb, 'Value', num2str(tval, '%.15g'));
cph = get_param(cb, 'PortHandles');
add_line(model, cph.Outport(1), inP);
end

function s = ternary(c, a, b)
if c, s = a; else, s = b; end
end