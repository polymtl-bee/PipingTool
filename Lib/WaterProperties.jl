module WaterProperties

export specheat, density, dynviscosity

__revise_mode__ = :eval # Tell Revise to track all changes, not just method definitions

"""
    density(T::Real)
Liquid water density (kg/m³), valid between 0 °C and 100 °C
Regression based on EES data at 200 kPa, valid for moderate pressures (100 - 500 kPa) as long as water is liquid
Error within ± 0.03 %
# Arguments
`T` : temperature in °C
# Outputs
`density` : density in kg/m³
# Examples
`density(60)` gives 983.219 (EES answer, Water, P=101.325 kPa: 983.196)
"""
function density(T::Real) 
    if (T < 0) || (T > 100) 
        error("Temperature ($T) out of range, must be between 0 °C and 100 °C")
    end
    density = 1000 + 0.0130*T - 0.00579*T^2 + 0.0000152*T^3
end

"""
    specheat(T::Real)
Liquid water specific heat (J/kg-K), valid between 0 °C and 100 °C
Regression based on EES data at 200 kPa, valid for moderate pressures (100 - 500 kPa) as long as water is liquid  
Error within ± 0.05 %
# Arguments
`T` : temperature in °C
# Outputs
`specheat` : specific heat in J/kg-K
# Examples
`specheat(60)` gives 4185.74 (EES answer, Water, P=101.325 kPa: 4184.95)
"""
function specheat(T::Real)
    if (T < 0) || (T > 100) 
        error("Temperature ($T) out of range, must be between 0 °C and 100 °C")
    end
    specheat = 4218 - 2.81*T + 0.0693*T^2 - 6.90e-04*T^3 + 2.77e-06*T^4
end

"""
    dynviscosity(T::Real)
Liquid water dynamic viscosity (kg/m-s), valid between 0 °C and 100 °C
Regression based on EES data at 200 kPa, valid for moderate pressures (100 - 500 kPa) as long as water is liquid
Error within ± 0.05 %
# Arguments
`T` : temperature in °C
# Outputs
`dynviscosity` : dynamic viscosity in kg/m-s
# Examples
`dynviscosity(60)` gives 0.00046744 (EES answer, Water, P=101.325 kPa: 0.000466035)
"""
function dynviscosity(T::Real)
    if (T < 0) || (T > 100) 
        error("Temperature ($T) out of range, must be between 0 °C and 100 °C")
    end
    dynviscosity = 1.785e-3 - 5.890e-5*T + 1.284e-6*T^2 - 1.754e-8*T^3 + 1.304e-10*T^4 - 3.952e-13*T^5
end

end    # module 