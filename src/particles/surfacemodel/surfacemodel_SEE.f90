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

MODULE MOD_SEE
!===================================================================================================================================
!> Main Routines of Surface Model: Secondary Electron Emission (SEE) due to particle bombardment
!===================================================================================================================================
! MODULES
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PRIVATE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
! Private Part ---------------------------------------------------------------------------------------------------------------------
! Public Part ----------------------------------------------------------------------------------------------------------------------
PUBLIC :: SecondaryElectronEmission
!===================================================================================================================================

CONTAINS

SUBROUTINE SecondaryElectronEmission(PartSurfaceModel_IN,PartID_IN,locBCID,Adsorption_prob_OUT,interactionCase,ProductSpec,ProductSpecNbr,&
           v_new,velocityDistribution)
!----------------------------------------------------------------------------------------------------------------------------------!
! Determine the probability of an electron being emitted due to an impacting particles (ion/electron bombardment)
!----------------------------------------------------------------------------------------------------------------------------------!
! MODULES                                                                                                                          !
!----------------------------------------------------------------------------------------------------------------------------------!
USE MOD_Globals           ,ONLY: abort
USE MOD_Equation_vars     ,ONLY: c
USE MOD_Particle_Vars     ,ONLY: PartState,Species,PartSpecies
USE MOD_Particle_Analyze  ,ONLY: PartIsElectron
USE MOD_Globals_Vars      ,ONLY: ElementaryCharge,ElectronMass
USE MOD_SurfaceModel_Vars ,ONLY: Adsorption
!----------------------------------------------------------------------------------------------------------------------------------!
IMPLICIT NONE
! INPUT / OUTPUT VARIABLES
INTEGER,INTENT(IN)      :: PartSurfaceModel_IN !< which SEE model?
                                               !< 5: SEE by Levko2015
                                               !< 6: SEE by Pagonakis2016 (originally from Harrower1956)
INTEGER,INTENT(IN)      :: PartID_IN           !< Bombarding Particle ID
REAL   ,INTENT(OUT)     :: Adsorption_prob_OUT !< probability of an electron being emitted due to an impacting particles
                                               !< (ion/electron bombardment)
INTEGER,INTENT(OUT)     :: interactionCase     !< what happens to the bombarding particle and is a new one created?
INTEGER,INTENT(OUT)     :: ProductSpec(2)      !< ProductSpec(1) new ID of impacting particle (the old one can change)
                                               !< ProductSpec(2) new ID of newly released electron
INTEGER,INTENT(OUT)     :: ProductSpecNbr      !< number of species for ProductSpec(1)
REAL,INTENT(OUT)        :: v_new  ! Velocity of emitted secondary electron
CHARACTER(LEN=*),INTENT(OUT)   :: velocityDistribution(2) !< Name of veloctiy distribution of reflected and newly created electron
INTEGER,INTENT(IN)             :: locBCID
!-----------------------------------------------------------------------------------------------------------------------------------
! LOCAL VARIABLES
REAL              :: eps_e  ! Energy of bombarding electron in eV
REAL              :: iRan   ! Random number
REAL              :: k_ee   ! Coefficient of emission of secondary electron
REAL              :: k_refl ! Coefficient for reflection of bombarding electron
!===================================================================================================================================
! Default 0
ProductSpec    = 0
ProductSpecNbr = 0
v_new          = 0.0
Adsorption_prob_OUT = 0. ! default
! Select particle surface modeling
SELECT CASE(PartSurfaceModel_IN)
CASE(5) ! 5: SEE by Levko2015 for copper electrodes
  !     ! D. Levko and L. L. Raja, Breakdown of atmospheric pressure microgaps at high excitation, J. Appl. Phys. 117, 173303 (2015)

  ProductSpec(1)  = PartSpecies(PartID_IN) ! old particle
  interactionCase = 3
  velocityDistribution(1) = ''
  velocityDistribution(2) = 'deltadistribution'


  ASSOCIATE (&
        phi            => 4.4  ,& ! eV -> cathode work function phi Ref. [20] Y. P. Raizer, Gas Discharge Physics (Springer, 1991)
        I              => 15.6  & ! eV -> ionization threshold of N2
        )
    IF(PARTISELECTRON(PartID_IN))THEN ! Bombarding electron
      ASSOCIATE (&
            delta_star_max => 1.06 ,& !    -> empir. fit. const. copper electrode Ref, [19] R. Cimino et al.,Phys.Rev.Lett. 2004
            s              => 1.35 ,& !    -> empir. fit. const. copper electrode Ref, [19] R. Cimino et al.,Phys.Rev.Lett. 2004
            eps_max        => 262  ,& ! eV -> empir. fit. const. copper electrode Ref, [19] R. Cimino et al.,Phys.Rev.Lett. 2004
            eps_0          => 150  ,& ! eV -> empir. fit. const. copper electrode Ref, [19] R. Cimino et al.,Phys.Rev.Lett. 2004
            velo2          => PartState(4,PartID_IN)**2 + PartState(5,PartID_IN)**2 + PartState(6,PartID_IN)**2 ,&
            mass           => Species(PartSpecies(PartID_IN))%MassIC &! mass of bombarding particle
            )
        ! Electron energy in [eV]
        eps_e = 0.5*mass*velo2/ElementaryCharge
        ! Calculate the electron impact coefficient
        IF(eps_e.LE.5)THEN ! Electron energy <= 5 eV
          k_ee = 0.
        ELSE
          k_ee = delta_star_max*s*( (eps_e/eps_max)/(s-1.+(eps_e/eps_max)**s) )
        END IF
        ! Calculate the elastic electron reflection coefficient
        k_refl = (SQRT(eps_e)-SQRT(eps_e+eps_0))**2/((SQRT(eps_e)+SQRT(eps_e+eps_0))**2)
        ! Decide SEE and/or reflection
        CALL RANDOM_NUMBER(iRan)
        IF(iRan.LT.(k_ee+k_refl))THEN ! Either SEE-E or reflection
          CALL RANDOM_NUMBER(iRan)
          IF(iRan.LT.k_ee/(k_ee+k_refl))THEN ! SEE
            !interactionCase = 3 ! SEE + perfect elastic scattering of the bombarding electron
            ProductSpec(2)  = Adsorption%ResultSpec(locBCID,PartSpecies(PartID_IN))  ! Species of the injected electron
            ProductSpecNbr = 1
            v_new           = SQRT(2.*(eps_e*ElementaryCharge-ElementaryCharge*phi)/ElectronMass) ! Velocity of emitted secondary electron
            eps_e           = 0.5*mass*(v_new**2)/ElementaryCharge               ! Energy of the injected electron
!WRITE (*,*) CHAR(27) // "[0;34mPartID_IN                  =", PartID_IN,CHAR(27),"[m"
!WRITE (*,*) CHAR(27) // "[0;34mPartState(1:3,PartID_IN)   =", PartState(1:3,PartID_IN),CHAR(27),"[m"
!WRITE (*,*) CHAR(27) // "[0;34mPartState(4:6,PartID_IN)   =", PartState(4:6,PartID_IN),CHAR(27),"[m"
!WRITE (*,*) CHAR(27) // "[0;34mBombarding electron: v_new =", v_new,CHAR(27),"[m"
!WRITE (*,*) CHAR(27) // "[0;34m                     eps_e =", eps_e,CHAR(27),"[m"
          ELSE ! Only perfect elastic scattering of the bombarding electron
            interactionCase = 2 ! Only perfect elastic scattering of the bombarding electron
            ProductSpecNbr = 0 ! do not create new particle
          END IF
          ! Original Code as described in the paper by Levko (2015)
          !   IF(k_refl.LT.k_ee)THEN ! -> region with a high chance of SEE
          !     IF(iRan.LT.k_refl/(k_ee+k_refl))THEN ! Reflection
          !       interactionCase = -1 ! only perfect elastic scattering of the bombarding electron
          !     ELSE ! SEE-E
          !       interactionCase = -2 ! SEE + perfect elastic scattering of the bombarding electron
          !       ProductSpec(2)      = 4
          !     END IF
          !   ELSE ! (k_ee.LE.k_refl) -> region with a high chance of reflection
          !     IF(iRan.LT.k_ee/(k_ee+k_refl))THEN ! SEE
          !       interactionCase = -2 ! SEE + perfect elastic scattering of the bombarding electron
          !       ProductSpec(2)      = 4
          !     ELSE ! Reflection
          !       interactionCase = -1 ! only perfect elastic scattering of the bombarding electron
          !     END IF
          !   END IF
        ELSE ! Removal of the bombarding electron
          !interactionCase = 3 ! Removal of the bombarding electron
          ProductSpec(1) = 0 ! just for sanity check
        END IF
      END ASSOCIATE
    ELSEIF(Species(PartSpecies(PartID_IN))%ChargeIC.NE.0.0)THEN ! Positive bombarding ion
      CALL RANDOM_NUMBER(iRan)
      !IF(iRan.LT.1.)THEN ! SEE-I: gamma=0.02 for the N2^+ ions and copper material
      IF(iRan.LT.0.02)THEN ! SEE-I: gamma=0.02 for the N2^+ ions and copper material
        !interactionCase = -2       ! SEE + perfect elastic scattering of the bombarding electron
        ProductSpec(2)  = Adsorption%ResultSpec(locBCID,PartSpecies(PartID_IN))  ! Species of the injected electron
        ProductSpecNbr = 1
        eps_e           = I-2.*phi ! Energy of the injected electron
        v_new           = SQRT(2.*(eps_e*ElementaryCharge-ElementaryCharge*phi)/ElectronMass) ! Velocity of emitted secondary electron
!WRITE (*,*) CHAR(27) // "[0;34mPartID_IN                  =", PartID_IN,CHAR(27),"[m"
!WRITE (*,*) CHAR(27) // "[0;31mPartState(1:3,PartID_IN) =", PartState(1:3,PartID_IN),CHAR(27),"[m"
!WRITE (*,*) CHAR(27) // "[0;31mPartState(4:6,PartID_IN) =", PartState(4:6,PartID_IN),CHAR(27),"[m"
!WRITE (*,*) CHAR(27) // "[0;31mPositive bombarding ion: v_new =", v_new,CHAR(27),"[m"
!WRITE (*,*) CHAR(27) // "[0;31m                         eps_e =", eps_e,CHAR(27),"[m"
      ELSE ! Removal of the bombarding ion
        !interactionCase = -1 ! Only perfect elastic scattering of the bombarding electron
        ProductSpec(1)  = -PartSpecies(PartID_IN) ! remove and sample
        interactionCase = 3 ! Removal of the bombarding ion
        ProductSpecNbr = 0 ! do not create new particle
      END IF
    ELSE ! Neutral bombarding particle
    !  IF(iRan.LT.0.1)THEN ! SEE-N: from svn-trunk PICLas version
    !    !interactionCase = -2 ! SEE + perfect elastic scattering of the bombarding electron
    !    ProductSpec(2)  = Adsorption%ResultSpec(locBCID,PartSpecies(PartID_IN))  ! Species of the injected electron
    !    ProductSpecNbr = 1
    !  ELSE
    !    !interactionCase = -1 ! Only perfect elastic scattering of the bombarding electron
    !    interactionCase = -1 ! Removal of the bombarding neutral
        ProductSpecNbr = 0 ! do not create new particle
    !    WRITE (*,*) "Neutral bombarding particle =", PartID_IN
    !    stop "stop"
    !  END IF
    END IF
  END ASSOCIATE
CASE(6) ! 6: SEE by Pagonakis2016 (originally from Harrower1956)
END SELECT

! Sanity check: is the newly created particle faster than c
IF(v_new.GT.c)THEN
  CALL abort(&
      __STAMP__&
      ,'SecondaryElectronEmission: Particle is faster than the speed of light: '&
      ,RealInfoOpt=v_new)
END IF

END SUBROUTINE SecondaryElectronEmission


END MODULE MOD_SEE
