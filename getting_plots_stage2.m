%% Stage 5 Validation — PV Fault Injection sweep + plot
mdl = 'Reformable_AI';
load_system(mdl);

faultCases = {
    'Healthy',      0, 0.0;
    'Shading',      1, 0.5;
    'Soiling',      2, 0.5;
    'Hotspot',      3, 0.5;
    'PID',          4, 0.5;
    'OpenCircuit',  5, 1.0;
    'ShortCircuit', 6, 1.0;
    };

results = struct();

for k = 1:size(faultCases,1)
    name = faultCases{k,1};
    ftype = faultCases{k,2};
    fsev  = faultCases{k,3};

    set_param([mdl '/Constant3'], 'Value', num2str(ftype));
    set_param([mdl '/Constant4'], 'Value', num2str(fsev));

    out = sim(mdl);

    results.(name).Rs_fault    = out.Rs_fault.Data;
    results.(name).Rsh_fault   = out.Rsh_fault.Data;
    results.(name).Iph_fault   = out.Iph_fault.Data;
    results.(name).TempRise    = out.Fault_TempRise.Data;
    results.(name).Severity    = out.Fault_Severity.Data;
    results.(name).Active      = out.Fault_Active.Data;
    results.(name).Time        = out.Rs_fault.Time;

    fprintf('%-14s | Rs_fault(end)=%.4f | Rsh_fault(end)=%.2f | Iph_fault(end)=%.4f | TempRise(end)=%.2f\n', ...
        name, results.(name).Rs_fault(end), results.(name).Rsh_fault(end), ...
        results.(name).Iph_fault(end), results.(name).TempRise(end));
end

%% Plot — one figure, 3 subplots, all 7 cases overlaid
figure('Name','Stage 5 Fault Validation','NumberTitle','off');
names = fieldnames(results);
colors = lines(numel(names));

subplot(3,1,1); hold on; grid on;
for k = 1:numel(names)
    plot(results.(names{k}).Time, results.(names{k}).Rs_fault, 'Color', colors(k,:), 'DisplayName', names{k});
end
ylabel('Rs\_fault (\Omega)'); title('Series Resistance'); legend show;

subplot(3,1,2); hold on; grid on;
for k = 1:numel(names)
    plot(results.(names{k}).Time, results.(names{k}).Rsh_fault, 'Color', colors(k,:), 'DisplayName', names{k});
end
ylabel('Rsh\_fault (\Omega)'); title('Shunt Resistance');

subplot(3,1,3); hold on; grid on;
for k = 1:numel(names)
    plot(results.(names{k}).Time, results.(names{k}).Iph_fault, 'Color', colors(k,:), 'DisplayName', names{k});
end
ylabel('Iph\_fault (A)'); xlabel('Time (s)'); title('Photocurrent');