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

MODULE MOD_Piclas_Init
!===================================================================================================================================
! contains global init and finalize
!===================================================================================================================================

INTERFACE InitPiclas
  MODULE PROCEDURE InitPiclas
END INTERFACE

INTERFACE FinalizePiclas
   MODULE PROCEDURE FinalizePiclas
END INTERFACE

PUBLIC:: FinalizePiclas
PUBLIC:: InitPiclas
!===================================================================================================================================
!PUBLIC:: InitDefineParameters

CONTAINS

!==================================================================================================================================
!> Define parameters.
!==================================================================================================================================
SUBROUTINE DefineParametersPiclas()
! MODULES
USE MOD_ReadInTools ,ONLY: prms
IMPLICIT NONE
!==================================================================================================================================
CALL prms%SetSection("Piclas Initialization")

CALL prms%CreateIntOption(      'TimeStampLength', 'Length of the floating number time stamp', '21')
#ifdef PARTICLES
CALL prms%CreateLogicalOption(  'UseDSMC'        , "Flag for using DSMC in Calculation", '.FALSE.')
#endif

END SUBROUTINE DefineParametersPiclas




SUBROUTINE InitPiclas(IsLoadBalance)
!----------------------------------------------------------------------------------------------------------------------------------!
! init Piclas data structure
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals
USE MOD_Globals_Vars         ,ONLY: TimeStampLenStr,TimeStampLenStr2
USE MOD_Preproc
USE MOD_ReadInTools          ,ONLY: prms
USE MOD_Interpolation_Vars   ,ONLY: InterpolationInitIsDone
USE MOD_Restart_Vars         ,ONLY: RestartInitIsDone
USE MOD_Restart              ,ONLY: InitRestart
USE MOD_Restart_Vars         ,ONLY: DoRestart
USE MOD_Mesh                 ,ONLY: InitMesh
USE MOD_Equation             ,ONLY: InitEquation
USE MOD_GetBoundaryFlux      ,ONLY: InitBC
USE MOD_DG                   ,ONLY: InitDG
USE MOD_Mortar               ,ONLY: InitMortar
#if ! (USE_HDG)
USE MOD_PML                  ,ONLY: InitPML
#endif /*USE_HDG*/
USE MOD_Dielectric           ,ONLY: InitDielectric
USE MOD_Filter               ,ONLY: InitFilter
USE MOD_Analyze              ,ONLY: InitAnalyze
USE MOD_RecordPoints         ,ONLY: InitRecordPoints
#if defined(ROS) || defined(IMPA)
USE MOD_LinearSolver         ,ONLY: InitLinearSolver
#endif /*ROS or IMPA*/
USE MOD_Restart_Vars         ,ONLY: N_Restart,InterpolateSolution,RestartNullifySolution
#if USE_MPI
USE MOD_MPI                  ,ONLY: InitMPIvars
#endif /*USE_MPI*/
#ifdef PARTICLES
USE MOD_DSMC_Vars            ,ONLY: UseDSMC, RadialWeighting
USE MOD_Particle_Vars        ,ONLY: Symmetry2D, Symmetry2DAxisymmetric, VarTimeStep
USE MOD_Particle_VarTimeStep ,ONLY: VarTimeStep_Init
USE MOD_ParticleInit         ,ONLY: InitParticles
USE MOD_TTMInit              ,ONLY: InitTTM,InitIMD_TTM_Coupling
USE MOD_TTM_Vars             ,ONLY: DoImportTTMFile
USE MOD_Particle_Surfaces    ,ONLY: InitParticleSurfaces
USE MOD_Particle_Mesh        ,ONLY: InitParticleMesh, InitElemBoundingBox
USE MOD_Particle_Analyze     ,ONLY: InitParticleAnalyze
USE MOD_SurfaceModel_Analyze ,ONLY: InitSurfModelAnalyze
USE MOD_Particle_MPI         ,ONLY: InitParticleMPI
#if defined(IMPA) || defined(ROS)
USE MOD_ParticleSolver       ,ONLY: InitPartSolver
#endif
#endif
#if USE_HDG
USE MOD_HDG                  ,ONLY: InitHDG
#endif
USE MOD_Interfaces           ,ONLY: InitInterfaces
#if USE_QDS_DG
USE MOD_QDS                  ,ONLY: InitQDS
#endif /*USE_QDS_DG*/
USE MOD_ReadInTools          ,ONLY: GETLOGICAL,GETREALARRAY,GETINT
!----------------------------------------------------------------------------------------------------------------------------------!
IMPLICIT NONE
! INPUT VARIABLES
LOGICAL,INTENT(IN)      :: IsLoadBalance
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
INTEGER                 :: TimeStampLength
!===================================================================================================================================
! Get length of the floating number time stamp
TimeStampLength = GETINT('TimeStampLength')
IF((TimeStampLength.LT.4).OR.(TimeStampLength.GT.30)) CALL abort(&
    __STAMP__&
    ,'TimeStampLength cannot be smaller than 4 and not larger than 30')
WRITE(UNIT=TimeStampLenStr ,FMT='(I0)') TimeStampLength
WRITE(UNIT=TimeStampLenStr2,FMT='(I0)') TimeStampLength-4

#ifdef PARTICLES
! DSMC handling:
useDSMC=GETLOGICAL('UseDSMC','.FALSE.')

!--- Flags for planar/axisymmetric simulation (2D)
Symmetry2D = GETLOGICAL('Particles-Symmetry2D')
Symmetry2DAxisymmetric = GETLOGICAL('Particles-Symmetry2DAxisymmetric')
IF(Symmetry2DAxisymmetric.AND.(.NOT.Symmetry2D)) THEN
  Symmetry2D = .TRUE.
END IF
IF(Symmetry2DAxisymmetric) THEN
  RadialWeighting%DoRadialWeighting = GETLOGICAL('Particles-RadialWeighting')
ELSE
  RadialWeighting%DoRadialWeighting = .FALSE.
  RadialWeighting%PerformCloning = .FALSE.
END IF

#endif /*PARTICLES*/

! Initialization
!CALL InitInterpolation()
IF(IsLoadBalance)THEN
  DoRestart=.TRUE.
  RestartInitIsDone=.TRUE.
  InterpolationInitIsDone=.TRUE.
  RestartNullifySolution=.FALSE.
  !BuildNewMesh       =.FALSE. !not used anymore?
  !WriteNewMesh       =.FALSE. !not used anymore?
  InterpolateSolution=.FALSE.
  N_Restart=PP_N
  CALL InitMortar()
ELSE
  CALL InitMortar()
  CALL InitRestart()
END IF

#ifdef PARTICLES
!--- Variable time step
VarTimeStep%UseLinearScaling = GETLOGICAL('Part-VariableTimeStep-LinearScaling')
VarTimeStep%UseDistribution = GETLOGICAL('Part-VariableTimeStep-Distribution')
IF (VarTimeStep%UseLinearScaling.OR.VarTimeStep%UseDistribution)  THEN
  VarTimeStep%UseVariableTimeStep = .TRUE.
  IF(.NOT.IsLoadBalance) CALL VarTimeStep_Init()
ELSE
  VarTimeStep%UseVariableTimeStep = .FALSE.
END IF
#endif

CALL InitMesh(2)
#if USE_MPI
CALL InitMPIVars()
#endif /*USE_MPI*/
#ifdef PARTICLES
!#if USE_MPI
CALL InitParticleMPI
CALL InitElemBoundingBox()
!#endif /*USE_MPI*/
CALL InitParticleSurfaces()
!CALL InitParticleMesh()
#endif /*PARTICLES*/
CALL InitEquation()
CALL InitBC()
!#ifdef PARTICLES
!CALL InitParticles()
!#endif
#if !(USE_HDG)
CALL InitPML() ! Perfectly Matched Layer (PML): electromagnetic-wave-absorbing layer
#endif /*USE_HDG*/
CALL InitDielectric() ! Dielectric media
CALL InitDG()
CALL InitFilter()
!CALL InitTimeDisc()
#if defined(ROS) || defined(IMPA)
CALL InitLinearSolver()
#endif /*ROS /IMEX*/
!#if defined(IMEX)
!CALL InitCSR()
!#endif /*IMEX*/
#ifdef PARTICLES
CALL InitParticles()
#if defined(IMPA) || defined(ROS)
CALL InitPartSolver()
#endif
!CALL GetSideType
#endif
CALL InitAnalyze()
CALL InitRecordPoints()
#ifdef PARTICLES
CALL InitParticleAnalyze()
CALL InitSurfModelAnalyze()
#endif

#if USE_HDG
CALL InitHDG()
#endif

#ifdef PARTICLES
  CALL InitTTM() ! FD grid based data from a Two-Temperature Model (TTM) from Molecular Dynamics (MD) Code IMD
IF(DoImportTTMFile)THEN
  CALL InitIMD_TTM_Coupling() ! use MD and TTM data to distribute the cell averaged charge to the atoms/ions
END IF
#endif /*PARTICLES*/

CALL InitInterfaces() ! set riemann solver identifier for face connectivity (vacuum, dielectric, PML ...)

#if USE_QDS_DG
CALL InitQDS()
#endif /*USE_QDS_DG*/

! do this last!
!CALL IgnoredStrings()
! write out parameters that are not used and remove multiple and unused, that are not needed to do restart if no parameter.ini is
! read in
IF (.NOT.IsLoadBalance) THEN
  CALL prms%WriteUnused()
  CALL prms%RemoveUnnecessary()
END IF

END SUBROUTINE InitPiclas


SUBROUTINE FinalizePiclas(IsLoadBalance)
!----------------------------------------------------------------------------------------------------------------------------------!
! finalize Piclas data structure
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Commandline_Arguments      ,ONLY: FinalizeCommandlineArguments
USE MOD_Globals
USE MOD_ReadInTools                ,ONLY: prms,FinalizeParameters
USE MOD_Restart                    ,ONLY: FinalizeRestart
USE MOD_Interpolation              ,ONLY: FinalizeInterpolation
USE MOD_Mesh                       ,ONLY: FinalizeMesh
USE MOD_Equation                   ,ONLY: FinalizeEquation
USE MOD_Interfaces                 ,ONLY: FinalizeInterfaces
#if USE_QDS_DG
USE MOD_QDS                        ,ONLY: FinalizeQDS
#endif /*USE_QDS_DG*/
USE MOD_GetBoundaryFlux            ,ONLY: FinalizeBC
USE MOD_DG                         ,ONLY: FinalizeDG
USE MOD_Mortar                     ,ONLY: FinalizeMortar
USE MOD_Dielectric                 ,ONLY: FinalizeDielectric
#if ! (USE_HDG)
USE MOD_PML                        ,ONLY: FinalizePML
#else
USE MOD_HDG                        ,ONLY: FinalizeHDG
#endif /*USE_HDG*/
USE MOD_Filter                     ,ONLY: FinalizeFilter
USE MOD_Analyze                    ,ONLY: FinalizeAnalyze
USE MOD_RecordPoints               ,ONLY: FinalizeRecordPoints
USE MOD_RecordPoints_Vars          ,ONLY: RP_Data
#if defined(ROS) || defined(IMPA)
USE MOD_LinearSolver               ,ONLY: FinalizeLinearSolver
#endif /*IMEX*/
#if USE_MPI
USE MOD_MPI                        ,ONLY: FinalizeMPI
#endif /*USE_MPI*/
#ifdef PARTICLES
USE MOD_Particle_Surfaces          ,ONLY: FinalizeParticleSurfaces
USE MOD_InitializeBackgroundField  ,ONLY: FinalizeBackGroundField
USE MOD_SuperB_Init                ,ONLY: FinalizeSuperB
USE MOD_Particle_Mesh              ,ONLY: FinalizeParticleMesh
USE MOD_Particle_Analyze           ,ONLY: FinalizeParticleAnalyze
USE MOD_PICDepo                    ,ONLY: FinalizeDeposition
USE MOD_ParticleInit               ,ONLY: FinalizeParticles
USE MOD_TTMInit                    ,ONLY: FinalizeTTM
USE MOD_DSMC_Init                  ,ONLY: FinalizeDSMC
USE MOD_MacroBody_Init             ,ONLY:FinalizeMacroBody
USE MOD_Particle_Boundary_Porous   ,ONLY:FinalizePorousBoundaryCondition
#if (PP_TimeDiscMethod==300)
USE MOD_FPFlow_Init                ,ONLY: FinalizeFPFlow
#endif
#if (PP_TimeDiscMethod==400)
USE MOD_BGK_Init                   ,ONLY: FinalizeBGK
#endif
USE MOD_SurfaceModel_Init          ,ONLY: FinalizeSurfaceModel
USE MOD_Particle_Boundary_Sampling ,ONLY: FinalizeParticleBoundarySampling
USE MOD_Particle_Vars              ,ONLY: ParticlesInitIsDone
USE MOD_PIC_Vars                   ,ONLY: PICInitIsDone
#if USE_MPI
USE MOD_Particle_MPI               ,ONLY: FinalizeParticleMPI
USE MOD_Particle_MPI_Vars          ,ONLY: ParticleMPIInitisdone
#endif /*USE_MPI*/
#endif /*PARTICLES*/
USE MOD_IO_HDF5                    ,ONLY: ClearElemData,ElementOut
!----------------------------------------------------------------------------------------------------------------------------------!
IMPLICIT NONE
! INPUT VARIABLES
LOGICAL,INTENT(IN)      :: IsLoadBalance
!----------------------------------------------------------------------------------------------------------------------------------!
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL                    :: Time
!===================================================================================================================================
CALL ClearElemData(ElementOut)
!Finalize
CALL FinalizeRecordPoints()
CALL FinalizeAnalyze()
CALL FinalizeDG()
#if defined(IMPA) || defined(ROS)
!CALL FinalizeCSR()
CALL FinalizeLinearSolver()
#endif /*IMEX*/
#if !(USE_HDG)
CALL FinalizePML()
#else
CALL FinalizeDielectric()
CALL FinalizeHDG()
#endif /*USE_HDG*/
CALL FinalizeEquation()
CALL FinalizeBC()
IF(.NOT.IsLoadBalance) CALL FinalizeInterpolation()
!CALL FinalizeTimeDisc()
CALL FinalizeRestart()
CALL FinalizeMesh()
CALL FinalizeMortar()
CALL FinalizeFilter()
#ifdef PARTICLES
CALL FinalizeSurfaceModel()
CALL FinalizeParticleBoundarySampling()
CALL FinalizePorousBoundaryCondition()
CALL FinalizeParticleSurfaces()
CALL FinalizeParticleMesh()
CALL FinalizeParticleAnalyze()
CALL FinalizeDeposition()
#if USE_MPI
CALL FinalizeParticleMPI()
#endif /*USE_MPI*/
CALL FinalizeDSMC()
#if (PP_TimeDiscMethod==300)
CALL FinalizeFPFlow()
#endif
#if (PP_TimeDiscMethod==400)
CALL FinalizeBGK()
#endif
CALL FinalizeParticles()
CALL FinalizeMacroBody()
CALL FinalizeBackGroundField()
CALL FinalizeSuperB()
#endif /*PARTICLES*/
#if USE_MPI
CALL FinalizeMPI()
#endif /*USE_MPI*/

#ifdef PARTICLES
ParticlesInitIsDone = .FALSE.
PICInitIsDone = .FALSE.
#if USE_MPI
ParticleMPIInitIsDone=.FALSE.
#endif /*USE_MPI*/

CALL FinalizeTTM() ! FD grid based data from a Two-Temperature Model (TTM) from Molecular Dynamics (MD) Code IMD
#endif /*PARTICLES*/

CALL FinalizeInterfaces()
#if USE_QDS_DG
CALL FinalizeQDS()
#endif /*USE_QDS_DG*/
CALL prms%finalize(IsLoadBalance) ! is the same as CALL FinalizeParameters(), but considers load balancing
CALL FinalizeCommandlineArguments()

CALL FinalizeTimeDisc()
! mssing arrays to deallocate
SDEALLOCATE(RP_Data)

! Before program termination: Finalize load balance
! Measure simulation duration
Time=PICLASTIME()
SWRITE(UNIT_stdOut,'(132("="))')
IF(.NOT.IsLoadBalance)THEN
#if USE_LOADBALANCE
  !! and additional required for restart with load balance
  !ReadInDone=.FALSE.
  !ParticleMPIInitIsDone=.FALSE.
  !ParticlesInitIsDone=.FALSE.
  CALL FinalizeLoadBalance()
#endif /*USE_LOADBALANCE*/
  SWRITE(UNIT_stdOut,'(A,F14.2,A)')  ' PICLAS FINISHED! [',Time-StartTime,' sec ]'
ELSE
  SWRITE(UNIT_stdOut,'(A,F14.2,A)')  ' PICLAS RUNNING! [',Time-StartTime,' sec ]'
END IF ! .NOT.IsLoadBalance
SWRITE(UNIT_stdOut,'(132("="))')

END SUBROUTINE FinalizePiclas


#if USE_LOADBALANCE
SUBROUTINE FinalizeLoadBalance()
!===================================================================================================================================
! Deallocate arrays
!===================================================================================================================================
! MODULES
USE MOD_LoadBalance_Vars
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! INPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
SDEALLOCATE(tCurrent)
InitLoadBalanceIsDone = .FALSE.

END SUBROUTINE FinalizeLoadBalance
#endif /*USE_LOADBALANCE*/


SUBROUTINE FinalizeTimeDisc()
!===================================================================================================================================
! Finalizes variables necessary for analyse subroutines
!===================================================================================================================================
! MODULES
USE MOD_TimeDisc_Vars,ONLY:TimeDiscInitIsDone
! IMPLICIT VARIABLE HANDLINGDGInitIsDone
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! OUTPUT VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
!===================================================================================================================================
TimeDiscInitIsDone = .FALSE.
END SUBROUTINE FinalizeTimeDisc


END MODULE MOD_Piclas_Init
