!==================================================================================================================================
! Copyright (c) 2010 - 2018 Prof. Claus-Dieter Munz and Prof. Stefanos Fasoulas
!
! This file is part of PICLas (gitlab.com/piclas/piclas). PICLas is free software: you can redistribute it and/or modify
! it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3
! of the License, or (at your option) any later version.
!
! PICLas is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty
! of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License v3.0 for more details.
!
! You should have received a copy of the GNU General Public License along with PICLas. If not, see <http://www.gnu.org/licenses/>.
!==================================================================================================================================
#include "piclas.h"


MODULE MOD_TimeDisc
!===================================================================================================================================
! Module for the GTS Temporal discretization
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!-----------------------------------------------------------------------------------------------------------------------------------
INTERFACE InitTime
  MODULE PROCEDURE InitTime
END INTERFACE

INTERFACE InitTimeDisc
  MODULE PROCEDURE InitTimeDisc
END INTERFACE

INTERFACE TimeDisc
  MODULE PROCEDURE TimeDisc
END INTERFACE

PUBLIC :: InitTime,InitTimeDisc,TimeDisc
!===================================================================================================================================
PUBLIC :: DefineParametersTimeDisc

CONTAINS

!=================================================================================================================================
!> Define parameters
!==================================================================================================================================
SUBROUTINE DefineParametersTimeDisc()
! MODULES
USE MOD_ReadInTools ,ONLY: prms
IMPLICIT NONE
!==================================================================================================================================
CALL prms%SetSection("TimeDisc")
!CALL prms%CreateStringOption('TimeDiscMethod', "Specifies the type of time-discretization to be used, \ne.g. the name of"//&
                                               !" a specific Runge-Kutta scheme. Possible values:\n"//&
                                               !"  * standardrk3-3\n  * carpenterrk4-5\n  * niegemannrk4-14\n"//&
                                               !"  * toulorgerk4-8c\n  * toulorgerk3-7c\n  * toulorgerk4-8f\n"//&
                                               !"  * ketchesonrk4-20\n  * ketchesonrk4-18", value='CarpenterRK4-5')
CALL prms%CreateRealOption(  'TEnd',           "End time of the simulation (mandatory).")
CALL prms%CreateRealOption(  'CFLScale',       "Scaling factor for the theoretical CFL number, typical range 0.1..1.0 (mandatory)")
CALL prms%CreateIntOption(   'maxIter',        "Stop simulation when specified number of timesteps has been performed.", value='-1')
CALL prms%CreateIntOption(   'NCalcTimeStepMax',"Compute dt at least after every Nth timestep.", value='1')

CALL prms%CreateIntOption(   'IterDisplayStep',"Step size of iteration that are displayed.", value='1')

END SUBROUTINE DefineParametersTimeDisc


SUBROUTINE InitTime()
!===================================================================================================================================
!>
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_TimeDisc_Vars          ,ONLY: time,TEnd,tAnalyze,tEndDiff,tAnalyzeDiff
USE MOD_Restart_Vars           ,ONLY: RestartTime
#ifdef PARTICLES
USE MOD_DSMC_Vars              ,ONLY: Iter_macvalout,Iter_macsurfvalout
USE MOD_Particle_Vars          ,ONLY: WriteMacroVolumeValues, WriteMacroSurfaceValues, MacroValSampTime
#endif /*PARTICLES*/
USE MOD_Analyze_Vars           ,ONLY: Analyze_dt,iAnalyze
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
! Setting the time variable, RestartTime is either zero or the actual restart time
time=RestartTime
#ifdef PARTICLES
iter_macvalout=0
iter_macsurfvalout=0
IF (WriteMacroVolumeValues.OR.WriteMacroSurfaceValues) MacroValSampTime = Time
#endif /*PARTICLES*/
iAnalyze=1
! Determine analyze time
tAnalyze=MIN(RestartTime+REAL(iAnalyze)*Analyze_dt,tEnd)

! fill initial analyze stuff
tAnalyzeDiff=tAnalyze-time    ! time to next analysis, put in extra variable so number does not change due to numerical errors
tEndDiff=tEnd-time            ! dito for end time

END SUBROUTINE InitTime


SUBROUTINE InitTimeDisc()
!===================================================================================================================================
! Get information for end time and max time steps from ini file
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_Globals
USE MOD_ReadInTools   ,ONLY: GetReal,GetInt, GETLOGICAL
USE MOD_TimeDisc_Vars ,ONLY: IterDisplayStepUser
USE MOD_TimeDisc_Vars ,ONLY: CFLScale,dt,TimeDiscInitIsDone,RKdtFrac,RKdtFracTotal,dtWeight
USE MOD_TimeDisc_Vars ,ONLY: IterDisplayStep,DoDisplayIter
#ifdef IMPA
USE MOD_TimeDisc_Vars ,ONLY: RK_c, RK_inc,RK_inflow,nRKStages
#endif
#ifdef ROS
USE MOD_TimeDisc_Vars ,ONLY: RK_c, RK_inflow,nRKStages
#endif
USE MOD_TimeDisc_Vars ,ONLY: TEnd
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
#if defined(IMPA) || defined(ROS)
INTEGER                   :: iCounter
REAL                      :: rtmp
#endif
!===================================================================================================================================
IF(TimeDiscInitIsDone)THEN
   SWRITE(*,*) "InitTimeDisc already called."
   RETURN
END IF
SWRITE(UNIT_StdOut,'(132("-"))')
SWRITE(UNIT_stdOut,'(A)') ' INIT TIMEDISC...'

! Read the normalized CFL number
CFLScale = GETREAL('CFLScale')
CALL fillCFL_DFL()

! Read the maximum number of time steps MaxIter and the end time TEnd from ini file
TEnd=GetReal('TEnd') ! must be read in here due to DSMC_init

! read in requested IterDisplayStep (i.e. how often the message "iter: etc" is displayed, might be changed dependent on Particle-dt)
DoDisplayIter=.FALSE.
IterDisplayStepUser = GETINT('IterDisplayStep','1')
IterDisplayStep = IterDisplayStepUser
IF(IterDisplayStep.GE.1) DoDisplayIter=.TRUE.

#ifdef ROS
RK_inflow(2)=RK_C(2)
rTmp=RK_c(2)
DO iCounter=3,nRKStages
  RK_inflow(iCounter)=MAX(RK_c(iCounter)-MAX(RK_c(iCounter-1),rTmp),0.)
  rTmp=MAX(rTmp,RK_c(iCounter))
  IF(RK_c(iCounter).GT.1.) RK_inflow(iCounter)=0.
END DO ! iCounter=2,nRKStages-1
#endif

#ifdef IMPA
! get time increment between current and next RK stage
DO iCounter=2,nRKStages-1
  RK_inc(iCounter)=RK_c(iCounter+1)-RK_c(iCounter)
END DO ! iCounter=2,nRKStages-1
RK_inc(nRKStages)=0.

! compute ratio of dt for particle surface flux emission (example a). Additionally, the ratio of RK_inflow(iStage)/RK_c(iStage)
! gives the ! maximum distance, the Surface Flux particles can during the initial implicit step (example b).
! example a)
!   particle number for stage 4: dt*RK_inflow(4)
! or: generate all particles for dt, but only particles with random number R < RK_c(iStage) participate in current stage.
! This results in dt*RK_inflow(iStage) particles in the current stage, hence, we can decide if we generate all particles or
! only the particles per stage. Currently, all particles are generated prior to the RK stages.
! example b)
! ESDIRKO4 from kennedy and carpenter without an acting force. Assume again stage 4. The initial particles during stage 2 are
! moved in stage 3 without tracking (because it could be dropped out of the domain and the negative increment of the time level.
! The new particles in this  stage could travel a distance up to RK_c(4)=SUM(ESDIRK_a(4,:)). Now, the new particles are pushed
! further into the domain than the particles of the second stage has moved. This would create a non-uniform particle distribution.
! this is prevented by reducing their maximum emission/initial distance by RK_inflow(4)/RK_c(4).
! Note: A small overlap is possible, but this is required. See the charts in the docu folder.
RK_inflow(2)=RK_C(2)
rTmp=RK_c(2)
DO iCounter=3,nRKStages
  RK_inflow(iCounter)=MAX(RK_c(iCounter)-MAX(RK_c(iCounter-1),rTmp),0.)
  rTmp=MAX(rTmp,RK_c(iCounter))
END DO ! iCounter=2,nRKStages-1
#endif

! Set timestep to a large number
dt=HUGE(1.)
#if (PP_TimeDiscMethod==1)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: LSERK3-3 '
#elif (PP_TimeDiscMethod==2)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: LSERK4-5 '
#elif (PP_TimeDiscMethod==3)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: TAYLOR'
#elif (PP_TimeDiscMethod==4)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: Direct Simulation Monte Carlo (DSMC)'
#elif (PP_TimeDiscMethod==6)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: LSERK4-14 '
#elif (PP_TimeDiscMethod==42)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: DSMC Reservoir and Debug'
#elif (PP_TimeDiscMethod==120)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: Heun/Crank-Nicolson1-2-2'
#elif (PP_TimeDiscMethod==121)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: ERK3/ESDIRK3-Particles and ESDIRK3-Field'
#elif (PP_TimeDiscMethod==122)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: ERK4/ESDIRK4-Particles and ESDIRK4-Field'
#elif (PP_TimeDiscMethod==123)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: ERK3/ESDIRK3-Particles and ESDIRK3-Field'
  SWRITE(UNIT_stdOut,'(A)') '                             Ascher - 2 - 3 -3               '
#elif (PP_TimeDiscMethod==130)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: ROS-2-2 by Iannelli'
#elif (PP_TimeDiscMethod==131)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: ROS-3-3 by Langer-Verwer'
#elif (PP_TimeDiscMethod==132)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: ROS-4-4 by Shampine'
#elif (PP_TimeDiscMethod==133)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: ROS-4-6 by Steinebach'
#elif (PP_TimeDiscMethod==134)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: ROS-6-6 by Kaps'
#elif (PP_TimeDiscMethod==300)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: Fokker-Planck (FP) Collision Operator'
#elif (PP_TimeDiscMethod==400)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: Bhatnagar-Gross-Krook (BGK) Collision Operator'
#elif (PP_TimeDiscMethod==500)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: Euler, Poisson'
#elif (PP_TimeDiscMethod==501)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: LSERK3-3, Poisson'
#elif (PP_TimeDiscMethod==502)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: LSERK4-5, Poisson'
#elif (PP_TimeDiscMethod==506)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: LSERK4-14, Poisson'
#elif (PP_TimeDiscMethod==509)
  SWRITE(UNIT_stdOut,'(A)') ' Method of time integration: Leapfrog, Poisson'
# endif
RKdtFrac=1.
RKdtFracTotal=1.
dtWeight=1.
TimediscInitIsDone = .TRUE.
SWRITE(UNIT_stdOut,'(A)')' INIT TIMEDISC DONE!'
SWRITE(UNIT_StdOut,'(132("-"))')
END SUBROUTINE InitTimeDisc



SUBROUTINE TimeDisc()
!===================================================================================================================================
! GTS Temporal discretization
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Globals_Vars           ,ONLY: SimulationEfficiency,PID,WallTime
USE MOD_PreProc
USE MOD_TimeDisc_Vars          ,ONLY: time,TEnd,dt,iter,IterDisplayStep,DoDisplayIter,dt_Min,tAnalyze,dtWeight,tEndDiff,tAnalyzeDiff
!USE MOD_Equation_Vars          ,ONLY: c
#if (PP_TimeDiscMethod==509)
USE MOD_TimeDisc_Vars          ,ONLY: dt_old
#endif /*(PP_TimeDiscMethod==509)*/
USE MOD_TimeAverage_vars       ,ONLY: doCalcTimeAverage
USE MOD_TimeAverage            ,ONLY: CalcTimeAverage
USE MOD_Analyze                ,ONLY: PerformAnalyze
USE MOD_Analyze_Vars           ,ONLY: Analyze_dt,iAnalyze
USE MOD_Restart_Vars           ,ONLY: RestartTime,RestartWallTime
USE MOD_HDF5_output            ,ONLY: WriteStateToHDF5
USE MOD_Mesh_Vars              ,ONLY: MeshFile,nGlobalElems,DoWriteStateToHDF5
USE MOD_RecordPoints_Vars      ,ONLY: RP_onProc
USE MOD_RecordPoints           ,ONLY: WriteRPToHDF5!,RecordPoints
USE MOD_LoadBalance_Vars       ,ONLY: nSkipAnalyze
#if !(USE_HDG)
USE MOD_PML_Vars               ,ONLY: DoPML,DoPMLTimeRamp,PMLTimeRamp
USE MOD_PML                    ,ONLY: PMLTimeRamping
#if USE_LOADBALANCE
#ifdef maxwell
#if defined(ROS) || defined(IMPA)
USE MOD_Precond_Vars           ,ONLY:UpdatePrecondLB
#endif /*ROS or IMPA*/
#endif /*maxwell*/
#endif /*USE_LOADBALANCE*/
#endif /*USE_HDG*/
#ifdef PP_POIS
USE MOD_Restart_Vars           ,ONLY: DoRestart
USE MOD_Equation               ,ONLY: EvalGradient
#endif /*PP_POIS*/
#if USE_MPI
#if USE_LOADBALANCE
USE MOD_LoadBalance            ,ONLY: LoadBalance,ComputeElemLoad
USE MOD_LoadBalance_Vars       ,ONLY: DoLoadBalance,ElemTime
USE MOD_LoadBalance_Vars       ,ONLY: LoadBalanceSample,PerformLBSample,PerformLoadBalance,LoadBalanceMaxSteps,nLoadBalanceSteps
USE MOD_Restart_Vars           ,ONLY: DoInitialAutoRestart,InitialAutoRestartSample,IAR_PerformPartWeightLB
USE MOD_Particle_Vars          ,ONLY: WriteMacroVolumeValues, WriteMacroSurfaceValues, MacroValSampTime
#endif /*USE_LOADBALANCE*/
#endif /*USE_MPI*/
#ifdef PARTICLES
USE MOD_Particle_Mesh          ,ONLY: CountPartsPerElem
USE MOD_HDF5_Output_Tools      ,ONLY: WriteIMDStateToHDF5
#else
USE MOD_AnalyzeField           ,ONLY: AnalyzeField
#endif /*PARTICLES*/
#if USE_QDS_DG
USE MOD_HDF5_Output_Tools      ,ONLY: WriteQDSToHDF5
USE MOD_QDS_DG_Vars            ,ONLY: DoQDS
#endif /*USE_QDS_DG*/
#ifdef PARTICLES
USE MOD_PICDepo                ,ONLY: Deposition
USE MOD_Particle_Vars          ,ONLY: DoImportIMDFile
#if USE_MPI
USE MOD_PICDepo_Vars           ,ONLY: DepositionType
#endif /*USE_MPI*/
USE MOD_Particle_Vars          ,ONLY: doParticleMerge, enableParticleMerge, vMPFMergeParticleIter, UseAdaptive
USE MOD_Particle_Tracking_vars ,ONLY: tTracking,tLocalization,nTracks,MeasureTrackTime
#if (USE_MPI) && (USE_LOADBALANCE) && defined(PARTICLES)
USE MOD_DSMC_Vars              ,ONLY: DSMC
#endif /* USE_LOADBALANCE && PARTICLES*/
USE MOD_Part_Emission          ,ONLY: AdaptiveBCAnalyze
USE MOD_Particle_Boundary_Vars ,ONLY: nAdaptiveBC, nPorousBC
#if USE_MPI
USE MOD_Particle_MPI           ,ONLY: IRecvNbOfParticles, MPIParticleSend,MPIParticleRecv,SendNbOfparticles
#endif /*USE_MPI*/
#endif /*PARTICLES*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                         :: tPreviousAnalyze         !> time of previous analyze.
                                                         !> Used for Nextfile info written into previous file if greater tAnalyze
REAL                         :: tPreviousAverageAnalyze  !> time of previous Average analyze.
REAL                         :: tZero
INTEGER(KIND=8)              :: iter_PID                 !> iteration counter since last InitPiclas call for PID calculation
REAL                         :: WallTimeStart            !> wall time of simulation start
REAL                         :: WallTimeEnd              !> wall time of simulation end
#if USE_LOADBALANCE
INTEGER                      :: tmp_LoadBalanceSample    !> loadbalance sample saved until initial autorestart ist finished
LOGICAL                      :: tmp_DoLoadBalance        !> loadbalance flag saved until initial autorestart ist finished
#endif /*USE_LOADBALANCE*/
LOGICAL                      :: finalIter
!===================================================================================================================================
tPreviousAnalyze=RestartTime
! first average analyze is not written at start but at first tAnalyze
tPreviousAverageAnalyze=tAnalyze
! saving the start of the simulation as restart time is overwritten during load balance step
!   In case the overwritten one is used, state write out is performed only next Nth analze-dt after restart instead after analyze-dt
!   w/o  tZero: nSkipAnalyze=5 , restart after iAnalyze=2 , next write out witout any restarts after iAnalyze=7
!   with tZero: nSkipAnalyze=5 , restart after iAnalyze=2 , next write out witout any restarts after iAnalyze=5
tZero = RestartTime

! write number of grid cells and dofs only once per computation
SWRITE(UNIT_stdOut,'(A13,ES16.7)')'#GridCells : ',REAL(nGlobalElems)
SWRITE(UNIT_stdOut,'(A13,ES16.7)')'#DOFs      : ',REAL(nGlobalElems*(PP_N+1)**3)
SWRITE(UNIT_stdOut,'(A13,ES16.7)')'#Procs     : ',REAL(nProcessors)
SWRITE(UNIT_stdOut,'(A13,ES16.7)')'#DOFs/Proc : ',REAL(nGlobalElems*(PP_N+1)**3/nProcessors)

!Evaluate Gradients to get Potential in case of Restart and Poisson Calc
#ifdef PP_POIS
IF(DoRestart) CALL EvalGradient()
#endif /*PP_POIS*/
! Write the state at time=0, i.e. the initial condition

#if defined(PARTICLES) && (USE_MPI)
! e.g. 'shape_function', 'shape_function_1d', 'shape_function_cylindrical', 'shape_function_spherical', 'shape_function_simple'
IF(TRIM(DepositionType(1:MIN(14,LEN(TRIM(ADJUSTL(DepositionType)))))).EQ.'shape_function')THEN
  ! open receive buffer for number of particles
  CALL IRecvNbofParticles()
  ! send number of particles
  CALL SendNbOfParticles()
  ! finish communication of number of particles and send particles
  CALL MPIParticleSend()
  ! finish communication
  CALL MPIParticleRecv()
END IF
#endif /*MPI PARTICLES*/

!#if (PP_TimeDiscMethod==1)||(PP_TimeDiscMethod==2)||(PP_TimeDiscMethod==6)||(PP_TimeDiscMethod>=501 && PP_TimeDiscMethod<=506)
!  CALL IRecvNbofParticles()
!  CALL MPIParticleSend()
!#endif /*USE_MPI*/
!  CALL Deposition(DoInnerParts=.TRUE.)
!#if USE_MPI
!  CALL MPIParticleRecv()
!  ! second buffer
!  CALL Deposition(DoInnerParts=.FALSE.)
!#endif /*USE_MPI*/
!#endif
CALL InitTimeStep() ! Initial time step calculation
WallTimeStart=PICLASTIME()
iter=0
iter_PID=0

! fill recordpoints buffer (first iteration)
!IF(RP_onProc) CALL RecordPoints(iter,t,forceSampling=.TRUE.)

dt=MINVAL((/dt_Min,tAnalyzeDiff,tEndDiff/)) ! quick fix: set dt for initial write DSMCHOState (WriteMacroVolumeValues=T)

#if USE_LOADBALANCE
IF (DoInitialAutoRestart) THEN
  tmp_DoLoadBalance     = DoLoadBalance
  DoLoadBalance         = .TRUE.
  tmp_LoadbalanceSample = LoadBalanceSample
  LoadBalanceSample     = InitialAutoRestartSample
  ! correct initialautrestartSample if partweight_initialautorestart is enabled so tAnalyze is calculated correctly
  ! LoadBalanceSample still needs to be zero
  IF (IAR_PerformPartWeightLB) InitialAutoRestartSample=1
  ! correction for first analyzetime due to auto initial restart
  IF (MIN(RestartTime+iAnalyze*Analyze_dt,tEnd,RestartTime+InitialAutoRestartSample*dt).LT.tAnalyze) THEN
    tAnalyze     = MIN(RestartTime+iAnalyze*Analyze_dt,tEnd,RestartTime+InitialAutoRestartSample*dt)
    tAnalyzeDiff = tAnalyze-time
    dt           = MINVAL((/dt_Min,tAnalyzeDiff,tEndDiff/))
  END IF
END IF
#endif /*USE_LOADBALANCE*/

CALL PerformAnalyze(time,FirstOrLastIter=.TRUE.,OutPutHDF5=.FALSE.)

#ifdef PARTICLES
IF(DoImportIMDFile) CALL WriteIMDStateToHDF5() ! write IMD particles to state file (and TTM if it exists)
#endif /*PARTICLES*/
IF(DoWriteStateToHDF5)THEN
!  #ifdef PARTICLES
!    CALL CountPartsPerElem(ResetNumberOfParticles=.TRUE.) !just for writing actual number into HDF5 (not for loadbalance!)
!  #endif /*PARTICLES*/
  CALL WriteStateToHDF5(TRIM(MeshFile),time,tPreviousAnalyze)
#if USE_QDS_DG
  IF(DoQDS) CALL WriteQDSToHDF5(time,tPreviousAnalyze)
#endif /*USE_QDS_DG*/
END IF

! if measurement of particle tracking time (used for analyze, load balancing uses own time measurement for tracking)
#ifdef PARTICLES
IF(MeasureTrackTime)THEN
  nTracks=0
  tTracking=0
  tLocalization=0
END IF
#endif /*PARTICLES*/

! No computation needed if tEnd=tStart!
IF(time.EQ.tEnd)RETURN

!-----------------------------------------------------------------------------------------------------------------------------------
! iterations starting up from here
!-----------------------------------------------------------------------------------------------------------------------------------
DO !iter_t=0,MaxIter

#ifdef PARTICLES
  IF(enableParticleMerge) THEN
    IF ((iter.GT.0).AND.(MOD(iter,vMPFMergeParticleIter).EQ.0)) doParticleMerge=.true.
  END IF
#endif /*PARTICLES*/

  tAnalyzeDiff=tAnalyze-time    ! time to next analysis, put in extra variable so number does not change due to numerical errors
  tEndDiff=tEnd-time            ! dito for end time

  !IF(time.LT.3e-8)THEN
  !    !RETURN
  !ELSE
  !  IF(time.GT.4e-8) dt_Min=MIN(dt_Min*1.2,2e-8)
  !END IF
#if (PP_TimeDiscMethod==509)
  IF (iter.GT.0) THEN
    dt_old=dt
  END IF
#endif /*(PP_TimeDiscMethod==509)*/
  dt=MINVAL((/dt_Min,tAnalyzeDiff,tEndDiff/))
  dtWeight=dt/dt_Min !might be further descreased by rk-stages
#if (PP_TimeDiscMethod==509)
  IF (iter.EQ.0) THEN
    dt_old=dt
  ELSE IF (ABS(dt-dt_old).GT.1.0E-6*dt_old) THEN
    SWRITE(UNIT_StdOut,'(A,G0)')'WARNING: dt changed from last iter by a relative difference of ',(dt-dt_old)/dt_old
  END IF
#endif /*(PP_TimeDiscMethod==509)*/
#if USE_LOADBALANCE
  ! check if loadbalancing is enabled with elemtime calculation and only LoadBalanceSample number of iteration left until analyze
  ! --> set PerformLBSample true
  IF ((tAnalyzeDiff.LE.LoadBalanceSample*dt &                                 ! all iterations in LoadbalanceSample interval
      .OR. (ALMOSTEQUALRELATIVE(tAnalyzeDiff,LoadBalanceSample*dt,1e-5))) &   ! make sure to get the first iteration in interval
      .AND. .NOT.PerformLBSample .AND. DoLoadBalance) PerformLBSample=.TRUE.  ! make sure Loadbalancing is enabled
#endif /*USE_LOADBALANCE*/
  IF (tAnalyzeDiff-dt.LT.dt/100.0) dt = tAnalyzeDiff
  IF (tEndDiff-dt.LT.dt/100.0) dt = tEndDiff
  IF ( dt .LT. 0. ) THEN
    SWRITE(UNIT_StdOut,*)'*** ERROR: Is something wrong with the defined tEnd?!? ***'
    CALL abort(&
    __STAMP__&
    ,'Error in tEndDiff or tAnalyzeDiff!')
  END IF

  IF(doCalcTimeAverage) CALL CalcTimeAverage(.FALSE.,dt,time,tPreviousAverageAnalyze) ! tPreviousAnalyze not used if finalize_flag=false

#if !(USE_HDG)
  IF(DoPML)THEN
    IF(DoPMLTimeRamp)THEN
      CALL PMLTimeRamping(time,PMLTimeRamp)
    END IF
  END IF
#endif /*NOT USE_HDG*/

! Perform Timestep using a global time stepping routine, attention: only RK3 has time dependent BC
#if (PP_TimeDiscMethod==1)
  CALL TimeStepByLSERK()
#elif (PP_TimeDiscMethod==2)
  CALL TimeStepByLSERK()
#elif (PP_TimeDiscMethod==3)
  CALL TimeStepByTAYLOR()
#elif (PP_TimeDiscMethod==4)
  CALL TimeStep_DSMC()
#elif (PP_TimeDiscMethod==6)
  CALL TimeStepByLSERK()
#elif (PP_TimeDiscMethod==42)
  CALL TimeStep_DSMC_Debug() ! Reservoir and Debug
#elif (PP_TimeDiscMethod==43)
  CALL TimeStep_DSMC_MacroBody() ! DSMC with MacroBody
#elif (PP_TimeDiscMethod==100)
  CALL TimeStepByEulerImplicit() ! O1 Euler Implicit
#elif (PP_TimeDiscMethod==120)
  CALL TimeStepByImplicitRK() ! O3 ERK/ESDIRK Particles + ESDIRK Field
#elif (PP_TimeDiscMethod==121)
  CALL TimeStepByImplicitRK() ! O3 ERK/ESDIRK Particles + ESDIRK Field
#elif (PP_TimeDiscMethod==122)
  CALL TimeStepByImplicitRK() ! O4 ERK/ESDIRK Particles + ESDIRK Field
#elif (PP_TimeDiscMethod==123)
  CALL TimeStepByImplicitRK() ! O3 ERK/ESDIRK Particles + ESDIRK Field
#elif (PP_TimeDiscMethod==130)
  CALL TimeStepByRosenbrock() ! linear Rosenbrock implicit
#elif (PP_TimeDiscMethod==131)
  CALL TimeStepByRosenbrock() ! linear Rosenbrock implicit
#elif (PP_TimeDiscMethod==132)
  CALL TimeStepByRosenbrock() ! linear Rosenbrock implicit
#elif (PP_TimeDiscMethod==133)
  CALL TimeStepByRosenbrock() ! linear Rosenbrock implicit
#elif (PP_TimeDiscMethod==134)
  CALL TimeStepByRosenbrock() ! linear Rosenbrock implicit
#elif (PP_TimeDiscMethod==300)
  CALL TimeStep_FPFlow()
#elif (PP_TimeDiscMethod==400)
  CALL TimeStep_BGK()
#elif (PP_TimeDiscMethod>=500) && (PP_TimeDiscMethod<=509)
#if USE_HDG
#if (PP_TimeDiscMethod==500) || (PP_TimeDiscMethod==509)
  CALL TimeStepPoisson() ! Euler Explicit or leapfrog, Poisson
#else
  CALL TimeStepPoissonByLSERK() ! Runge Kutta Explicit, Poisson
#endif
#else
  CALL abort(&
  __STAMP__&
  ,'Timedisc 50x only available for EQNSYS Poisson!',PP_N,999.)
#endif /*USE_HDG*/
#endif
  ! calling the analyze routines
  iter=iter+1
  iter_PID=iter_PID+1
  time=time+dt
  IF(MPIroot) THEN
    IF(DoDisplayIter)THEN
      IF(MOD(iter,IterDisplayStep).EQ.0) THEN
         !SWRITE(*,*) "iter:", iter,"time:",time ! old format
         !SWRITE(UNIT_stdOut,'(A,I21,A6,ES26.16E3,25X)',ADVANCE='NO')" iter:", iter,"time:",time ! new format for analyze time output
         SWRITE(UNIT_stdOut,'(A,I21,A6,ES26.16E3,25X)'              )" iter:", iter,"time:",time ! new format for analyze time output
      END IF
    END IF
  END IF
  ! calling the analyze routines
  IF(ALMOSTEQUAL(dt,tEndDiff))THEN
    finalIter=.TRUE.
  ELSE
    finalIter=.FALSE.
  END IF
  CALL PerformAnalyze(time,FirstOrLastIter=finalIter,OutPutHDF5=.FALSE.)
#ifdef PARTICLES
  ! sampling of near adaptive boundary element values
  IF((nAdaptiveBC.GT.0).OR.UseAdaptive.OR.(nPorousBC.GT.0)) CALL AdaptiveBCAnalyze()
#endif /*PARICLES*/
  ! output of state file
  !IF ((dt.EQ.tAnalyzeDiff).OR.(dt.EQ.tEndDiff)) THEN   ! timestep is equal to time to analyze or end
  IF((ALMOSTEQUAL(dt,tAnalyzeDiff)).OR.(ALMOSTEQUAL(dt,tEndDiff)))THEN
    WallTimeEnd=PICLASTIME()
    IF(MPIroot)THEN ! determine the SimulationEfficiency and PID here,
                    ! because it is used in ComputeElemLoad -> WriteElemTimeStatistics
      WallTime = WallTimeEnd-StartTime
      SimulationEfficiency = (time-RestartTime)/((WallTimeEnd-RestartWallTime)*nProcessors/3600.) ! in [s] / [CPUh]
      PID=(WallTimeEnd-WallTimeStart)*nProcessors/(nGlobalElems*(PP_N+1)**3*iter_PID)
    END IF

#if USE_MPI
#if !defined(LSERK) && !defined(IMPA) && !defined(ROS)
    CALL CountPartsPerElem(ResetNumberOfParticles=.TRUE.) !for scaling of tParts of LB
#endif
#if USE_LOADBALANCE
#ifdef PARTICLES
    ! Check if loadbalancing is enabled with partweight and set PerformLBSample true to calculate elemtimes with partweight
    ! LoadBalanceSample is 0 if partweightLB or IAR_partweighlb are enabled. If only one of them is set Loadbalancesample switches
    ! during time loop
    IF (LoadBalanceSample.EQ.0 .AND. DoLoadBalance .AND. .NOT.PerformLBSample) PerformLBSample=.TRUE.
#endif /*PARICLES*/
    ! routine calculates imbalance and if greater than threshold PerformLoadBalance=.TRUE.
    CALL ComputeElemLoad()
#ifdef maxwell
#if defined(ROS) || defined(IMPA)
    UpdatePrecondLB=PerformLoadBalance
#endif /*ROS or IMPA*/
#endif /*maxwell*/
#endif /*USE_LOADBALANCE*/
#endif /*USE_MPI*/

#if USE_LOADBALANCE
    IF(MOD(iAnalyze,nSkipAnalyze).EQ.0 .OR. PerformLoadBalance .OR. ALMOSTEQUAL(dt,tEndDiff))THEN
#else
    IF( MOD(iAnalyze,nSkipAnalyze).EQ.0 .OR. ALMOSTEQUAL(dt,tEndDiff))THEN
#endif /*USE_LOADBALANCE*/
      ! Analyze for output
      CALL PerformAnalyze(tAnalyze,FirstOrLastIter=finalIter,OutPutHDF5=.TRUE.)
      ! write information out to std-out of console
      CALL WriteInfoStdOut()
      ! Write state to file
      IF(DoWriteStateToHDF5)THEN
!  #ifdef PARTICLES
!          CALL CountPartsPerElem(ResetNumberOfParticles=.TRUE.) !just for writing actual number into HDF5 (not for loadbalance!)
!  #endif /*PARTICLES*/
        CALL WriteStateToHDF5(TRIM(MeshFile),time,tPreviousAnalyze)
#if USE_QDS_DG
        IF(DoQDS) CALL WriteQDSToHDF5(time,tPreviousAnalyze)
#endif /*USE_QDS_DG*/
      END IF
      IF(doCalcTimeAverage) CALL CalcTimeAverage(.TRUE.,dt,time,tPreviousAverageAnalyze)
      ! Write recordpoints data to hdf5
      IF(RP_onProc) CALL WriteRPtoHDF5(tAnalyze,.TRUE.)
      tPreviousAnalyze=tAnalyze
      tPreviousAverageAnalyze=tAnalyze
      SWRITE(UNIT_StdOut,'(132("-"))')
    END IF ! actual analyze is done
    iter_PID=0
#if USE_LOADBALANCE
    ! Check if load balancing must be performed
    IF(DoLoadBalance.AND.PerformLBSample.AND.(LoadBalanceMaxSteps.GT.nLoadBalanceSteps))THEN
      IF(time.LT.tEnd)THEN ! do not perform a load balance restart when the last timestep is performed
        IF(PerformLoadBalance) THEN
          ! DO NOT DELETE THIS: ONLY recalculate the timestep when the mesh is changed!
          !CALL InitTimeStep() ! re-calculate time step after load balance is performed
          RestartTime=time ! Set restart simulation time to current simulation time because the time is not read from the state file
          RestartWallTime=PICLASTIME() ! Set restart wall time if a load balance step is performed
          dtWeight=1. ! is intialized in InitTimeDisc which is not called in LoadBalance, but needed for restart (RestartHDG)
        END IF
        CALL LoadBalance()
        IF(PerformLoadBalance .AND. MOD(iAnalyze,nSkipAnalyze).NE.0) &
          CALL PerformAnalyze(time,FirstOrLastIter=.FALSE.,OutPutHDF5=.TRUE.)
        !      dt=dt_Min !not sure if nec., was here before InitTimtStep was created, overwritten in next iter anyway
        ! CALL WriteStateToHDF5(TRIM(MeshFile),time,tPreviousAnalyze) ! not sure if required
      END IF
    ELSE
      ElemTime=0. ! nullify ElemTime before measuring the time in the next cycle
    END IF
    PerformLBSample=.FALSE.
    IF (DoInitialAutoRestart) THEN
      DoInitialAutoRestart = .FALSE.
      DoLoadBalance = tmp_DoLoadBalance
      LoadBalanceSample = tmp_LoadBalanceSample
      iAnalyze=0
#ifdef PARTICLES
      DSMC%SampNum=0
      IF (WriteMacroVolumeValues .OR. WriteMacroSurfaceValues) MacroValSampTime = Time
#endif /*PARTICLES*/
    END IF
#endif /*USE_LOADBALANCE*/
    ! count analyze dts passed
    iAnalyze=iAnalyze+1
    tAnalyze=MIN(tZero+REAL(iAnalyze)*Analyze_dt,tEnd)
    WallTimeStart=PICLASTIME()
  END IF !dt_analyze
  IF(time.GE.tEnd)EXIT ! done, worst case: one additional time step
END DO ! iter_t
END SUBROUTINE TimeDisc

#if (PP_TimeDiscMethod==1) || (PP_TimeDiscMethod==2) || (PP_TimeDiscMethod==6)
SUBROUTINE TimeStepByLSERK()
!===================================================================================================================================
! Hesthaven book, page 64
! Low-Storage Runge-Kutta integration of degree 4 with 5 stages.
! This procedure takes the current time (time), the time step dt and the solution at
! the current time U(time) and returns the solution at the next time level.
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_Vector
USE MOD_TimeDisc_Vars          ,ONLY: dt,iStage,time
USE MOD_TimeDisc_Vars          ,ONLY: RK_a,RK_b,RK_c,nRKStages
USE MOD_DG_Vars                ,ONLY: U,Ut
USE MOD_PML_Vars               ,ONLY: U2,U2t,nPMLElems,DoPML,PMLnVar
USE MOD_PML                    ,ONLY: PMLTimeDerivative,CalcPMLSource
#if USE_QDS_DG
USE MOD_QDS_DG_Vars            ,ONLY: UQDS,UQDSt,nQDSElems,DoQDS
USE MOD_QDS_Equation_vars      ,ONLY: QDSnVar
USE MOD_QDS_DG                 ,ONLY: QDSTimeDerivative,QDSReCalculateDGValues,QDSCalculateMacroValues
#endif /*USE_QDS_DG*/
USE MOD_Filter                 ,ONLY: Filter
USE MOD_Equation               ,ONLY: DivCleaningDamping
USE MOD_Equation               ,ONLY: CalcSource
USE MOD_DG                     ,ONLY: DGTimeDerivative_weakForm
#ifdef PP_POIS
USE MOD_Equation               ,ONLY: DivCleaningDamping_Pois,EvalGradient
USE MOD_DG                     ,ONLY: DGTimeDerivative_weakForm_Pois
USE MOD_Equation_Vars          ,ONLY: Phi,Phit,nTotalPhi
#endif /*PP_POIS*/
#ifdef PARTICLES
USE MOD_Particle_Tracking_vars ,ONLY: tTracking,tLocalization,DoRefMapping,MeasureTrackTime,TriaTracking
USE MOD_PICDepo                ,ONLY: Deposition
USE MOD_PICInterpolation       ,ONLY: InterpolateFieldToParticle
USE MOD_Particle_Vars          ,ONLY: PartState, Pt, Pt_temp, LastPartPos, DelayTime, PEM, PDM, &
                                      doParticleMerge,PartPressureCell,DoFieldIonization
USE MOD_PICModels              ,ONLY: FieldIonization
USE MOD_part_RHS               ,ONLY: CalcPartRHS
USE MOD_Particle_Tracking      ,ONLY: ParticleTracing,ParticleRefTracking,ParticleTriaTracking
USE MOD_part_emission          ,ONLY: ParticleInserting
USE MOD_DSMC                   ,ONLY: DSMC_main
USE MOD_DSMC_Vars              ,ONLY: useDSMC, DSMC_RHS
USE MOD_part_MPFtools          ,ONLY: StartParticleMerge
USE MOD_Particle_Analyze_Vars  ,ONLY: DoVerifyCharge
USE MOD_PIC_Analyze            ,ONLY: VerifyDepositedCharge
USE MOD_Part_Tools             ,ONLY: UpdateNextFreePosition,isPushParticle
USE MOD_Particle_Mesh          ,ONLY: CountPartsPerElem
USE MOD_TimeDisc_Vars          ,ONLY: iter
#if USE_MPI
USE MOD_Particle_MPI_Vars      ,ONLY: DoExternalParts
USE MOD_Particle_MPI           ,ONLY: IRecvNbOfParticles, MPIParticleSend,MPIParticleRecv,SendNbOfparticles
USE MOD_Particle_MPI_Vars      ,ONLY: PartMPIExchange
USE MOD_Particle_MPI_Vars      ,ONLY: ExtPartState,ExtPartSpecies,ExtPartMPF,ExtPartToFIBGM
#endif /*USE_MPI*/
#endif /*PARTICLES*/
#if USE_LOADBALANCE
USE MOD_LoadBalance_Timers     ,ONLY: LBStartTime,LBSplitTime,LBPauseTime
#endif /*USE_LOADBALANCE*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                          :: Ut_temp(   1:PP_nVar,0:PP_N,0:PP_N,0:PP_N,1:PP_nElems) ! temporal variable for Ut
REAL                          :: U2t_temp(  1:PMLnVar,0:PP_N,0:PP_N,0:PP_N,1:nPMLElems) ! temporal variable for U2t
#if USE_QDS_DG
REAL                          :: UQDSt_temp(1:QDSnVar,0:PP_N,0:PP_N,0:PP_N,1:nQDSElems) ! temporal variable for UQDSt
#endif /*USE_QDS_DG*/
REAL                          :: tStage,b_dt(1:nRKStages)
#ifdef PARTICLES
REAL                          :: timeStart,timeEnd
INTEGER                       :: iPart
#endif /*PARTICLES*/
#ifdef PP_POIS
REAL                          :: Phit_temp(1:4,0:PP_N,0:PP_N,0:PP_N,1:PP_nElems)
#endif /*PP_POIS*/
#if USE_LOADBALANCE
REAL                          :: tLBStart ! load balance
#endif /*USE_LOADBALANCE*/
!===================================================================================================================================

! RK coefficients
DO iStage=1,nRKStages
  b_dt(iStage)=RK_b(iStage)*dt
END DO
iStage=1

#ifdef PARTICLES
CALL CountPartsPerElem(ResetNumberOfParticles=.TRUE.) !for scaling of tParts of LB. Also done for state output of PartsPerElem

IF ((time.GE.DelayTime).OR.(iter.EQ.0)) THEN
  ! communicate shape function particles
#if USE_MPI
  PartMPIExchange%nMPIParticles=0
  IF(DoExternalParts)THEN
    ! as we do not have the shape function here, we have to deallocate something
    SDEALLOCATE(ExtPartState)
    SDEALLOCATE(ExtPartSpecies)
    SDEALLOCATE(ExtPartToFIBGM)
    SDEALLOCATE(ExtPartMPF)
    ! open receive buffer for number of particles
    CALL IRecvNbofParticles()
    ! send number of particles
    CALL SendNbOfParticles()
  END IF
#endif /*USE_MPI*/
END IF

#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
IF (time.GE.DelayTime) THEN
  ! forces on particle
  ! can be used to hide sending of number of particles
  CALL InterpolateFieldToParticle(DoInnerParts=.TRUE.)
  IF(DoFieldIonization) CALL FieldIonization()
  CALL CalcPartRHS()
END IF
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_INTERPOLATION,tLBStart)
#endif /*USE_LOADBALANCE*/

IF ((time.GE.DelayTime).OR.(iter.EQ.0)) THEN
  ! communicate shape function particles
#if USE_MPI
  PartMPIExchange%nMPIParticles=0
  IF(DoExternalParts)THEN
    ! finish communication of number of particles and send particles
    CALL MPIParticleSend()
  END IF
#endif /*USE_MPI*/
  ! because of emission and UpdateParticlePosition
  CALL Deposition(DoInnerParts=.TRUE.)
#if USE_MPI
  IF(DoExternalParts)THEN
    ! finish communication
    CALL MPIParticleRecv()
  END IF
  ! here: finish deposition with delta kernel
  !       maps source terms in physical space
  ! ALWAYS require
  PartMPIExchange%nMPIParticles=0
#endif /*USE_MPI*/
  CALL Deposition(DoInnerParts=.FALSE.)
  IF(DoVerifyCharge) CALL VerifyDepositedCharge()
END IF

#endif /*PARTICLES*/

! field solver
! time measurement in weakForm
CALL DGTimeDerivative_weakForm(time,time,0,doSource=.TRUE.)
#if USE_LOADBALANCE
CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
IF(DoPML) THEN
  CALL CalcPMLSource()
  CALL PMLTimeDerivative()
END IF
#if USE_QDS_DG
IF(DoQDS) THEN
  CALL QDSReCalculateDGValues()
  CALL QDSTimeDerivative(time,time,0,doSource=.TRUE.,doPrintInfo=.TRUE.)
END IF
#endif /*USE_QDS_DG*/
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_PML,tLBStart)
#endif /*USE_LOADBALANCE*/
CALL DivCleaningDamping()

#ifdef PP_POIS
! Potential
CALL DGTimeDerivative_weakForm_Pois(time,time,0)
CALL DivCleaningDamping_Pois()
#endif /*PP_POIS*/

! first RK step
#if USE_LOADBALANCE
CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/

! EM field
Ut_temp = Ut
U = U + Ut*b_dt(1)

#ifdef PP_POIS
Phit_temp = Phit
Phi = Phi + Phit*b_dt(1)
CALL EvalGradient()
#endif /*PP_POIS*/

#if USE_LOADBALANCE
CALL LBSplitTime(LB_DG,tLBStart)
#endif /*USE_LOADBALANCE*/
!PML auxiliary variables
IF(DoPML) THEN
  U2t_temp = U2t
  U2 = U2 + U2t*b_dt(1)
END IF
#if USE_QDS_DG
IF(DoQDS) THEN
  UQDSt_temp = UQDSt
  UQDS = UQDS + UQDSt*b_dt(1)
END IF
#endif /*USE_QDS_DG*/
#if USE_LOADBALANCE
CALL LBSplitTime(LB_PML,tLBStart)
#endif /*USE_LOADBALANCE*/


#ifdef PARTICLES
LastPartPos(1:3,1:PDM%ParticleVecLength)=PartState(1:3,1:PDM%ParticleVecLength)
PEM%lastElement(1:PDM%ParticleVecLength)=PEM%Element(1:PDM%ParticleVecLength)
IF (time.GE.DelayTime) THEN
  DO iPart=1,PDM%ParticleVecLength
    IF (PDM%ParticleInside(iPart)) THEN
      Pt_temp(1:3,iPart) = PartState(4:6,iPart)
      PartState(1:3,iPart) = PartState(1:3,iPart) + PartState(4:6,iPart) * b_dt(1)
      ! Don't push the velocity component of neutral particles!
      IF(isPushParticle(iPart))THEN
        Pt_temp(4:6,iPart) = Pt(1:3,iPart)
        PartState(4:6,iPart) = PartState(4:6,iPart) + Pt(1:3,iPart)*b_dt(1)
      END IF
    END IF ! PDM%ParticleInside(iPart)
  END DO ! iPart=1,PDM%ParticleVecLength
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/
END IF

IF ((time.GE.DelayTime).OR.(iter.EQ.0)) THEN
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
#if USE_MPI
  CALL IRecvNbofParticles()
#endif /*USE_MPI*/
#if USE_LOADBALANCE
  CALL LBSplitTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/

  IF(MeasureTrackTime) CALL CPU_TIME(TimeStart)
  IF(DoRefMapping)THEN
    CALL ParticleRefTracking()
  ELSE
    IF (TriaTracking) THEN
      CALL ParticleTriaTracking()
    ELSE
      CALL ParticleTracing()
    END IF
  END IF
  IF(MeasureTrackTime) THEN
    CALL CPU_TIME(TimeEnd)
    tTracking=tTracking+TimeEnd-TimeStart
  END IF
#if USE_LOADBALANCE
  CALL LBSplitTime(LB_TRACK,tLBStart)
#endif /*USE_LOADBALANCE*/
#if USE_MPI
  CALL SendNbOfParticles()
#endif /*USE_MPI*/
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
END IF
#endif /*PARTICLES*/

DO iStage=2,nRKStages
  tStage=time+dt*RK_c(iStage)
#ifdef PARTICLES
  ! deposition
  IF (time.GE.DelayTime) THEN
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
#if USE_MPI
    CALL InterpolateFieldToParticle(DoInnerParts=.TRUE.)
#endif /*USE_MPI*/
#if USE_LOADBALANCE
    CALL LBSplitTime(LB_INTERPOLATION,tLBStart)
#endif /*USE_LOADBALANCE*/
#if USE_MPI
    CALL MPIParticleSend()
#endif /*USE_MPI*/
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/

    !    ! deposition
    CALL Deposition(DoInnerParts=.TRUE.)
#if USE_MPI
    CALL MPIParticleRecv()
#endif /*USE_MPI*/
#if USE_LOADBALANCE
    CALL LBSplitTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
    CALL InterpolateFieldToParticle(DoInnerParts=.FALSE.)
    CALL CalcPartRHS()
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_INTERPOLATION,tLBStart)
#endif /*USE_LOADBALANCE*/

    CALL Deposition(DoInnerParts=.FALSE.)
    IF(DoVerifyCharge) CALL VerifyDepositedCharge()
#if USE_MPI
    ! null here, careful
    PartMPIExchange%nMPIParticles=0
#endif /*USE_MPI*/
    !    IF (usevMPF) THEN
    !      CALL !DepositionMPF()
    !    ELSE
    !      CALL Deposition()
    !    END IF
  END IF
  CALL CountPartsPerElem(ResetNumberOfParticles=.FALSE.) !for scaling of tParts of LB !why not rigth after "tStage=time+dt*RK_c(iStage)"?!
#endif /*PARTICLES*/

  ! field solver
  CALL DGTimeDerivative_weakForm(time,tStage,0,doSource=.TRUE.)
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  IF(DoPML) THEN
    CALL CalcPMLSource()
    CALL PMLTimeDerivative()
  END IF
#if USE_QDS_DG
  IF(DoQDS) THEN
    !CALL QDSReCalculateDGValues()
    CALL QDSTimeDerivative(time,time,0,doSource=.TRUE.)
  END IF
#endif /*USE_QDS_DG*/
#if USE_LOADBALANCE
  CALL LBSplitTime(LB_PML,tLBStart)
#endif /*USE_LOADBALANCE*/
  CALL DivCleaningDamping()
#ifdef PP_POIS
  CALL DGTimeDerivative_weakForm_Pois(time,tStage,0)
  CALL DivCleaningDamping_Pois()
#endif



  ! performe RK steps
  ! field step
  Ut_temp = Ut - Ut_temp*RK_a(iStage)
  U = U + Ut_temp*b_dt(iStage)
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_DG,tLBStart)
#endif /*USE_LOADBALANCE*/

#ifdef PP_POIS
  Phit_temp = Phit - Phit_temp*RK_a(iStage)
  Phi = Phi + Phit_temp*b_dt(iStage)
  CALL EvalGradient()
#endif

  !PML auxiliary variables
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  IF(DoPML)THEN
    U2t_temp = U2t - U2t_temp*RK_a(iStage)
    U2 = U2 + U2t_temp*b_dt(iStage)
  END IF
#if USE_QDS_DG
  IF(DoQDS)THEN
    UQDSt_temp = UQDSt - UQDSt_temp*RK_a(iStage)
    UQDS = UQDS + UQDSt_temp*b_dt(iStage)
  END IF
#endif /*USE_QDS_DG*/
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_PML,tLBStart)
#endif /*USE_LOADBALANCE*/

#ifdef PARTICLES
  ! particle step
  IF (time.GE.DelayTime) THEN
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    LastPartPos(1:3,1:PDM%ParticleVecLength)=PartState(1:3,1:PDM%ParticleVecLength)
    PEM%lastElement(1:PDM%ParticleVecLength)=PEM%Element(1:PDM%ParticleVecLength)
    DO iPart=1,PDM%ParticleVecLength
      IF (PDM%ParticleInside(iPart)) THEN
        Pt_temp(1:3,iPart) = PartState(4:6,iPart) - RK_a(iStage) * Pt_temp(1:3,iPart)
        PartState(1:3,iPart) = PartState(1:3,iPart) + Pt_temp(1:3,iPart)*b_dt(iStage)
        ! Don't push the velocity component of neutral particles!
        IF(isPushParticle(iPart))THEN
          Pt_temp(4:6,iPart) =        Pt(1:3,iPart) - RK_a(iStage) * Pt_temp(4:6,iPart)
          PartState(4:6,iPart) = PartState(4:6,iPart) + Pt_temp(4:6,iPart)*b_dt(iStage)
        END IF
      END IF ! PDM%ParticleInside(iPart)
    END DO ! iPart=1,PDM%ParticleVecLength
#if USE_LOADBALANCE
    CALL LBSplitTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/
#if USE_MPI
    CALL IRecvNbofParticles()
#endif /*USE_MPI*/
#if USE_LOADBALANCE
    CALL LBSplitTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
    IF(MeasureTrackTime) CALL CPU_TIME(TimeStart)
    IF(DoRefMapping)THEN
      CALL ParticleRefTracking()
    ELSE
      IF (TriaTracking) THEN
        CALL ParticleTriaTracking()
      ELSE
        CALL ParticleTracing()
      END IF
    END IF
    IF(MeasureTrackTime) THEN
      CALL CPU_TIME(TimeEnd)
      tTracking=tTracking+TimeEnd-TimeStart
    END IF
#if USE_LOADBALANCE
    CALL LBSplitTime(LB_TRACK,tLBStart)
#endif /*USE_LOADBALANCE*/
#if USE_MPI
    CALL SendNbOfParticles()
#endif /*USE_MPI*/
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
  END IF
#endif /*PARTICLES*/

END DO
#if USE_QDS_DG
IF(DoQDS) THEN
  CALL QDSCalculateMacroValues()
END IF
#endif /*USE_QDS_DG*/

#ifdef PARTICLES
IF (time.GE.DelayTime) THEN
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  IF(MeasureTrackTime) CALL CPU_TIME(TimeStart)
  CALL ParticleInserting()
  IF(MeasureTrackTime) THEN
    CALL CPU_TIME(TimeEnd)
    tLocalization=tLocalization+TimeEnd-TimeStart
  END IF
#if USE_LOADBALANCE
  CALL LBSplitTime(LB_EMISSION,tLBStart)
#endif /*USE_LOADBALANCE*/
#if USE_MPI
  CALL MPIParticleSend()
  CALL MPIParticleRecv()
  PartMPIExchange%nMPIParticles=0
#endif /*USE_MPI*/
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
END IF

IF (doParticleMerge) THEN
  IF (.NOT.(useDSMC.OR.PartPressureCell)) THEN
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    ALLOCATE(PEM%pStart(1:PP_nElems)           , &
             PEM%pNumber(1:PP_nElems)          , &
             PEM%pNext(1:PDM%maxParticleNumber), &
             PEM%pEnd(1:PP_nElems) )
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_SPLITMERGE,tLBStart)
#endif /*USE_LOADBALANCE*/
  END IF
END IF

IF ((time.GE.DelayTime).OR.(time.EQ.0)) CALL UpdateNextFreePosition()

IF (doParticleMerge) THEN
  CALL StartParticleMerge()
  IF (.NOT.(useDSMC.OR.PartPressureCell)) THEN
    DEALLOCATE(PEM%pStart , &
               PEM%pNumber, &
               PEM%pNext  , &
               PEM%pEnd   )
  END IF
  CALL UpdateNextFreePosition()
END IF

IF (useDSMC) THEN
  IF (time.GE.DelayTime) THEN

    CALL DSMC_main()
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    PartState(4:6,1:PDM%ParticleVecLength) = PartState(4:6,1:PDM%ParticleVecLength) + DSMC_RHS(1:3,1:PDM%ParticleVecLength)
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_DSMC,tLBStart)
#endif /*USE_LOADBALANCE*/
  END IF
END IF
#endif /*PARTICLES*/

END SUBROUTINE TimeStepByLSERK
#endif

#if (PP_TimeDiscMethod==3)
SUBROUTINE TimeStepByTAYLOR()
!===================================================================================================================================
! TAYLOR DG
! time order = N+1
! This procedure takes the current time (time), the time step dt and the solution at
! the current time U(time) and returns the solution at the next time level.
!===================================================================================================================================
! MODULES
USE MOD_DG_Vars,ONLY:U,Ut,nTotalU
USE MOD_PreProc
USE MOD_TimeDisc_Vars,ONLY:dt,time
USE MOD_DG,ONLY:DGTimeDerivative_weakForm
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL             :: U_temp(1:PP_nVar,0:PP_N,0:PP_N,0:PP_N,1:PP_nElems) ! temporal variable for Ut
REAL             :: Factor
INTEGER          :: tIndex,i
!===================================================================================================================================
Factor = dt
#ifdef OPTIMIZED
DO i=1,nTotalU
  U_temp(i,0,0,0,1) = U(i,0,0,0,1)
END DO
#else
U_temp=U
#endif OPTIMIZED

DO tIndex=0,PP_N
  CALL DGTimeDerivative_weakForm(time,time,tIndex,doSource=.TRUE.)
#ifdef OPTIMIZED
DO i=1,nTotalU
  U(i,0,0,0,1) = Ut(i,0,0,0,1)
  U_temp(i,0,0,0,1) = U_temp(i,0,0,0,1) + Factor*Ut(i,0,0,0,1)
END DO
#else
 U=Ut
 U_temp = U_temp + Factor*Ut
#endif
 Factor = Factor*dt/REAL(tIndex+2)
END DO ! tIndex

#ifdef OPTIMIZED
DO i=1,nTotalU
  U(i,0,0,0,1) = U_temp(i,0,0,0,1)
END DO
#else
U=U_temp
#endif
END SUBROUTINE TimeStepByTAYLOR
#endif

#if (PP_TimeDiscMethod==4)
SUBROUTINE TimeStep_DSMC()
!===================================================================================================================================
! Hesthaven book, page 64
! Low-Storage Runge-Kutta integration of degree 4 with 5 stages.
! This procedure takes the current time t, the time step dt and the solution at
! the current time U(t) and returns the solution at the next time level.
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_TimeDisc_Vars            ,ONLY: dt, IterDisplayStep, iter, TEnd, Time
#ifdef PARTICLES
USE MOD_Globals                  ,ONLY: abort
USE MOD_Particle_Vars            ,ONLY: PartState, LastPartPos, PDM, PEM, DoSurfaceFlux, WriteMacroVolumeValues
USE MOD_Particle_Vars            ,ONLY: WriteMacroSurfaceValues, Symmetry2D, Symmetry2DAxisymmetric, VarTimeStep
USE MOD_DSMC_Vars                ,ONLY: DSMC_RHS, DSMC, CollisMode
USE MOD_DSMC                     ,ONLY: DSMC_main
USE MOD_part_tools               ,ONLY: UpdateNextFreePosition
USE MOD_part_emission            ,ONLY: ParticleInserting
USE MOD_surface_flux             ,ONLY: ParticleSurfaceflux
USE MOD_Particle_Tracking_vars   ,ONLY: tTracking,DoRefMapping,MeasureTrackTime,TriaTracking
USE MOD_Particle_Tracking        ,ONLY: ParticleTracing,ParticleRefTracking,ParticleTriaTracking
USE MOD_SurfaceModel             ,ONLY: UpdateSurfModelVars, SurfaceModel_main
USE MOD_Particle_Boundary_Porous ,ONLY: PorousBoundaryRemovalProb_Pressure
USE MOD_Particle_Boundary_Vars   ,ONLY: nPorousBC
#if USE_MPI
USE MOD_Particle_MPI             ,ONLY: IRecvNbOfParticles, MPIParticleSend,MPIParticleRecv,SendNbOfparticles
#endif /*USE_MPI*/
#if USE_LOADBALANCE
USE MOD_LoadBalance_Timers       ,ONLY: LBStartTime,LBSplitTime,LBPauseTime
#endif /*USE_LOADBALANCE*/
#endif /*PARTICLES*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                       :: timeEnd, timeStart, dtVar, RandVal, NewYPart, NewYVelo
INTEGER                    :: iPart
#if USE_LOADBALANCE
REAL                       :: tLBStart
#endif /*USE_LOADBALANCE*/
!===================================================================================================================================
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/

  IF (DoSurfaceFlux) THEN
    ! treat surface with respective model
    CALL SurfaceModel_main()
    CALL UpdateSurfModelVars()
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_SURF,tLBStart)
#endif /*USE_LOADBALANCE*/

    CALL ParticleSurfaceflux()
  END IF

#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  DO iPart=1,PDM%ParticleVecLength
    IF (PDM%ParticleInside(iPart)) THEN
    ! Variable time step: getting the right time step for the particle (can be constant across an element)
    IF (VarTimeStep%UseVariableTimeStep) THEN
      dtVar = dt * VarTimeStep%ParticleTimeStep(iPart)
    ELSE
      dtVar = dt
    END IF
    IF (PDM%dtFracPush(iPart)) THEN
      ! Surface flux (dtFracPush): previously inserted particles are pushed a random distance between 0 and v*dt
      !                            LastPartPos and LastElem already set!
      CALL RANDOM_NUMBER(RandVal)
      dtVar = dtVar * RandVal
      PDM%dtFracPush(iPart) = .FALSE.
    ELSE
      LastPartPos(1:3,iPart)=PartState(1:3,iPart)
      PEM%lastElement(iPart)=PEM%Element(iPart)
    END IF
    PartState(1:3,iPart) = PartState(1:3,iPart) + PartState(4:6,iPart) * dtVar
    ! Axisymmetric treatment of particles: rotation of the position and velocity vector
    IF(Symmetry2DAxisymmetric) THEN
      IF (PartState(2,iPart).LT.0.0) THEN
        NewYPart = -SQRT(PartState(2,iPart)**2 + (PartState(3,iPart))**2)
      ELSE
        NewYPart = SQRT(PartState(2,iPart)**2 + (PartState(3,iPart))**2)
      END IF
      ! Rotation: Vy' =   Vy * cos(alpha) + Vz * sin(alpha) =   Vy * y/y' + Vz * z/y'
      !           Vz' = - Vy * sin(alpha) + Vz * cos(alpha) = - Vy * z/y' + Vz * y/y'
      ! Right-hand system, using new y and z positions after tracking, position vector and velocity vector DO NOT have to
      ! coincide (as opposed to Bird 1994, p. 391, where new positions are calculated with the velocity vector)
      NewYVelo = (PartState(5,iPart)*(PartState(2,iPart))+PartState(6,iPart)*PartState(3,iPart))/NewYPart
      PartState(6,iPart) = (-PartState(5,iPart)*PartState(3,iPart)+PartState(6,iPart)*(PartState(2,iPart)))/NewYPart
      PartState(2,iPart) = NewYPart
      PartState(3,iPart) = 0.0
      PartState(5,iPart) = NewYVelo
      END IF
    END IF
  END DO
#if USE_LOADBALANCE
  CALL LBSplitTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/

  ! Resetting the particle positions in the third dimension for the 2D/axisymmetric case
  IF(Symmetry2D) THEN
    LastPartPos(3,1:PDM%ParticleVecLength) = 0.0
    PartState(3,1:PDM%ParticleVecLength) = 0.0
  END IF

#if USE_MPI
  ! open receive buffer for number of particles
  CALL IRecvNbOfParticles()
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
#endif /*USE_MPI*/
  IF(MeasureTrackTime) CALL CPU_TIME(TimeStart)
  ! actual tracking
  IF(DoRefMapping)THEN
    CALL ParticleRefTracking()
  ELSE
    IF (TriaTracking) THEN
      CALL ParticleTriaTracking()
    ELSE
      CALL ParticleTracing()
    END IF
  END IF
  IF (nPorousBC.GT.0) THEN
    CALL PorousBoundaryRemovalProb_Pressure()
  END IF
  IF(MeasureTrackTime) THEN
    CALL CPU_TIME(TimeEnd)
    tTracking=tTracking+TimeEnd-TimeStart
  END IF
#if USE_MPI
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  ! send number of particles
  CALL SendNbOfParticles()
  ! finish communication of number of particles and send particles
  CALL MPIParticleSend()
  ! finish communication
  CALL MPIParticleRecv()
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
#endif /*USE_MPI*/

  ! absorptions could have happened
  CALL UpdateSurfModelVars()

#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  CALL ParticleInserting()
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_EMISSION,tLBStart)
#endif /*USE_LOADBALANCE*/

  IF (CollisMode.NE.0) THEN
    CALL UpdateNextFreePosition()
  ELSE IF ( (MOD(iter,IterDisplayStep).EQ.0) .OR. &
            (Time.ge.(1-DSMC%TimeFracSamp)*TEnd) .OR. &
            WriteMacroVolumeValues.OR.WriteMacroSurfaceValues ) THEN
    CALL UpdateNextFreePosition() !postpone UNFP for CollisMode=0 to next IterDisplayStep or when needed for DSMC-Sampling
  ELSE IF (PDM%nextFreePosition(PDM%CurrentNextFreePosition+1).GT.PDM%maxParticleNumber .OR. &
           PDM%nextFreePosition(PDM%CurrentNextFreePosition+1).EQ.0) THEN
    CALL abort(&
    __STAMP__&
    ,'maximum nbr of particles reached!')  !gaps in PartState are not filled until next UNFP and array might overflow more easily!
  END IF

  CALL DSMC_main()

#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  PartState(4:6,1:PDM%ParticleVecLength) = PartState(4:6,1:PDM%ParticleVecLength) + DSMC_RHS(1:3,1:PDM%ParticleVecLength)
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_DSMC,tLBStart)
#endif /*USE_LOADBALANCE*/

END SUBROUTINE TimeStep_DSMC
#endif


#if (PP_TimeDiscMethod==42)
SUBROUTINE TimeStep_DSMC_Debug()
!===================================================================================================================================
! Hesthaven book, page 64
! Low-Storage Runge-Kutta integration of degree 4 with 5 stages.
! This procedure takes the current time t, the time step dt and the solution at
! the current time U(t) and returns the solution at the next time level.
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_TimeDisc_Vars          ,ONLY: dt
USE MOD_Filter                 ,ONLY: Filter
#ifdef PARTICLES
USE MOD_Particle_Vars          ,ONLY: DoSurfaceFlux
USE MOD_Particle_Vars          ,ONLY: PartState, LastPartPos, PDM,PEM
USE MOD_DSMC_Vars              ,ONLY: DSMC_RHS, DSMC
USE MOD_DSMC                   ,ONLY: DSMC_main
USE MOD_part_tools             ,ONLY: UpdateNextFreePosition
USE MOD_part_emission          ,ONLY: ParticleInserting
USE MOD_part_pos_and_velo      ,ONLY: SetParticleVelocity
USE MOD_surface_flux           ,ONLY: ParticleSurfaceflux
USE MOD_Particle_Tracking_vars ,ONLY: tTracking,DoRefMapping,MeasureTrackTime,TriaTracking
USE MOD_Particle_Tracking      ,ONLY: ParticleTracing,ParticleRefTracking,ParticleTriaTracking
USE MOD_SurfaceModel           ,ONLY: UpdateSurfModelVars, SurfaceModel_main
#if USE_MPI
USE MOD_Particle_MPI           ,ONLY: IRecvNbOfParticles, MPIParticleSend,MPIParticleRecv,SendNbOfparticles
#endif /*USE_MPI*/
#endif
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER               :: iPart
REAL                  :: timeStart, timeEnd, RandVal, dtFrac
!===================================================================================================================================

IF (DSMC%ReservoirSimu) THEN ! fix grid should be defined for reservoir simu
  ! treat surface with respective model
  CALL SurfaceModel_main()
  CALL UpdateSurfModelVars()

  CALL UpdateNextFreePosition()

  CALL DSMC_main()

  PartState(4:6,1:PDM%ParticleVecLength) = PartState(4:6,1:PDM%ParticleVecLength) + DSMC_RHS(1:3,1:PDM%ParticleVecLength)
  IF(DSMC%CompareLandauTeller) THEN
    DO iPart=1,PDM%ParticleVecLength
      PDM%nextFreePosition(iPart)=iPart
    END DO
    CALL SetParticleVelocity(1,0,PDM%ParticleVecLength,1)
  END IF
ELSE
  IF (DoSurfaceFlux) THEN
    ! treat surface with respective model
    CALL SurfaceModel_main()

    CALL ParticleSurfaceflux()
    DO iPart=1,PDM%ParticleVecLength
      IF (PDM%ParticleInside(iPart)) THEN
        IF (.NOT.PDM%dtFracPush(iPart)) THEN
          LastPartPos(1:3,iPart)=PartState(1:3,iPart)
          PEM%lastElement(iPart)=PEM%Element(iPart)
          PartState(1:3,iPart) = PartState(1:3,iPart) + PartState(4:6,iPart) * dt
        ELSE !dtFracPush (SurfFlux): LastPartPos and LastElem already set!
          CALL RANDOM_NUMBER(RandVal)
          dtFrac = dt * RandVal
          PartState(1:3,iPart) = PartState(1:3,iPart) + PartState(4:6,iPart) * dtFrac
          PDM%dtFracPush(iPart) = .FALSE.
        END IF
      END IF
    END DO
  ELSE
    LastPartPos(1:3,1:PDM%ParticleVecLength)=PartState(1:3,1:PDM%ParticleVecLength)
    ! bugfix if more than 2.x mio (2000001) particle per process
    ! tested with 64bit Ubuntu 12.04 backports
    DO iPart = 1, PDM%ParticleVecLength
      PEM%lastElement(iPart)=PEM%Element(iPart)
    END DO
    !PEM%lastElement(1:PDM%ParticleVecLength)=PEM%Element(1:PDM%ParticleVecLength)
    PartState(1:3,1:PDM%ParticleVecLength) = PartState(1:3,1:PDM%ParticleVecLength) + PartState(4:6,1:PDM%ParticleVecLength) * dt
  END IF
#if USE_MPI
  ! open receive buffer for number of particles
  CALL IRecvNbOfParticles()
#endif /*USE_MPI*/
  IF(MeasureTrackTime) CALL CPU_TIME(TimeStart)
  ! actual tracking
  IF(DoRefMapping)THEN
    CALL ParticleRefTracking()
  ELSE
    IF (TriaTracking) THEN
      CALL ParticleTriaTracking()
    ELSE
      CALL ParticleTracing()
    END IF
  END IF
  IF(MeasureTrackTime) THEN
    CALL CPU_TIME(TimeEnd)
    tTracking=tTracking+TimeEnd-TimeStart
  END IF
#if USE_MPI
  ! send number of particles
  CALL SendNbOfParticles()
  ! finish communication of number of particles and send particles
  CALL MPIParticleSend()
  ! finish communication
  CALL MPIParticleRecv()
#endif /*USE_MPI*/
  CALL UpdateSurfModelVars()
  CALL ParticleInserting()
  CALL UpdateNextFreePosition()
  CALL DSMC_main()
  PartState(4:6,1:PDM%ParticleVecLength) = PartState(4:6,1:PDM%ParticleVecLength) + DSMC_RHS(1:3,1:PDM%ParticleVecLength)
END IF

END SUBROUTINE TimeStep_DSMC_Debug
#endif

#if (PP_TimeDiscMethod==43)
SUBROUTINE TimeStep_DSMC_MacroBody()
!===================================================================================================================================
!> Timedisc solving DSMC with macroscopic bodies in domain
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_TimeDisc_Vars            ,ONLY: dt, IterDisplayStep, iter, TEnd, Time
#ifdef PARTICLES
USE MOD_Globals                  ,ONLY: abort
USE MOD_Particle_Vars            ,ONLY: PartState, LastPartPos, PDM, PEM, DoSurfaceFlux, WriteMacroVolumeValues
USE MOD_Particle_Vars            ,ONLY: WriteMacroSurfaceValues, Symmetry2D, Symmetry2DAxisymmetric, VarTimeStep
USE MOD_MacroBody                ,ONLY: MacroBody_main
USE MOD_MacroBody_tools          ,ONLY: MarkMacroBodyElems
USE MOD_DSMC_Vars                ,ONLY: DSMC_RHS, DSMC, CollisMode
USE MOD_DSMC                     ,ONLY: DSMC_main
USE MOD_part_tools               ,ONLY: UpdateNextFreePosition
USE MOD_part_emission            ,ONLY: ParticleInserting
USE MOD_surface_flux             ,ONLY: ParticleSurfaceflux
USE MOD_Particle_Tracking_vars   ,ONLY: tTracking,DoRefMapping,MeasureTrackTime,TriaTracking
USE MOD_Particle_Tracking        ,ONLY: ParticleTracing,ParticleRefTracking,ParticleTriaTracking
USE MOD_SurfaceModel             ,ONLY: UpdateSurfModelVars, SurfaceModel_main
USE MOD_Particle_Boundary_Porous ,ONLY: PorousBoundaryRemovalProb_Pressure
USE MOD_Particle_Boundary_Vars   ,ONLY: nPorousBC
#if USE_MPI
USE MOD_Particle_MPI             ,ONLY: IRecvNbOfParticles, MPIParticleSend,MPIParticleRecv,SendNbOfparticles
#endif /*USE_MPI*/
#if USE_LOADBALANCE
USE MOD_LoadBalance_Timers       ,ONLY: LBStartTime,LBSplitTime,LBPauseTime
#endif /*USE_LOADBALANCE*/
#endif /*PARTICLES*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                       :: timeEnd, timeStart, dtVar, RandVal, NewYPart, NewYVelo
INTEGER                    :: iPart
#if USE_LOADBALANCE
REAL                       :: tLBStart
#endif /*USE_LOADBALANCE*/
!===================================================================================================================================
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/

  IF (DoSurfaceFlux) THEN
    ! treat surface with respective model
    CALL SurfaceModel_main()
    CALL UpdateSurfModelVars()
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_SURF,tLBStart)
#endif /*USE_LOADBALANCE*/

    CALL ParticleSurfaceflux()
  END IF

#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  DO iPart=1,PDM%ParticleVecLength
    IF (PDM%ParticleInside(iPart)) THEN
    ! Variable time step: getting the right time step for the particle (can be constant across an element)
    IF (VarTimeStep%UseVariableTimeStep) THEN
      dtVar = dt * VarTimeStep%ParticleTimeStep(iPart)
    ELSE
      dtVar = dt
    END IF
    IF (PDM%dtFracPush(iPart)) THEN
      ! Surface flux (dtFracPush): previously inserted particles are pushed a random distance between 0 and v*dt
      !                            LastPartPos and LastElem already set!
      CALL RANDOM_NUMBER(RandVal)
      dtVar = dtVar * RandVal
      PDM%dtFracPush(iPart) = .FALSE.
    ELSE
      LastPartPos(1,iPart)=PartState(1,iPart)
      LastPartPos(2,iPart)=PartState(2,iPart)
      LastPartPos(3,iPart)=PartState(3,iPart)
      PEM%lastElement(iPart)=PEM%Element(iPart)
    END IF
    PartState(1,iPart) = PartState(1,iPart) + PartState(4,iPart) * dtVar
    PartState(2,iPart) = PartState(2,iPart) + PartState(5,iPart) * dtVar
    PartState(3,iPart) = PartState(3,iPart) + PartState(6,iPart) * dtVar
    ! Axisymmetric treatment of particles: rotation of the position and velocity vector
    IF(Symmetry2DAxisymmetric) THEN
      IF (PartState(2,iPart).LT.0.0) THEN
        NewYPart = -SQRT(PartState(2,iPart)**2 + (PartState(3,iPart))**2)
      ELSE
        NewYPart = SQRT(PartState(2,iPart)**2 + (PartState(3,iPart))**2)
      END IF
      ! Rotation: Vy' =   Vy * cos(alpha) + Vz * sin(alpha) =   Vy * y/y' + Vz * z/y'
      !           Vz' = - Vy * sin(alpha) + Vz * cos(alpha) = - Vy * z/y' + Vz * y/y'
      ! Right-hand system, using new y and z positions after tracking, position vector and velocity vector DO NOT have to
      ! coincide (as opposed to Bird 1994, p. 391, where new positions are calculated with the velocity vector)
      NewYVelo = (PartState(5,iPart)*(PartState(2,iPart))+PartState(6,iPart)*PartState(3,iPart))/NewYPart
      PartState(6,iPart) = (-PartState(5,iPart)*PartState(3,iPart)+PartState(6,iPart)*(PartState(2,iPart)))/NewYPart
      PartState(2,iPart) = NewYPart
      PartState(3,iPart) = 0.0
      PartState(5,iPart) = NewYVelo
      END IF
    END IF
  END DO
#if USE_LOADBALANCE
  CALL LBSplitTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/

  ! Resetting the particle positions in the third dimension for the 2D/axisymmetric case
  IF(Symmetry2D) THEN
    LastPartPos(3,1:PDM%ParticleVecLength) = 0.0
    PartState(3,1:PDM%ParticleVecLength) = 0.0
  END IF

#if USE_MPI
  ! open receive buffer for number of particles
  CALL IRecvNbOfParticles()
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
#endif /*USE_MPI*/
  IF(MeasureTrackTime) CALL CPU_TIME(TimeStart)
  ! actual tracking
  IF(DoRefMapping)THEN
    CALL ParticleRefTracking()
  ELSE
    IF (TriaTracking) THEN
      CALL ParticleTriaTracking()
    ELSE
      CALL ParticleTracing()
    END IF
  END IF
  IF (nPorousBC.GT.0) THEN
    CALL PorousBoundaryRemovalProb_Pressure()
  END IF
  IF(MeasureTrackTime) THEN
    CALL CPU_TIME(TimeEnd)
    tTracking=tTracking+TimeEnd-TimeStart
  END IF
#if USE_MPI
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  ! send number of particles
  CALL SendNbOfParticles()
  ! finish communication of number of particles and send particles
  CALL MPIParticleSend()
  ! finish communication
  CALL MPIParticleRecv()
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
#endif /*USE_MPI*/

  ! absorptions could have happened
  CALL UpdateSurfModelVars()

#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  CALL ParticleInserting()
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_EMISSION,tLBStart)
#endif /*USE_LOADBALANCE*/

  IF (CollisMode.NE.0) THEN
    CALL UpdateNextFreePosition()
  ELSE IF ( (MOD(iter,IterDisplayStep).EQ.0) .OR. &
            (Time.ge.(1-DSMC%TimeFracSamp)*TEnd) .OR. &
            WriteMacroVolumeValues.OR.WriteMacroSurfaceValues ) THEN
    CALL UpdateNextFreePosition() !postpone UNFP for CollisMode=0 to next IterDisplayStep or when needed for DSMC-Sampling
  ELSE IF (PDM%nextFreePosition(PDM%CurrentNextFreePosition+1).GT.PDM%maxParticleNumber .OR. &
           PDM%nextFreePosition(PDM%CurrentNextFreePosition+1).EQ.0) THEN
    CALL abort(&
    __STAMP__&
    ,'maximum nbr of particles reached!')  !gaps in PartState are not filled until next UNFP and array might overflow more easily!
  END IF

  CALL MacroBody_main()
  CALL MarkMacroBodyElems()

  CALL DSMC_main()

#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  PartState(4:6,1:PDM%ParticleVecLength) = PartState(4:6,1:PDM%ParticleVecLength) + DSMC_RHS(1:3,1:PDM%ParticleVecLength)
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_DSMC,tLBStart)
#endif /*USE_LOADBALANCE*/

END SUBROUTINE TimeStep_DSMC_MacroBody
#endif

#if (PP_TimeDiscMethod==100)
SUBROUTINE TimeStepByEulerImplicit()
!===================================================================================================================================
! Euler Implicit method:
! U^n+1 = U^n + dt*R(U^n+1)
! (I -dt*R)*U^n+1 = U^n
! Solve Linear System
!===================================================================================================================================
! MODULES
USE MOD_DG_Vars,          ONLY:U,Ut
USE MOD_DG,               ONLY:DGTimeDerivative_weakForm
USE MOD_TimeDisc_Vars,    ONLY:dt,time
USE MOD_LinearSolver,     ONLY : LinearSolver
USE MOD_LinearOperator,   ONLY:EvalResidual
#ifdef PARTICLES
USE MOD_PICDepo,          ONLY : Deposition!, DepositionMPF
USE MOD_PICInterpolation, ONLY : InterpolateFieldToParticle
USE MOD_PIC_Vars,         ONLY : PIC
USE MOD_Particle_Vars,    ONLY : PartState, Pt, LastPartPos, DelayTime, PEM, PDM!, usevMPF
USE MOD_part_RHS,         ONLY : CalcPartRHS
USE MOD_part_emission,    ONLY : ParticleInserting
USE MOD_DSMC,             ONLY : DSMC_main
USE MOD_DSMC_Vars,        ONLY : useDSMC, DSMC_RHS, DSMC
USE MOD_PIC_Analyze,      ONLY: VerifyDepositedCharge
USE MOD_part_tools,       ONLY : UpdateNextFreePosition
#endif
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL               :: tstage,coeff,Norm_R0
!===================================================================================================================================

! one Euler implicit step
! time for source is time + dt
tstage = time + dt
coeff  = dt*1.

#ifdef maxwell
IF(PrecondType.GT.0)THEN
  IF (iter==0) CALL BuildPrecond(time,time,0,1.,dt)
END IF
#endif /*maxwell*/

IF (time.GE.DelayTime) CALL ParticleInserting()

IF ((time.GE.DelayTime).OR.(time.EQ.0)) THEN
!  IF (usevMPF) THEN
!    CALL DepositionMPF()
!  ELSE
    CALL Deposition()
!  END IF
  !CALL VerifyDepositedCharge()
END IF

IF (time.GE.DelayTime) THEN
  CALL InterpolateFieldToParticle()
  CALL CalcPartRHS()
END IF
! particles
LastPartPos(1:3,1:PDM%ParticleVecLength)=PartState(1:3,1:PDM%ParticleVecLength)
PEM%lastElement(1:PDM%ParticleVecLength)=PEM%Element(1:PDM%ParticleVecLength)
IF (time.GE.DelayTime) THEN ! Euler-Explicit only for Particles
  PartState(1:3,1:PDM%ParticleVecLength) = PartState(1:3,1:PDM%ParticleVecLength) + dt * PartState(4:6,1:PDM%ParticleVecLength)
  PartState(4:6,1:PDM%ParticleVecLength) = PartState(4:6,1:PDM%ParticleVecLength) + dt * Pt(1:3,1:PDM%ParticleVecLength)
END IF


#if USE_MPI
  ! open receive buffer for number of particles
  CALL IRecvNbofParticles()
#endif /*USE_MPI*/
  IF(MeasureTrackTime) CALL CPU_TIME(TimeStart)
  ! actual tracking
  IF(DoRefMapping)THEN
    CALL ParticleRefTracking()
  ELSE
    CALL ParticleTracing()
  END IF
  IF(MeasureTrackTime) THEN
    CALL CPU_TIME(TimeEnd)
    tTracking=tTracking+TimeEnd-TimeStart
  END IF
#if USE_MPI
  ! send number of particles
  CALL SendNbOfParticles()
  ! finish communication of number of particles and send particles
  CALL MPIParticleSend()
  ! finish communication
  CALL MPIParticleRecv()
#endif /*USE_MPI*/


! EM field
! U predict
!U = U
! b
LinSolverRHS = U
ImplicitSource=0.
CALL EvalResidual(time,Coeff,Norm_R0)
CALL LinearSolver(tstage,coeff,Norm_R0=Norm_R0)
CALL DivCleaningDamping()
CALL UpdateNextFreePosition()
IF (useDSMC) THEN
  CALL DSMC_main()
  PartState(4:6,1:PDM%ParticleVecLength) = PartState(4:6,1:PDM%ParticleVecLength) + DSMC_RHS(1:3,1:PDM%ParticleVecLength)
END IF

END SUBROUTINE TimeStepByEulerImplicit
#endif /*PP_TimeDiscMethod==100*/


#if IMPA
SUBROUTINE TimeStepByImplicitRK()
!===================================================================================================================================
! IMEX time integrator
! ESDIRK for particles
! ERK for field
! from: Kennedy & Carpenter 2003
! Additive Runge-Kutta schemes for convection-diffusion-reaction equations
! This procedure takes the current time t, the time step dt and the solution at
! the current time U(t) and returns the solution at the next time level.
! test timedisc for implicit particle treatment || highly relativistic
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_TimeDisc_Vars          ,ONLY: dt,iter,iStage, nRKStages,dt_old, time
USE MOD_TimeDisc_Vars          ,ONLY: ERK_a,ESDIRK_a,RK_b,RK_c
USE MOD_LinearSolver_Vars      ,ONLY: ImplicitSource, DoPrintConvInfo,FieldStage
USE MOD_DG_Vars                ,ONLY: U,Un
#if USE_HDG
USE MOD_HDG                    ,ONLY: HDG
#else /*pure DG*/
USE MOD_DG_Vars                ,ONLY: Ut
USE MOD_DG                     ,ONLY: DGTimeDerivative_weakForm
USE MOD_Predictor              ,ONLY: Predictor,StorePredictor
USE MOD_LinearSolver_Vars      ,ONLY: LinSolverRHS
USE MOD_Equation               ,ONLY: DivCleaningDamping
USE MOD_Equation               ,ONLY: CalcSource
#ifdef maxwell
USE MOD_Precond                ,ONLY: BuildPrecond
USE MOD_Precond_Vars           ,ONLY: UpdatePrecond
#endif /*maxwell*/
#endif /*USE_HDG*/
USE MOD_Newton                 ,ONLY: ImplicitNorm,FullNewton
#ifdef PARTICLES
USE MOD_TimeDisc_Vars          ,ONLY: RK_fillSF
USE MOD_Equation_Vars          ,ONLY: c2_inv
USE MOD_Particle_Mesh          ,ONLY: CountPartsPerElem
USE MOD_PICDepo_Vars           ,ONLY: PartSource,DoDeposition
USE MOD_LinearSolver_Vars      ,ONLY: ExplicitPartSource
USE MOD_Timedisc_Vars          ,ONLY: RKdtFrac,RKdtFracTotal
USE MOD_LinearSolver_Vars      ,ONLY: DoUpdateInStage,PartXk
USE MOD_Predictor              ,ONLY: PartPredictor,PredictorType
USE MOD_Particle_Vars          ,ONLY: PartIsImplicit,PartLorentzType,doParticleMerge,PartPressureCell,PartDtFrac &
                                      ,DoForceFreeSurfaceFlux,PartStateN,PartStage,PartQ,DoSurfaceFlux,PEM,PDM  &
                                      , Pt,LastPartPos,DelayTime,PartState,PartMeshHasReflectiveBCs,PartDeltaX
USE MOD_Particle_Analyze_Vars  ,ONLY: DoVerifyCharge
USE MOD_PIC_Analyze            ,ONLY: VerifyDepositedCharge
USE MOD_PICDepo                ,ONLY: Deposition
USE MOD_PICInterpolation       ,ONLY: InterpolateFieldToParticle
USE MOD_part_RHS               ,ONLY: CalcPartRHS,PartVeloToImp
USE MOD_part_emission          ,ONLY: ParticleInserting
USE MOD_surface_flux           ,ONLY: ParticleSurfaceflux
USE MOD_DSMC                   ,ONLY: DSMC_main
USE MOD_DSMC_Vars              ,ONLY: useDSMC, DSMC_RHS
USE MOD_Particle_Tracking      ,ONLY: ParticleTracing,ParticleRefTracking,ParticleTriaTracking
USE MOD_Particle_Tracking_vars ,ONLY: DoRefMapping,TriaTracking
USE MOD_ParticleSolver         ,ONLY: ParticleNewton, SelectImplicitParticles
USE MOD_Part_RHS               ,ONLY: PartRHS
USE MOD_PICInterpolation       ,ONLY: InterpolateFieldToSingleParticle
USE MOD_PICInterpolation_Vars  ,ONLY: FieldAtParticle
USE MOD_part_MPFtools          ,ONLY: StartParticleMerge
#if USE_MPI
USE MOD_Particle_MPI           ,ONLY: IRecvNbOfParticles, MPIParticleSend,MPIParticleRecv,SendNbOfparticles
USE MOD_Particle_MPI_Vars      ,ONLY: PartMPIExchange
USE MOD_Particle_MPI_Vars      ,ONLY: DoExternalParts,PartMPI
USE MOD_Particle_MPI_Vars      ,ONLY: ExtPartState,ExtPartSpecies,ExtPartMPF,ExtPartToFIBGM
#endif /*USE_MPI*/
USE MOD_PIC_Analyze            ,ONLY: CalcDepositedCharge
USE MOD_part_tools             ,ONLY: UpdateNextFreePosition
#ifdef CODE_ANALYZE
USE MOD_Particle_Mesh_Vars     ,ONLY: Geo
USE MOD_Particle_Tracking      ,ONLY: ParticleSanityCheck
#endif /*CODE_ANALYZE*/
#endif /*PARTICLES*/
#if USE_LOADBALANCE
USE MOD_LoadBalance_Timers     ,ONLY: LBStartTime,LBSplitTime,LBPauseTime
#ifdef maxwell
USE MOD_Precond_Vars           ,ONLY: UpdatePrecondLB
#endif /*maxwell*/
#endif /*USE_LOADBALANCE*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL               :: tstage
! implicit
REAL               :: alpha
REAL               :: sgamma
! particle surface flux
! RK counter
INTEGER            :: iCounter
#ifdef PARTICLES
INTEGER            :: iElem,i,j,k
REAL               :: dtloc,RandVal
INTEGER            :: iPart,nParts
REAL               :: LorentzFacInv
!LOGICAL            :: NoInterpolation ! fields cannot be interpolated, because particle is "outside", hence, fields and
!                                      ! forces of previous stage are used
REAL               :: n_loc(1:3)
LOGICAL            :: reMap
#ifdef CODE_ANALYZE
REAL               :: IntersectionPoint(1:3)
INTEGER            :: ElemID
LOGICAL            :: ishit
#endif /*CODE_ANALYZE*/
#endif /*PARTICLES*/
#if USE_LOADBALANCE
REAL               :: tLBStart ! load balance
#endif /*USE_LOADBALANCE*/
#ifdef maxwell
LOGICAL            :: UpdatePrecondLoc
#endif /*maxwell*/
!===================================================================================================================================

#if !(USE_HDG)
#ifdef maxwell
! caution hard coded
IF (iter==0)THEN
  CALL BuildPrecond(time,time,0,RK_b(nRKStages),dt)
  dt_old=dt
ELSE
  UpdatePrecondLoc=.FALSE.
#if USE_LOADBALANCE
  IF(UpdatePrecondLB) UpdatePrecondLoc=.TRUE.
  UpdatePrecondLb=.FALSE.
#endif /*USE_LOADBALANCE*/
  IF(UpdatePrecond)THEN
    IF(dt.NE.dt_old) UpdatePrecondLoc=.TRUE.
    dt_old=dt
  END IF
  IF(UpdatePrecondLoc) CALL BuildPrecond(time,time,0,RK_b(nRKStages),dt)
END IF
#endif /*maxwell*/
#endif /*DG*/

#ifdef PARTICLES
#if USE_LOADBALANCE
CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
! particle locating
! at the wrong position? depending on how we do it...
IF (time.GE.DelayTime) THEN
  CALL ParticleInserting() ! do not forget to communicate the emitted particles ... for shape function
END IF
#if USE_LOADBALANCE
CALL LBSplitTime(LB_EMISSION,tLBStart)
#endif /*USE_LOADBALANCE*/
! select, if particles are treated implicitly or explicitly
CALL SelectImplicitParticles()
#if USE_LOADBALANCE
CALL LBPauseTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/
#endif /*PARTICLES*/

! ----------------------------------------------------------------------------------------------------------------------------------
! stage 1 - initialization
! ----------------------------------------------------------------------------------------------------------------------------------

tStage=time
#ifdef PARTICLES
IF((time.GE.DelayTime).OR.(iter.EQ.0))THEN
! communicate shape function particles
#if USE_MPI
  PartMPIExchange%nMPIParticles=0
  IF(DoExternalParts)THEN
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    ! as we do not have the shape function here, we have to deallocate something
    SDEALLOCATE(ExtPartState)
    SDEALLOCATE(ExtPartSpecies)
    SDEALLOCATE(ExtPartToFIBGM)
    SDEALLOCATE(ExtPartMPF)
    ! open receive buffer for number of particles
    CALL IRecvNbofParticles()
    ! send number of particles
    CALL SendNbOfParticles()
    ! finish communication of number of particles and send particles
    CALL MPIParticleSend()
    ! finish communication
    CALL MPIParticleRecv()
    ! set exchanged number of particles to zero
    PartMPIExchange%nMPIParticles=0
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
  END IF
#endif /*USE_MPI*/
END IF

! simulation with delay-time, compute the
IF(DelayTime.GT.0.)THEN
  IF((iter.EQ.0).AND.(time.LT.DelayTime))THEN
    ! perform normal deposition
    CALL Deposition(DoInnerParts=.TRUE.)
#if USE_MPI
    ! here: finish deposition with delta kernal
    !       maps source terms in physical space
    ! ALWAYS require
    PartMPIExchange%nMPIParticles=0
#endif /*USE_MPI*/
    CALL Deposition(DoInnerParts=.FALSE.)
  END IF
END IF

! compute source of first stage for Maxwell solver
IF (time.GE.DelayTime) THEN
  ! if we call it correctly, we may save here work between different RK-stages
  ! because of emmision and UpdateParticlePosition
  CALL Deposition(DoInnerParts=.TRUE.)
#if USE_MPI
  ! here: finish deposition with delta kernal
  !       maps source terms in physical space
  ! ALWAYS require
  PartMPIExchange%nMPIParticles=0
#endif /*USE_MPI*/
  CALL Deposition(DoInnerParts=.FALSE.)
END IF

ImplicitSource=0.
#ifdef PARTICLES
ExplicitPartSource=0.
#endif /*PARTICLES*/
#if !(USE_HDG)
#if USE_LOADBALANCE
CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
CALL CalcSource(tStage,1.,ImplicitSource)
#if USE_LOADBALANCE
CALL LBPauseTime(LB_DG,tLBStart)
#endif /*USE_LOADBALANCE*/
#else
! set required for fluid model and HDG, because field may have changed due to different particle distribution
! HDG time measured in HDG
CALL HDG(time,U,iter)
#endif
IF(DoVerifyCharge) CALL VerifyDepositedCharge()


IF(time.GE.DelayTime)THEN
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  ! velocity to impulse
  CALL PartVeloToImp(VeloToImp=.TRUE.)
  PartStateN(1:6,1:PDM%ParticleVecLength)=PartState(1:6,1:PDM%ParticleVecLength)
  PEM%ElementN(1:PDM%ParticleVecLength)  =PEM%Element(1:PDM%ParticleVecLength)
  IF(PartMeshHasReflectiveBCs) PEM%NormVec(1:3,1:PDM%ParticleVecLength) =0.
  PEM%PeriodicMoved(1:PDM%ParticleVecLength) = .FALSE.
  IF(iter.EQ.0)THEN ! caution with emission: fields should also be interpolated to new particles, this is missing
                    ! or should be done directly during emission...
    ! should be already be done
    DO iPart=1,PDM%ParticleVecLength
      IF(.NOT.PDM%ParticleInside(iPart))CYCLE
      IF(PartIsImplicit(iPart))THEN
        CALL InterpolateFieldToSingleParticle(iPart,FieldAtParticle(1:6,iPart))
        CALL PartRHS(iPart,FieldAtParticle(1:6,iPart),Pt(1:3,iPart))
      END IF ! ParticleIsImplicit
      PDM%IsNewPart(iPart)=.FALSE.
      !PEM%ElementN(iPart) = PEM%Element(iPart)
    END DO ! iPart
  END IF
  RKdtFracTotal=0.
  RKdtFrac     =0.
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/

  ! surface flux
  IF(DoSurfaceFlux)THEN
    RKdtFrac      = 1.0 ! RK_c(iStage)
    RKdtFracTotal = 1.0 ! RK_c(iStage)
    RK_fillSF     = 1.0
    IF(DoPrintConvInfo) nParts=0
    ! Measurement as well in ParticleSurfaceFlux
    CALL ParticleSurfaceflux()
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    ! compute emission for all particles during dt
    DO iPart=1,PDM%ParticleVecLength
      IF(PDM%ParticleInside(iPart))THEN
        IF(PDM%IsNewPart(iPart))THEN
          IF(DoPrintConvInfo) nParts=nParts+1
          ! nullify
          PartStage(1:6,:,iPart)=0.
          ! f(u^n) for position
          ! CAUTION: position in reference space has to be computed during emission for implicit particles
          ! interpolate field at surface position
          CALL InterpolateFieldToSingleParticle(iPart,FieldAtParticle(1:6,iPart))
          ! RHS at interface
          CALL PartRHS(iPart,FieldAtParticle(1:6,iPart),Pt(1:3,iPart))
          ! f(u^n) for velocity
          IF(.NOT.DoForceFreeSurfaceFlux) PartStage(4:6,1,iPart)=Pt(1:3,iPart)
          ! position NOT known but we backup the state
          PartStateN(1:3,iPart) = PartState(1:3,iPart)
          ! initial velocity equals velocity of surface flux
          PartStateN(4:6,iPart) = PartState(4:6,iPart)
          ! gives entry point into domain
          PEM%ElementN(iPart)      = PEM%Element(iPart)
          IF(PartMeshHasReflectiveBCs) PEM%NormVec(1:3,iPart)   = 0.
          PEM%PeriodicMoved(iPart) = .FALSE.
          CALL RANDOM_NUMBER(RandVal)
          PartDtFrac(iPart)=RandVal
          PartIsImplicit(iPart)=.TRUE.
          ! particle crosses surface at time^n + (1.-RandVal)*dt
          ! for all stages   t_Stage =< time^n + (1.-RandVal)*dt particle is outside of domain
          ! for              t_Stage >  time^n + (1.-RandVal)*dt particle is in domain and can be advanced in time
        ELSE
          ! set DtFrac to unity
          PartDtFrac(iPart)=1.0
        END IF ! IsNewPart
      ELSE
        PartIsImplicit(iPart)=.FALSE.
      END IF ! ParticleInside
    END DO ! iPart
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_SURFFLUX,tLBStart)
#endif /*USE_LOADBALANCE*/
    IF(DoPrintConvInfo)THEN
#if USE_MPI
      IF(PartMPI%MPIRoot)THEN
        CALL MPI_REDUCE(MPI_IN_PLACE,nParts,1,MPI_INTEGER,MPI_SUM,0,PartMPI%COMM, IERROR)
      ELSE
        CALL MPI_REDUCE(nParts       ,iPart,1,MPI_INTEGER,MPI_SUM,0,PartMPI%COMM, IERROR)
      END IF
#endif /*USE_MPI*/
      SWRITE(UNIT_StdOut,'(A,I10)') ' SurfaceFlux-Particles: ',nParts
    END IF
  END IF
END IF ! time.GE. DelayTime
#endif /*PARTICLES*/

#if !(USE_HDG)
! LoadBalance Time-Measurement is in DGTimeDerivative_weakForm
IF(iter.EQ.0) CALL DGTimeDerivative_weakForm(time, time, 0,doSource=.FALSE.)
iStage=0
#if USE_LOADBALANCE
CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
CALL StorePredictor()
! copy U to U^0
Un = U
#if USE_LOADBALANCE
CALL LBPauseTime(LB_DG,tLBStart)
#endif /*USE_LOADBALANCE*/
#endif /*DG*/

! ----------------------------------------------------------------------------------------------------------------------------------
! stage 2 to 6
! ----------------------------------------------------------------------------------------------------------------------------------
DO iStage=2,nRKStages
  ! time of current stage
  tStage = time + RK_c(iStage)*dt
  alpha  = ESDIRK_a(iStage,iStage)*dt
  sGamma = 1.0/alpha
  IF(DoPrintConvInfo)THEN
    SWRITE(UNIT_StdOut,'(A)')    '-----------------------------'
    SWRITE(UNIT_StdOut,'(A,I2)') 'istage:',istage
  END IF
#if !(USE_HDG)
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  ! store predictor
  CALL StorePredictor()

  ! compute the f(u^s-1)
  ! compute the f(u^s-1)
  ! DG-solver, Maxwell's equations
  FieldStage (:,:,:,:,:,iStage-1) = Ut + ImplicitSource
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_DG,tLBStart)
#endif /*USE_LOADBALANCE*/
#endif /*DG*/

  ! and particles
#ifdef PARTICLES
  IF (time.GE.DelayTime) THEN
    IF(DoPrintConvInfo)THEN
      SWRITE(UNIT_StdOut,'(A)') '-----------------------------'
      SWRITE(UNIT_StdOut,'(A)') ' compute last stage value.   '
    END IF
    IF(iStage.EQ.2)THEN
      CALL CountPartsPerElem(ResetNumberOfParticles=.TRUE.)
    ELSE
      CALL CountPartsPerElem(ResetNumberOfParticles=.FALSE.)
    END IF
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    ! normal
    DO iPart=1,PDM%ParticleVecLength
      IF(.NOT.PDM%ParticleInside(iPart))THEN
        PartIsImplicit(iPart)=.FALSE.
        PDM%IsNewPart(iPart) =.FALSE.
        CYCLE
      END IF
      !IF(PDM%IsNewPart(iPart)) CYCLE ! ignore surface flux particles
      IF(PartIsImplicit(iPart))THEN
        ! caution, implicit is already back-roated for the computation of Pt and Velocity/Momentum
        reMap=.FALSE.
        IF(PartMeshHasReflectiveBCs)THEN
          IF(SUM(ABS(PEM%NormVec(1:3,iPart))).GT.0.)THEN
            PEM%NormVec(1:3,iPart)=0.
            reMap=.TRUE.
          END IF
        END IF
        IF(PEM%PeriodicMoved(iPart))THEN
          PEM%PeriodicMoved(iPart)=.FALSE.
          Remap=.TRUE.
        END IF
        IF(reMap)THEN
          ! recompute the particle position AFTER movement
          ! can be theroretically outside of the mesh, because it is the not-shifted particle position,velocity
          PartState(1:6,iPart)=PartXK(1:6,iPart)+PartDeltaX(1:6,iPart)
        END IF
        IF(PartLorentzType.NE.5)THEN
          PartStage(1:3,iStage-1,iPart) = PartState(4:6,iPart)
          PartStage(4:6,iStage-1,iPart) = Pt(1:3,iPart)
        ELSE
          LorentzFacInv=1.0+DOT_PRODUCT(PartState(4:6,iPart),PartState(4:6,iPart))*c2_inv
          LorentzFacInv=1.0/SQRT(LorentzFacInv)
          PartStage(1  ,iStage-1,iPart) = PartState(4,iPart) * LorentzFacInv
          PartStage(2  ,iStage-1,iPart) = PartState(5,iPart) * LorentzFacInv
          PartStage(3  ,iStage-1,iPart) = PartState(6,iPart) * LorentzFacInv
          PartStage(4:6,iStage-1,iPart) = Pt(1:3,iPart)
        END IF
      ELSE ! PartIsExplicit
        CALL InterpolateFieldToSingleParticle(iPart,FieldAtParticle(1:6,iPart))
        reMap=.FALSE.
        IF(PartMeshHasReflectiveBCs)THEN
          IF(SUM(ABS(PEM%NormVec(1:3,iPart))).GT.0.)THEN
            n_loc=PEM%NormVec(1:3,iPart)
            ! particle is actually located outside, hence, it moves in the mirror field
            ! mirror electric field, constant B field
            FieldAtParticle(1:3,iPart)=FieldAtParticle(1:3,iPart)-2.*DOT_PRODUCT(FieldAtParticle(1:3,iPart),n_loc)*n_loc
            FieldAtParticle(4:6,iPart)=FieldAtParticle(4:6,iPart)!-2.*DOT_PRODUCT(FieldAtParticle(4:6,iPart),n_loc)*n_loc
            PEM%NormVec(1:3,iPart)=0.
            ! and of coarse, the velocity has to be back-rotated, because the particle has not hit the wall
            reMap=.TRUE.
          END IF
        END IF
        IF(PEM%PeriodicMoved(iPart))THEN
          PEM%PeriodicMoved(iPart)=.FALSE.
          Remap=.TRUE.
        END IF
        IF(reMap)THEN
          ! recompute explicit push, requires only the velocity/momentum
          PartState(4:6,iPart) = ERK_a(iStage-1,iStage-2)*PartStage(4:6,iStage-2,iPart)
          DO iCounter=1,iStage-2
            PartState(4:6,iPart)=PartState(4:6,iPart)+ERK_a(iStage-1,iCounter)*PartStage(4:6,iCounter,iPart)
          END DO ! iCounter=1,iStage-2
          PartState(4:6,iPart)=PartStateN(4:6,iPart)+dt*PartState(4:6,iPart)
          ! luckily - nothing to do
        END IF
        IF(PartLorentzType.EQ.5)THEN
          LorentzFacInv=1.0/SQRT(1.0+DOT_PRODUCT(PartState(4:6,iPart),PartState(4:6,iPart))*c2_inv)
          CALL PartRHS(iPart,FieldAtParticle(1:6,iPart),Pt(1:3,iPart),LorentzFacInv)
        ELSE
          LorentzFacInv = 1.0
          CALL PartRHS(iPart,FieldAtParticle(1:6,iPart),Pt(1:3,iPart))
        END IF ! PartLorentzType.EQ.5
        PartStage(1  ,iStage-1,iPart) = PartState(4,iPart)*LorentzFacInv
        PartStage(2  ,iStage-1,iPart) = PartState(5,iPart)*LorentzFacInv
        PartStage(3  ,iStage-1,iPart) = PartState(6,iPart)*LorentzFacInv
        PartStage(4:6,iStage-1,iPart) = Pt(1:3,iPart)
      END IF ! ParticleIsImplicit
    END DO ! iPart
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/
    ! new method
  END IF
#endif /*PARTICLES*/

  !--------------------------------------------------------------------------------------------------------------------------------
  ! explicit - particle  pusher
  !--------------------------------------------------------------------------------------------------------------------------------

#ifdef PARTICLES
  IF(DoPrintConvInfo)THEN
    SWRITE(UNIT_StdOut,'(A)') '-----------------------------'
    SWRITE(UNIT_StdOut,'(A)') ' explicit particles'
  END IF
  ExplicitPartSource=0.
  ! particle step || only explicit particles
  IF (time.GE.DelayTime) THEN
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    DO iPart=1,PDM%ParticleVecLength
      IF(.NOT.PDM%ParticleInside(iPart))CYCLE
      IF(.NOT.PartIsImplicit(iPart))THEN !explicit particles only
        ! particle movement from PartSateN
        LastPartPos(1,iPart)  =PartStateN(1,iPart)
        LastPartPos(2,iPart)  =PartStateN(2,iPart)
        LastPartPos(3,iPart)  =PartStateN(3,iPart)
        PEM%lastElement(iPart)=PEM%ElementN(iPart)
        ! delete rotation || periodic movement
        IF(PartMeshHasReflectiveBCs) PEM%NormVec(1:3,iPart) = 0.
        PEM%PeriodicMoved(iPart) =.FALSE.
        ! compute explicit push
        PartState(1:6,iPart) = ERK_a(iStage,iStage-1)*PartStage(1:6,iStage-1,iPart)
        DO iCounter=1,iStage-2
          PartState(1:6,iPart)=PartState(1:6,iPart)+ERK_a(iStage,iCounter)*PartStage(1:6,iCounter,iPart)
        END DO ! iCounter=1,iStage-2
        PartState(1:6,iPart)=PartStateN(1:6,iPart)+dt*PartState(1:6,iPart)
      END IF ! ParticleIsExplicit
    END DO ! iPart
#if USE_LOADBALANCE
    CALL LBSplitTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/

#if USE_MPI
    ! mpi-routines should be extended by additional input: PartisImplicit, better criterion, saves computational time
  ! open receive buffer for number of particles
    CALL IRecvNbofParticles()
#endif /*USE_MPI*/
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
    IF(DoRefMapping)THEN
      ! tracking routines has to be extended for optional flag, like deposition
      CALL ParticleRefTracking(doParticle_In=.NOT.PartIsImplicit(1:PDM%ParticleVecLength))
    ELSE
      IF (TriaTracking) THEN
        CALL ParticleTriaTracking(doParticle_In=.NOT.PartIsImplicit(1:PDM%ParticleVecLength))
      ELSE
        CALL ParticleTracing(doParticle_In=.NOT.PartIsImplicit(1:PDM%ParticleVecLength))
      END IF
    END IF
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
#if USE_MPI
    ! send number of particles
    CALL SendNbOfParticles(doParticle_In=.NOT.PartIsImplicit(1:PDM%ParticleVecLength))
    ! finish communication of number of particles and send particles
    CALL MPIParticleSend()
    ! finish communication
    CALL MPIParticleRecv()
    ! set exchanged number of particles to zero
    PartMPIExchange%nMPIParticles=0
#endif /*USE_MPI*/
#if USE_LOADBALANCE
    CALL LBSplitTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
    ! if new
    ! map particle from gamma*v to velocity
    CALL PartVeloToImp(VeloToImp=.FALSE.,doParticle_In=.NOT.PartIsImplicit(1:PDM%ParticleVecLength))
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/
    ! deposit explicit, local particles
    CALL Deposition(DoInnerParts=.TRUE.,doParticle_In=.NOT.PartIsImplicit(1:PDM%ParticleVecLength))
    CALL Deposition(DoInnerParts=.FALSE.,doParticle_In=.NOT.PartIsImplicit(1:PDM%ParticleVecLength)) ! external particles arg
    !PartMPIExchange%nMPIParticles=0
    IF(DoDeposition) THEN
      DO iElem=1,PP_nElems
        DO k=0,PP_N; DO j=0,PP_N; DO i=0,PP_N
          ExplicitPartSource(1:4,i,j,k,iElem)=PartSource(1:4,i,j,k,iElem)
        END DO; END DO; END DO !i,j,k
      END DO !iElem
    END IF
    ! map particle from v to gamma*v
    CALL PartVeloToImp(VeloToImp=.TRUE.,doParticle_In=.NOT.PartIsImplicit(1:PDM%ParticleVecLength))
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/
  END IF
#endif /*PARTICLES*/

  !--------------------------------------------------------------------------------------------------------------------------------
  ! implicit - particle pusher & Maxwell's field
  !--------------------------------------------------------------------------------------------------------------------------------

#if !(USE_HDG)
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  ! compute RHS for linear solver
  LinSolverRHS=ESDIRK_a(iStage,iStage-1)*FieldStage(:,:,:,:,:,iStage-1)
  DO iCounter=1,iStage-2
    LinSolverRHS=LinSolverRHS +ESDIRK_a(iStage,iCounter)*FieldStage(:,:,:,:,:,iCounter)
  END DO ! iCoutner=1,iStage-2
  LinSolverRHS=Un+dt*LinSolverRHS
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_DG,tLBStart)
#endif /*USE_LOADBALANCE*/
  ! get predictor of u^s+1 ! wrong position
  ! CALL Predictor(iStage,dt,Un,FieldStage) ! sets new value for U_DG
#endif /*DG*/

#ifdef PARTICLES
  IF(DoPrintConvInfo)THEN
    SWRITE(UNIT_StdOut,'(A)') '-----------------------------'
    SWRITE(UNIT_StdOut,'(A)') ' implicit particles '
  END IF
  IF (time.GE.DelayTime) THEN
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    DO iPart=1,PDM%ParticleVecLength
      IF(.NOT.PDM%ParticleInside(iPart))THEN
        PartIsImplicit(iPart)=.FALSE.
        PDM%IsNewPart(iPart) =.FALSE.
        CYCLE
      END IF
      IF(PartIsImplicit(iPart))THEN
        ! ignore surface flux particle
        ! dirty hack, if particle does not take part in implicit treating, it is removed from this list
        ! surface flux particles
        LastPartPos(1,iPart)=PartStateN(1,iPart)
        LastPartPos(2,iPart)=PartStateN(2,iPart)
        LastPartPos(3,iPart)=PartStateN(3,iPart)
        PEM%lastElement(iPart)=PEM%ElementN(iPart)
        IF(PartMeshHasReflectiveBCs) PEM%NormVec(1:3,iPart) =0.
        PEM%PeriodicMoved(iPart) = .FALSE.
        ! compute Q and U
        PartQ(1:6,iPart) = ESDIRK_a(iStage,iStage-1)*PartStage(1:6,iStage-1,iPart)
        DO iCounter=1,iStage-2
          PartQ(1:6,iPart) = PartQ(1:6,iPart) + ESDIRK_a(iStage,iCounter)*PartStage(1:6,iCounter,iPart)
        END DO ! iCounter=1,iStage-2
        IF(DoSurfaceFlux)THEN
          Dtloc=PartDtFrac(iPart)*dt
        ELSE
          Dtloc=dt
        END IF
        PartQ(1:6,iPart) = PartStateN(1:6,iPart) + dtloc* PartQ(1:6,iPart)
        ! do not use a predictor
        ! position is already safed
        ! caution: has to use 4:6 because particle is not tracked
        !IF(PredictorType.GT.0)THEN
        PartState(1:6,iPart)=PartQ(1:6,iPart)
        !ELSE
        !  PartState(4:6,iPart)=PartQ(4:6,iPart)
        !END IF
        ! store the information before the Newton method || required for init
        PartDeltaX(1:6,iPart) = 0. ! PartState(1:6,iPart)-PartStateN(1:6,iPart)
        PartXk(1:6,iPart)     = PartState(1:6,iPart)
      END IF ! PartIsImplicit
    END DO ! iPart
#if USE_LOADBALANCE
    ! the measurement contains information from SurfaceFlux and implicit particle pushing
    ! simplicity: added to push time
    CALL LBPauseTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/
    IF(PredictorType.GT.0)THEN
#if USE_LOADBALANCE
      CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
#if USE_MPI
      ! mpi-routines should be extended by additional input: PartisImplicit, better criterion, saves computational time
      ! open receive buffer for number of particles
      CALL IRecvNbofParticles()
#endif /*USE_MPI*/
#if USE_LOADBALANCE
      CALL LBPauseTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
      IF(DoRefMapping)THEN
        ! tracking routines has to be extended for optional flag, like deposition
        !CALL ParticleRefTracking()
        CALL ParticleRefTracking(doParticle_In=PartIsImplicit(1:PDM%ParticleVecLength))
      ELSE
        !CALL ParticleTracing()
        IF (TriaTracking) THEN
          CALL ParticleTriaTracking(doParticle_In=PartIsImplicit(1:PDM%ParticleVecLength))
        ELSE
          CALL ParticleTracing(doParticle_In=PartIsImplicit(1:PDM%ParticleVecLength))
        END IF
      END IF
#if USE_MPI
#if USE_LOADBALANCE
      CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
      ! send number of particles
      CALL SendNbOfParticles(doParticle_In=PartIsImplicit(1:PDM%ParticleVecLength))
      !CALL SendNbOfParticles() ! all particles to get initial deposition right \\ without emmission
      ! finish communication of number of particles and send particles
      CALL MPIParticleSend()
      ! finish communication
      CALL MPIParticleRecv()
      PartMPIExchange%nMPIParticles=0
      IF(DoExternalParts)THEN
        ! as we do not have the shape function here, we have to deallocate something
        SDEALLOCATE(ExtPartState)
        SDEALLOCATE(ExtPartSpecies)
        SDEALLOCATE(ExtPartToFIBGM)
        SDEALLOCATE(ExtPartMPF)
      END IF
#if USE_LOADBALANCE
      CALL LBSplitTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
#endif /*USE_MPI*/
      DO iPart=1,PDM%ParticleVecLength
        IF(PartIsImplicit(iPart))THEN
          IF(.NOT.PDM%ParticleInside(iPart)) PartIsImplicit(iPart)=.FALSE.
          IF(.NOT.PDM%ParticleInside(iPart)) PDM%IsNewPart(iPart)=.FALSE.
        END IF ! PartIsImplicit
      END DO ! iPart
#if USE_LOADBALANCE
      CALL LBPauseTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/
    END IF

  END IF
#endif /*PARTICLES*/
  ! full newton for particles and fields
  CALL FullNewton(time,tStage,alpha)
#if !(USE_HDG)
  CALL DivCleaningDamping()
#endif /*DG*/
#ifdef PARTICLES
  IF (time.GE.DelayTime) THEN
    IF(DoUpdateInStage) CALL UpdateNextFreePosition()
  END IF

#ifdef CODE_ANALYZE
  !SWRITE(*,*) 'sanity check'
  DO iPart=1,PDM%ParticleVecLength
    IF(.NOT.PDM%ParticleInside(iPart)) CYCLE
     CALL ParticleSanityCheck(iPart)
  END DO
#endif /*CODE_ANALYZE*/

#endif /*PARTICLES*/
END DO

#ifdef PARTICLES
IF (time.GE.DelayTime) THEN
  IF(DoSurfaceFlux)THEN
    DO iPart=1,PDM%ParticleVecLength
      IF(PDM%ParticleInside(iPart))THEN
        IF(PDM%IsNewPart(iPart)) THEN
          PartDtFrac(iPart)=1.
          PDM%IsNewPart(iPart)=.FALSE.
        END IF
      END IF ! ParticleInside
    END DO ! iPart
  END IF

! particle step || only explicit particles
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  ! add here new method
  DO iPart=1,PDM%ParticleVecLength
    IF(.NOT.PDM%ParticleInside(iPart))CYCLE
    IF(DoSurfaceFlux)THEN
      ! sanity check
      IF(PDM%IsNewPart(iPart)) CALL abort(&
   __STAMP__&
   ,' Particle error with surfaceflux. Part-ID: ',iPart)
    END IF
    LastPartPos(1,iPart)=PartStateN(1,iPart)
    LastPartPos(2,iPart)=PartStateN(2,iPart)
    LastPartPos(3,iPart)=PartStateN(3,iPart)
    PEM%lastElement(iPart)=PEM%ElementN(iPart)
    IF(.NOT.PartIsImplicit(iPart))THEN
      ! LastPartPos(1,iPart)=PartState(1,iPart)
      ! LastPartPos(2,iPart)=PartState(2,iPart)
      ! LastPartPos(3,iPart)=PartState(3,iPart)
      ! PEM%lastElement(iPart)=PEM%Element(iPart)
      CALL InterpolateFieldToSingleParticle(iPart,FieldAtParticle(1:6,iPart))
      reMap=.FALSE.
      IF(PartMeshHasReflectiveBCs)THEN
        IF(SUM(ABS(PEM%NormVec(1:3,iPart))).GT.0.)THEN
          n_loc=PEM%NormVec(1:3,iPart)
          ! particle is actually located outside, hence, it moves in the mirror field
          ! mirror electric field, constant B field
          FieldAtParticle(1:3,iPart)=FieldAtParticle(1:3,iPart)-2.*DOT_PRODUCT(FieldAtParticle(1:3,iPart),n_loc)*n_loc
          FieldAtParticle(4:6,iPart)=FieldAtParticle(4:6,iPart)!-2.*DOT_PRODUCT(FieldAtParticle(4:6,iPart),n_loc)*n_loc
          PEM%NormVec(1:3,iPart)=0.
          ! and of coarse, the velocity has to be back-rotated, because the particle has not hit the wall
          reMap=.TRUE.
        END IF
      END IF
      IF(PEM%PeriodicMoved(iPart))THEN
        PEM%PeriodicMoved(iPart)=.FALSE.
        Remap=.TRUE.
      END IF
      IF(reMap)THEN
        ! recompute explicit push, requires only the velocity/momentum
        iStage=nRKStages
        PartState(4:6,iPart) = ERK_a(iStage,iStage-1)*PartStage(4:6,iStage-1,iPart)
        DO iCounter=1,iStage-2
          PartState(4:6,iPart)=PartState(4:6,iPart)+ERK_a(iStage,iCounter)*PartStage(4:6,iCounter,iPart)
        END DO ! iCounter=1,iStage-2
        PartState(4:6,iPart)=PartStateN(4:6,iPart)+dt*PartState(4:6,iPart)
      END IF
      ! compute acceleration
      IF(PartLorentzType.EQ.5)THEN
        LorentzFacInv=1.0/SQRT(1.0+DOT_PRODUCT(PartState(4:6,iPart),PartState(4:6,iPart))*c2_inv)
        CALL PartRHS(iPart,FieldAtParticle(1:6,iPart),Pt(1:3,iPart),LorentzFacInv)
      ELSE
        LorentzFacInv = 1.0
        CALL PartRHS(iPart,FieldAtParticle(1:6,iPart),Pt(1:3,iPart))
      END IF ! PartLorentzType.EQ.5
      PartState(1  ,iPart) = RK_b(nRKStages)*LorentzFacInv*PartState(4,iPart)
      PartState(2  ,iPart) = RK_b(nRKStages)*LorentzFacInv*PartState(5,iPart)
      PartState(3  ,iPart) = RK_b(nRKStages)*LorentzFacInv*PartState(6,iPart)
      PartState(4:6,iPart) = RK_b(nRKSTages)*Pt(1:3,iPart)
      !  stage 1 ,nRKStages-1
      DO iCounter=1,nRKStages-1
        PartState(1:6,iPart) = PartState(1:6,iPart)   &
                             + RK_b(iCounter)*PartStage(1:6,iCounter,iPart)
      END DO ! counter
      PartState(1:6,iPart) = PartStateN(1:6,iPart)+dt*PartState(1:6,iPart)

    END IF ! ParticleIsExplicit
  END DO ! iPart
#if USE_LOADBALANCE
  CALL LBSplitTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/

iStage=0
#if USE_MPI
  ! mpi-routines should be extended by additional input: PartisImplicit, better criterion, saves computational time
  ! open receive buffer for number of particles
  CALL IRecvNbofParticles()
#endif /*USE_MPI*/
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
  IF(DoRefMapping)THEN
    ! tracking routines has to be extended for optional flag, like deposition
    !CALL ParticleRefTracking()
    CALL ParticleRefTracking() !(doParticle_In=.NOT.PartIsImplicit(1:PDM%ParticleVecLength))
  ELSE
    !CALL ParticleTracing()
    IF (TriaTracking) THEN
      CALL ParticleTriaTracking() !doParticle_In=.NOT.PartIsImplicit(1:PDM%ParticleVecLength))
    ELSE
      CALL ParticleTracing() !doParticle_In=.NOT.PartIsImplicit(1:PDM%ParticleVecLength))
    END IF
  END IF
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
#if USE_MPI
  ! send number of particles
  CALL SendNbOfParticles() !doParticle_In=.NOT.PartIsImplicit(1:PDM%ParticleVecLength))
  !CALL SendNbOfParticles() ! all particles to get initial deposition right \\ without emmission
  ! finish communication of number of particles and send particles
  CALL MPIParticleSend()
  ! finish communication
  CALL MPIParticleRecv()
! #endif ! old -> new is 9 lines below
  PartMPIExchange%nMPIParticles=0
  IF(DoExternalParts)THEN
    ! as we do not have the shape function here, we have to deallocate something
    SDEALLOCATE(ExtPartState)
    SDEALLOCATE(ExtPartSpecies)
    SDEALLOCATE(ExtPartToFIBGM)
    SDEALLOCATE(ExtPartMPF)
  END IF
#endif
#if USE_LOADBALANCE
  CALL LBSplitTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
  ! map particle from gamma*v to v
  CALL PartVeloToImp(VeloToImp=.FALSE.)
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/
END IF
#endif /*PARTICLES*/

!----------------------------------------------------------------------------------------------------------------------------------
! DSMC
!----------------------------------------------------------------------------------------------------------------------------------
#ifdef PARTICLES
IF (useDSMC) THEN ! UpdateNextFreePosition is only required for DSMC
  CALL UpdateNextFreePosition()
  CALL DSMC_main()
  PartState(4:6,1:PDM%ParticleVecLength) = PartState(4:6,1:PDM%ParticleVecLength) + DSMC_RHS(1:3,1:PDM%ParticleVecLength)
END IF

!----------------------------------------------------------------------------------------------------------------------------------
! split and merge
!----------------------------------------------------------------------------------------------------------------------------------
IF (doParticleMerge) THEN
  IF (.NOT.(useDSMC.OR.PartPressureCell)) THEN
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    ALLOCATE(PEM%pStart(1:PP_nElems)           , &
             PEM%pNumber(1:PP_nElems)          , &
             PEM%pNext(1:PDM%maxParticleNumber), &
             PEM%pEnd(1:PP_nElems) )
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_SPLITMERGE,tLBStart)
#endif /*USE_LOADBALANCE*/
  END IF
END IF

IF ((time.GE.DelayTime).OR.(iter.EQ.0)) CALL UpdateNextFreePosition()

IF (doParticleMerge) THEN
  CALL StartParticleMerge()
  IF (.NOT.(useDSMC.OR.PartPressureCell)) THEN
    DEALLOCATE(PEM%pStart , &
               PEM%pNumber, &
               PEM%pNext  , &
               PEM%pEnd   )
  END IF
  CALL UpdateNextFreePosition()
END IF
#endif /*PARTICLES*/

END SUBROUTINE TimeStepByImplicitRK
#endif /*IMPA*/


#if ROS
SUBROUTINE TimeStepByRosenbrock()
!===================================================================================================================================
! Rosenbrock-Method
! from: Kaps. 1979
! linear,implicit Runge-Kutta method
! RK-method is 1 Newton-Step
! optimized implementation following E. Hairer in "Solving Ordinary Differential Equations 2" p.111FF
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_TimeDisc_Vars          ,ONLY: dt,iter,iStage, nRKStages,dt_inv,dt_old, time
USE MOD_TimeDisc_Vars          ,ONLY: RK_a,RK_c,RK_g,RK_b,RK_gamma
USE MOD_LinearSolver_Vars      ,ONLY: FieldStage,DoPrintConvInfo
USE MOD_DG_Vars                ,ONLY: U,Un
#if USE_HDG
USE MOD_HDG                    ,ONLY: HDG
#else /*pure DG*/
USE MOD_Precond_Vars           ,ONLY: UpdatePrecond
USE MOD_LinearOperator         ,ONLY: MatrixVector
USE MOD_LinearSolver           ,ONLY: LinearSolver
USE MOD_DG_Vars                ,ONLY: Ut
USE MOD_DG                     ,ONLY: DGTimeDerivative_weakForm
USE MOD_LinearSolver_Vars      ,ONLY: LinSolverRHS
USE MOD_Equation               ,ONLY: DivCleaningDamping
USE MOD_Equation               ,ONLY: CalcSource
#ifdef maxwell
USE MOD_Precond                ,ONLY: BuildPrecond
#endif /*maxwell*/
#endif /*USE_HDG*/
#ifdef PARTICLES
USE MOD_Equation_Vars          ,ONLY: c2_inv
USE MOD_LinearOperator         ,ONLY: PartMatrixVector, PartVectorDotProduct
USE MOD_ParticleSolver         ,ONLY: Particle_GMRES
USE MOD_LinearSolver_Vars      ,ONLY: PartXK,R_PartXK,DoFieldUpdate
USE MOD_Particle_Mesh          ,ONLY: CountPartsPerElem
USE MOD_Particle_Vars          ,ONLY: PartLorentzType,doParticleMerge,PartPressureCell,PartDtFrac,PartStateN,PartStage,PartQ &
    ,DoSurfaceFlux,PEM,PDM,Pt,LastPartPos,DelayTime,PartState,PartMeshHasReflectiveBCs
USE MOD_Particle_Analyze_Vars  ,ONLY: DoVerifyCharge
USE MOD_PIC_Analyze            ,ONLY: VerifyDepositedCharge
USE MOD_PICDepo                ,ONLY: Deposition
USE MOD_PICInterpolation       ,ONLY: InterpolateFieldToParticle
USE MOD_part_RHS               ,ONLY: CalcPartRHS,PartVeloToImp
USE MOD_part_emission          ,ONLY: ParticleInserting
USE MOD_surface_flux           ,ONLY: ParticleSurfaceflux
USE MOD_DSMC                   ,ONLY: DSMC_main
USE MOD_DSMC_Vars              ,ONLY: useDSMC, DSMC_RHS
USE MOD_Particle_Tracking      ,ONLY: ParticleTracing,ParticleRefTracking,ParticleTriaTracking
USE MOD_Particle_Tracking_vars ,ONLY: DoRefMapping,TriaTracking
USE MOD_Part_RHS               ,ONLY: PartRHS
USE MOD_PICInterpolation       ,ONLY: InterpolateFieldToSingleParticle
USE MOD_PICInterpolation_Vars  ,ONLY: FieldAtParticle
USE MOD_part_MPFtools          ,ONLY: StartParticleMerge
#if USE_MPI
USE MOD_Particle_MPI           ,ONLY: IRecvNbOfParticles, MPIParticleSend,MPIParticleRecv,SendNbOfparticles
USE MOD_Particle_MPI_Vars      ,ONLY: PartMPIExchange
USE MOD_Particle_MPI_Vars      ,ONLY: DoExternalParts,PartMPI
USE MOD_Particle_MPI_Vars      ,ONLY: ExtPartState,ExtPartSpecies,ExtPartMPF,ExtPartToFIBGM
#endif /*USE_MPI*/
USE MOD_PIC_Analyze            ,ONLY: CalcDepositedCharge
USE MOD_part_tools             ,ONLY: UpdateNextFreePosition
#endif /*PARTICLES*/
#if USE_LOADBALANCE
USE MOD_LoadBalance_Timers     ,ONLY: LBStartTime,LBSplitTime,LBPauseTime
#ifdef maxwell
USE MOD_Precond_Vars           ,ONLY: UpdatePrecondLB
#endif /*maxwell*/
#endif /*USE_LOADBALANCE*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL               :: tstage
! implicit
REAL               :: coeff,coeff_inv
!INTEGER            :: i,j
REAL               :: tRatio
! particle surface flux
! RK counter
INTEGER            :: iCounter
#ifdef PARTICLES
REAL               :: coeff_loc,dt_inv_loc, LorentzFacInv
REAL               :: PartDeltaX(1:6), PartRHS_loc(1:6), Norm_P2, Pt_tmp(1:6), PartRHS_tild(1:6),FieldAtParticle_loc(1:6)
REAL               :: RandVal!, LorentzFac
REAL               :: AbortCrit
INTEGER            :: iPart,nParts
REAL               :: n_loc(1:3)
LOGICAL            :: reMap
#endif /*PARTICLES*/
#if USE_LOADBALANCE
REAL               :: tLBStart
#endif /*USE_LOADBALANCE*/
#ifdef maxwell
LOGICAL            :: UpdatePrecondLoc
#endif /*maxwell*/
!===================================================================================================================================

coeff=dt*RK_gamma
coeff_inv=1./coeff
dt_inv=1.
#if !(USE_HDG)
#ifdef maxwell
! caution hard coded
IF (iter==0)THEN
  CALL BuildPrecond(time,time,0,RK_b(nRKStages),dt)
  dt_old=dt
ELSE
  UpdatePrecondLoc=.FALSE.
#if USE_LOADBALANCE
  IF(UpdatePrecondLB) UpdatePrecondLoc=.TRUE.
  UpdatePrecondLb=.FALSE.
#endif /*USE_LOADBALANCE*/
  IF(UpdatePrecond)THEN
    IF(dt.NE.dt_old) UpdatePrecondLoc=.TRUE.
    dt_old=dt
  END IF
  IF(UpdatePrecondLoc) CALL BuildPrecond(time,time,0,RK_b(nRKStages),dt)
END IF
#endif /*maxwell*/
#endif /*DG*/
dt_inv=dt_inv/dt
tRatio = 1.

! ! ! sanity check
! ! print*,'RK_gamma',RK_gamma
! DO istage=2,nRKStages
!   DO iCounter=1,nRKStages
!     print*,'a',iStage,iCounter,RK_a(iStage,iCounter)
!   END DO
! END DO
! DO istage=2,nRKStages
!   DO iCounter=1,nRKStages
!     print*,'c',iStage,iCounter,RK_g(iStage,iCounter)
!   END DO
! END DO
! DO iCounter=1,nRKStages
!   print*,'b',iStage,iCounter,RK_b(iCounter)
! END DO
! time level of stage
! DO istage=2,nRKStages
!  print*,'aa',SUM(RK_A(iStage,:))*RK_gamma,RK_c
! END DO

#ifdef PARTICLES
#if USE_LOADBALANCE
CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
! particle locating
! at the wrong position? depending on how we do it...
IF (time.GE.DelayTime) THEN
  CALL ParticleInserting() ! do not forget to communicate the emitted particles ... for shape function
END IF
#if USE_LOADBALANCE
CALL LBPauseTime(LB_EMISSION,tLBStart)
#endif /*USE_LOADBALANCE*/
#endif /*PARTICLES*/

! ----------------------------------------------------------------------------------------------------------------------------------
! stage 1 - initialization && first linear solver
! ----------------------------------------------------------------------------------------------------------------------------------
tStage=time

#ifdef PARTICLES
! compute number of emitted particles during Rosenbrock-Step
IF(time.GE.DelayTime)THEN
  ! surface flux
  ! major difference to all other routines:
  ! Rosenbrock is one Newton-Step, hence, all particles cross the surface at time^n, however, the time-step size
  ! different for all particles, hence, some move slower, same move faster. this is not 100% correct, however,
  ! typical, RK_c(1) is zero.... and we compute the first stage..
  IF(DoSurfaceFlux)THEN
    IF(DoPrintConvInfo) nParts=0
    ! LB time measurement is performed within ParticleSurfaceflux
    CALL ParticleSurfaceflux()
    ! compute emission for all particles during dt
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    DO iPart=1,PDM%ParticleVecLength
      ! only particle within
      IF(PDM%ParticleInside(iPart))THEN
        ! copy elemnent N
        ! check if new particle
        IF(PDM%IsNewPart(iPart))THEN
          ! initialize of surface-flux particles
          IF(DoPrintConvInfo) nParts=nParts+1
          ! gives entry point into domain
          CALL RANDOM_NUMBER(RandVal)
          PartDtFrac(iPart)=RandVal
          ! particle crosses surface at time^n + (1.-RandVal)*dt
          ! for all stages   t_Stage =< time^n + (1.-RandVal)*dt particle is outside of domain
          ! for              t_Stage >  time^n + (1.-RandVal)*dt particle is in domain and can be advanced in time
          ! particle is no-longer a SF particle
          PDM%IsNewPart(iPart) = .FALSE.
        ELSE
          ! set DtFrac to unity
          PartDtFrac(iPart)=1.0
        END IF ! IsNewPart
      END IF ! ParticleInside
    END DO ! iPart
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_SURFFLUX,tLBStart)
#endif /*USE_LOADBALANCE*/
    IF(DoPrintConvInfo)THEN
#if USE_MPI
      IF(PartMPI%MPIRoot)THEN
        CALL MPI_REDUCE(MPI_IN_PLACE,nParts,1,MPI_INTEGER,MPI_SUM,0,PartMPI%COMM, IERROR)
      ELSE
        CALL MPI_REDUCE(nParts       ,iPart,1,MPI_INTEGER,MPI_SUM,0,PartMPI%COMM, IERROR)
      END IF
#endif /*USE_MPI*/
      SWRITE(UNIT_StdOut,'(A,I10)') ' SurfaceFlux-Particles: ',nParts
    END IF
  END IF
END IF

IF((time.GE.DelayTime).OR.(iter.EQ.0))THEN
! communicate shape function particles for deposition
#if USE_MPI
  PartMPIExchange%nMPIParticles=0
  IF(DoExternalParts)THEN
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    ! as we do not have the shape function here, we have to deallocate something
    SDEALLOCATE(ExtPartState)
    SDEALLOCATE(ExtPartSpecies)
    SDEALLOCATE(ExtPartToFIBGM)
    SDEALLOCATE(ExtPartMPF)
    ! open receive buffer for number of particles
    CALL IRecvNbofParticles()
    ! send number of particles
    CALL SendNbOfParticles()
    ! finish communication of number of particles and send particles
    CALL MPIParticleSend()
    ! finish communication
    CALL MPIParticleRecv()
    ! set exchanged number of particles to zero
    PartMPIExchange%nMPIParticles=0
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
  END IF
#endif /*USE_MPI*/
END IF

! simulation with delay-time, compute the
IF(DelayTime.GT.0.)THEN
  IF((iter.EQ.0).AND.(time.LT.DelayTime))THEN
    ! perform normal deposition
    CALL Deposition(DoInnerParts=.TRUE.)
#if USE_MPI
    ! here: finish deposition with delta kernal
    !       maps source terms in physical space
    ! ALWAYS require
    PartMPIExchange%nMPIParticles=0
#endif /*USE_MPI*/
    CALL Deposition(DoInnerParts=.FALSE.)
  END IF
END IF

! compute source of first stage for Maxwell solver
IF (time.GE.DelayTime) THEN
  ! if we call it correctly, we may save here work between different RK-stages
  ! because of emmision and UpdateParticlePosition
  CALL Deposition(DoInnerParts=.TRUE.)
#if USE_MPI
  ! here: finish deposition with delta kernal
  !       maps source terms in physical space
  ! ALWAYS require
  PartMPIExchange%nMPIParticles=0
#endif /*USE_MPI*/
  CALL Deposition(DoInnerParts=.FALSE.)
END IF

#if USE_HDG
! update the fields due to changed particle number: emission or velocity change in DSMC
! LB measurement is performed within HDG
IF(DoFieldUpdate) CALL HDG(time,U,iter)
#endif
IF(DoVerifyCharge) CALL VerifyDepositedCharge()

IF(time.GE.DelayTime)THEN
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  ! map velocity space to relativistic momentum
  iStage=1
  CALL PartVeloToImp(VeloToImp=.TRUE.)
  PartStateN(1:PDM%ParticleVecLength,1:6)=PartState(1:6,1:PDM%ParticleVecLength)
  PEM%ElementN(1:PDM%ParticleVecLength)  =PEM%Element(1:PDM%ParticleVecLength)
  ! should be already be done
  DO iPart=1,PDM%ParticleVecLength
    IF(.NOT.PDM%ParticleInside(iPart))CYCLE
    ! store old particle position
    LastPartPos(1,iPart)  =PartStateN(1,iPart)
    LastPartPos(2,iPart)  =PartStateN(2,iPart)
    LastPartPos(3,iPart)  =PartStateN(3,iPart)
    ! copy date
    PEM%lastElement(iPart)=PEM%ElementN(iPart)
    IF(PartMeshHasReflectiveBCs) PEM%NormVec(1:3,iPart)=0.
    PEM%PeriodicMoved(iPart) = .FALSE.
    ! build RHS of particle with current DG solution and particle position
    CALL InterpolateFieldToSingleParticle(iPart,FieldAtParticle(1:6,iPart))
    ! compute particle RHS at time^n
    IF(PartLorentzType.EQ.5)THEN
      LorentzFacInv=1.0/SQRT(1.0+DOT_PRODUCT(PartState(4:6,iPart),PartState(4:6,iPart))*c2_inv)
      CALL PartRHS(iPart,FieldAtParticle(1:6,iPart),Pt(1:3,iPart),LorentzFacInv)
    ELSE
      LorentzFacInv = 1.0
      CALL PartRHS(iPart,FieldAtParticle(1:6,iPart),Pt(1:3,iPart))
    END IF ! PartLorentzType.EQ.5
    ! compute current Pt_tmp for the particle
    Pt_tmp(1) =LorentzFacInv*PartState(4,iPart)
    Pt_tmp(2) =LorentzFacInv*PartState(5,iPart)
    Pt_tmp(3) =LorentzFacInv*PartState(6,iPart)
    Pt_tmp(4) =Pt(1,iPart)
    Pt_tmp(5) =Pt(2,iPart)
    Pt_tmp(6) =Pt(3,iPart)
    ! how it works
    ! A x = b
    ! A(x-x0) = b - A x0
    ! set x0 = b
    ! A deltaX = b - A b
    ! xNeu = b  + deltaX
    ! fix matrix during iteration
    PartXK(1:6,iPart)   = PartState(1:6,iPart) ! which is partstateN
    R_PartXK(1:6,iPart) = Pt_tmp(1:6)          ! the delta is not changed
    PartDeltaX=0.
    ! guess for new value is Pt_tmp: remap to reuse old GMRES
    ! OLD
    ! CALL PartMatrixVector(time,Coeff_inv,iPart,Pt_tmp,PartDeltaX)
    ! PartRHS_loc =Pt_tmp - PartDeltaX
    ! CALL PartVectorDotProduct(PartRHS_loc,PartRHS_loc,Norm_P2)
    ! AbortCrit=1e-16
    ! PartDeltaX=0.
    ! CALL Particle_GMRES(time,coeff_inv,iPart,PartRHS_loc,SQRT(Norm_P2),AbortCrit,PartDeltaX)
    ! NEW version is more stable, hence we use it!
    IF(DoSurfaceFlux)THEN
      coeff_loc=PartDtFrac(iPart)*coeff
    ELSE
      coeff_loc=coeff
    END IF
    Pt_tmp=coeff_loc*Pt_Tmp
    CALL PartMatrixVector(time,Coeff_loc,iPart,Pt_tmp,PartDeltaX)
    PartRHS_loc =Pt_tmp - PartDeltaX
    CALL PartVectorDotProduct(PartRHS_loc,PartRHS_loc,Norm_P2)
    AbortCrit=1e-16
    PartDeltaX=0.
    CALL Particle_GMRES(time,coeff_loc,iPart,PartRHS_loc,SQRT(Norm_P2),AbortCrit,PartDeltaX)
    ! update particle
    PartState(1:6,iPart)=Pt_tmp+PartDeltaX(1:6)
    PartStage(1,1,iPart) = PartState(1,iPart)
    PartStage(2,1,iPart) = PartState(2,iPart)
    PartStage(3,1,iPart) = PartState(3,iPart)
    PartStage(4,1,iPart) = PartState(4,iPart)
    PartStage(5,1,iPart) = PartState(5,iPart)
    PartStage(6,1,iPart) = PartState(6,iPart)
  END DO ! iPart
  ! track particle
  iStage=1
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/
END IF ! time.GE. DelayTime
IF(DoFieldUpdate)THEN
#endif /*PARTICLES*/

#if !(USE_HDG)
! LB measurement is performed within DGTimeDerivative_weakForm and LinearSolver (again DGTimeDerivative_weakForm)
! the copy time of the arrays is ignored within this measurement
Un = U
! solve linear system for electromagnetic field
! RHS is f(u^n+0) = DG_u^n + source^n
CALL DGTimeDerivative_weakForm(time, time, 0,doSource=.TRUE.) ! source terms are added NOT added in linearsolver
LinSolverRHS =Ut
CALL LinearSolver(tStage,coeff_inv)
FieldStage (:,:,:,:,:,1) = U
#endif /*DG*/
#ifdef PARTICLES
END IF ! DoFieldUpdate
#endif /*PARTICLES*/

! ----------------------------------------------------------------------------------------------------------------------------------
! stage 2 to nRKStages
! ----------------------------------------------------------------------------------------------------------------------------------
DO iStage=2,nRKStages
  ! time of current stage
  tStage = time + RK_c(iStage)*dt
  IF(DoPrintConvInfo)THEN
    SWRITE(UNIT_StdOut,'(A)')    '-----------------------------'
    SWRITE(UNIT_StdOut,'(A,I2)') 'istage:',istage
  END IF

  !--------------------------------------------------------------------------------------------------------------------------------
  ! DGSolver: explicit contribution and 1/dt_inv sum_ij RK_g FieldStage
  ! is the state before the linear system is solved
  !--------------------------------------------------------------------------------------------------------------------------------
#if !(USE_HDG)
#ifdef PARTICLES
  IF(DoFieldUpdate) THEN
#endif /*PARTICLES*/
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    ! compute contribution of h Time * sum_j=1^iStage-1
    ! In optimized version sum_j=1^&iStage-1 c_ij/dt*Y_J
    LinSolverRHS = RK_g(iStage,iStage-1)*FieldStage(:,:,:,:,:,iStage-1)
    DO iCounter=1,iStage-2
      LinSolverRHS = LinSolverRHS+RK_g(iStage,iCounter)*FieldStage(:,:,:,:,:,iCounter)
    END DO ! iCounter=1,iStage-2
    ! not required in the optimized implementation, instead
    ! !! matrix vector WITH dt and contribution of Time * sum
    ! !! Jacobian times sum_j^iStage-1 gamma_ij k_j
    ! !U=LinSolverRHS
    ! !CALL DGTimeDerivative_weakForm(time, time, 0,doSource=.FALSE.)
    ! !LinSolverRHS=Ut*dt
    ! OPTIMIZED IMPLEMENTATION
    LinSolverRHS=dt_inv*LinSolverRHS
    ! compute explicit contribution  AGAIN no dt
    U = RK_a(iStage,iStage-1)*FieldStage(:,:,:,:,:,iStage-1)
    DO iCounter=1,iStage-2
      U=U+RK_a(iStage,iCounter)*FieldStage(:,:,:,:,:,iCounter)
    END DO ! iCounter=1,iStage-2
    U=Un+U
    CALL DivCleaningDamping()
    ! this U is required for the particles and the interpolation, hence, we have to continue with the particles
    ! which gives us the source terms, too...
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_DG,tLBStart)
#endif /*USE_LOADBALANCE*/
#ifdef PARTICLES
  END IF
#endif /*PARTICLES*/
#endif /*NOT HDG->DG*/

  !--------------------------------------------------------------------------------------------------------------------------------
  ! particle  pusher: explicit contribution and Time * sum
  ! is the state before the linear system is solved
  !--------------------------------------------------------------------------------------------------------------------------------
#ifdef PARTICLES
  IF (time.GE.DelayTime) THEN
    IF(DoPrintConvInfo)THEN
      SWRITE(UNIT_StdOut,'(A)') '-----------------------------'
      SWRITE(UNIT_StdOut,'(A)') ' Implicit step.   '
    END IF
    IF(iStage.EQ.2)THEN
      CALL CountPartsPerElem(ResetNumberOfParticles=.TRUE.)
    ELSE
      CALL CountPartsPerElem(ResetNumberOfParticles=.FALSE.)
    END IF
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    ! normal
    ! move particle to PartState^n + dt*sum_j=1^(iStage-1)*aij k_j
    DO iPart=1,PDM%ParticleVecLength
      IF(.NOT.PDM%ParticleInside(iPart)) CYCLE
      ! compute contribution of 1/dt* sum_j=1^iStage-1 c(i,j) = diag(gamma)-gamma^inv
      PartQ(1:6,iPart) = RK_g(iStage,iStage-1)*PartStage(1:6,iStage-1,iPart)
      DO iCounter=1,iStage-2
        PartQ(1:6,iPart) = PartQ(1:6,iPart) +RK_g(iStage,iCounter)*PartStage(1:6,iCounter,iPart)
      END DO ! iCounter=1,iStage-2
      IF(DoSurfaceFlux)THEN
        dt_inv_loc=dt_inv/PartDtFrac(iPart)
      ELSE
        dt_inv_loc=dt_inv
      END IF
      PartQ(1:6,iPart) = dt_inv_loc*PartQ(1:6,iPart)
      ! compute explicit contribution which is
      PartState(1:6,iPart) = RK_a(iStage,iStage-1)*PartStage(1:6,iStage-1,iPart)
      DO iCounter=1,iStage-2
        PartState(1:6,iPart)=PartState(1:6,iPart)+RK_a(iStage,iCounter)*PartStage(1:6,iCounter,iPart)
      END DO ! iCounter=1,iStage-2
      PartState(1:6,iPart)=PartStateN(1:6,iPart)+PartState(1:6,iPart)
    END DO ! iPart=1,PDM%ParticleVecLength
    CALL PartVeloToImp(VeloToImp=.FALSE.)
#if USE_LOADBALANCE
    CALL LBSplitTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/
#if USE_MPI
    ! mpi-routines should be extended by additional input: PartisImplicit, better criterion, saves computational time
    ! open receive buffer for number of particles
    CALL IRecvNbofParticles()
#endif /*USE_MPI*/
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
    IF(DoRefMapping)THEN
      ! tracking routines has to be extended for optional flag, like deposition
      CALL ParticleRefTracking()
    ELSE
      IF (TriaTracking) THEN
        CALL ParticleTriaTracking()
      ELSE
        CALL ParticleTracing()
      END IF
    END IF
#if USE_MPI
    ! send number of particles
    CALL SendNbOfParticles()
    ! finish communication of number of particles and send particles
    CALL MPIParticleSend()
    ! finish communication
    CALL MPIParticleRecv()
#endif /*USE_MPI*/
#if USE_LOADBALANCE
    CALL LBSplitTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
    ! compute particle source terms on field solver of implicit particles :)
    CALL Deposition(DoInnerParts=.TRUE.)
    CALL Deposition(DoInnerParts=.FALSE.)
    ! map particle from v to gamma v
#if USE_HDG
    ! update the fields due to changed particle position and velocity/momentum
    ! LB-TimeMeasurement is performed within HDG
    IF(DoFieldUpdate) CALL HDG(time,U,iter)
#endif
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    CALL PartVeloToImp(VeloToImp=.TRUE.)
    ! should be already be done
    DO iPart=1,PDM%ParticleVecLength
      IF(.NOT.PDM%ParticleInside(iPart))CYCLE
      ! position currently updated, hence store the data for tracking
      LastPartPos(1,iPart)  =PartStateN(1,iPart)
      LastPartPos(2,iPart)  =PartStateN(2,iPart)
      LastPartPos(3,iPart)  =PartStateN(3,iPart)
      PEM%lastElement(iPart)=PEM%ElementN(iPart)
      ! build RHS of particle with current DG solution and particle position
      ! CAUTION: we have to use a local variable here. The Jacobian matrix is FIXED for one time step,
      ! hence the fields for the matrix-vector-multiplication shall NOT be updated
      CALL InterpolateFieldToSingleParticle(iPart,FieldAtParticle_loc(1:6))
      reMap=.FALSE.
      IF(PartMeshHasReflectiveBCs)THEN
        IF(SUM(ABS(PEM%NormVec(1:3,iPart))).GT.0.)THEN
          n_loc=PEM%NormVec(1:3,iPart)
          ! particle is actually located outside, hence, it moves in the mirror field
          ! mirror electric field, constant B field
          FieldAtParticle(1:3,iPart)=FieldAtParticle(1:3,iPart)-2.*DOT_PRODUCT(FieldAtParticle(1:3,iPart),n_loc)*n_loc
          FieldAtParticle(4:6,iPart)=FieldAtParticle(4:6,iPart)!-2.*DOT_PRODUCT(FieldAtParticle(4:6,iPart),n_loc)*n_loc
          PEM%NormVec(1:3,iPart)=0.
          ! and of coarse, the velocity has to be back-rotated, because the particle has not hit the wall
          reMap=.TRUE.
        END IF
      END IF
      IF(PEM%PeriodicMoved(iPart))THEN
        PEM%PeriodicMoved(iPart)=.FALSE.
        Remap=.TRUE.
      END IF
      IF(reMap)THEN
        ! and of coarse, the velocity has to be back-rotated, because the particle has not hit the wall
        ! it is more stable, to recompute the position
        ! compute explicit contribution which is
        PartState(1:6,iPart) = RK_a(iStage,iStage-1)*PartStage(1:6,iStage-1,iPart)
        DO iCounter=1,iStage-2
          PartState(1:6,iPart)=PartState(1:6,iPart)+RK_a(iStage,iCounter)*PartStage(1:6,iCounter,iPart)
        END DO ! iCounter=1,iStage-2
        PartState(1:6,iPart)=PartStateN(1:6,iPart)+PartState(1:6,iPart)
      END IF ! PartMeshHasReflectiveBCs
      ! compute particle RHS at time^n
      IF(PartLorentzType.EQ.5)THEN
        LorentzFacInv=1.0/SQRT(1.0+DOT_PRODUCT(PartState(4:6,iPart),PartState(4:6,iPart))*c2_inv)
        CALL PartRHS(iPart,FieldAtParticle_loc(1:6),Pt(1:3,iPart),LorentzFacInv)
      ELSE
        LorentzFacInv = 1.0
        CALL PartRHS(iPart,FieldAtParticle_loc(1:6),Pt(1:3,iPart))
      END IF ! PartLorentzType.EQ.5
      ! compute current Pt_tmp for the particle
      Pt_tmp(1) = LorentzFacInv*PartState(4,iPart)
      Pt_tmp(2) = LorentzFacInv*PartState(5,iPart)
      Pt_tmp(3) = LorentzFacInv*PartState(6,iPart)
      Pt_tmp(4) = Pt(1,iPart)
      Pt_tmp(5) = Pt(2,iPart)
      Pt_tmp(6) = Pt(3,iPart)
      IF(DoSurfaceFlux)THEN
        coeff_loc=PartDtFrac(iPart)*coeff
      ELSE
        coeff_loc=coeff
      END IF
      PartRHS_loc =(Pt_tmp + PartQ(1:6,iPart))*coeff_loc
      ! guess for new particleposition is PartState || reuse of OLD GMRES
      CALL PartMatrixVector(time,Coeff_loc,iPart,PartRHS_loc,PartDeltaX)
      PartRHS_tild = PartRHS_loc - PartDeltaX
      PartDeltaX=0.
      CALL PartVectorDotProduct(PartRHS_tild,PartRHS_tild,Norm_P2)
      AbortCrit=1e-16
      CALL Particle_GMRES(time,coeff_loc,iPart,PartRHS_tild,SQRT(Norm_P2),AbortCrit,PartDeltaX)
      ! update particle to k_iStage
      PartState(1:6,iPart)=PartRHS_loc+PartDeltaX(1:6)
      !PartState(1:6,iPart)=PartRHS_loc+PartDeltaX(1:6)
      ! and store value as k_iStage
      IF(iStage.LT.nRKStages)THEN
        PartStage(1,iStage,iPart) = PartState(1,iPart)
        PartStage(2,iStage,iPart) = PartState(2,iPart)
        PartStage(3,iStage,iPart) = PartState(3,iPart)
        PartStage(4,iStage,iPart) = PartState(4,iPart)
        PartStage(5,iStage,iPart) = PartState(5,iPart)
        PartStage(6,iStage,iPart) = PartState(6,iPart)
      END IF
    END DO ! iPart
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/
  END IF
  IF(DoFieldUpdate) THEN
#endif /*PARTICLES*/

  !--------------------------------------------------------------------------------------------------------------------------------
  ! DGSolver: now, we can add the contribution of the particles
  ! LB-TimeMeasurement is performed in DGTimeDerivative_weakForm and LinearSolver (DGTimeDerivative_weakForm), hence,
  ! it is neglected here, array copy assumed to be zero
  !--------------------------------------------------------------------------------------------------------------------------------
#if !(USE_HDG)
    ! next DG call is f(u^n + dt sum_j^i-1 a_ij k_j) + source terms
    CALL DGTimeDerivative_weakForm(time, time, 0,doSource=.TRUE.) ! source terms are not-added in linear solver
    ! CAUTION: invert sign of Ut
    LinSolverRHS = LinSolverRHS + Ut
    CALL LinearSolver(tStage,coeff_inv)
    ! and store U in fieldstage
    IF(iStage.LT.nRKStages) FieldStage (:,:,:,:,:,iStage) = U
#endif /*NOT HDG->DG*/
#ifdef PARTICLES
  END IF ! DoFieldUpdate
#endif /*PARTICLES*/
END DO


#if !(USE_HDG)
#ifdef PARTICLES
IF(DoFieldUpdate)THEN
#endif /*PARTICLES*/
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  ! update field step
  U = RK_b(nRKStages)* U
  DO iCounter=1,nRKStages-1
    U = U +  RK_b(iCounter)* FieldStage(:,:,:,:,:,iCounter)
  END DO ! counter
  U = Un +  U
  CALL DivCleaningDamping()
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_DG,tLBStart)
#endif /*USE_LOADBALANCE*/
#ifdef PARTICLES
END IF ! DoFieldUpdate
#endif /*PARTICLES*/
#endif /*NOT HDG->DG*/

#ifdef PARTICLES
! particle step || only explicit particles
IF (time.GE.DelayTime) THEN
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  ! add here new method
  DO iPart=1,PDM%ParticleVecLength
    IF(.NOT.PDM%ParticleInside(iPart))CYCLE
    !  stage 1 ,nRKStages-1
    PartState(1:6,iPart) = RK_b(nRKStages)*PartState(1:6,iPart)
    DO iCounter=1,nRKStages-1
      PartState(1:6,iPart) = PartState(1:6,iPart) + RK_b(iCounter)*PartStage(1:6,iCounter,iPart)
    END DO ! counter
    PartState(1:6,iPart) = PartStateN(1:6,iPart)+PartState(1:6,iPart)
  END DO ! iPart
#if USE_LOADBALANCE
  CALL LBSplitTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/
  iStage=0
#if USE_MPI
  ! mpi-routines should be extended by additional input: PartisImplicit, better criterion, saves computational time
  ! open receive buffer for number of particles
  CALL IRecvNbofParticles()
#endif /*USE_MPI*/
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
  IF(DoRefMapping)THEN
    ! tracking routines has to be extended for optional flag, like deposition
    CALL ParticleRefTracking()
  ELSE
    IF (TriaTracking) THEN
      CALL ParticleTriaTracking()
    ELSE
      CALL ParticleTracing()
    END IF
  END IF
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
#if USE_MPI
  ! send number of particles
  CALL SendNbOfParticles() ! all particles to get initial deposition right \\ without emmission
  ! finish communication of number of particles and send particles
  CALL MPIParticleSend()
  ! finish communication
  CALL MPIParticleRecv()
  PartMPIExchange%nMPIParticles=0
  IF(DoExternalParts)THEN
    ! as we do not have the shape function here, we have to deallocate something
    SDEALLOCATE(ExtPartState)
    SDEALLOCATE(ExtPartSpecies)
    SDEALLOCATE(ExtPartToFIBGM)
    SDEALLOCATE(ExtPartMPF)
  END IF
#endif
#if USE_LOADBALANCE
  CALL LBSplitTime(LB_PARTCOMM,tLBStart)
#endif /*USE_LOADBALANCE*/
  ! map particle from gamma*v to v
  CALL PartVeloToImp(VeloToImp=.FALSE.)
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/
END IF
#endif /*PARTICLES*/

!----------------------------------------------------------------------------------------------------------------------------------
! DSMC
!----------------------------------------------------------------------------------------------------------------------------------
#ifdef PARTICLES
IF (useDSMC) THEN
  CALL UpdateNextFreePosition()
  CALL DSMC_main()
  PartState(4:6,1:PDM%ParticleVecLength) = PartState(4:6,1:PDM%ParticleVecLength) + DSMC_RHS(1:3,1:PDM%ParticleVecLength)
END IF

!----------------------------------------------------------------------------------------------------------------------------------
! split and merge
!----------------------------------------------------------------------------------------------------------------------------------
IF (doParticleMerge) THEN
  IF (.NOT.(useDSMC.OR.PartPressureCell)) THEN
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    ALLOCATE(PEM%pStart(1:PP_nElems)           , &
             PEM%pNumber(1:PP_nElems)          , &
             PEM%pNext(1:PDM%maxParticleNumber), &
             PEM%pEnd(1:PP_nElems) )
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_SPLITMERGE,tLBStart)
#endif /*USE_LOADBALANCE*/
  END IF
END IF

IF ((time.GE.DelayTime).OR.(iter.EQ.0)) CALL UpdateNextFreePosition()

IF (doParticleMerge) THEN
  CALL StartParticleMerge()
  IF (.NOT.(useDSMC.OR.PartPressureCell)) THEN
    DEALLOCATE(PEM%pStart , &
               PEM%pNumber, &
               PEM%pNext  , &
               PEM%pEnd   )
  END IF
  CALL UpdateNextFreePosition()
END IF
#endif /*PARTICLES*/

END SUBROUTINE TimeStepByRosenbrock
#endif /*ROS  */


#if (PP_TimeDiscMethod==300)
SUBROUTINE TimeStep_FPFlow()
!===================================================================================================================================
!
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_TimeDisc_Vars             ,ONLY: dt, IterDisplayStep, iter, TEnd, Time
USE MOD_Filter                    ,ONLY: Filter
USE MOD_Globals                   ,ONLY: abort
USE MOD_Particle_Vars             ,ONLY: PartState, LastPartPos, PDM, PEM, DoSurfaceFlux, WriteMacroVolumeValues
USE MOD_Particle_Vars             ,ONLY: VarTimeStep, Symmetry2D, Symmetry2DAxisymmetric
USE MOD_DSMC_Vars                 ,ONLY: DSMC_RHS, DSMC, CollisMode
USE MOD_part_tools                ,ONLY: UpdateNextFreePosition
USE MOD_part_emission             ,ONLY: ParticleInserting
USE MOD_surface_flux              ,ONLY: ParticleSurfaceflux
USE MOD_Particle_Tracking_vars    ,ONLY: tTracking,DoRefMapping,MeasureTrackTime,TriaTracking
USE MOD_Particle_Tracking         ,ONLY: ParticleTracing,ParticleRefTracking,ParticleTriaTracking
#if USE_MPI
USE MOD_Particle_MPI              ,ONLY: IRecvNbOfParticles, MPIParticleSend,MPIParticleRecv,SendNbOfparticles
#endif /*USE_MPI*/
USE MOD_FPFlow                    ,ONLY: FPFlow_main, FP_DSMC_main
USE MOD_FPFlow_Vars               ,ONLY: CoupledFPDSMC
USE MOD_Particle_Boundary_Porous  ,ONLY: PorousBoundaryRemovalProb_Pressure
USE MOD_Particle_Boundary_Vars    ,ONLY: nPorousBC
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                  :: timeEnd, timeStart
INTEGER               :: iPart
REAL                  :: RandVal, dtVar, NewYPart, NewYVelo
!===================================================================================================================================
IF (DoSurfaceFlux) THEN
  CALL ParticleSurfaceflux()
END IF

DO iPart=1,PDM%ParticleVecLength
  IF (PDM%ParticleInside(iPart)) THEN
  ! Variable time step: getting the right time step for the particle (can be constant across an element)
  IF (VarTimeStep%UseVariableTimeStep) THEN
    dtVar = dt * VarTimeStep%ParticleTimeStep(iPart)
  ELSE
    dtVar = dt
  END IF
  IF (PDM%dtFracPush(iPart)) THEN
    ! Surface flux (dtFracPush): previously inserted particles are pushed a random distance between 0 and v*dt
    !                            LastPartPos and LastElem already set!
    CALL RANDOM_NUMBER(RandVal)
    dtVar = dtVar * RandVal
    PDM%dtFracPush(iPart) = .FALSE.
  ELSE
    LastPartPos(1,iPart)=PartState(1,iPart)
    LastPartPos(2,iPart)=PartState(2,iPart)
    LastPartPos(3,iPart)=PartState(3,iPart)
    PEM%lastElement(iPart)=PEM%Element(iPart)
  END IF
  PartState(1,iPart) = PartState(1,iPart) + PartState(4,iPart) * dtVar
  PartState(2,iPart) = PartState(2,iPart) + PartState(5,iPart) * dtVar
  PartState(3,iPart) = PartState(3,iPart) + PartState(6,iPart) * dtVar
  ! Axisymmetric treatment of particles: rotation of the position and velocity vector
  IF(Symmetry2DAxisymmetric) THEN
    IF (PartState(2,iPart).LT.0.0) THEN
      NewYPart = -SQRT(PartState(2,iPart)**2 + (PartState(3,iPart))**2)
    ELSE
      NewYPart = SQRT(PartState(2,iPart)**2 + (PartState(3,iPart))**2)
    END IF
    ! Rotation: Vy' =   Vy * cos(alpha) + Vz * sin(alpha) =   Vy * y/y' + Vz * z/y'
    !           Vz' = - Vy * sin(alpha) + Vz * cos(alpha) = - Vy * z/y' + Vz * y/y'
    ! Right-hand system, using new y and z positions after tracking, position vector and velocity vector DO NOT have to
    ! coincide (as opposed to Bird 1994, p. 391, where new positions are calculated with the velocity vector)
    NewYVelo = (PartState(5,iPart)*(PartState(2,iPart))+PartState(6,iPart)*PartState(3,iPart))/NewYPart
    PartState(6,iPart) = (-PartState(5,iPart)*PartState(3,iPart)+PartState(6,iPart)*(PartState(2,iPart)))/NewYPart
    PartState(2,iPart) = NewYPart
    PartState(3,iPart) = 0.0
    PartState(5,iPart) = NewYVelo
    END IF
  END IF
END DO

! Resetting the particle positions in the third dimension for the 2D/axisymmetric case
IF(Symmetry2D) THEN
  LastPartPos(3,1:PDM%ParticleVecLength) = 0.0
  PartState(3,1:PDM%ParticleVecLength) = 0.0
END IF

#if USE_MPI
! open receive buffer for number of particles
CALL IRecvNbOfParticles()
#endif /*USE_MPI*/
IF(MeasureTrackTime) CALL CPU_TIME(TimeStart)
! actual tracking
IF(DoRefMapping)THEN
  CALL ParticleRefTracking()
ELSE
  IF (TriaTracking) THEN
    CALL ParticleTriaTracking()
  ELSE
    CALL ParticleTracing()
  END IF
END IF
IF (nPorousBC.GT.0) THEN
  CALL PorousBoundaryRemovalProb_Pressure()
END IF
IF(MeasureTrackTime) THEN
  CALL CPU_TIME(TimeEnd)
  tTracking=tTracking+TimeEnd-TimeStart
END IF
#if USE_MPI
! send number of particles
CALL SendNbOfParticles()
! finish communication of number of particles and send particles
CALL MPIParticleSend()
! finish communication
CALL MPIParticleRecv()
#endif /*USE_MPI*/
CALL ParticleInserting()
IF (CollisMode.NE.0) THEN
  CALL UpdateNextFreePosition()
ELSE IF ( (MOD(iter,IterDisplayStep).EQ.0) .OR. &
          (Time.ge.(1-DSMC%TimeFracSamp)*TEnd) .OR. &
          WriteMacroVolumeValues ) THEN
  CALL UpdateNextFreePosition() !postpone UNFP for CollisMode=0 to next IterDisplayStep or when needed for DSMC-Sampling
ELSE IF (PDM%nextFreePosition(PDM%CurrentNextFreePosition+1).GT.PDM%maxParticleNumber .OR. &
         PDM%nextFreePosition(PDM%CurrentNextFreePosition+1).EQ.0) THEN
  CALL abort(&
__STAMP__,&
'maximum nbr of particles reached!')  !gaps in PartState are not filled until next UNFP and array might overflow more easily!
END IF

IF (CoupledFPDSMC) THEN
  CALL FP_DSMC_main()
ELSE
  CALL FPFlow_main()
END IF

PartState(4:6,1:PDM%ParticleVecLength) = PartState(4:6,1:PDM%ParticleVecLength) + DSMC_RHS(1:3,1:PDM%ParticleVecLength)


END SUBROUTINE TimeStep_FPFlow
#endif

#if (PP_TimeDiscMethod==400)
SUBROUTINE TimeStep_BGK()
!===================================================================================================================================
!> description
!===================================================================================================================================
! MODULES
USE MOD_PreProc
USE MOD_TimeDisc_Vars             ,ONLY: dt, IterDisplayStep, iter, TEnd, Time
USE MOD_Filter                    ,ONLY: Filter
USE MOD_Globals                   ,ONLY: abort
USE MOD_Particle_Vars             ,ONLY: PartState, LastPartPos, PDM, PEM, DoSurfaceFlux, WriteMacroVolumeValues
USE MOD_Particle_Vars             ,ONLY: VarTimeStep, Symmetry2D, Symmetry2DAxisymmetric
USE MOD_DSMC_Vars                 ,ONLY: DSMC_RHS, DSMC, CollisMode
USE MOD_part_tools                ,ONLY: UpdateNextFreePosition
USE MOD_part_emission             ,ONLY: ParticleInserting
USE MOD_surface_flux              ,ONLY: ParticleSurfaceflux
USE MOD_Particle_Tracking_vars    ,ONLY: tTracking,DoRefMapping,MeasureTrackTime,TriaTracking
USE MOD_Particle_Tracking         ,ONLY: ParticleTracing,ParticleRefTracking,ParticleTriaTracking
#if USE_MPI
USE MOD_Particle_MPI              ,ONLY: IRecvNbOfParticles, MPIParticleSend,MPIParticleRecv,SendNbOfparticles
#endif /*USE_MPI*/
USE MOD_BGK                       ,ONLY: BGK_main, BGK_DSMC_main
USE MOD_BGK_Vars                  ,ONLY: CoupledBGKDSMC
USE MOD_Particle_Boundary_Porous  ,ONLY: PorousBoundaryRemovalProb_Pressure
USE MOD_Particle_Boundary_Vars    ,ONLY: nPorousBC
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                  :: timeEnd, timeStart
INTEGER               :: iPart
REAL                  :: RandVal, dtVar, NewYPart, NewYVelo
!===================================================================================================================================
IF (DoSurfaceFlux) THEN
  CALL ParticleSurfaceflux()
END IF

DO iPart=1,PDM%ParticleVecLength
  IF (PDM%ParticleInside(iPart)) THEN
  ! Variable time step: getting the right time step for the particle (can be constant across an element)
  IF (VarTimeStep%UseVariableTimeStep) THEN
    dtVar = dt * VarTimeStep%ParticleTimeStep(iPart)
  ELSE
    dtVar = dt
  END IF
  IF (PDM%dtFracPush(iPart)) THEN
    ! Surface flux (dtFracPush): previously inserted particles are pushed a random distance between 0 and v*dt
    !                            LastPartPos and LastElem already set!
    CALL RANDOM_NUMBER(RandVal)
    dtVar = dtVar * RandVal
    PDM%dtFracPush(iPart) = .FALSE.
  ELSE
    LastPartPos(1:3,iPart)=PartState(1:3,iPart)
    PEM%lastElement(iPart)=PEM%Element(iPart)
  END IF
  PartState(1:3,iPart) = PartState(1:3,iPart) + PartState(4:6,iPart) * dtVar
  ! Axisymmetric treatment of particles: rotation of the position and velocity vector
  IF(Symmetry2DAxisymmetric) THEN
    IF (PartState(2,iPart).LT.0.0) THEN
      NewYPart = -SQRT(PartState(2,iPart)**2 + (PartState(3,iPart))**2)
    ELSE
      NewYPart = SQRT(PartState(2,iPart)**2 + (PartState(3,iPart))**2)
    END IF
    ! Rotation: Vy' =   Vy * cos(alpha) + Vz * sin(alpha) =   Vy * y/y' + Vz * z/y'
    !           Vz' = - Vy * sin(alpha) + Vz * cos(alpha) = - Vy * z/y' + Vz * y/y'
    ! Right-hand system, using new y and z positions after tracking, position vector and velocity vector DO NOT have to
    ! coincide (as opposed to Bird 1994, p. 391, where new positions are calculated with the velocity vector)
    NewYVelo = (PartState(5,iPart)*(PartState(2,iPart))+PartState(6,iPart)*PartState(3,iPart))/NewYPart
    PartState(6,iPart) = (-PartState(5,iPart)*PartState(3,iPart)+PartState(6,iPart)*(PartState(2,iPart)))/NewYPart
    PartState(2,iPart) = NewYPart
    PartState(3,iPart) = 0.0
    PartState(5,iPart) = NewYVelo
    END IF
  END IF
END DO

! Resetting the particle positions in the third dimension for the 2D/axisymmetric case
IF(Symmetry2D) THEN
  LastPartPos(3,1:PDM%ParticleVecLength) = 0.0
  PartState(3,1:PDM%ParticleVecLength) = 0.0
END IF

#if USE_MPI
! open receive buffer for number of particles
CALL IRecvNbOfParticles()
#endif /*USE_MPI*/
IF(MeasureTrackTime) CALL CPU_TIME(TimeStart)
! actual tracking
IF(DoRefMapping)THEN
  CALL ParticleRefTracking()
ELSE
  IF (TriaTracking) THEN
    CALL ParticleTriaTracking()
  ELSE
    CALL ParticleTracing()
  END IF
END IF
IF (nPorousBC.GT.0) THEN
  CALL PorousBoundaryRemovalProb_Pressure()
END IF
IF(MeasureTrackTime) THEN
  CALL CPU_TIME(TimeEnd)
  tTracking=tTracking+TimeEnd-TimeStart
END IF
#if USE_MPI
! send number of particles
CALL SendNbOfParticles()
! finish communication of number of particles and send particles
CALL MPIParticleSend()
! finish communication
CALL MPIParticleRecv()
#endif /*USE_MPI*/
CALL ParticleInserting()
IF (CollisMode.NE.0) THEN
  CALL UpdateNextFreePosition()
ELSE IF ( (MOD(iter,IterDisplayStep).EQ.0) .OR. &
          (Time.ge.(1-DSMC%TimeFracSamp)*TEnd) .OR. &
          WriteMacroVolumeValues ) THEN
  CALL UpdateNextFreePosition() !postpone UNFP for CollisMode=0 to next IterDisplayStep or when needed for DSMC-Sampling
ELSE IF (PDM%nextFreePosition(PDM%CurrentNextFreePosition+1).GT.PDM%maxParticleNumber .OR. &
         PDM%nextFreePosition(PDM%CurrentNextFreePosition+1).EQ.0) THEN
  CALL abort(&
__STAMP__,&
'maximum nbr of particles reached!')  !gaps in PartState are not filled until next UNFP and array might overflow more easily!
END IF
  IF (CoupledBGKDSMC) THEN
    CALL BGK_DSMC_main()
  ELSE
    CALL BGK_main()
  END IF

PartState(4:6,1:PDM%ParticleVecLength) = PartState(4:6,1:PDM%ParticleVecLength) + DSMC_RHS(1:3,1:PDM%ParticleVecLength)

END SUBROUTINE TimeStep_BGK
#endif

#if USE_HDG
#if (PP_TimeDiscMethod==500) || (PP_TimeDiscMethod==509)
SUBROUTINE TimeStepPoisson()
!===================================================================================================================================
! Euler (500) or Leapfrog (509) -push with HDG
!===================================================================================================================================
! MODULES
USE MOD_Globals                ,ONLY: Abort, LocalTime
USE MOD_DG_Vars                ,ONLY: U
USE MOD_PreProc
USE MOD_TimeDisc_Vars          ,ONLY: dt,iter,time
#if (PP_TimeDiscMethod==509)
USE MOD_TimeDisc_Vars          ,ONLY: dt_old
#endif /*(PP_TimeDiscMethod==509)*/
USE MOD_HDG                    ,ONLY: HDG
USE MOD_Particle_Tracking_vars ,ONLY: DoRefMapping
#ifdef PARTICLES
USE MOD_PICDepo                ,ONLY: Deposition
USE MOD_PICInterpolation       ,ONLY: InterpolateFieldToParticle
USE MOD_Particle_Vars          ,ONLY: PartState, Pt, LastPartPos,PEM, PDM, doParticleMerge, DelayTime, PartPressureCell
USE MOD_Particle_Vars          ,ONLY: DoSurfaceFlux, DoForceFreeSurfaceFlux
USE MOD_Particle_Analyze       ,ONLY: CalcCoupledPowerPart
USE MOD_Particle_Analyze_Vars  ,ONLY: CalcCoupledPower,PCoupl
#if (PP_TimeDiscMethod==509)
USE MOD_Particle_Vars          ,ONLY: velocityAtTime, velocityOutputAtTime
#endif /*(PP_TimeDiscMethod==509)*/
USE MOD_part_RHS               ,ONLY: CalcPartRHS
USE MOD_part_emission          ,ONLY: ParticleInserting
USE MOD_surface_flux           ,ONLY: ParticleSurfaceflux
USE MOD_DSMC                   ,ONLY: DSMC_main
USE MOD_DSMC_Vars              ,ONLY: useDSMC, DSMC_RHS
USE MOD_part_MPFtools          ,ONLY: StartParticleMerge
USE MOD_PIC_Analyze            ,ONLY: VerifyDepositedCharge
USE MOD_Particle_Analyze_Vars  ,ONLY: DoVerifyCharge,PartAnalyzeStep
#if USE_MPI
USE MOD_Particle_MPI           ,ONLY: IRecvNbOfParticles, MPIParticleSend,MPIParticleRecv,SendNbOfparticles
USE MOD_Particle_MPI_Vars      ,ONLY: PartMPIExchange
USE MOD_Particle_MPI_Vars      ,ONLY:  DoExternalParts
USE MOD_Particle_MPI_Vars      ,ONLY: ExtPartState,ExtPartSpecies,ExtPartMPF,ExtPartToFIBGM
#endif
USE MOD_Part_Tools             ,ONLY: UpdateNextFreePosition,isPushParticle
USE MOD_Particle_Tracking_vars ,ONLY: DoRefMapping,TriaTracking
USE MOD_Particle_Tracking      ,ONLY: ParticleTracing,ParticleRefTracking,ParticleCollectCharges,ParticleTriaTracking
#endif
#if USE_LOADBALANCE
USE MOD_LoadBalance_Timers     ,ONLY: LBStartTime,LBSplitTime,LBPauseTime
#endif /*USE_LOADBALANCE*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                    :: iPart
REAL                       :: RandVal, dtFrac
#if USE_LOADBALANCE
REAL                       :: tLBStart ! load balance
#endif /*USE_LOADBALANCE*/
#ifdef PARTICLES
REAL                       :: EDiff
#endif /*PARTICLES*/
!===================================================================================================================================
#ifdef PARTICLES
IF ((time.GE.DelayTime).OR.(iter.EQ.0)) THEN
  ! communicate shape function particles
#if USE_MPI
  PartMPIExchange%nMPIParticles=0
  IF(DoExternalParts)THEN
    ! as we do not have the shape function here, we have to deallocate something
    SDEALLOCATE(ExtPartState)
    SDEALLOCATE(ExtPartSpecies)
    SDEALLOCATE(ExtPartToFIBGM)
    SDEALLOCATE(ExtPartMPF)
    ! open receive buffer for number of particles
    CALL IRecvNbofParticles()
    ! send number of particles
    CALL SendNbOfParticles()
    ! finish communication of number of particles and send particles
    CALL MPIParticleSend()
  END IF
#endif /*USE_MPI*/
  CALL Deposition(DoInnerParts=.TRUE.) ! because of emmision and UpdateParticlePosition
#if USE_MPI
  IF(DoExternalParts)THEN
    ! finish communication
    CALL MPIParticleRecv()
  END IF
  ! here: finish deposition with delta kernal
  !       maps source terms in physical space
  ! ALWAYS require
  PartMPIExchange%nMPIParticles=0
#endif /*USE_MPI*/
  CALL Deposition(DoInnerParts=.FALSE.) ! needed for closing communication
  IF(MOD(iter,PartAnalyzeStep).EQ.0)THEN ! Move this function to Deposition routine
    IF(DoVerifyCharge) CALL VerifyDepositedCharge()
  END IF
END IF
#endif /*PARTICLES*/

CALL HDG(time,U,iter)

#ifdef PARTICLES
#if USE_LOADBALANCE
CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
! set last data already here, since surfaceflux moved before interpolation
LastPartPos(1,1:PDM%ParticleVecLength)=PartState(1,1:PDM%ParticleVecLength)
LastPartPos(2,1:PDM%ParticleVecLength)=PartState(2,1:PDM%ParticleVecLength)
LastPartPos(3,1:PDM%ParticleVecLength)=PartState(3,1:PDM%ParticleVecLength)
PEM%lastElement(1:PDM%ParticleVecLength)=PEM%Element(1:PDM%ParticleVecLength)
#if USE_LOADBALANCE
CALL LBPauseTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/
IF (time.GE.DelayTime) THEN
  IF (DoSurfaceFlux) THEN
    CALL ParticleSurfaceflux() !dtFracPush (SurfFlux): LastPartPos and LastElem already set!
  END IF
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  CALL InterpolateFieldToParticle(DoInnerParts=.TRUE.)   ! forces on particles
  !CALL InterpolateFieldToParticle(DoInnerParts=.FALSE.) ! only needed when MPI communication changes the number of parts
#if USE_LOADBALANCE
  CALL LBSplitTime(LB_INTERPOLATION,tLBStart)
#endif /*USE_LOADBALANCE*/
  CALL CalcPartRHS()
  IF (CalcCoupledPower) PCoupl = 0. ! if output of coupled power is active: reset PCoupl
  DO iPart=1,PDM%ParticleVecLength
    IF (PDM%ParticleInside(iPart)) THEN
      ! If coupled power output is active and particle carries charge, determine its kinetic energy and store in EDiff
      IF (CalcCoupledPower) CALL CalcCoupledPowerPart(iPart,'before',EDiff)
      IF (DoSurfaceFlux .AND. PDM%dtFracPush(iPart)) THEN !DoSurfaceFlux for compiler-optimization if .FALSE.
        CALL RANDOM_NUMBER(RandVal)
        dtFrac = dt * RandVal
        PDM%IsNewPart(iPart)=.FALSE. !no IsNewPart-treatment for surffluxparts
      ELSE
        dtFrac = dt
#if (PP_TimeDiscMethod==509)
        IF (PDM%IsNewPart(iPart)) THEN
          ! Don't push the velocity component of neutral particles!
          IF(isPushParticle(iPart))THEN
            !-- v(n) => v(n-0.5) by a(n):
            PartState(4:6,iPart) = PartState(4:6,iPart) - Pt(1:3,iPart) * dt*0.5
          END IF
          PDM%IsNewPart(iPart)=.FALSE. !IsNewPart-treatment is now done
        ELSE
          IF ((ABS(dt-dt_old).GT.1.0E-6*dt_old).AND.&
               isPushParticle(iPart)) THEN ! Don't push the velocity component of neutral particles!
            PartState(4:6,iPart)  = PartState(4:6,iPart) + Pt(1:3,iPart) * (dt_old-dt)*0.5
          END IF
        END IF
#endif /*(PP_TimeDiscMethod==509)*/
      END IF
#if (PP_TimeDiscMethod==509)
      IF (DoSurfaceFlux .AND. PDM%dtFracPush(iPart) .AND. .NOT.DoForceFreeSurfaceFlux) THEN
        !-- x(BC) => x(n+1) by v(BC+X):
        PartState(1:3,iPart) = PartState(1:3,iPart) + ( PartState(4:6,iPart) + Pt(1,iPart) * dtFrac*0.5 ) * dtFrac
        ! Don't push the velocity component of neutral particles!
        IF(isPushParticle(iPart))THEN
          !-- v(BC) => v(n+0.5) by a(BC):
          PartState(4:6,iPart) = PartState(4:6,iPart) + Pt(1:3,iPart) * (dtFrac - dt*0.5)
        END IF
        PDM%dtFracPush(iPart) = .FALSE.
      ELSE IF (DoSurfaceFlux .AND. PDM%dtFracPush(iPart)) THEN !DoForceFreeSurfaceFlux
        !-- x(n) => x(n+1) by v(n+0.5)=v(BC)
        PartState(1:3,iPart) = PartState(1:3,iPart) + PartState(4:6,iPart) * dtFrac
        PDM%dtFracPush(iPart) = .FALSE.
      ELSE
        ! Don't push the velocity component of neutral particles!
        IF(isPushParticle(iPart))THEN
          !-- v(n-0.5) => v(n+0.5) by a(n):
          PartState(4:6,iPart) = PartState(4:6,iPart) + Pt(1:3,iPart) * dt
        END IF
        !-- x(n) => x(n+1) by v(n+0.5):
        PartState(1:3,iPart) = PartState(1:3,iPart) + PartState(4:6,iPart) * dt
      END IF
#else /*(PP_TimeDiscMethod==509)*/
        !-- x(n) => x(n+1) by v(n):
        PartState(1:3,iPart) = PartState(1:3,iPart) + PartState(4:6,iPart) * dtFrac
      IF (DoForceFreeSurfaceFlux .AND. DoSurfaceFlux .AND. PDM%dtFracPush(iPart)) THEN
        PDM%dtFracPush(iPart) = .FALSE.
      ELSE
        ! Don't push the velocity component of neutral particles!
        IF(isPushParticle(iPart))THEN
          !-- v(n) => v(n+1) by a(n):
          PartState(4:6,iPart) = PartState(4:6,iPart) + Pt(1:3,iPart) * dtFrac
        END IF
        IF (DoSurfaceFlux .AND. PDM%dtFracPush(iPart)) THEN
          PDM%dtFracPush(iPart) = .FALSE.
        END IF
      END IF
#endif /*(PP_TimeDiscMethod==509)*/
      ! If coupled power output is active and particle carries charge, calculate energy difference and add to output variable
      IF (CalcCoupledPower) CALL CalcCoupledPowerPart(iPart,'after',EDiff)
    END IF
  END DO
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/

#if USE_MPI
  CALL IRecvNbofParticles() ! open receive buffer for number of particles
#endif
  IF(DoRefMapping)THEN
    CALL ParticleRefTracking()
  ELSE
    IF (TriaTracking) THEN
      CALL ParticleTriaTracking()
    ELSE
      CALL ParticleTracing()
    END IF
  END IF
  CALL ParticleInserting()
#if USE_MPI
  CALL SendNbOfParticles() ! send number of particles
  CALL MPIParticleSend()  ! finish communication of number of particles and send particles
  CALL MPIParticleRecv()  ! finish communication
#endif
#if (PP_TimeDiscMethod==509)
  IF (velocityOutputAtTime) THEN
#if USE_MPI
    PartMPIExchange%nMPIParticles=0
#endif /*USE_MPI*/
    CALL Deposition(DoInnerParts=.TRUE.) ! because of emission and UpdateParticlePosition
    CALL Deposition(DoInnerParts=.FALSE.) ! needed for closing communication
    IF(MOD(iter,PartAnalyzeStep).EQ.0)THEN ! Move this function to Deposition routine
      IF(DoVerifyCharge) CALL VerifyDepositedCharge()
    END IF
    CALL HDG(time,U,iter)
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    CALL InterpolateFieldToParticle(DoInnerParts=.TRUE.)   ! forces on particles
    !CALL InterpolateFieldToParticle(DoInnerParts=.FALSE.) ! only needed when MPI communication changes the number of parts
#if USE_LOADBALANCE
    CALL LBSplitTime(LB_INTERPOLATION,tLBStart)
#endif /*USE_LOADBALANCE*/
    CALL CalcPartRHS()
    DO iPart=1,PDM%ParticleVecLength
      IF (PDM%ParticleInside(iPart)) THEN
        !-- v(n+0.5) => v(n+1) by a(n+1):
        velocityAtTime(iPart,1:3) = PartState(4:6,iPart) + Pt(1:3,iPart) * dt*0.5
      END IF
    END DO
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/
  END IF !velocityOutputAtTime
#endif /*(PP_TimeDiscMethod==509)*/
  CALL ParticleCollectCharges()
END IF

#if USE_MPI
PartMPIExchange%nMPIParticles=0 ! and set number of received particles to zero for deposition
#endif
IF (doParticleMerge) THEN
  IF (.NOT.(useDSMC.OR.PartPressureCell)) THEN
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    ALLOCATE(PEM%pStart(1:PP_nElems)           , &
             PEM%pNumber(1:PP_nElems)          , &
             PEM%pNext(1:PDM%maxParticleNumber), &
             PEM%pEnd(1:PP_nElems) )
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_SPLITMERGE,tLBStart)
#endif /*USE_LOADBALANCE*/
  END IF
END IF

IF ((time.GE.DelayTime).OR.(iter.EQ.0)) CALL UpdateNextFreePosition()

IF (doParticleMerge) THEN
  CALL StartParticleMerge()
  IF (.NOT.(useDSMC.OR.PartPressureCell)) THEN
    DEALLOCATE(PEM%pStart , &
               PEM%pNumber, &
               PEM%pNext  , &
               PEM%pEnd   )
  END IF
  CALL UpdateNextFreePosition()
END IF

IF (useDSMC) THEN
  IF (time.GE.DelayTime) THEN
    CALL DSMC_main()
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    PartState(4:6,1:PDM%ParticleVecLength) = PartState(4:6,1:PDM%ParticleVecLength) + DSMC_RHS(1:3,1:PDM%ParticleVecLength)
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_DSMC,tLBStart)
#endif /*USE_LOADBALANCE*/
  END IF
END IF
#endif /*PARTICLES*/

END SUBROUTINE TimeStepPoisson
#endif /*(PP_TimeDiscMethod==500) || (PP_TimeDiscMethod==509)*/

#if (PP_TimeDiscMethod==501) || (PP_TimeDiscMethod==502) || (PP_TimeDiscMethod==506)
SUBROUTINE TimeStepPoissonByLSERK()
!===================================================================================================================================
! Hesthaven book, page 64
! Low-Storage Runge-Kutta integration of degree 4 with 5 stages.
! This procedure takes the current time t, the time step dt and the solution at
! the current time U(t) and returns the solution at the next time level.
!===================================================================================================================================
! MODULES
USE MOD_Globals                ,ONLY: Abort, LocalTime
USE MOD_PreProc
USE MOD_TimeDisc_Vars          ,ONLY: dt,iStage,RKdtFrac,RKdtFracTotal,time,iter,dt_Min,dtWeight
USE MOD_TimeDisc_Vars          ,ONLY: RK_a,RK_b,RK_c,nRKStages
USE MOD_DG_Vars                ,ONLY: U
#ifdef PARTICLES
USE MOD_PICDepo                ,ONLY: Deposition
USE MOD_PICInterpolation       ,ONLY: InterpolateFieldToParticle
USE MOD_Particle_Vars          ,ONLY: PartState, Pt, Pt_temp, LastPartPos, DelayTime,  PEM, PDM, &
                                      doParticleMerge,PartPressureCell,DoSurfaceFlux,DoForceFreeSurfaceFlux,DoFieldIonization
USE MOD_PICModels              ,ONLY: FieldIonization
USE MOD_part_RHS               ,ONLY: CalcPartRHS
USE MOD_part_emission          ,ONLY: ParticleInserting
USE MOD_surface_flux           ,ONLY: ParticleSurfaceflux
USE MOD_DSMC                   ,ONLY: DSMC_main
USE MOD_DSMC_Vars              ,ONLY: useDSMC, DSMC_RHS
USE MOD_part_MPFtools          ,ONLY: StartParticleMerge
USE MOD_PIC_Analyze            ,ONLY: VerifyDepositedCharge
USE MOD_Particle_Analyze_Vars  ,ONLY: PartAnalyzeStep
USE MOD_Particle_Analyze_Vars  ,ONLY: DoVerifyCharge
USE MOD_Particle_Analyze       ,ONLY: CalcCoupledPowerPart
USE MOD_Particle_Analyze_Vars  ,ONLY: CalcCoupledPower,PCoupl
#if USE_MPI
USE MOD_Particle_MPI           ,ONLY: IRecvNbOfParticles, MPIParticleSend,MPIParticleRecv,SendNbOfparticles
USE MOD_Particle_MPI_Vars      ,ONLY: PartMPIExchange
USE MOD_Particle_MPI_Vars      ,ONLY: DoExternalParts
USE MOD_Particle_MPI_Vars      ,ONLY: ExtPartState,ExtPartSpecies,ExtPartMPF,ExtPartToFIBGM
#endif
USE MOD_Particle_Mesh          ,ONLY: CountPartsPerElem
USE MOD_Particle_Tracking_vars ,ONLY: DoRefMapping,TriaTracking
USE MOD_Part_Tools             ,ONLY: UpdateNextFreePosition,isPushParticle
USE MOD_Particle_Tracking      ,ONLY: ParticleTracing,ParticleRefTracking,ParticleCollectCharges,ParticleTriaTracking
USE MOD_SurfaceModel           ,ONLY: UpdateSurfModelVars, SurfaceModel_main
#endif /*PARTICLES*/
USE MOD_HDG                    ,ONLY: HDG
#if USE_LOADBALANCE
USE MOD_LoadBalance_Timers     ,ONLY: LBStartTime,LBSplitTime,LBPauseTime
#endif /*USE_LOADBALANCE*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL           :: tStage,b_dt(1:nRKStages)
REAL           :: Pa_rebuilt_coeff(1:nRKStages),Pa_rebuilt(1:3,1:nRKStages),Pv_rebuilt(1:3,1:nRKStages),v_rebuilt(1:3,0:nRKStages-1)
INTEGER        :: iPart, iStage_loc
REAL           :: RandVal
#ifdef PARTICLES
REAL           :: EDiff
#endif /*PARTICLES*/
#if USE_LOADBALANCE
REAL           :: tLBStart
#endif /*USE_LOADBALANCE*/
!===================================================================================================================================

DO iStage_loc=1,nRKStages
  ! RK coefficients
  b_dt(iStage_loc)=RK_b(iStage_loc)*dt
  ! Rebuild Pt_tmp-coefficients assuming F=const. (value at wall) in previous stages
  IF (iStage_loc.EQ.1) THEN
    Pa_rebuilt_coeff(iStage_loc) = 1.
  ELSE
    Pa_rebuilt_coeff(iStage_loc) = 1. - RK_a(iStage_loc)*Pa_rebuilt_coeff(iStage_loc-1)
  END IF
END DO
iStage=1

! first RK step
#ifdef PARTICLES
CALL CountPartsPerElem(ResetNumberOfParticles=.TRUE.) !for scaling of tParts of LB
tStage=time
RKdtFrac = RK_c(2)
dtWeight = dt/dt_Min * RKdtFrac
RKdtFracTotal=RKdtFrac

IF ((time.GE.DelayTime).OR.(iter.EQ.0)) THEN
  ! communicate shape function particles
#if USE_MPI
  PartMPIExchange%nMPIParticles=0
  IF(DoExternalParts)THEN
    ! as we do not have the shape function here, we have to deallocate something
    SDEALLOCATE(ExtPartState)
    SDEALLOCATE(ExtPartSpecies)
    SDEALLOCATE(ExtPartToFIBGM)
    SDEALLOCATE(ExtPartMPF)
    ! open receive buffer for number of particles
    CALL IRecvNbofParticles()
    ! send number of particles
    CALL SendNbOfParticles()
    ! finish communication of number of particles and send particles
    CALL MPIParticleSend()
  END IF
#endif /*USE_MPI*/
  CALL Deposition(DoInnerParts=.TRUE.) ! because of emission and UpdateParticlePosition
#if USE_MPI
  IF(DoExternalParts)THEN
    ! finish communication
    CALL MPIParticleRecv()
  END IF
  ! here: finish deposition with delta kernel
  !       maps source terms in physical space
  ! ALWAYS require
  PartMPIExchange%nMPIParticles=0
#endif /*USE_MPI*/
  CALL Deposition(DoInnerParts=.FALSE.) ! needed for closing communication
  IF(MOD(iter,PartAnalyzeStep).EQ.0)THEN ! Move this function to Deposition routine
    IF(DoVerifyCharge) CALL VerifyDepositedCharge()
  END IF
END IF
#endif /*PARTICLES*/

CALL HDG(tStage,U,iter)

#ifdef PARTICLES
! set last data already here, since surfaceflux moved before interpolation
#if USE_LOADBALANCE
CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
LastPartPos(1,1:PDM%ParticleVecLength)=PartState(1,1:PDM%ParticleVecLength)
LastPartPos(2,1:PDM%ParticleVecLength)=PartState(2,1:PDM%ParticleVecLength)
LastPartPos(3,1:PDM%ParticleVecLength)=PartState(3,1:PDM%ParticleVecLength)
PEM%lastElement(1:PDM%ParticleVecLength)=PEM%Element(1:PDM%ParticleVecLength)
#if USE_LOADBALANCE
CALL LBPauseTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/
IF (time.GE.DelayTime) THEN
  IF (DoSurfaceFlux) THEN
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    CALL SurfaceModel_main()
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_SURF,tLBStart)
#endif /*USE_LOADBALANCE*/

    CALL ParticleSurfaceflux() !dtFracPush (SurfFlux): LastPartPos and LastElem already set!
  END IF
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  CALL InterpolateFieldToParticle(DoInnerParts=.TRUE.)   ! forces on particles
  !CALL InterpolateFieldToParticle(DoInnerParts=.FALSE.) ! only needed when MPI communation changes the number of parts
#if USE_LOADBALANCE
  CALL LBSplitTime(LB_INTERPOLATION,tLBStart)
#endif /*USE_LOADBALANCE*/
  IF(DoFieldIonization) CALL FieldIonization()
  CALL CalcPartRHS()
  IF (CalcCoupledPower) PCoupl = 0. ! if output of coupled power is active: reset PCoupl
  DO iPart=1,PDM%ParticleVecLength
    IF (PDM%ParticleInside(iPart)) THEN
      ! If coupled power output is active and particle carries charge, determine its kinetic energy and store in EDiff
      IF (CalcCoupledPower) CALL CalcCoupledPowerPart(iPart,'before',EDiff)
      !-- Pt is not known only for new Surfaceflux-Parts -> change IsNewPart back to F for other Parts
      IF (.NOT.DoSurfaceFlux) THEN
        PDM%IsNewPart(iPart)=.FALSE.
      ELSE
        IF (.NOT.PDM%dtFracPush(iPart)) PDM%IsNewPart(iPart)=.FALSE.
      END IF
      !-- Particle Push
      IF (.NOT.PDM%IsNewPart(iPart)) THEN
        Pt_temp(1:3,iPart) = PartState(4:6,iPart)
        PartState(1:3,iPart) = PartState(1:3,iPart) + PartState(4:6,iPart) * b_dt(1)
        ! Don't push the velocity component of neutral particles!
        IF(isPushParticle(iPart))THEN
          Pt_temp(4:6,iPart) = Pt(1:3,iPart)
          PartState(4:6,iPart) = PartState(4:6,iPart) + Pt(1:3,iPart)*b_dt(1)
        END IF
      ELSE !IsNewPart: no Pt_temp history available!
        IF (DoSurfaceFlux .AND. PDM%dtFracPush(iPart)) THEN !SF, new in current RKStage
          CALL RANDOM_NUMBER(RandVal)
          IF (DoForceFreeSurfaceFlux) Pt(1:3,iPart)=0.
        ELSE
          CALL abort(&
__STAMP__&
,'Error in LSERK-HDG-Timedisc: This case should be impossible...')
        END IF
        Pa_rebuilt(:,:)=0.
        ! Don't push the velocity component of neutral particles!
        IF(isPushParticle(iPart))THEN
          DO iStage_loc=1,iStage
            Pa_rebuilt(1:3,iStage_loc)=Pa_rebuilt_coeff(iStage_loc)*Pt(1:3,iPart)
          END DO
        END IF
        v_rebuilt(:,:)=0.
        DO iStage_loc=iStage-1,0,-1
          IF (iStage_loc.EQ.iStage-1) THEN
            v_rebuilt(1:3,iStage_loc) = PartState(4:6,iPart) + (RandVal-1.)*b_dt(iStage_loc+1)*Pa_rebuilt(1:3,iStage_loc+1)
          ELSE
            v_rebuilt(1:3,iStage_loc) = v_rebuilt(1:3,iStage_loc+1) - b_dt(iStage_loc+1)*Pa_rebuilt(1:3,iStage_loc+1)
          END IF
        END DO
        Pv_rebuilt(:,:)=0.
        DO iStage_loc=1,iStage
          IF (iStage_loc.EQ.1) THEN
            Pv_rebuilt(1:3,iStage_loc) = v_rebuilt(1:3,0)
          ELSE
            Pv_rebuilt(1:3,iStage_loc) = v_rebuilt(1:3,iStage_loc-1) - RK_a(iStage_loc)*Pv_rebuilt(1:3,iStage_loc-1)
          END IF
        END DO
        Pt_temp(1:3,iPart) = Pv_rebuilt(1:3,iStage)
        PartState(1:3,iPart) = PartState(1:3,iPart) + Pt_temp(1:3,iPart)*b_dt(iStage)*RandVal
        ! Don't push the velocity component of neutral particles!
        IF(isPushParticle(iPart))THEN
          Pt_temp(4:6,iPart) = Pa_rebuilt(1:3,iStage)
          PartState(4:6,iPart) = PartState(4:6,iPart) + Pt_temp(4:6,iPart)*b_dt(iStage)*RandVal
        END IF
        PDM%dtFracPush(iPart) = .FALSE.
        IF (.NOT.DoForceFreeSurfaceFlux) PDM%IsNewPart(iPart) = .FALSE. !change to false: Pt_temp is now rebuilt...
      END IF !IsNewPart
      ! If coupled power output is active and particle carries charge, calculate energy difference and add to output variable
      IF (CalcCoupledPower) CALL CalcCoupledPowerPart(iPart,'after',EDiff)
    END IF
  END DO
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/

#if USE_MPI
  CALL IRecvNbofParticles() ! open receive buffer for number of particles
#endif
  IF(DoRefMapping)THEN
    CALL ParticleRefTracking()
  ELSE
    IF (TriaTracking) THEN
      CALL ParticleTriaTracking()
    ELSE
      CALL ParticleTracing()
    END IF
  END IF

  CALL UpdateSurfModelVars()

#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  CALL ParticleInserting()
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_EMISSION,tLBStart)
#endif /*USE_LOADBALANCE*/
#if USE_MPI
  CALL SendNbOfParticles() ! send number of particles
  CALL MPIParticleSend()   ! finish communication of number of particles and send particles
  CALL MPIParticleRecv()   ! finish communication
#endif
  CALL ParticleCollectCharges()
END IF

#endif /*PARTICLES*/

! perform RK steps
DO iStage=2,nRKStages
  tStage=time+dt*RK_c(iStage)
#ifdef PARTICLES
  CALL CountPartsPerElem(ResetNumberOfParticles=.FALSE.) !for scaling of tParts of LB
  IF (iStage.NE.nRKStages) THEN
    RKdtFrac = RK_c(iStage+1)-RK_c(iStage)
    RKdtFracTotal=RKdtFracTotal+RKdtFrac
  ELSE
    RKdtFrac = 1.-RK_c(nRKStages)
    RKdtFracTotal=1.
  END IF
  dtWeight = dt/dt_Min * RKdtFrac

  ! deposition
  IF (time.GE.DelayTime) THEN
    CALL Deposition(DoInnerParts=.TRUE.) ! because of emission and UpdateParticlePosition
#if USE_MPI
    ! here: finish deposition with delta kernel
    !       maps source terms in physical space
    ! ALWAYS require
    PartMPIExchange%nMPIParticles=0
#endif /*USE_MPI*/
    CALL Deposition(DoInnerParts=.FALSE.) ! needed for closing communication
  IF(MOD(iter,PartAnalyzeStep).EQ.0)THEN ! Move this function to Deposition routine
    IF(DoVerifyCharge) CALL VerifyDepositedCharge()
  END IF
  END IF
#endif /*PARTICLES*/

  CALL HDG(tStage,U,iter)

#ifdef PARTICLES
#if USE_LOADBALANCE
  CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
  ! set last data already here, since surfaceflux moved before interpolation
  LastPartPos(1:3,1:PDM%ParticleVecLength)=PartState(1:3,1:PDM%ParticleVecLength)
  PEM%lastElement(1:PDM%ParticleVecLength)=PEM%Element(1:PDM%ParticleVecLength)
#if USE_LOADBALANCE
  CALL LBPauseTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/
  IF (time.GE.DelayTime) THEN
    IF (DoSurfaceFlux)THEN
#if USE_LOADBALANCE
      CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
      CALL SurfaceModel_main()
#if USE_LOADBALANCE
      CALL LBPauseTime(LB_SURF,tLBStart)
#endif /*USE_LOADBALANCE*/
      CALL ParticleSurfaceflux() !dtFracPush (SurfFlux): LastPartPos and LastElem already set!
    END IF
    ! forces on particle
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    CALL InterpolateFieldToParticle(DoInnerParts=.TRUE.)   ! forces on particles
    !CALL InterpolateFieldToParticle(DoInnerParts=.FALSE.) ! only needed when MPI communation changes the number of parts
#if USE_LOADBALANCE
    CALL LBSplitTime(LB_INTERPOLATION,tLBStart)
#endif /*USE_LOADBALANCE*/
    CALL CalcPartRHS()
    ! particle step
    DO iPart=1,PDM%ParticleVecLength
      IF (PDM%ParticleInside(iPart)) THEN
        ! If coupled power output is active and particle carries charge, determine its kinetic energy and store in EDiff
        IF (CalcCoupledPower) CALL CalcCoupledPowerPart(iPart,'before',EDiff)
        IF (.NOT.PDM%IsNewPart(iPart)) THEN
          Pt_temp(1:3,iPart) = PartState(4:6,iPart) - RK_a(iStage) * Pt_temp(1:3,iPart)
          PartState(1:3,iPart) = PartState(1:3,iPart) + Pt_temp(1:3,iPart)*b_dt(iStage)
          ! Don't push the velocity component of neutral particles!
          IF(isPushParticle(iPart))THEN
            Pt_temp(4:6,iPart) = Pt(1:3,iPart) - RK_a(iStage) * Pt_temp(4:6,iPart)
            PartState(4:6,iPart) = PartState(4:6,iPart) + Pt_temp(4:6,iPart)*b_dt(iStage)
          END IF
        ELSE !IsNewPart: no Pt_temp history available!
          IF (DoSurfaceFlux .AND. PDM%dtFracPush(iPart)) THEN !SF, new in current RKStage
            CALL RANDOM_NUMBER(RandVal)
            PDM%dtFracPush(iPart) = .FALSE.
          ELSE !new but without SF in current RKStage (i.e., from ParticleInserting or diffusive wall reflection)
               ! -> rebuild Pt_tmp-coefficients assuming F=const. (value at last Pos) in previous stages
            RandVal=1. !"normal" particles (i.e. not from SurfFlux) are pushed with whole timestep!
          END IF
          IF (DoForceFreeSurfaceFlux) Pt(1:3,iPart)=0.
          Pa_rebuilt(:,:)=0.
          ! Don't push the velocity component of neutral particles!
          IF(isPushParticle(iPart))THEN
            DO iStage_loc=1,iStage
              Pa_rebuilt(1:3,iStage_loc)=Pa_rebuilt_coeff(iStage_loc)*Pt(1:3,iPart)
            END DO
          END IF
          v_rebuilt(:,:)=0.
          DO iStage_loc=iStage-1,0,-1
            IF (iStage_loc.EQ.iStage-1) THEN
              v_rebuilt(1:3,iStage_loc) = PartState(4:6,iPart) + (RandVal-1.)*b_dt(iStage_loc+1)*Pa_rebuilt(1:3,iStage_loc+1)
            ELSE
              v_rebuilt(1:3,iStage_loc) = v_rebuilt(1:3,iStage_loc+1) - b_dt(iStage_loc+1)*Pa_rebuilt(1:3,iStage_loc+1)
            END IF
          END DO
          Pv_rebuilt(:,:)=0.
          DO iStage_loc=1,iStage
            IF (iStage_loc.EQ.1) THEN
              Pv_rebuilt(1:3,iStage_loc) = v_rebuilt(1:3,0)
            ELSE
              Pv_rebuilt(1:3,iStage_loc) = v_rebuilt(1:3,iStage_loc-1) - RK_a(iStage_loc)*Pv_rebuilt(1:3,iStage_loc-1)
            END IF
          END DO
          Pt_temp(1:3,iPart) = Pv_rebuilt(1:3,iStage)
          PartState(1:3,iPart) = PartState(1:3,iPart) + Pt_temp(1:3,iPart)*b_dt(iStage)*RandVal
          ! Don't push the velocity component of neutral particles!
          IF(isPushParticle(iPart))THEN
            Pt_temp(4:6,iPart) = Pa_rebuilt(1:3,iStage)
            PartState(4:6,iPart) = PartState(4:6,iPart) + Pt_temp(4:6,iPart)*b_dt(iStage)*RandVal
          END IF
          IF (.NOT.DoForceFreeSurfaceFlux .OR. iStage.EQ.nRKStages) PDM%IsNewPart(iPart) = .FALSE. !change to false: Pt_temp is now rebuilt...
        END IF !IsNewPart
        ! If coupled power output is active and particle carries charge, calculate energy difference and add to output variable
        IF (CalcCoupledPower) CALL CalcCoupledPowerPart(iPart,'after',EDiff)
      END IF
    END DO
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_PUSH,tLBStart)
#endif /*USE_LOADBALANCE*/

    ! particle tracking
#if USE_MPI
    CALL IRecvNbofParticles() ! open receive buffer for number of particles
#endif
    IF(DoRefMapping)THEN
      CALL ParticleRefTracking()
    ELSE
      IF (TriaTracking) THEN
        CALL ParticleTriaTracking()
      ELSE
        CALL ParticleTracing()
      END IF
    END IF

    CALL UpdateSurfModelVars()

#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    CALL ParticleInserting()
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_EMISSION,tLBStart)
#endif /*USE_LOADBALANCE*/
#if USE_MPI
    CALL SendNbOfParticles() ! send number of particles
    CALL MPIParticleSend()   ! finish communication of number of particles and send particles
    CALL MPIParticleRecv()   ! finish communication
#endif
    CALL ParticleCollectCharges()
  END IF
#endif /*PARTICLES*/
END DO

#ifdef PARTICLES
#if USE_MPI
PartMPIExchange%nMPIParticles=0 ! and set number of received particles to zero for deposition
#endif
IF (doParticleMerge) THEN
  IF (.NOT.(useDSMC.OR.PartPressureCell)) THEN
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    ALLOCATE(PEM%pStart(1:PP_nElems)           , &
             PEM%pNumber(1:PP_nElems)          , &
             PEM%pNext(1:PDM%maxParticleNumber), &
             PEM%pEnd(1:PP_nElems) )
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_SPLITMERGE,tLBStart)
#endif /*USE_LOADBALANCE*/
  END IF
END IF

IF ((time.GE.DelayTime).OR.(iter.EQ.0)) CALL UpdateNextFreePosition()

IF (doParticleMerge) THEN
  CALL StartParticleMerge()
  IF (.NOT.(useDSMC.OR.PartPressureCell)) THEN
    DEALLOCATE(PEM%pStart , &
               PEM%pNumber, &
               PEM%pNext  , &
               PEM%pEnd   )
  END IF
  CALL UpdateNextFreePosition()
END IF

IF (useDSMC) THEN
  IF (time.GE.DelayTime) THEN
    CALL DSMC_main()
#if USE_LOADBALANCE
    CALL LBStartTime(tLBStart)
#endif /*USE_LOADBALANCE*/
    PartState(4:6,1:PDM%ParticleVecLength) = PartState(4:6,1:PDM%ParticleVecLength) + DSMC_RHS(1:3,1:PDM%ParticleVecLength)
#if USE_LOADBALANCE
    CALL LBPauseTime(LB_DSMC,tLBStart)
#endif /*USE_LOADBALANCE*/
  END IF
END IF
#endif /*PARTICLES*/

END SUBROUTINE TimeStepPoissonByLSERK
#endif /*(PP_TimeDiscMethod==501) || (PP_TimeDiscMethod==502) || (PP_TimeDiscMethod==506)*/
#endif /*USE_HDG*/


SUBROUTINE FillCFL_DFL()
!===================================================================================================================================
! scaling of the CFL number, from paper GASSNER, KOPRIVA, "A comparision of the Gauss and Gauss-Lobatto
! Discontinuous Galerkin Spectral Element Method for Wave Propagation Problems" . For N=1-10,
! input CFLscale can now be 1. and will be scaled adequately depending on PP_N, NodeType and TimeDisc method
! DFLscale dependance not implemented jet.
!===================================================================================================================================

! MODULES
USE MOD_Globals
USE MOD_PreProc
USE MOD_TimeDisc_Vars,ONLY:CFLScale,CFLtoOne
#if (PP_TimeDiscMethod==2)
USE MOD_TimeDisc_Vars,ONLY:CFLScaleAlpha
#endif
#if (PP_TimeDiscMethod==6) || (PP_TimeDiscMethod==1)
USE MOD_TimeDisc_Vars,ONLY:CFLScaleAlpha
#endif
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
! CFL in DG depends on the polynomial degree

CFLToOne=1.0/CFLScale
#if (PP_TimeDiscMethod==3)
#  if (PP_NodeType==1)
  !Gauss  Taylor DG Timeorder=SpaceOrder
  CFLscale=CFLscale*0.55*(2*PP_N+1)/(PP_N+1)
#  elif (PP_NodeType==2)
  !Gauss-Lobatto  Taylor DG Timeorder=SpaceOrder, scales with N+1
  CFLscale=CFLscale*(2*PP_N+1)/(PP_N+1)
#  endif /*PP_NodeType*/
#endif /*PP_TimeDiscMethod*/

#if (PP_TimeDiscMethod==1) || (PP_TimeDiscMethod==2)
IF(PP_N.GT.15) CALL abort(&
  __STAMP__&
  ,'Polynomial degree is to high!',PP_N,999.)
CFLScale=CFLScale*CFLScaleAlpha(PP_N)
#endif
#if (PP_TimeDiscMethod==6)
IF(PP_N.GT.15) CALL abort(&
  __STAMP__&
  ,'Polynomial degree is to high!',PP_N,999.)
CFLScale=CFLScale*CFLScaleAlpha(PP_N)
#endif
!scale with 2N+1
CFLScale = CFLScale/(2.*PP_N+1.)
SWRITE(UNIT_stdOut,'(A,ES16.7)') '   CFL:',CFLScale
END SUBROUTINE fillCFL_DFL


SUBROUTINE InitTimeStep()
!===================================================================================================================================
!initial time step calculations for new timedisc-loop
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_TimeDisc_Vars,      ONLY: dt, dt_Min
USE MOD_TimeDisc_Vars,      ONLY: sdtCFLOne
#if !(USE_HDG)
USE MOD_CalcTimeStep,       ONLY:CalcTimeStep
USE MOD_TimeDisc_Vars,      ONLY: CFLtoOne
#endif
#ifdef PARTICLES
USE MOD_Particle_Vars,      ONLY: ManualTimeStep, useManualTimestep
#endif /*PARTICLES*/
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
#ifdef PARTICLES
! For tEnd != tStart we have to advance the solution in time
IF(useManualTimeStep)THEN
  ! particle time step is given externally and not calculated through the solver
  dt_Min=ManualTimeStep
ELSE ! .NO. ManualTimeStep
#endif /*PARTICLES*/
  ! time step is calculated by the solver
  ! first Maxwell time step for explicit LSRK
#if !(USE_HDG)
  dt_Min    = CalcTimeStep()
  sdtCFLOne = 1.0/(dt_Min*CFLtoOne)
#else
  dt_Min    = 0
  sdtCFLOne = -1.0 !dummy for HDG!!!
#endif /*USE_HDG*/

  dt=dt_Min
  ! calculate time step for sub-cycling of divergence correction
  ! automatic particle time step of quasi-stationary time integration is not implemented
#ifdef PARTICLES
END IF ! useManualTimestep

#endif /*PARTICLES*/

SWRITE(UNIT_StdOut,'(132("-"))')
SWRITE(UNIT_StdOut,'(A,ES16.7)')'Initial Timestep  : ', dt_Min
! using sub-cycling requires an addional time step
SWRITE(UNIT_StdOut,*)'CALCULATION RUNNING...'
END SUBROUTINE InitTimeStep


SUBROUTINE WriteInfoStdOut()
!===================================================================================================================================
!> writes information to console std_out
!===================================================================================================================================
! MODULES
USE MOD_Globals
USE MOD_Globals_Vars           ,ONLY: SimulationEfficiency,PID
USE MOD_PreProc
USE MOD_TimeDisc_Vars          ,ONLY: iter,dt_Min
#if defined(IMPA) || defined(ROS)
USE MOD_LinearSolver_Vars      ,ONLY: totalIterLinearSolver
#endif /*IMPA || ROS*/
#ifdef PARTICLES
USE MOD_Particle_Tracking_vars ,ONLY: CountNbOfLostParts,nLostParts
#ifdef IMPA
USE MOD_LinearSolver_vars      ,ONLY: nPartNewton
USE MOD_LinearSolver_Vars      ,ONLY: totalFullNewtonIter
#endif /*IMPA*/
#if defined(IMPA) || defined(ROS)
USE MOD_LinearSolver_Vars      ,ONLY: TotalPartIterLinearSolver
#endif /*IMPA || ROS*/
#endif /*PARTICLES*/
! IMPLICIT VARIABLE HANDLINGDGInitIsDone
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                      :: TimeArray(8)              ! Array for system time
#ifdef PARTICLES
INTEGER                      :: nLostPartsTot
#endif /*PARTICLES*/
!===================================================================================================================================
#ifdef PARTICLES
IF(CountNbOfLostParts)THEN
#if USE_MPI
  IF(MPIRoot) THEN
    CALL MPI_REDUCE(nLostParts,nLostPartsTot,1,MPI_INTEGER,MPI_SUM,0,MPI_COMM_WORLD,IERROR)
  ELSE ! no Root
    CALL MPI_REDUCE(nLostParts,nLostPartsTot,1,MPI_INTEGER,MPI_SUM,0,MPI_COMM_WORLD,IERROR)
  END IF
#else
  nLostPartsTot=nLostParts
#endif /*USE_MPI*/
END IF
#endif /*PARICLES*/
IF(MPIroot)THEN
  ! simulation time per CPUh efficiency in [s]/[CPUh]
  !SimulationEfficiency = (time-RestartTime)/((WallTimeEnd-StartTime)*nProcessors/3600.) ! in [s] / [CPUh]
  ! Get calculation time per DOF
  !PID=(WallTimeEnd-WallTimeStart)*nProcessors/(nGlobalElems*(PP_N+1)**3*iter_PID)
  CALL DATE_AND_TIME(values=TimeArray) ! get System time
  WRITE(UNIT_StdOut,'(132("-"))')
  WRITE(UNIT_stdOut,'(A,I2.2,A1,I2.2,A1,I4.4,A1,I2.2,A1,I2.2,A1,I2.2)') &
    ' Sys date  :    ',TimeArray(3),'.',TimeArray(2),'.',TimeArray(1),' ',TimeArray(5),':',TimeArray(6),':',TimeArray(7)
  WRITE(UNIT_stdOut,'(A,ES12.5,A)')' PID: CALCULATION TIME PER TSTEP/DOF: [',PID,' sec ]'
  WRITE(UNIT_stdOut,'(A,ES12.5,A)')' EFFICIENCY: SIMULATION TIME PER CALCULATION in [s]/[Core-h]: [',SimulationEfficiency,&
                                                                                        ' sec/h ]'
  WRITE(UNIT_StdOut,'(A,ES16.7)')' Timestep  : ',dt_Min
  WRITE(UNIT_stdOut,'(A,ES16.7)')'#Timesteps : ',REAL(iter)
#ifdef PARTICLES
  IF(CountNbOfLostParts)THEN
    WRITE(UNIT_stdOut,'(A,I12)')' NbOfLostParticle : ',nLostPartsTot
  END IF
#endif /*PARICLES*/
END IF !MPIroot
#if defined(IMPA) || defined(ROS)
SWRITE(UNIT_stdOut,'(132("="))')
SWRITE(UNIT_stdOut,'(A32,I12)') ' Total iteration Linear Solver    ',totalIterLinearSolver
TotalIterLinearSolver=0
#endif /*IMPA && ROS*/
#if defined(IMPA) && defined(PARTICLES)
SWRITE(UNIT_stdOut,'(A32,I12)')  ' IMPLICIT PARTICLE TREATMENT    '
SWRITE(UNIT_stdOut,'(A32,I12)')  ' Total iteration Newton         ',nPartNewton
SWRITE(UNIT_stdOut,'(A32,I12)')  ' Total iteration GMRES          ',TotalPartIterLinearSolver
IF(nPartNewton.GT.0)THEN
  SWRITE(UNIT_stdOut,'(A35,F12.2)')' Average GMRES steps per Newton    ',REAL(TotalPartIterLinearSolver)&
                                                                        /REAL(nPartNewton)
END IF
nPartNewTon=0
TotalPartIterLinearSolver=0
#if IMPA
SWRITE(UNIT_stdOut,'(A32,I12)')  ' Total iteration outer-Newton    ',TotalFullNewtonIter
totalFullNewtonIter=0
#endif
SWRITE(UNIT_stdOut,'(132("="))')
#endif /*IMPA && PARTICLE*/
#if defined(ROS) && defined(PARTICLES)
SWRITE(UNIT_stdOut,'(A32,I12)')  ' IMPLICIT PARTICLE TREATMENT    '
SWRITE(UNIT_stdOut,'(A32,I12)')  ' Total iteration GMRES          ',TotalPartIterLinearSolver
TotalPartIterLinearSolver=0
SWRITE(UNIT_stdOut,'(132("="))')
#endif /*IMPA && PARTICLE*/
END SUBROUTINE WriteInfoStdOut


END MODULE MOD_TimeDisc
