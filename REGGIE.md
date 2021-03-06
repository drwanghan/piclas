# PICLas Regression Testing

PICLas utilizes the Reggie2.0 toolbox for regression testing. A detailed documentation on its usage is available [at this repository](https://gitlab.com/reggie2.0/reggie2.0/blob/master/README.md). A list detailing the test cases and which features are tested is given below.

# List of Cases

## Check-in

Overview of the test cases performed after a commit.

| **No.** |                  **Case**                   |    **CMAKE-CONFIG**    |           **Feature**           | **Execution**  |   **Comparing**   | **Readme** |
| :-----: | :-----------------------------------------: | :--------------------: | :-----------------------------: | :------------: | :---------------: | :--------: |
|   01    |                  run_basic                  |      maxwell,RK4       |           DG-Operator           | nProcs=1,2,5,8 |      L2,Linf      |            |
|   02    |                 CHE_maxwell                 |  pure maxwell DG,RK4   |           DG-Operator           | nProcs=1,2,5,8 |      L2,Linf      |            |
|   03    |                 CHE_poisson                 |      Poisson,RK3       |           DG-Operator           | nProcs=1,2,5,8 |      L2,Linf      |            |
|   04    | [CHE_PIC_maxwell_RK4](#CHE_PIC_maxwell_RK4) |   PIC (maxwell, RK4)   |                                 |                |                   |            |
|   05    |            [CHE_DSMC](#CHE_DSMC)            |          DSMC          |                                 |                |                   |            |
|   06    |         CHE_PIC_maxwell_implicitBC          | maxwell,PIC,ImplicitO4 | Implicit reflective particle BC |    nProcs=1    | Particle Position |            |
|   07    |         [CHE_BGK](#CHE_BGK/FPFlow)          |        BGK-Flow        |                                 |                |                   |            |
|   08    |        [CHE_FPFlow](#CHE_BGK/FPFlow)        |        FP-Flow         |                                 |                |                   |            |

#### CHE_PIC_maxwell_RK4

Regression testing for PIC, solving the complete Maxwell equations with RK4: [Link to build](regressioncheck/checks/CHE_PIC_maxwell_RK4/builds.ini).

| **No.** |       **Case**       | **CMAKE-CONFIG** |        **Feature**         | **Execution** |     **Comparing**      | **Readme** |
| :-----: | :------------------: | :--------------: | :------------------------: | :-----------: | :--------------------: | :--------: |
|   01    | gyrotron_variable_Bz |                  |        variable Bz         |  nProcs=1,2   | Database.csv, relative |            |
|   02    |     IMD_coupling     |                  | mapping from IMP to PICLas |   nProcs=1    |    PartPata in Box     |            |
|   03    |  initialIonization   |                  |                            |   nProcs=2    |        PartPata        |            |
|   04    | single_particle_PML  |                  |            PML             |   particle    |   nProcs=1,2,5,8,10    |            |

#### CHE_DSMC

Small test cases to check features with DSMC timedisc: [Link to build](regressioncheck/checks/CHE_DSMC/builds.ini).

| **No.** | **Case**                                 | **CMAKE-CONFIG** | **Feature**                                                                                                       | **Execution**     | **Comparing**                      | **Readme**                                                                                 |
| :-----: | :--------------------------------------: | :--------------: | :---------------------------------------------------------------------------------------------------------------: | :-----------:     | :--------------------------------: | :----------------------------------------------------------------------------------------: |
|         | 2D_VTS_Insert_CellLocal                  |                  | 2D/Axisymmetric, linear time step scaling: Initial particle insertion by cell_local                               | nProcs=2          | PartAnalyze: NumDens, Temp         | [Link](regressioncheck/checks/CHE_DSMC/2D_VTS_Insert_CellLocal/readme.md)                  |
|         | 2D_VTS_SurfFlux_Tria                     |                  | 2D/Axisymmetric, linear time step scaling: Particle emission through surface flux                                 | nProcs=2          | PartAnalyze: NumDens, Temp         | [Link](regressioncheck/checks/CHE_DSMC/2D_VTS_SurfFlux_Tria/readme.md)                     |
|         | BackgroundGas_VHS_MCC                    |                  | Reservoir simulation of an ionization using a background gas with DSMC and MCC-based collision probabilities      | nProcs=1          | PartAnalyze: NumDens, Temp         | [Link](regressioncheck/checks/CHE_DSMC/BackgroundGas_VHS_MCC/readme.md)                    |
|         | BC_DiffuseWall_TempGrad                  |                  | Reservoir with a boundary temperature gradient along the x-axis                                                   | nProcs=1,4        | Temperature                        | [Link](regressioncheck/checks/CHE_DSMC/BC_DiffuseWall_TempGrad/readme.md)                  |
|         | BC_InnerReflective_8elems                |                  | Inner reflective BC (dielectric surfaces) low error tolerance                                                     | nProcs=1,2,4,8    | h5diff: DSMCSurfState              | [Link](regressioncheck/checks/CHE_DSMC/BC_InnerReflective_8elems/readme.md)                |
|         | BC_InnerReflective_36elems               |                  | Inner reflective BC (dielectric surfaces) high error tolerance                                                    | nProcs=1,2,4,8,12 | h5diff: DSMCSurfState              | [Link](regressioncheck/checks/CHE_DSMC/BC_InnerReflective_36elems/readme.md)               |
|         | BC_PorousBC                              |                  | PorousBC as a pump with 2 species                                                                                 | nProcs=3          | Total # of removed part through BC |                                                                                            |
|         | BC_PorousBC_2DAxi                        |                  | PorousBC as a pump with 2 species (axisymmetric, with/without radial weighting)                                   | nProcs=1,2        | Total number density               | [Link](regressioncheck/checks/CHE_DSMC/BC_PorousBC_2DAxi/readme.md)                        |
|         | cube                                     |                  | Collismode=2,3                                                                                                    | nProcs=2          |                                    |                                                                                            |
|         | SurfFlux_RefMapping_Tracing_TriaTracking |                  | Surface flux emission (collisionless) with ARM (with all three trackings) and TriaSurfaceFlux (only TriaTracking) | nProcs=1          | PartAnalyze: nPart, TransTemp      | [Link](regressioncheck/checks/CHE_DSMC/SurfFlux_RefMapping_Tracing_TriaTracking/readme.md) |
|         | SurfFlux_Tria_Adaptive_ConstPressure     |                  | TriaSurfaceFlux with AdaptiveType=1/2                                                                             | nProcs=4          | Integrated mass flux               |                                                                                            |
|         | SurfFlux_Tria_Adaptive_ConstMassflow     |                  | TriaSurfaceFlux with AdaptiveType=3,4                                                                             | nProcs=1          | Integrated mass flux               |                                                                                            |
|         | SurfaModel_Sampling                      |                  | Surface model sampling check                                                                                      | nProcs=1,2,4      |                                    | [Link](regressioncheck/checks/CHE_DSMC/SurfaceModel_Sampling/readme.md)                    |
|         | SurfaceModel_SMCR                        |                  | Surfacemodel 3 init/run check                                                                                     | nProcs=1,4        |                                    | [Link](regressioncheck/checks/CHE_DSMC/SurfaceModel_SMCR/readme.md)                        |

#### CHE_BGK/FPFlow

Both methods share the same regression tests in the different folders (CHE_BGK: [BGK build](regressioncheck/checks/CHE_BGK/builds.ini), CHE_FPFlow: [FPFlow build](regressioncheck/checks/CHE_FPFlow/builds.ini)

| **No.** | **Case**                     | **CMAKE-CONFIG**     | **Feature**                                                                         | **Execution**   | **Comparing**                                    | **Readme**                                                               |
| :-----: | :--------------------------: | :------------------: | :---------------------------------------------------:                               | :-------------: | :----------------------------------------------: | :----------------------------------------------------------------------: |
|         | 2D_VTS_Insert_CellLocal      |                      | 2D/Axisymmetric, linear time step scaling: Initial particle insertion by cell_local | nProcs=2        | PartAnalyze: NumDens, Temp                       | [Link](regressioncheck/checks/CHE_BGK/2D_VTS_Insert_CellLocal/readme.md) |
|         | 2D_VTS_SurfFlux_Tria         |                      | 2D/Axisymmetric, linear time step scaling: Particle emission through surface flux   | nProcs=2        | PartAnalyze: NumDens, Temp                       | [Link](regressioncheck/checks/CHE_BGK/2D_VTS_SurfFlux_Tria/readme.md)    |
|         | CHE_BGK/RELAX_N2             |                      | N2: Relax to thermal equi. continuous/quantized vibration                           | nProcs=1        | T_rot,T_vib,T_trans                              | [Link](regressioncheck/checks/CHE_BGK/RELAX_N2/readme.md)                |
|         | CHE_BGK/RELAX_CH4            |                      | CH4: Relax to thermal equi. continuous/quantized vibration                          | nProcs=1        | T_rot,T_vib,T_trans                              | [Link](regressioncheck/checks/CHE_BGK/RELAX_CH4/readme.md)               |


## Nightly

Overview of the test cases performed during the nightly regression testing.

| **No.** | **Case**                                                                    | **CMAKE-CONFIG**                                | **Feature**                                               | **Execution**                               | **Comparing**                                                                    | **Readme**                                                                                                           |
| :-----: | :-------------------------------------------------------------------------: | :---------------------------------------------: | :---------------------------------------------------:     | :-----------------------------------------: | :----------------------------------------------:                                 | :------------------------------------------------------------------------------------------------------------------: |
| -       | [NIG_convtest](#nig_convtest_maxwell)                                       | maxwell, RK4                                    | Spatial order of convergence for Maxwell field solver     |                                             |                                                                                  |                                                                                                                      |
| -       | [NIG_convtest_poisson](#nig_convtest_poisson)                               | poisson, RK3                                    | Spatial order of convergence for HDG field solver         |                                             |                                                                                  |                                                                                                                      |
| -       | [NIG_convtest_t](#nig_convtest_t)                                           | maxwell, RK3,RK4,CN,ImplicitO3,ImplicitO4,ROS46 | Temporal order of convergence for particle push           |                                             |                                                                                  |                                                                                                                      |
| -       | [NIG_Reservoir](#nig_reservoir)                                             | maxwell, DSMC                                   | Relaxation, (Surface-) Chemistry                          |                                             |                                                                                  |                                                                                                                      |
| -       | [NIG_tracking_DSMC](#nig_tracking_dsmc)                                     | maxwell, DSMC                                   | Tracking                                                  |                                             |                                                                                  |                                                                                                                      |
| -       | [NIG_MacroBody](#nig_macrobody)                                             | maxwell, MACROBODY                              | Tracking with MacroBody, Volume portion calculation       |                                             |                                                                                  |                                                                                                                      |
| -       | [NIG_PIC_poisson_RK3](#nig_pic_poisson_rk3)                                 | poisson, PIC, RK3                               |                                                           |                                             |                                                                                  |                                                                                                                      |
| -       | [NIG_PIC_maxwell_RK4](#nig_pic_maxwell_rk4)                                 | maxwell, PIC, RK4                               |                                                           |                                             |                                                                                  |                                                                                                                      |
| -       | [NIG_maxwell_RK4](#nig_maxwell_rk4)                                         | maxwell, RK4, Particles=OFF                     |                                                           |                                             |                                                                                  |                                                                                                                      |
| -       | [NIG_Surfacemodel](#nig_surfacemodel)                                       | maxwell, RESERVOIR, Particles=ON                | Surface model tests                                       |                                             |                                                                                  |                                                                                                                      |
| -       | [NIG_LoadBalance](#nig_loadbalance)                                         | maxwell, DSMC, Particles=ON                     | Loadbalance                                               |                                             |                                                                                  |                                                                                                                      |
| 1       | NIG_PIC_maxwell_bgfield                                                     | maxwell,PIC,RK4                                 | External Background-field,h5                              | nProcs=2                                    | DG_Solution                                                                      |                                                                                                                      |
| 2       | NIG_poisson_powerdensity                                                    | Poisson, Crank-Nicolson                         | Implicit, CalcTimeAvg                                     | DoRefMapping=T/F, nProcs=2                  | Final TimeAvg, h5diff                                                            |                                                                                                                      |
| 3       | feature_emission_gyrotron                                                   | maxwell,RK4                                     | Part-Inflow,TimeDep                                       | N=1,3,6,9,10, nProcs=1,2,10,25, gyro-circle | LineIntegration of nPartIn                                                       |                                                                                                                      |
| 4       | feature_TWT_recordpoints                                                    | maxwell,RK4                                     | RPs, ExactFlux                                            | nProcs=1,4, RPs, interior TE-Inflow         | RP_State, RP_Daata                                                               |                                                                                                                      |
| 5       | NIG_PIC_poisson_plasma_wave                                                 | poisson,RK4,CN                                  | Poisson-PIC,Shape-Function-1D                             | nProcs=2, Imex for CN                       | W_el LineIntegration over 2Per                                                   |                                                                                                                      |
| 6       | NIG_PIC_poisson_Leapfrog/parallel_plates                                    | poisson,Leapfrog                                | Poisson-PIC,CalcCoupledPower                              | nProcs=1                                    | PartAnalyzeLeapfrog_ref.csv                                                      | [Link](regressioncheck/checks/NIG_PIC_poisson_Leapfrog/parallel_plates/readme.md)                                    |
| 7       | NIG_PIC_poisson_Leapfrog/parallel_plates_AC                                 | poisson,Leapfrog                                | Poisson-PIC,CalcCoupledPower                              | nProcs=1                                    | PartAnalyzeLeapfrog_ref.csv                                                      | [Link](regressioncheck/checks/NIG_PIC_poisson_Leapfrog/parallel_plates_AC/readme.md)                                 |
| 8       | NIG_PIC_poisson_Leapfrog/2D_innerBC_dielectric_surface_charge               | poisson,Leapfrog                                | Poisson-PIC,Dielectric surface charging,Cartesian geometry| nProcs=1,2,5,7,12                           | DG_Source,DG_SourceExt,ElemData                                                  | [Link](regressioncheck/checks/NIG_PIC_poisson_Leapfrog/2D_innerBC_dielectric_surface_charge/readme.md)               |
| 9       | NIG_PIC_poisson_Leapfrog/Dielectric_sphere_surface_charging                 | poisson,Leapfrog                                | Poisson-PIC,Dielectric surface charging                   | nProcs=1,2,3,7,12                           | DG_Source,DG_SourceExt,ElemData,DielectricGlobal                                 | [Link](regressioncheck/checks/NIG_PIC_poisson_Leapfrog/Dielectric_sphere_surface_charging/readme.md)                 |
| 10      | NIG_PIC_poisson_Leapfrog/Dielectric_sphere_surface_charging_mortar          | poisson,Leapfrog                                | Poisson-PIC,Dielectric surface charging,mortars           | nProcs=1,2,3,7,12                           | DG_Source,DG_SourceExt,ElemData,DielectricGlobal                                 | [Link](regressioncheck/checks/NIG_PIC_poisson_Leapfrog/Dielectric_sphere_surface_charging_mortar/readme.md)          |
| 11      | NIG_PIC_poisson_Leapfrog/Dielectric_sphere_surface_charging_PStateBound     | poisson,Leapfrog                                | Poisson-PIC,Dielectric surface charging,PartStateBoundary | nProcs=1,2                                  | PartStateBoundary,DSMCSurfState,DG_Source,DG_SourceExt,ElemData,DielectricGlobal | [Link](regressioncheck/checks/NIG_PIC_poisson_Leapfrog/Dielectric_sphere_surface_charging_PStateBound/readme.md)     |
| 12      | NIG_PIC_Deposition/Plasma_Ball_cell_volweight_mean                          | maxwell,RK3                                     | Maxwell-PIC,shape function (different dimensions)         | nProcs=1,5,10                               | Particle_ref.csv                                                                 | [Link](regressioncheck/checks/NIG_PIC_Deposition/Plasma_Ball_cell_volweight_mean/readme.md)                          |
| 13      | NIG_PIC_Deposition/Plasma_Ball_Shape-function                               | maxwell,RK3                                     | Maxwell-PIC,deposition cell_volweight_mean                | nProcs=1,5,10                               | Xd_X-dir_ref.csv                                                                 | [Link](regressioncheck/checks/NIG_PIC_Deposition/Plasma_Ball_Shape-function/readme.md)                               |


### NIG Convergence Tests

### NIG_convtest_maxwell

Convergence tests (spatially by varying either the polynomial degree of the solution or the number of mesh cells) for Maxwell's equations on conforming, non-conforming (hanging nodes/Mortars) Cartesian or non-orthogonal meshes with open or PEC boundaries: [Link CMAKE-CONFIG](regressioncheck/checks/NIG_convtest/builds.ini).

| **No.** |          **Case**           | **CMAKE-CONFIG** |                                     **Feature**                                     | **Execution** | **Comparing** | **Readme** |
| :-----: | :-------------------------: | :--------------: | :---------------------------------------------------------------------------------: | :-----------: | :-----------: | :--------: |
|    1    |          h_mortar           |                  |                         h-convergence (non-conforming mesh)                         |   nProcs=1    |               |            |
|    2    |            h_N2             |                  |                 h-convergence (conforming Cartesian mesh with N=2)                  |   nProcs=1    |               |            |
|    3    |            h_N4             |                  |                 h-convergence (conforming Cartesian mesh with N=2)                  |   nProcs=1    |               |            |
|    4    |      h_non_orthogonal       |                  |                         h-convergence (non-orthogonal mesh)                         |   nProcs=4    |               |            |
|    5    |              p              |                  |                                    p-convergence                                    |   nProcs=1    |               |            |
|    6    | p_cylinder_TE_wave_circular |                  | p-convergence (cylindrical mesh periodic in z and PEC walls, circular polarization) |   nProcs=4    |               |            |
|    7    |  p_cylinder_TE_wave_linear  |                  |  p-convergence (cylindrical mesh periodic in z and PEC walls, linear polarization)  |   nProcs=4    |               |            |
|    8    |          p_mortar           |                  |                         p-convergence (non-conforming mesh)                         |   nProcs=1    |               |            |

### NIG_convtest_poisson

Convergence tests (spatially by varying either the number of mesh cells) for Poisson's equations on conforming, non-conforming (hanging nodes/Mortars) Cartesian meshes with exact Dirichlet boundaries: [Link CMAKE-CONFIG](regressioncheck/checks/NIG_convtest_poisson/builds.ini).

| **No.** |  **Case**   | **CMAKE-CONFIG** |               **Feature**                | **Execution** | **Comparing** |                             **Readme**                             |
| :-----: | :---------: | :--------------: | :--------------------------------------: | :-----------: | :-----------: | :----------------------------------------------------------------: |
|  23-x   | h_N1_mortar |                  | h-convergence (N=1, non-conforming mesh) |   nProcs=1    |               | [Link](regressioncheck/checks/NIG_convtest_poisson/h_N1/readme.md) |

### NIG_convtest_t

Convergence tests (temporally by varying the time step) for integrating the path of a single particle in a spatially varying and temporally constant magnetic field: [Link CMAKE-CONFIG](regressioncheck/checks/NIG_convtest_t/builds.ini).

| **No.** |                **Case**                 | **CMAKE-CONFIG** |                             **Feature**                              | **Execution** |    **Comparing**     | **Readme** |
| :-----: | :-------------------------------------: | :--------------: | :------------------------------------------------------------------: | :-----------: | :------------------: | :--------: |
|    1    |       PIC_CN_magnetostatic_Bz_exp       |                  |                 spiral drift, Crank-Nickolson method                 |   nProcs=1    | L2 error of position |            |
|    2    | PIC_Euler-Explicit_magnetostatic_Bz_exp |                  |             spiral particle drift, explicit Euler method             |   nProcs=1    | L2 error of position |            |
|    3    |   PIC_ImplicitO3_magnetostatic_Bz_exp   |                  |              spiral particle drift, implicit 3rd order               |   nProcs=1    | L2 error of position |            |
|    4    |   PIC_ImplicitO4_magnetostatic_Bz_exp   |                  |              spiral particle drift, implicit 4th order               |   nProcs=1    | L2 error of position |            |
|    5    |      PIC_RK3_magnetostatic_Bz_exp       |                  |             spiral particle drift, Runge-Kutta 3rd order             |   nProcs=1    | L2 error of position |            |
|    6    |     PIC_RK3_magnetostatic_Bz_exp_I      |                  |              particle deflection, Runge-Kutta 3rd order              |   nProcs=1    | L2 error of position |            |
|    7    |     PIC_RK3_magnetostatic_Bz_exp_II     |                  |       particle undergoing a single loop, Runge-Kutta 3rd order       |   nProcs=1    | L2 error of position |            |
|    8    |    PIC_RK3_magnetostatic_Bz_exp_III     |                  |             spiral particle drift, Runge-Kutta 3rd order             |   nProcs=1    | L2 error of position |            |
|    9    |      PIC_RK4_magnetostatic_Bz_exp       |                  |             spiral particle drift, Runge-Kutta 4th order             |   nProcs=1    | L2 error of position |            |
|   10    |     PIC_ROS46_magnetostatic_Bz_exp      |                  | spiral particle drift, Rosenbrock 4th order (resulting in 1st order) |   nProcs=1    | L2 error of position |            |


#### NIG_Reservoir

Testing more complex DSMC routines with reservoir (heat bath) simulations: [Link CMAKE-CONFIG](regressioncheck/checks/NIG_Reservoir/builds.ini).

| **No.** |             **Case**              | **CMAKE-CONFIG** |                                          **Feature**                                          | **Execution** | **Comparing** |                                        **Readme**                                        |
| :-----: | :-------------------------------: | :--------------: | :-------------------------------------------------------------------------------------------: | :-----------: | :-----------: | :--------------------------------------------------------------------------------------: |
|    1    |      CHEM_EQUI_TCE_Air_5Spec      |                  |                    Reservoir of high-temperature air (N2, O2) dissociating                    |   nProcs=1    |               |      [Link](regressioncheck/checks/NIG_Reservoir/CHEM_EQUI_TCE_Air_5Spec/readme.md)      |
|    2    | CHEM_QK_multi-ionization_C_to_C6+ |                  |                      QK impact ionization, from neutral to fully ionized                      |   nProcs=1    |               | [Link](regressioncheck/checks/NIG_Reservoir/CHEM_QK_multi-ionization_C_to_C6+/readme.md) |
|    3    |    CHEM_RATES_diss_recomb_CH4     |                  | TCE rates for a (non-linear) polyatomic dissociation + recombination: CH4 + M <-> CH3 + H + M |   nProcs=1    |               |    [Link](regressioncheck/checks/NIG_Reservoir/CHEM_RATES_diss_recomb_CH4/readme.md)     |
|    4    |    CHEM_RATES_diss_recomb_CO2     |                  |   TCE rates for a (linear) polyatomic dissociation + recombination: CO2 + M <-> CO + O + N    |   nProcs=1    |               |    [Link](regressioncheck/checks/NIG_Reservoir/CHEM_RATES_diss_recomb_CO2/readme.md)     |
|    5    |     CHEM_RATES_diss_recomb_N2     |                  |          TCE rates for a diatomic dissociation + recombination: N2 + M <-> N + N + M          |   nProcs=1    |               |     [Link](regressioncheck/checks/NIG_Reservoir/CHEM_RATES_diss_recomb_N2/readme.md)     |
|    6    |     CHEM_RATES_exchange_CH4_H     |                  |                        TCE rates for an exchange: CH4 + H <-> CH3 + H2                        |   nProcs=1    |               |      [Link](regressioncheck/checks/NIG_Reservoir/CHEM_RATES_exchange_CH3/readme.md)      |
|    7    |     CHEM_RATES_QK_diss_ion_N2     |                  |  QK rates for a dissociation and ionization : N2 + M -> N + N + M  and  N2 + M -> N2+ e- + M  |   nProcs=1    |               |     [Link](regressioncheck/checks/NIG_Reservoir/CHEM_RATES_QK_diss_ion_N2/readme.md)     |
|    8    |       CHEM_RATES_QK_diss_N2       |                  |                       QK rates for a dissociation : N2 + M -> N + N + M                       |   nProcs=1    |               |       [Link](regressioncheck/checks/NIG_Reservoir/CHEM_RATES_QK_diss_N2/readme.md)       |
|    9    | CHEM_RATES_QK_ionization-recomb_H |                  |               QK rates for ionization and recombination: H + e <-> HIon + e + e               |   nProcs=1    |               | [Link](regressioncheck/checks/NIG_Reservoir/CHEM_RATES_QK_ionization-recomb_H/readme.md) |
|   10    |      CHEM_RATES_QK_recomb_N2      |                  |                       QK rates for a recombination: N + N + M -> N2 + M                       |   nProcs=1    |               |      [Link](regressioncheck/checks/NIG_Reservoir/CHEM_RATES_QK_recomb_N2/readme.md)      |
|   11    |             RELAX_CH4             |                  |              Rotational, vibrational relaxation towards equilibrium temperature               |   nProcs=2    |               |             [Link](regressioncheck/checks/NIG_Reservoir/RELAX_CH4/readme.md)             |
|   12    |           RELAX_CH4_PDR           |                  | Relaxation towards equilibrium with prohibiting double relaxation (single/multi mode for CH4) |   nProcs=2    |               |           [Link](regressioncheck/checks/NIG_Reservoir/RELAX_CH4_PDR/readme.md)           |
|   13    |             RELAX_CO2             |                  |              Rotational, vibrational relaxation towards equilibrium temperature               |   nProcs=2    |               |             [Link](regressioncheck/checks/NIG_Reservoir/RELAX_CO2/readme.md)             |
|   14    |             RELAX_N2              |                  |                        Rotational, vibrational, electronic relaxation                         |   nProcs=1    |               |             [Link](regressioncheck/checks/NIG_Reservoir/RELAX_N2/readme.md)              |
|   15    |            RELAX_N2Ion            |                  |                        Rotational, vibrational, electronic relaxation                         |   nProcs=1    |               |            [Link](regressioncheck/checks/NIG_Reservoir/RELAX_N2Ion/readme.md)            |
|   16    |         VarRelaxProb_cold         |                  |          Relaxation of a cold reservoir of N2 with variable relaxation probabilities          | nProcs=1,2,3  |               |         [Link](regressioncheck/checks/NIG_Reservoir/VarRelaxProb_cold/readme.md)         |
|   17    |         VarRelaxProb_hot          |                  |       Relaxation of a hot reservoir of N2 and O2 with variable relaxation probabilities       |  nProcs=2,3   |               |         [Link](regressioncheck/checks/NIG_Reservoir/VarRelaxProb_hot/readme.md)          |
|   18    |       VarRelaxProb_Restart        |                  |                  Initial Autorestart with variable relaxation probabilities                   |  nProcs=1,2   |               |       [Link](regressioncheck/checks/NIG_Reservoir/VarRelaxProb_Restart/readme.md)        |

#### NIG_MacroBody

Testing of routines when using MacroBodies: [Link to build](regressioncheck/checks/NIG_MacroBody/builds.ini).

| **No.** |       **Case**        | **CMAKE-CONFIG** |  **Feature**   | **Execution** | **Comparing** |                                  **Readme**                                  |
| :-----: | :-------------------: | :--------------: | :------------: | :-----------: | :-----------: | :--------------------------------------------------------------------------: |
|    1    | SphereMovingInChannel | TD=MACROBODY(43) | nMacroBodies>0 |   nProcs=1    |               | [Link](regressioncheck/checks/NIG_MacroBody/SphereMovingInChannel/readme.md) |
|    1    |     SphereSample      | TD=MACROBODY(43) | nMacroBodies>0 |   nProcs=1    |               |     [Link](regressioncheck/checks/NIG_MacroBody/SphereSample/readme.md)      |
|    2    |   SphereThroughCube   | TD=MACROBODY(43) | nMacroBodies>0 |   nProcs=1    |               |   [Link](regressioncheck/checks/NIG_MacroBody/SphereThroughCube/readme.md)   |
|    3    |  SphereWithEmission   | TD=MACROBODY(43) | nMacroBodies>0 |   nProcs=1    |               |  [Link](regressioncheck/checks/NIG_MacroBody/SphereWithEmission/readme.md)   |

#### NIG_tracking_DSMC

Testing of different tracking routines with DSMC: [Link to build](regressioncheck/checks/NIG_tracking_DSMC/builds.ini).

| **No.** |     **Case**      | **CMAKE-CONFIG** |           **Feature**           |                 **Execution**                  |          **Comparing**           | **Readme** |
| :-----: | :---------------: | :--------------: | :-----------------------------: | :--------------------------------------------: | :------------------------------: | :--------: |
|    1    |     ANSA box      |                  |                                 | DoRefMapping=T,F; TriaTracking=F,T; nProcs=1,2 | PartInt, PartPos in bounding box |            |
|    2    |      curved       |                  |                                 |          DoRefMapping=T  , nProcs=1,2          | PartInt with relative tolerance  |            |
|    3    |      mortar       |                  |                                 | DoRefMapping=T,F; TriaTracking=F,T; nProcs=1,2 | PartInt, PartPos in bounding box |            |
|    4    |  mortar_hexpress  |                  | Mortar mesh built with HEXPRESS |           TriaTracking=T; nProcs=2,4           |             PartInt              |            |
|    5    |     periodic      |                  |                                 |       DoRefMapping=T,F, nProcs=1,2,5,10        | PartInt, PartPos in bounding box |            |
|    6    |  periodic_2cells  |                  |                                 |  DoRefMapping=T,F;TriaTracking=T,F, nProcs=1   |     PartPos in bounding box      |            |
|    7    |    semicircle     |                  |                                 |          DoRefMapping=T,F, nProcs=1,2          |     PartPos in bounding box      |            |
|    8    |    sphere_soft    |                  |                                 | DoRefMapping=T;RefMappingGuess=1,3,nProcs=1,2  |     PartPos in bounding box      |            |
|    9    | tracing_cylinder1 |                  |  mortar,curved,single particle  |            DoRefMapping=F, nProcs=1            |    PartPos-X in bounding box     |            |
|   10    | tracing_cylinder2 |                  |  mortar,curved,single particle  |            DoRefMapping=F, nProcs=1            |    PartPos-X in bounding box     |            |

#### NIG_SuperB

Testing of different SuperB examples (via piclas or standalone superB binary), which generate a 3D magnetic field distribution to be used in piclas: [Link to build](regressioncheck/checks/NIG_SuperB/builds.ini).

| **No.** | **Case**          | **CMAKE-CONFIG**                             | **Feature**                     | **Execution**                                  | **Comparing**                                                    | **Readme**                                                          |
| :-----: | :---------------: | :-------------------------:                  | :-----------------------------: | :--------------------------------------------: | :------------------------------:                                 | :--------:                                                          |
| 1       | LinearConductor   | PICLAS_BUILD_POSTI=ON, POSTI_BUILD_SUPERB=ON | straight conducting line        | piclas, superB binaries (single-core)          | convergence test with number of segments of the linear conductor | [Link](regressioncheck/checks/NIG_SuperB/LinearConductor/readme.md) |
| 2       | CircularCoil      | PICLAS_BUILD_POSTI=ON, POSTI_BUILD_SUPERB=ON | circular shaped coil            | piclas, superB binaries (single-core)          | reference solution h5diff                                        | [Link](regressioncheck/checks/NIG_SuperB/CircularCoil/readme.md)    |
| 3       | RectangularCoil   | PICLAS_BUILD_POSTI=ON, POSTI_BUILD_SUPERB=ON | rectangular shaped coil         | piclas, superB binaries (single-core)          | reference solution h5diff                                        | [Link](regressioncheck/checks/NIG_SuperB/RectangularCoil/readme.md) |
| 4       | SphericalMagnet   | PICLAS_BUILD_POSTI=ON, POSTI_BUILD_SUPERB=ON | spherically shaped hard magnet  | piclas, superB binaries (single-core)          | convergence test with number of nodes of the spherical magnet    | [Link](regressioncheck/checks/NIG_SuperB/SphericalMagnet/readme.md) |
| 5       | CubicMagnet       | PICLAS_BUILD_POSTI=ON, POSTI_BUILD_SUPERB=ON | cubic shaped hard magnet        | piclas, superB binaries (single-core)          | reference solution h5diff                                        | [Link](regressioncheck/checks/NIG_SuperB/CubicMagnet/readme.md)     |

#### NIG_PIC_poisson_RK3

Testing PIC compiled with Runge-Kutta 3 integration, solving Poisson's equation: [Link to build](regressioncheck/checks/NIG_PIC_poisson_RK3/builds.ini).

| **No.** |         **Case**          | **CMAKE-CONFIG** |    **Feature**    |  **Execution**  |          **Comparing**           |                                       **Readme**                                       |
| :-----: | :-----------------------: | :--------------: | :---------------: | :-------------: | :------------------------------: | :------------------------------------------------------------------------------------: |
|    1    | 2D_SFLocalDepoBC_innerBC  |                  | Shape-Function-ND | nProcs=1,2,5,10 | h5diff of DG_Source and ElemData | [Link](regressioncheck/checks/NIG_PIC_poisson_RK3/2D_SFLocalDepoBC_innerBC/readme.md)  |
|    2    | 2D_SFLocalDepoBC_periodic |                  | Shape-Function-ND | nProcs=1,2,5,10 | h5diff of DG_Source and ElemData | [Link](regressioncheck/checks/NIG_PIC_poisson_RK3/2D_SFLocalDepoBC_periodic/readme.md) |
|    3    |      parallel_plates      |                  | CalcCoupledPower  |    nProcs=1     |      PartAnalyzeRK3_ref.csv      |      [Link](regressioncheck/checks/NIG_PIC_poisson_RK3/parallel_plates/readme.md)      |
|    4    |    parallel_plates_AC     |                  | CalcCoupledPower  |    nProcs=1     |      PartAnalyzeRK3_ref.csv      |    [Link](regressioncheck/checks/NIG_PIC_poisson_RK3/parallel_plates_AC/readme.md)     |
|    5    |          turner           |                  |                   |    nProcs=4     |    L2 error, PartAnalyze.csv     |                                                                                        |

#### NIG_PIC_maxwell_RK4

Testing PIC compiled with Runge-Kutta 4 integration, solving Maxwell's equations: [Link to build](regressioncheck/checks/NIG_PIC_maxwell_RK4/builds.ini).

| **No.** |     **Case**      | **CMAKE-CONFIG** |         **Feature**          |                **Execution**                |       **Comparing**        | **Readme** |
| :-----: | :---------------: | :--------------: | :--------------------------: | :-----------------------------------------: | :------------------------: | :--------: |
|    1    | external_bgfield  |                  | External Background-field,h5 |                  nProcs=2                   |        DG_Solution         |            |
|    2    | emission_gyrotron |                  |     Part-Inflow,TimeDep      | N=1,3,6,9,10, nProcs=1,2,10,25, gyro-circle | LineIntegration of nPartIn |            |
|    3    |  single_particle  |                  |                              |              nProcs=1,2,3,4,5               |    L2 error, DG_Source     |            |
|    4    | TWT_recordpoints  |                  |        RPs, ExactFlux        |     nProcs=1,4, RPs, interior TE-Inflow     |     RP_State, RP_Data      |            |

#### NIG_maxwell_RK4

Testing the field solver (without compiling particle related routines) with Runge-Kutta 4 integration, solving Maxwell's equations: [Link to build](regressioncheck/checks/NIG_maxwell_RK4/builds.ini).

| **No.** |      **Case**       | **CMAKE-CONFIG** | **Feature** |   **Execution**   |      **Comparing**       |                                **Readme**                                |
| :-----: | :-----------------: | :--------------: | :---------: | :---------------: | :----------------------: | :----------------------------------------------------------------------: |
|    1    | dipole_cylinder_PML |                  |             |    nProcs=1,4     |  L2 error, DG_Solution   |                                                                          |
|    2    |    ExactFlux_PML    |                  |             |   nProcs=1,4,8    |  L2 error, FieldAnalyze  |                                                                          |
|    3    |   MortarPlaneWave   |                  |   Mortars   | nProcs=1,2,5,7,12 | DG_Solution,FieldAnalyze | [Link](regressioncheck/checks/NIG_maxwell_RK4/MortarPlaneWave/readme.md) |

#### NIG_SurfaceModel

Testing the surface models with RESERVOIR timedisc: [Link to build](regressioncheck/checks/NIG_SurfaceModel/builds.ini).

| **No.** |  **Case**  | **CMAKE-CONFIG** |  **Feature**   |         **Execution**         | **Comparing**  |                              **Readme**                               |
| :-----: | :--------: | :--------------: | :------------: | :---------------------------: | :------------: | :-------------------------------------------------------------------: |
|    1    | AdsorbHeat |                  | surfacemodel=3 | nProcs=1, LateralInactive=T,F | SurfaceAnalyze | [Link](regressioncheck/checks/NIG_SurfaceModel/AdsorbHeat/readme.md)  |
|    2    | TPD_reggie |                  | surfacemodel=3 |           nProcs=1            | SurfaceAnalyze | [Link](regressioncheck/checks/NIG_SurfaceModel/TPD_reggies/readme.md) |

#### NIG_LoadBalance

Testing the LoadBalance feature with different timediscs: [Link to build](regressioncheck/checks/NIG_LoadBalance/builds.ini).

| **No.** |           **Case**           | **CMAKE-CONFIG** |                     **Feature**                     |                                                         **Execution**                                                         | **Comparing** |                              **Readme**                               |
| :-----: | :--------------------------: | :--------------: | :-------------------------------------------------: | :---------------------------------------------------------------------------------------------------------------------------: | :-----------: | :-------------------------------------------------------------------: |
|    1    |       sphere_soft_DSMC       |                  |                                                     |                                                                                                                               |               |                                                                       |
|    1    |  sphere_soft_RK4_with_DSMC   |                  |                                                     |                                                                                                                               |               |                                                                       |
|    1    | sphere_soft_RK4_without_DSMC |                  |                                                     |                                                                                                                               |               |                                                                       |
|    1    |         SurfaceModel         |                  | LoadBalance with surfacemodels 0, 2 and 3 with DSMC | nProcs=4, DoLoadBalance=T,F ,PartWeightLoadBalance=F,T ,DoInitialAutRestart=T,T ,InitialAutoRestart-PartWeightLoadBalance=F,F |               | [Link](regressioncheck/checks/NIG_LoadBalance/SurfaceModel/readme.md) |

## Weekly

Overview of the test cases performed every week.

| **No.** |              **Case**              |                       **CMAKE-CONFIG**                       |                                      **Feature**                                      |         **Execution**         |                **Comparing**                 |                                        **Readme**                                         |
| :-----: | :--------------------------------: | :----------------------------------------------------------: | :-----------------------------------------------------------------------------------: | :---------------------------: | :------------------------------------------: | :---------------------------------------------------------------------------------------: |
|    1    |  feature_PIC_maxwell_plasma_wave   |                    maxwell,RK4,ImplicitO4                    |                            Maxwell-PIC,SF1D, FastPeriodic                             | nProcs=2, IMEX for ImplicitO4 |        W_el LineIntegration over 2Per        |                                                                                           |
|    2    |         CHEM_EQUI_diss_CH4         | [Reservoir](regressioncheck/checks/WEK_Reservoir/builds.ini) |        Relaxation into equilibrium with dissociation and recombination of CH4         |           nProcs=2            |             PartAnalyze_ref.csv              |         [Link](regressioncheck/checks/WEK_Reservoir/CHEM_EQUI_diss_CH4/readme.md)         |
|    3    |        CHEM_EQUI_exch_CH3-H        |                              **                              |    Relaxation into equilibrium with exchange/radical reaction of CH3+H <-> CH2+H2     |           nProcs=2            |             PartAnalyze_ref.csv              |        [Link](regressioncheck/checks/WEK_Reservoir/CHEM_EQUI_exch_CH3-H/readme.md)        |
|    4    |       CHEM_EQUI_ionization_H       |                              **                              |          Relaxation into equilibrium with ionization and recombination of H           |           nProcs=1            |             PartAnalyze_ref.csv              |       [Link](regressioncheck/checks/WEK_Reservoir/CHEM_EQUI_ionization_H/readme.md)       |
|    5    | CHEM_EQUI_diss_CH4_2DAxi_RadWeight |                              **                              |    Analagous to CHEM_EQUI_diss_CH4 with 2D axisymmetric mesh with radial weighting    |           nProcs=2            |             PartAnalyze_ref.csv              | [Link](regressioncheck/checks/WEK_Reservoir/CHEM_EQUI_diss_CH4_2DAxi_RadWeight/readme.md) |
|    6    |     Flow_Argon_Cylinder_Curved     |      [DSMC](regressioncheck/checks/WEK_DSMC/builds.ini)      |    Hypersonic Argon flow around a cylinder (pseudo 2D) with DSMC on a curved mesh     |           nProcs=2            |                                              |       [Link](regressioncheck/checks/WEK_DSMC/Flow_Argon_Cylinder_Curved/readme.md)        |
|    7    |   Flow_Argon_Cylinder_LinearMesh   |                              **                              |        Hypersonic Argon flow around a cylinder (2D) with DSMC on a linear mesh        |           nProcs=4            |                                              |     [Link](regressioncheck/checks/WEK_DSMC/Flow_Argon_Cylinder_LinearMesh/readme.md)      |
|    8    |    SurfFlux_RefMapping_Tracing     |                              **                              | Surface flux emission with DoRefMapping and Tracing tracking routines (collisionless) |           nProcs=1            |               Database.csv_ref               |       [Link](regressioncheck/checks/WEK_DSMC/SurfFlux_RefMapping_Tracing/readme.md)       |
|    9    |         Flow_N2_70degCone          |                              **                              |                            2D-Axissymmetric 70 degree cone                            |           nProcs=12           | Surface Sampling, includes CalcSurfaceImpact |            [Link](regressioncheck/checks/WEK_DSMC/Flow_N2_70degCone/readme.md)            |
