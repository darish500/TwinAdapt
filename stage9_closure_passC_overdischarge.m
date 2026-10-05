function stage9_closure_passC_overdischarge()
% stage9_closure_passC_overdischarge  Stage 9 Closure Pass C -- trace the
% Battery_Fault_OverDischarge anomaly (residual LOWER than Healthy, the
% one fault in the whole dataset that moved the wrong direction).
%
% Reads R0_fault, Q_fault, OCV_delta_fault from the three "To Workspace"
% blocks (To Workspace7/9/10) Khalid added inside Battery_Fault_Model,
% tapping the wires right where they're labeled R0_fault/Q_fault/
% OCV_delta_fault -- using their actual logged variable names (confirmed
% by unzipping the updated .slx and reading each To Workspace block's
% VariableName property directly), not the longer names first suggested.
%
% This does NOT fix anything. It runs Healthy and OverDischarge back to
% back in a single call (so `out` is never overwritten between the two
% conditions) and prints/plots the actual intermediate values side by
% side, so the root cause can be read off real numbers instead of
% guessed at.

results = struct();

for cond = {'Healthy','OverDischarge'}
    name = cond{1};
    evalin('base', 'reformable_AI;');
    Stage9_Feature_SampleTime = evalin('base','Stage9_Feature_SampleTime');

    % Reset everything to healthy first
    set_param('Reformable_AI_2025/Constant3','Value','0');  % PV fault type
    set_param('Reformable_AI_2025/Constant4','Value','0');
    set_param('Reformable_AI_2025/Constant5','Value','0');  % Batt fault type
    set_param('Reformable_AI_2025/Constant6','Value','0');
    set_param('Reformable_AI_2025/Constant7','Value','0');
    set_param('Reformable_AI_2025/Constant8','Value','0');
    set_param('Reformable_AI_2025/Constant9','Value','0');
    set_param('Reformable_AI_2025/Constant10','Value','0');
    set_param('Reformable_AI_2025/Constant11','Value','0');
    set_param('Reformable_AI_2025/Constant12','Value','0');
    set_param('Reformable_AI_2025/G_test','Value','1000');

    if strcmp(name,'OverDischarge')
        set_param('Reformable_AI_2025/Constant5','Value','2');  % Batt_FaultType = OverDischarge
        set_param('Reformable_AI_2025/Constant6','Value','1');  % full severity
    end

    out = sim('Reformable_AI_2025');

    t_grid = (0:Stage9_Feature_SampleTime:out.tout(end))';
    rs = @(sig) resample_signal_local(sig, t_grid);

    R = struct();
    R.t_grid = t_grid;
    R.R0_aged  = rs(out.R0_aged);
    R.R0_fault = rs(out.R0_fault);
    R.Q_fault  = rs(out.Q_fault);
    R.OCV_delta_fault = rs(out.OCV_delta_fault);
    R.True_Battery_Voltage = rs(out.True_Battery_Voltage);
    R.True_Battery_Current = rs(out.True_Battery_Current);
    R.Battery_Voltage_Final = rs(out.Battery_Voltage_Final);
    R.Battery_Twin_Voltage = rs(out.Battery_Twin_Voltage);
    R.Battery_Twin_SOC_Estimate = rs(out.Battery_Twin_SOC_Estimate);
    R.Battery_Residual_Voltage = rs(out.Battery_Residual_Voltage);
    R.Battery_AbsResidual_Voltage = rs(out.Battery_AbsResidual_Voltage);

    results.(name) = R;
end

H  = results.Healthy;
OD = results.OverDischarge;

fprintf('=== Fault-chain values (mean over run) ===\n');
fprintf('%-32s %14s %14s\n','Quantity','Healthy','OverDischarge');
fprintf('%-32s %14.6f %14.6f\n','R0_aged (pre-fault)', mean(H.R0_aged), mean(OD.R0_aged));
fprintf('%-32s %14.6f %14.6f\n','R0_fault (post-fault)', mean(H.R0_fault), mean(OD.R0_fault));
fprintf('%-32s %14.6f %14.6f\n','Q_fault (capacity, Ah)', mean(H.Q_fault), mean(OD.Q_fault));
fprintf('%-32s %14.6f %14.6f\n','OCV_delta_fault', mean(H.OCV_delta_fault), mean(OD.OCV_delta_fault));
fprintf('\n');
fprintf('%-32s %14.6f %14.6f\n','True_Battery_Voltage', mean(H.True_Battery_Voltage), mean(OD.True_Battery_Voltage));
fprintf('%-32s %14.6f %14.6f\n','Battery_Voltage_Final (measured)', mean(H.Battery_Voltage_Final), mean(OD.Battery_Voltage_Final));
fprintf('%-32s %14.6f %14.6f\n','Battery_Twin_Voltage', mean(H.Battery_Twin_Voltage), mean(OD.Battery_Twin_Voltage));
fprintf('%-32s %14.6f %14.6f\n','Battery_Twin_SOC_Estimate', mean(H.Battery_Twin_SOC_Estimate), mean(OD.Battery_Twin_SOC_Estimate));
fprintf('%-32s %14.6f %14.6f\n','Battery_Residual_Voltage (signed mean)', mean(H.Battery_Residual_Voltage), mean(OD.Battery_Residual_Voltage));
fprintf('%-32s %14.6f %14.6f\n','Battery_AbsResidual_Voltage', mean(H.Battery_AbsResidual_Voltage), mean(OD.Battery_AbsResidual_Voltage));

fprintf('\n--- Sanity check: is the fault even being applied as expected? ---\n');
fprintf('R0_fault should be HIGHER than R0_aged under OverDischarge (R0 rises).\n');
fprintf('Q_fault should be LOWER than the Q used in Healthy (capacity loss).\n');
if mean(OD.R0_fault) > mean(OD.R0_aged) && mean(OD.Q_fault) < mean(H.Q_fault)
    fprintf('CONFIRMED: fault parameters move in the documented direction.\n');
else
    fprintf('UNEXPECTED: fault parameters do NOT move as documented -- check Battery_Fault_Model wiring first.\n');
end

figure('Name','Closure Pass C: Healthy vs OverDischarge');
subplot(3,1,1);
plot(H.t_grid, H.Battery_Residual_Voltage, 'b-'); hold on;
plot(OD.t_grid, OD.Battery_Residual_Voltage, 'r-'); yline(0,'k--');
legend('Healthy','OverDischarge','Location','best');
xlabel('Time (s)'); ylabel('Residual (V)');
title('Signed Battery\_Residual\_Voltage -- watch for sign crossings, not just magnitude');

subplot(3,1,2);
plot(H.t_grid, H.Battery_Twin_SOC_Estimate, 'b-'); hold on;
plot(OD.t_grid, OD.Battery_Twin_SOC_Estimate, 'r-');
legend('Healthy','OverDischarge','Location','best');
xlabel('Time (s)'); ylabel('Twin SOC (%)');
title('Twin SOC estimate -- should be ~identical (Twin never sees Q\_fault)');

subplot(3,1,3);
plot(H.t_grid, H.True_Battery_Voltage, 'b-'); hold on;
plot(OD.t_grid, OD.True_Battery_Voltage, 'r--');
plot(H.t_grid, H.Battery_Twin_Voltage, 'c-');
plot(OD.t_grid, OD.Battery_Twin_Voltage, 'm--');
legend('True V (Healthy)','True V (OverDischarge)','Twin V (Healthy)','Twin V (OverDischarge)','Location','best');
xlabel('Time (s)'); ylabel('Voltage (V)');
title('Physical vs Twin voltage -- the gap IS the residual');

saveas(gcf, 'Stage9_ClosureC_OverDischarge_Trace.png');
save('Stage9_ClosureC_Trace.mat','H','OD');
fprintf('\nSaved Stage9_ClosureC_OverDischarge_Trace.png and Stage9_ClosureC_Trace.mat.\n');

end

function y = resample_signal_local(sig, t_grid)
if numel(sig.Time) < 2
    y = repmat(double(sig.Data(1)), numel(t_grid), 1);
else
    y = interp1(sig.Time, double(sig.Data), t_grid, 'linear', 'extrap');
end
end