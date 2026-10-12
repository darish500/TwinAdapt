function K = Stage13_catalogue(asset)
% One element per (sensor channel x fault type). asset = 'pv' or 'batt'.
if strcmp(asset,'pv')
    ch      = {'G','Tc','V','I'};              % irradiance, cell temperature, voltage, current
    target  = [0 1 2 3];                       % selector value used by the model
    stuckP  = {'StuckAt_G','StuckAt_Tc','StuckAt_V_pv','StuckAt_I_pv'};
    stuckV  = [600  30   17   1.0 ];           % frozen reading
    biasV   = [80   5    0.5  0.10];           % constant offset
    noiseV  = [60   3    0.4  0.15];           % extra noise standard deviation
    driftV  = [0.5  0.04 0.003 0.001];         % offset growth per second (150 s run -> x150)
    pBias = 'FaultBias_Value';  pNoise = 'ExcessiveNoise_Sigma';  pDrift = 'ExtraDrift_Rate';
else
    ch      = {'V','I','T'};                   % battery voltage, current, temperature
    target  = [0 1 2];
    stuckP  = {'StuckAt_V_batt','StuckAt_I_batt','StuckAt_T_batt'};
    stuckV  = [12.8 1.5 25];
    biasV   = [0.2  0.3 5];
    noiseV  = [0.3  0.4 3];
    driftV  = [0.002 0.003 0.04];
    pBias = 'FaultBias_Value_batt';  pNoise = 'ExcessiveNoise_Sigma_batt';  pDrift = 'ExtraDrift_Rate_batt';
end
typeName = {'bias','stuck','noise','drift'};
typeCode = [1 2 6 7];                          % codes used by the model's FaultType selector
K = struct('channel',{},'target',{},'typeName',{},'type',{},'param',{},'value',{});
for c = 1:numel(ch)
    for t = 1:4
        switch typeName{t}
            case 'bias',  p = pBias;      v = biasV(c);
            case 'stuck', p = stuckP{c};  v = stuckV(c);
            case 'noise', p = pNoise;     v = noiseV(c);
            case 'drift', p = pDrift;     v = driftV(c);
        end
        K(end+1) = struct('channel',ch{c},'target',target(c),'typeName',typeName{t}, ...
                          'type',typeCode(t),'param',p,'value',v); %#ok<AGROW>
    end
end
end