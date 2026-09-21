% Test 1: zero-noise reproduction
reformable_AI;
noise_V_batt=0; bias_V_batt=0; drift_V_batt=0; dV_batt=1e-6;
noise_I_batt=0; bias_I_batt=0; drift_I_batt=0; dI_batt=1e-6;
noise_T_batt=0; bias_T_batt=0; drift_T_batt=0; dT_batt=1e-6;
out = sim('Reformable_AI_2025');
fprintf('--- Test 1: Zero-noise ---\n');
fprintf('V: true=%.4f measured=%.4f diff=%.6f\n', out.True_Battery_Voltage.Data(end), out.Battery_Measured_Voltage.Data(end), out.Battery_Measured_Voltage.Data(end)-out.True_Battery_Voltage.Data(end));
fprintf('I: true=%.4f measured=%.4f diff=%.6f\n', out.True_Battery_Current.Data(end), out.Battery_Measured_Current.Data(end), out.Battery_Measured_Current.Data(end)-out.True_Battery_Current.Data(end));
fprintf('T: true=%.4f measured=%.4f diff=%.6f\n', out.True_Battery_Temperature.Data(end), out.Battery_Measured_Temperature.Data(end), out.Battery_Measured_Temperature.Data(end)-out.True_Battery_Temperature.Data(end));

out = sim('Reformable_AI_2025');
fprintf('--- Test 2: Noise stats ---\n');
fprintf('V: mean=%.3f (true~%.1f) std=%.3f (cfg=%.2f)\n', mean(out.Battery_Measured_Voltage.Data), out.True_Battery_Voltage.Data(1), std(out.Battery_Measured_Voltage.Data), noise_V_batt);
fprintf('I: mean=%.3f (true~%.1f) std=%.3f (cfg=%.2f)\n', mean(out.Battery_Measured_Current.Data), out.True_Battery_Current.Data(1), std(out.Battery_Measured_Current.Data), noise_I_batt);
fprintf('T: mean=%.3f (true~%.1f) std=%.3f (cfg=%.2f)\n', mean(out.Battery_Measured_Temperature.Data), out.True_Battery_Temperature.Data(1), std(out.Battery_Measured_Temperature.Data), noise_T_batt);


noise_V_batt=0; noise_I_batt=0; noise_T_batt=0;
dV_batt=1e-6; dI_batt=1e-6; dT_batt=1e-6;
bias_V_batt=0.3; bias_I_batt=0.1; bias_T_batt=2;
out = sim('Reformable_AI_2025');
fprintf('--- Test 3: Bias ---\n');
fprintf('V: true=%.4f measured=%.4f expected=%.4f\n', out.True_Battery_Voltage.Data(end), out.Battery_Measured_Voltage.Data(end), out.True_Battery_Voltage.Data(end)+bias_V_batt);
fprintf('I: true=%.4f measured=%.4f expected=%.4f\n', out.True_Battery_Current.Data(end), out.Battery_Measured_Current.Data(end), out.True_Battery_Current.Data(end)+bias_I_batt);
fprintf('T: true=%.4f measured=%.4f expected=%.4f\n', out.True_Battery_Temperature.Data(end), out.Battery_Measured_Temperature.Data(end), out.True_Battery_Temperature.Data(end)+bias_T_batt);

noise_V_batt=0; noise_I_batt=0; noise_T_batt=0;
bias_V_batt=0; bias_I_batt=0; bias_T_batt=0;
dV_batt=1e-6; dI_batt=1e-6; dT_batt=1e-6;
drift_V_batt=0.01;
out = sim('Reformable_AI_2025');
fprintf('--- Test 5: Drift ---\n');
fprintf('Observed=%.4f V over %.2f s (expected %.4f)\n', out.Battery_Measured_Voltage.Data(end)-out.Battery_Measured_Voltage.Data(1), out.tout(end)-out.tout(1), drift_V_batt*(out.tout(end)-out.tout(1)));

noise_V_batt=0; noise_I_batt=0; noise_T_batt=0;
bias_V_batt=0; bias_I_batt=0; bias_T_batt=0;
drift_V_batt=0; drift_I_batt=0; drift_T_batt=0;
dV_batt=1e-6; dI_batt=1e-6; dT_batt=1e-6;
V_batt_max = 10;
out = sim('Reformable_AI_2025');
fprintf('--- Test 7: Saturation ---\n');
fprintf('True=%.4f Measured=%.4f (should clip at %.1f)\n', out.True_Battery_Voltage.Data(end), out.Battery_Measured_Voltage.Data(end), V_batt_max);