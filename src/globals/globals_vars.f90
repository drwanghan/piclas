#include "boltzplatz.h"

MODULE MOD_Globals_Vars
!===================================================================================================================================
! Provides parameters, used globally (please use EXTREMLY carefully!) 
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES 
!-----------------------------------------------------------------------------------------------------------------------------------
REAL                                  :: PI
REAL                                  :: sPI
REAL                                  :: epsMach,TwoepsMach
REAL,PARAMETER                       :: EuMas = 0.577215664901533_8                        ! Euler-Mascheroni constant
REAL,PARAMETER                       :: PlanckConst = 6.62606957E-34                        ! Planck constant [J s] SI-Unit!
!===================================================================================================================================

!CONTAINS

END MODULE MOD_Globals_Vars
