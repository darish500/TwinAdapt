function Stage11a_test_mismatch_hooks()
model = 'Reformable_AI_2025';
tg = (0:0.5:30)';
%        name                  workspace variable        multiplier  SOC offset   which output must move
cases = { 'baseline',          '',                       1,          0,           '-'   ; ...
          'PV Iph_ref x1.05',  'PV_Twin_Iph_ref',        1.05,       0,           'I'   ; ...
          'PV Rsh x0.5',       'PV_Twin_Rsh',            0.5,        0,           'I'   ; ...
          'PV Ki x1.5',        'PV_Twin_Ki',             1.5,        0,           'I'   ; ...
          'PV n x1.1',         'PV_Twin_n',              1.1,        0,           'I'   ; ...
          'Batt R0 x1.5',      'Battery_Twin_R0',        1.5,        0,           'V'   ; ...
          'Batt R1 x1.5',      'Battery_Twin_R1',        1.5,        0,           'V'   ; ...
          'Batt Capacity x0.8','Battery_Twin_Capacity',  0.8,        0,           'S'   ; ...
          'Batt SOC_init -5',  '',                       1,          -5,          'S'   };
n = size(cases,1);
A = zeros(numel(tg), n);  B = A;  S = A;

for i = 1:n
    if bdIsLoaded(model), close_system(model, 0); end
    evalin('base','reformable_AI;');                       % reload the workspace values first
    load_system(model);
    c = onCleanup(@() close_system(model, 0));
    set_param(model,'FastRestart','off');
    set_param(model,'DefaultParameterBehavior','Tunable');   % the Stage 9 fix, so workspace edits reach the model
    set_param(model,'StopTime','30');

    if ~isempty(cases{i,2})                                % change one Twin parameter
        v = evalin('base', cases{i,2});
        assignin('base', cases{i,2}, v * cases{i,3});
    end
    if cases{i,4} ~= 0                                     % shift the Twin's starting SOC
        s0 = evalin('base','Battery_Twin_SOC_init');
        set_param([model '/Battery_Digital_Twin/Integrator'], 'InitialCondition', num2str(s0 + cases{i,4}));
    end

    out = sim(model);
    g = @(nm) interp1(out.get(nm).Time, squeeze(out.get(nm).Data), tg);
    A(:,i) = g('PV_Twin_Current');
    B(:,i) = g('Battery_Twin_Voltage');
    S(:,i) = g('Battery_Twin_SOC_Estimate');
    clear c
end

fprintf('\n%-20s %14s %14s %14s   %s\n', 'case', 'max dI_twin (A)', 'max dV_twin (V)', 'max dSOC (pts)', 'result');
for i = 1:n
    d = [max(abs(A(:,i)-A(:,1))), max(abs(B(:,i)-B(:,1))), max(abs(S(:,i)-S(:,1)))];
    switch cases{i,5}
        case 'I', ok = d(1) > 1e-6;
        case 'V', ok = d(2) > 1e-6;
        case 'S', ok = d(3) > 1e-6;
        otherwise, ok = true;
    end
    fprintf('%-20s %14.6f %14.6f %14.6f   %s\n', cases{i,1}, d(1), d(2), d(3), ternary(ok));
end
fprintf('\nIph_ref x1.05 should raise the Twin current by about %.3f A\n', 0.05*evalin('base','PV_Twin_Iph_ref'));
end

function s = ternary(ok)
if ok, s = 'PASS (hook works)'; else, s = 'FAIL (no effect)'; end
end