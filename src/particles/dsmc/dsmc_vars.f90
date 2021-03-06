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
MODULE MOD_DSMC_Vars
!===================================================================================================================================
! Contains the DSMC variables
!===================================================================================================================================
! MODULES
#if USE_MPI
USE MOD_Particle_MPI_Vars, ONLY: tPartMPIConnect
#endif
! IMPLICIT VARIABLE HANDLING
IMPLICIT NONE
PUBLIC
SAVE
!-----------------------------------------------------------------------------------------------------------------------------------
! GLOBAL VARIABLES
!-----------------------------------------------------------------------------------------------------------------------------------
TYPE tTLU_Data
  DOUBLE PRECISION                        :: Emin
  DOUBLE PRECISION                        :: Emax
  DOUBLE PRECISION                        :: deltaE
  DOUBLE PRECISION , ALLOCATABLE          :: deltabj(:)
  DOUBLE PRECISION , ALLOCATABLE          :: ChiTable(:,:)
END TYPE

TYPE(tTLU_Data)              :: TLU_Data


REAL                          :: Debug_Energy(2)=0.0        ! debug variable energy conservation
INTEGER                       :: DSMCSumOfFormedParticles   !number of formed particles per iteration in chemical reactions
                                                            ! for counting the nextfreeparticleposition
REAL  , ALLOCATABLE           :: DSMC_RHS(:,:)              ! RHS of the DSMC Method/ deltaV (npartmax, direction)
INTEGER                       :: CollisMode                 ! Mode of Collision:, ini_1
                                                            !    0: No Collisions (=free molecular flow with DSMC-Sampling-Routines)
                                                            !    1: Elastic Collision
                                                            !    2: Relaxation + Elastic Collision
                                                            !    3: Chemical Reactions
INTEGER                       :: SelectionProc              ! Mode of Selection Procedure:
                                                            !    1: Laux Default
                                                            !    2: Gimmelsheim

INTEGER                       :: PairE_vMPF(2)              ! 1: Pair chosen for energy redistribution
                                                            ! 2: partical with minimal MPF of this Pair
LOGICAL                       :: useDSMC
REAL    , ALLOCATABLE         :: PartStateIntEn(:,:)        ! 1st index: 1:npartmax 
!                                                           ! 2nd index: Evib, Erot, Eel

LOGICAL                       :: useRelaxProbCorrFactor     ! Use the relaxation probability correction factor of Lumpkin

TYPE tVarVibRelaxProb
  REAL, ALLOCATABLE           :: ProbVibAvNew(:)            ! New Average of vibrational relaxation probability (1:nSPecies)
                                                            ! , VibRelaxProb = 2
  REAL, ALLOCATABLE           :: ProbVibAv(:,:)             ! Average of vibrational relaxation probability of the Element
                                                            ! (1:nElems,nSpecies), VibRelaxProb = 2
  INTEGER, ALLOCATABLE        :: nCollis(:)                 ! Number of Collisions (1:nSPecies), VibRelaxProb = 2
  REAL                        :: alpha                      ! Relaxation factor of ProbVib, VibRelaxProb = 2
END TYPE tVarVibRelaxProb

TYPE(tVarVibRelaxProb) VarVibRelaxProb

TYPE tRadialWeighting
  REAL                        :: PartScaleFactor
  INTEGER                     :: NextClone
  INTEGER                     :: CloneDelayDiff
  LOGICAL                     :: DoRadialWeighting          ! Enables radial weighting in the axisymmetric simulations
  LOGICAL                     :: PerformCloning             ! Flag whether the cloning/deletion routine should be performed,
                                                            ! when using radial weighting (e.g. no cloning for the BGK/FP methods)
  INTEGER                     :: CloneMode                  ! 1 = Clone Delay
                                                            ! 2 = Clone Random Delay
  INTEGER, ALLOCATABLE        :: ClonePartNum(:)
  INTEGER                     :: CloneInputDelay
  LOGICAL                     :: CellLocalWeighting
  INTEGER                     :: nSubSides
END TYPE tRadialWeighting

TYPE(tRadialWeighting)        :: RadialWeighting

TYPE tClonedParticles
  ! Clone Delay: Clones are inserted at the next time step
  INTEGER                     :: Species
  REAL                        :: PartState(1:6)
  REAL                        :: PartStateIntEn(1:3)
  INTEGER                     :: Element
  REAL                        :: LastPartPos(1:3)
  REAL                        :: WeightingFactor
  INTEGER, ALLOCATABLE        :: VibQuants(:)
END TYPE

TYPE(tClonedParticles),ALLOCATABLE :: ClonedParticles(:,:)

TYPE tSpecInit
  REAL                        :: TVib                       ! vibrational temperature, ini_1
  REAL                        :: TRot                       ! rotational temperature, ini_1
  REAL                        :: Telec                      ! electronic temperature, ini_1
END TYPE tSpecInit

TYPE tSpeciesDSMC                                           ! DSMC Species Param
  TYPE(tSpecInit),ALLOCATABLE :: Init(:) !   =>NULL()
  TYPE(tSpecInit),ALLOCATABLE :: Surfaceflux(:)
  LOGICAL                     :: PolyatomicMol              ! Species is a polyatomic molecule
  INTEGER                     :: SpecToPolyArray            !
  CHARACTER(LEN=64)           :: Name                       ! Species Name, required for DSMCSpeciesElectronicDatabase
  INTEGER                     :: InterID                    ! Identification number (e.g. for DSMC_prob_calc), ini_2
                                                            !     1   : Atom
                                                            !     2   : Molecule
                                                            !     4   : Electron
                                                            !     10  : Atomic ion
                                                            !     15  : Atomic CEX/MEX ion
                                                            !     20  : Molecular ion
                                                            !     40  : Excited atom
                                                            !     100 : Excited atomic ion
                                                            !     200 : Excited molecule
                                                            !     400 : Excited molecular ion
  REAL                        :: TrefVHS                    ! VHS reference temp, ini_2
  REAL                        :: DrefVHS                    ! VHS reference diameter, ini_2
  REAL                        :: omegaVHS                   ! VHS exponent omega, ini_2
  INTEGER                     :: NumOfPro                   ! Number of Protons, ini_2
  REAL                        :: Eion_eV                    ! Energy of Ionisation in eV, ini_2
  REAL                        :: RelPolarizability          ! relative polarizability, ini_2
  INTEGER                     :: NumEquivElecOutShell       ! number of equivalent electrons in outer shell, ini2
  INTEGER                     :: Xi_Rot                     ! Rotational DOF
  REAL                        :: GammaVib                   ! GammaVib = Xi_Vib(T_t)² * exp(CharaTVib/T_t) / 2 -> correction fact
                                                            ! for vib relaxation -> see 'Vibrational relaxation rates
                                                            ! in the DSMC method', Gimelshein et al., 2002
  REAL                        :: CharaTVib                  ! Charac vibrational Temp, ini_2
  REAL                        :: Ediss_eV                   ! Energy of Dissosiation in eV, ini_2
  INTEGER                     :: MaxVibQuant                ! Max vib quantum number + 1
  INTEGER                     :: MaxElecQuant               ! Max elec quantum number + 1
  INTEGER                     :: DissQuant                  ! Vibrational quantum number corresponding to the dissociation energy
                                                            ! (used for QK chemistry, not using MaxVibQuant to avoid confusion with
                                                            !   the TSHO model)
  REAL                        :: RotRelaxProb               ! rotational relaxation probability
  REAL                        :: VibRelaxProb               ! vibrational relaxation probability
  REAL                        :: ElecRelaxProb              ! electronic relaxation probability
                                                            !this should be a value for every transition, and not fix!
  REAL                        :: VFD_Phi3_Factor            ! Factor of Phi3 in VFD Method: Phi3 = 0 => VFD -> TCE, ini_2
  REAL                        :: CollNumRotInf              ! Collision number for rotational relaxation according to Parker or
                                                            ! Zhang, ini_2 -> model dependent!
  REAL                        :: TempRefRot                 ! Referece temperature for rotational relaxation according to Parker or
                                                            ! Zhang, ini_2 -> model dependent!
  REAL, ALLOCATABLE           :: MW_ConstA(:)               ! Model Constant 'A' of Milikan-White Model for vibrational relax, ini_2
  REAL, ALLOCATABLE           :: MW_ConstB(:)               ! Model Constant 'B' of Milikan-White Model for vibrational relax, ini_2
  REAL, ALLOCATABLE           :: CollNumVib(:)              ! vibrational collision number
  REAL                        :: VibCrossSec                ! vibrational cross section, ini_2
  REAL, ALLOCATABLE           :: CharaVelo(:)               ! characteristic velocity according to Boyd & Abe, nec for vib
                                                            ! relaxation
#if (PP_TimeDiscMethod==42)
#ifdef CODE_ANALYZE
  INTEGER,ALLOCATABLE,DIMENSION(:)  :: levelcounter         ! counter for electronic levels; only debug
  INTEGER,ALLOCATABLE,DIMENSION(:)  :: dtlevelcounter       ! counter for produced electronic levels per timestep; only debug
  REAL,ALLOCATABLE,DIMENSION(:,:,:) :: ElectronicTransition ! counter for electronic transition from state i to j
#endif
#endif
  REAL,ALLOCATABLE,DIMENSION(:,:) :: ElectronicState        ! Array with electronic State for each species
                                                            ! first  index: 1 - degeneracy & 2 - char. Temp,el
                                                            ! second index: energy level
  INTEGER                           :: SymmetryFactor
  REAL                              :: CharaTRot
  REAL, ALLOCATABLE                 :: PartitionFunction(:) ! Partition function for each species in given temperature range
  REAL                              :: EZeroPoint           ! Zero point energy for molecules
  REAL                              :: HeatOfFormation      ! Heat of formation of the respective species [Kelvin]
  INTEGER                           :: PreviousState        ! Species number of the previous state (e.g. N for NIon)
  LOGICAL                           :: FullyIonized         ! Flag if the species is fully ionized (e.g. C^6+)
  INTEGER                           :: NextIonizationSpecies! SpeciesID of the next higher ionization level (required for field
!                                                           ! ionization)
  ! Collision cross-sections for MCC
  LOGICAL                           :: UseCollXSec          ! Flag if the collisions of the species with a background gas should be
                                                            ! treated with read-in collision cross-section (currently only with BGG)
  REAL,ALLOCATABLE                  :: CollXSec(:,:)        ! Collision cross-section as read-in from the database
                                                            ! 1: Energy (at read-in in [eV], during simulation in [J])
                                                            ! 2: Cross-section at the respective energy level [m^2]
  REAL                              :: ProbNull             ! Collision probability at the maximal collision frequency for the
                                                            ! null collision method of MCC
  REAL                              :: MaxCollFreq          ! Maximal collision frequency at certain energy level and cross-section
END TYPE tSpeciesDSMC

TYPE(tSpeciesDSMC), ALLOCATABLE     :: SpecDSMC(:)          ! Species DSMC params (nSpec)

TYPE tDSMC
  INTEGER                       :: ElectronSpecies          ! Species of the electron
  REAL                          :: EpsElecBin               ! percentage parameter of electronic energy level merging
  REAL                          :: GammaQuant               ! GammaQuant for zero point energy in Evib (perhaps also Erot),
                                                            ! should be 0.5 or 0
  INTEGER(KIND=8), ALLOCATABLE  :: NumColl(:)               ! Number of Collision for each case + entire Collision number
  REAL                          :: TimeFracSamp=0.          ! %-of simulation time for sampling
  INTEGER                       :: SampNum                  ! number of Samplingsteps
  INTEGER                       :: NumOutput                ! number of Outputs
  REAL                          :: DeltaTimeOutput          ! Time intervall for Output
  LOGICAL                       :: ReservoirSimu            ! Flag for reservoir simulation
  LOGICAL                       :: ReservoirSimuRate        ! Does not performe the collision.
                                                            ! Switch to enable to create reaction rates curves
  LOGICAL                       :: ReservoirSurfaceRate     ! Switch enabling surface rate output without changing surface coverages
  LOGICAL                       :: ReservoirRateStatistic   ! if false, calculate the reaction coefficient rate by the probability
                                                            ! Default Value is false
  INTEGER                       :: VibEnergyModel           ! Model for vibration Energy:
                                                            !       0: SHO (default value!)
                                                            !       1: TSHO
  LOGICAL                       :: DoTEVRRelaxation         ! Flag for T-V-E-R or more simple T-V-R T-E-R relaxation
  INTEGER                       :: PartNumOctreeNode        ! Max Number of Particles per Octree Node
  INTEGER                       :: PartNumOctreeNodeMin     ! Min Number of Particles per Octree Node
  LOGICAL                       :: UseOctree                ! Flag for Octree
  LOGICAL                       :: UseNearestNeighbour      ! Flag for Nearest Neighbour or classic statistical pairing
  LOGICAL                       :: CalcSurfaceVal           ! Flag for calculation of surfacevalues like heatflux or force at walls
  LOGICAL                       :: CalcSurfaceTime          ! Flag for sampling in time-domain or iterations
  REAL                          :: CalcSurfaceSumTime       ! Flag for sampling in time-domain or iterations
  REAL                          :: CollProbMean             ! Summation of collision probability
  REAL                          :: CollProbMax              ! Maximal collision probability per cell
  REAL, ALLOCATABLE             :: CalcRotProb(:,:)         ! Summation of rotation relaxation probability (nSpecies + 1,3)
                                                            !     1: Mean Prob
                                                            !     2: Max Prob
                                                            !     3: Sample size
  REAL, ALLOCATABLE             :: CalcVibProb(:,:)         ! Summation of vibration relaxation probability (nSpecies + 1,3)
                                                            !     1: Mean Prob
                                                            !     2: Max Prob
                                                            !     3: Sample size
  REAL                          :: MeanFreePath
  REAL                          :: MCSoverMFP               ! Subcell local mean collision distance over mean free path
  INTEGER                       :: CollProbMeanCount        ! counter of possible collision pairs
  INTEGER                       :: CollSepCount             ! counter of actual collision pairs
  REAL                          :: CollSepDist              ! Summation of mean collision separation distance
  LOGICAL                       :: CalcQualityFactors       ! Enables/disables the calculation and output of flow-field variables
  REAL, ALLOCATABLE             :: QualityFacSamp(:,:)      ! Sampling of quality factors
                                                            !     1: Maximal collision prob
                                                            !     2: Time-averaged mean collision prob
                                                            !     3: Mean collision separation distance over mean free path
                                                            !     4: Sample size
  REAL, ALLOCATABLE             :: QualityFacSampRot(:,:,:) ! Sampling of quality rot relax factors (nElem,nSpec+1,2)
                                                            !     1: Time-averaged mean rot relax prob
                                                            !     2: Maximal rot relax prob
  INTEGER, ALLOCATABLE          :: QualityFacSampRotSamp(:,:)!Sample size for QualityFacSampRot
  REAL, ALLOCATABLE             :: QualityFacSampVib(:,:,:) ! Sampling of quality vib relax factors (nElem,nSpec+1,2)
                                                            !     1: Instantanious time-averaged mean vib relax prob
                                                            !     2: Instantanious maximal vib relax prob
  INTEGER, ALLOCATABLE          :: QualityFacSampVibSamp(:,:,:)!Sample size for QualityFacSampVib
  REAL, ALLOCATABLE             :: QualityFacSampRelaxSize(:,:)! Samplie size of quality relax factors (nElem,nSpec+1)
  LOGICAL                       :: ElectronicModel          ! Flag for Electronic State of atoms and molecules
  CHARACTER(LEN=64)             :: ElectronicModelDatabase  ! Name of Electronic State Database | h5 file
  INTEGER                       :: NumPolyatomMolecs        ! Number of polyatomic molecules
  LOGICAL                       :: OutputMeshInit           ! Write Outputmesh (for const. pressure BC) at Init.
  LOGICAL                       :: OutputMeshSamp           ! Write Outputmesh (for const. pressure BC)
                                                            ! with sampling values at t_analyze
  REAL                          :: RotRelaxProb             ! Model for calculation of rotational relaxation probability, ini_1
                                                            !    0-1: constant probability  (0: no relaxation)
                                                            !    2: Boyd's model
                                                            !    3: Nonequilibrium Direction Dependent model (Zhang,Schwarzentruber)
  REAL                          :: VibRelaxProb             ! Model for calculation of vibrational relaxation probability, ini_1
                                                            !    0-1: constant probability (0: no relaxation)
                                                            !    2: Boyd's model, with correction from Abe
  REAL                          :: ElecRelaxProb            ! electronic relaxation probability
  LOGICAL                       :: PolySingleMode           ! Separate relaxation of each vibrational mode of a polyatomic in a
                                                            ! loop over all vibrational modes (every mode has its own corrected
                                                            ! relaxation probability, comparison with the same random number
                                                            ! while the previous probability is added to the next)
  REAL, ALLOCATABLE             :: InstantTransTemp(:)      ! Instantaneous translational temprerature for each cell (nSpieces+1)
  LOGICAL                       :: BackwardReacRate         ! Enables the automatic calculation of the backward reaction rate
                                                            ! coefficient with the equilibrium constant by partition functions
  REAL                          :: PartitionMaxTemp         ! Temperature limit for pre-stored partition function (DEF: 20 000K)
  REAL                          :: PartitionInterval        ! Temperature interval for pre-stored partition function (DEF: 10K)
  REAL, ALLOCATABLE             :: veloMinColl(:)           ! min velo-magn. for spec allowed to perform collision (def.: 0.)
#if (PP_TimeDiscMethod==42)
  LOGICAL                       :: CompareLandauTeller      ! Keeps the translational temperature at the fixed value of the init
#endif
  LOGICAL                       :: MergeSubcells            ! Merge subcells after quadtree division if number of particles within
                                                            ! subcell is less than 7
END TYPE tDSMC

TYPE(tDSMC)                     :: DSMC

TYPE tBGGas
  INTEGER                       :: BGGasSpecies             ! Number which Species is Background Gas
  REAL                          :: BGGasDensity             ! Density of Background Gas
  REAL                          :: BGColl_SpecPartNum       ! PartNum of BGGas per cell
  INTEGER                       :: BGMeanEVibQua            ! Mean EVib qua number for dissociation probability
  INTEGER, ALLOCATABLE          :: PairingPartner(:)        ! Index of the background particle generated for the pairing with a
                                                            ! regular particle
END TYPE tBGGas

TYPE(tBGGas)                        :: BGGas

LOGICAL                             :: UseMCC
CHARACTER(LEN=256)                  :: MCC_Database
INTEGER                             :: MCC_TotalPairNum

TYPE tPairData
  REAL              :: CRela2                               ! squared relative velo of the particles in a pair
  REAL              :: Prob                                 ! colision probability
  INTEGER           :: iPart_p1                             ! first particle of the pair
  INTEGER           :: iPart_p2                             ! second particle of the pair
  INTEGER           :: PairType                             ! type of pair (=iCase, CollInf%Coll_Case)
  REAL, ALLOCATABLE :: Sigma(:)                             ! cross sections sigma of the pair
                                                            !       0: sigma total
                                                            !       1: sigma elast
                                                            !       2: sigma ionization
                                                            !       3: sigma exciation
  REAL              :: Ec                                   ! Collision Energy
  LOGICAL           :: NeedForRec                           ! Flag if pair is need for Recombination
END TYPE tPairData

TYPE(tPairData), ALLOCATABLE    :: Coll_pData(:)            ! Data of collision pairs into a cell (nPair)

TYPE tCollInf             ! informations of collision
  INTEGER       , ALLOCATABLE    :: Coll_Case(:,:)          ! Case of species combination (Spec1, Spec2)
  INTEGER                        :: NumCase                 ! Number of possible collision combination
  INTEGER       , ALLOCATABLE    :: Coll_CaseNum(:)         ! number of species combination per cell Sab (number of cases)
  REAL          , ALLOCATABLE    :: Coll_SpecPartNum(:)     ! number of particle of species n per cell (nSpec)
  REAL          , ALLOCATABLE    :: Cab(:)                  ! species factor for cross section (number of case)
  INTEGER       , ALLOCATABLE    :: KronDelta(:)            ! (number of case)
  REAL          , ALLOCATABLE    :: FracMassCent(:,:)       ! mx/(my+mx) (nSpec, number of cases)
  REAL          , ALLOCATABLE    :: MassRed(:)              ! reduced mass (number of cases)
  REAL          , ALLOCATABLE    :: MeanMPF(:)
  LOGICAL                        :: ProhibitDoubleColl = .FALSE.
  INTEGER       , ALLOCATABLE    :: OldCollPartner(:)        ! index of old coll partner to prohibit double collisions(maxPartNum)
END TYPE

TYPE(tCollInf)               :: CollInf

TYPE tSampDSMC             ! DSMC sample
  REAL                           :: PartV(3), PartV2(3)     ! Velocity, Velocity^2 (vx,vy,vz)
  REAL                           :: PartNum                 ! Particle Number
  INTEGER                        :: SimPartNum
  REAL                           :: ERot                    ! Rotational  Energy
  REAL                           :: EVib                    ! Vibrational Energy
  REAL                           :: EElec                   ! electronic  Energy
END TYPE

TYPE(tSampDSMC), ALLOCATABLE     :: SampDSMC(:,:)           ! DSMC sample array (number of Elements, nSpec)

TYPE tMacroDSMC           ! DSMC output
  REAL                            :: PartV(4), PartV2(3)    ! Velocity, Velocity^2 (vx,vy,vz,|v|)
  REAL                            :: PartNum                ! Particle Number
  REAL                            :: Temp(4)                ! Temperature (Tx, Ty, Tz, Tt)
  REAL                            :: NumDens                ! Particle density
  REAL                            :: TVib                   ! Vibrational Temp
  REAL                            :: TRot                   ! Rotational Temp
  REAL                            :: TElec                  ! Electronic Temp
END TYPE

TYPE(tMacroDSMC), ALLOCATABLE     :: MacroDSMC(:,:)         ! DSMC sample array (number of Elements, nSpec)

TYPE tReactInfo
   REAL,  ALLOCATABLE             :: Xi_Total(:,:)          ! Total DOF of Reaction (quant num part1, quant num part2)
   REAL,  ALLOCATABLE             :: Beta_Diss_Arrhenius(:,:) ! Beta_d for calculation of the Dissociation probability
                                                            ! (quant num part1, quant num part2)
   REAL,  ALLOCATABLE             :: Beta_Exch_Arrhenius(:,:) ! Beta_d for calculation of the Excchange reaction probability
                                                            ! (quant num part1, quant num part2)
   REAL,  ALLOCATABLE             :: Beta_Rec_Arrhenius(:,:)  ! Beta_d for calculation of the Recombination reaction probability
                                                            ! (nSpecies, quant num part3)
   INTEGER, ALLOCATABLE           :: StoichCoeff(:,:)     ! Stoichiometric coefficient (nSpecies,1:2) (1: reactants, 2: products)
END TYPE

TYPE tArbDiss
  INTEGER                         :: NumOfNonReactives      ! Number
  INTEGER, ALLOCATABLE            :: NonReactiveSpecies(:)    ! Array with the non-reactive collision partners for dissociation
END TYPE

TYPE tChemReactions
  INTEGER                         :: NumOfReact             ! Number of possible Reactions
  TYPE(tArbDiss), ALLOCATABLE     :: ArbDiss(:)  !
  LOGICAL, ALLOCATABLE            :: QKProcedure(:)         ! Defines if QK Procedure is selected
  INTEGER, ALLOCATABLE            :: QKMethod(:)            ! Recombination method for Q-K model (1 by Bird / 2 by Gallis)
  REAL,ALLOCATABLE,DIMENSION(:,:) :: QKCoeff                ! QKRecombiCoeff for Birds method
  REAL, ALLOCATABLE               :: NumReac(:)             ! Number of occured reactions for each reaction number
  INTEGER, ALLOCATABLE            :: ReacCount(:)           ! Counter of chemical reactions for the determination of rate
                                                            ! coefficient based on the reaction probabilities
  REAL, ALLOCATABLE               :: ReacCollMean(:)        ! Mean Collision Probability for each reaction number
  INTEGER, ALLOCATABLE            :: ReacCollMeanCount(:)   ! counter for mean Collision Probability max for each reaction number
!  INTEGER(KIND=8), ALLOCATABLE    :: NumReac(:)            ! Number of occured reactions for each reaction number
  CHARACTER(LEN=5),ALLOCATABLE    :: ReactType(:)           ! Type of Reaction (reaction num)
                                                            !    i (electron impact ionization)
                                                            !    R (molecular recombination
                                                            !    D (molecular dissociation)
                                                            !    E (molecular exchange reaction)
                                                            !    x (simple charge exchange reaction)
  INTEGER, ALLOCATABLE            :: DefinedReact(:,:,:)    ! Defined Reaction
                                                            !(reaction num; 1:reactant, 2:product;
                                                            !  1-3 spezieses of reactants and products,
                                                            ! 0: no spezies -> only 2 reactants or products)
  INTEGER, ALLOCATABLE            :: ReactCase(:,:)             ! Case of reaction in combination of (spec1, spec2)
  INTEGER, ALLOCATABLE            :: ReactNum(:,:,:)            ! Number of Reaction of (spec1, spec2,
                                                                ! Case 1: Recomb: func. of species 3
                                                                ! Case 2: dissociation, only 1
                                                                ! Case 3: exchange reaction, only 1
                                                                ! Case 4: RN of 1. dissociation
                                                                !               2. exchange
                                                                ! Case 5: RN of 1. dissociation 1
                                                                !               2. dissociation 2
                                                                ! Case 6: associative ionization (N + N -> N2(ion) + e)
                                                                ! Case 7: 3 dissociations possible (at least 1 poly)
                                                                ! Case 8: 4 dissociations possible
                                                                ! Case 9: 3 diss and 1 exchange possible
                                                                ! Case 10: 2 diss and 1 exchange possible
                                                                ! Case 11: 2 diss, 1 exchange and 1 recomb possible
                                                                ! Case 12: 2 diss and 1 recomb possible
                                                                ! Case 13: 1 diss, 1 exchange and 1 recomb possible
                                                                ! Case 14: 1 diss and 1 recomb possible
                                                                ! Case 15: 1 exchange and 1 recomb possible
                                                                ! Case 16: simple CEX, only 1
                                                                ! Case 17: associative ionization and recombination possible
   INTEGER, ALLOCATABLE           :: ReactNumRecomb(:,:,:)      ! Number of Reaction of (spec1, spec2, spec3)
   REAL,  ALLOCATABLE             :: Arrhenius_Prefactor(:)     ! pre-exponential factor af of Arrhenius ansatz (nReactions)
   REAL,  ALLOCATABLE             :: Arrhenius_Powerfactor(:)   ! powerfactor bf of temperature in Arrhenius ansatz (nReactions)
   REAL,  ALLOCATABLE             :: EActiv(:)              ! activation energy (relative to k) (nReactions)
   REAL,  ALLOCATABLE             :: EForm(:)               ! heat of formation  (relative to k) (nReactions)
   REAL,  ALLOCATABLE             :: MeanEVib_PerIter(:)    ! MeanEVib per iteration for calculation of
   INTEGER,  ALLOCATABLE          :: MeanEVibQua_PerIter(:) ! MeanEVib per iteration for calculation of
                                                            ! xi_vib per cell (nSpecies)
   REAL,  ALLOCATABLE             :: CEXa(:)                ! CEX log-factor (g-dep. cross section in Angstrom (nReactions)
   REAL,  ALLOCATABLE             :: CEXb(:)                ! CEX const. factor (g-dep. cross section in Angstrom (nReactions)
   REAL,  ALLOCATABLE             :: MEXa(:)                ! MEX log-factor (g-dep. cross section in Angstrom (nReactions)
   REAL,  ALLOCATABLE             :: MEXb(:)                ! MEX const. factor (g-dep. cross section in Angstrom (nReactions)
   REAL,  ALLOCATABLE             :: ELa(:)                 ! EL log-factor (g&cut-off-angle-dep. cs in Angstrom (nReactions)
   REAL,  ALLOCATABLE             :: ELb(:)                 ! EL const. factor (g&cut-off-angle-dep. cs in Angstrom (nReactions)
   LOGICAL, ALLOCATABLE           :: DoScat(:)              ! Do Scattering Calculation by Lookup table
   CHARACTER(LEN=200),ALLOCATABLE :: TLU_FileName(:)        ! Name of file containing table lookup data for Scattering
   INTEGER                       :: RecombParticle = 0      ! P. Index for Recombination, if zero -> no recomb particle avaible
   INTEGER                       :: nPairForRec
   REAL, ALLOCATABLE             :: Hab(:)                  ! Factor Hab of Arrhenius Ansatz for diatomic/polyatomic molecs
   TYPE(tReactInfo), ALLOCATABLE  :: ReactInfo(:)           ! Informations of Reactions (nReactions)
END TYPE

TYPE(tChemReactions)              :: ChemReac


TYPE tQKAnalytic
  REAL, ALLOCATABLE               :: ForwardRate(:)
END TYPE

TYPE(tQKAnalytic), ALLOCATABLE    :: QKAnalytic(:)

REAL                              :: realtime               ! realtime of simulation

TYPE tPolyatomMolDSMC !DSMC Species Param
  LOGICAL                         :: LinearMolec            ! Is a linear Molec?
  INTEGER                         :: NumOfAtoms             ! Number of Atoms in Molec
  INTEGER                         :: VibDOF                 ! DOF in Vibration, equals number of independent SHO's
  REAL, ALLOCATABLE              :: CharaTVibDOF(:)        ! Chara TVib for each DOF
  INTEGER,ALLOCATABLE           :: LastVibQuantNums(:,:)    ! Last quantum numbers for vibrational inserting (VibDOF,nInits)
  INTEGER, ALLOCATABLE          :: MaxVibQuantDOF(:)      ! Max Vib Quant for each DOF
  REAL                            :: Xi_Vib_Mean            ! mean xi vib for chemical reactions
  REAL                            :: TVib
  REAL, ALLOCATABLE              :: GammaVib(:)            ! GammaVib: correction factor for Gimelshein Relaxation Procedure
  REAL, ALLOCATABLE              :: VibRelaxProb(:)
  REAL, ALLOCATABLE              :: CharaTRotDOF(:)        ! Chara TRot for each DOF
END TYPE

TYPE (tPolyatomMolDSMC), ALLOCATABLE    :: PolyatomMolDSMC(:)        ! Infos for Polyatomic Molecule

TYPE tPolyatomMolVibQuant !DSMC Species Param
  INTEGER, ALLOCATABLE               :: Quants(:)            ! Vib quants of each DOF for each particle
END TYPE

TYPE (tPolyatomMolVibQuant), ALLOCATABLE    :: VibQuantsPar(:)

REAL,ALLOCATABLE                  :: MacroSurfaceVal(:,:,:,:)      ! variables,p,q,sides
REAL,ALLOCATABLE                  :: MacroSurfaceSpecVal(:,:,:,:,:)! Macrovalues for Species specific surface output
                                                                   ! (4,p,q,nSurfSides,nSpecies)
                                                                   ! 1: Surface Collision Counter
                                                                   ! 2: Accomodation
                                                                   ! 3: Coverage
                                                                   ! 4 (or 2): Impact energy trans
                                                                   ! 5 (or 3): Impact energy rot
                                                                   ! 6 (or 4): Impact energy vib

! some variables redefined
!TYPE tMacroSurfaceVal                                       ! DSMC sample for Wall
!  REAL                           :: Heatflux                !
!  REAL                           :: Force(3)                ! x, y, z direction
!  REAL, ALLOCATABLE              :: Counter(:)              ! Wall-Collision counter of all Species
!  REAL                           :: CounterOut              ! Wall-Collision counter for Output
!END TYPE
!
!TYPE(tMacroSurfaceVal), ALLOCATABLE     :: MacroSurfaceVal(:) ! Wall sample array (number of BC-Sides)

! MacValout and MacroVolSample have to be separated due to autoinitialrestart
INTEGER(KIND=8)                   :: iter_macvalout             ! iterations since last macro volume output
INTEGER(KIND=8)                   :: iter_macsurfvalout         ! iterations since last macro surface output
!-----------------------------------------------convergence criteria-------------------------------------------------
LOGICAL                           :: SamplingActive             ! Identifier if DSMC Sampling is activated
LOGICAL                           :: UseQCrit                   ! Identifier if Q-Criterion (Burt,Boyd) for
                                                                ! Sampling Start is used
INTEGER                           :: QCritTestStep              ! Time Steps between Q criterion evaluations
                                                                ! (=Length of Analyze Interval)
INTEGER(KIND=8)                  :: QCritLastTest              ! Time Step of last Q criterion evaluation
REAL                              :: QCritEpsilon               ! Steady State if Q < 1 + Qepsilon
INTEGER, ALLOCATABLE              :: QCritCounter(:,:)          ! Exit / Wall Collision Counter for
                                                                ! each boundary side (Side, Interval)
REAL, ALLOCATABLE                 :: QLocal(:)                  ! Intermediate Criterion (per cell)
LOGICAL                           :: UseSSD                     ! Identifier if Steady-State-Detection
                                                                ! for Sampling Start is used (only  if UseQCrit=FALSE)
INTEGER                           :: ReactionProbGTUnityCounter ! Count the number of ReactionProb>1 (turn off the warning after
!                                                               ! reaching 1000 outputs of said warning

TYPE tSampler ! DSMC sampling for Steady-State Detection
  REAL                            :: Energy(3)                  ! Energy in Cell (Translation)
  REAL                            :: Velocity(3)                ! Velocity in Cell (x,y,z)
  REAL                            :: PartNum                    ! Particle Number in Cell
  REAL                            :: ERot                       ! Energy in Cell (Rotation)
  REAL                            :: EVib                       ! Energy of Cell (Vibration)
  REAL                            :: EElec                      ! Energy of Cell (Electronic State)
END TYPE

TYPE (tSampler), ALLOCATABLE      :: Sampler(:,:)               ! DSMC sample array (number of Elements, number of Species)
TYPE (tSampler), ALLOCATABLE      :: History(:,:,:)             ! History of Averaged Values (number of Elements,
                                                                ! number of Species, number of Samples)
INTEGER                           :: iSamplingIters             ! Counter for Sampling Iteration
INTEGER                           :: nSamplingIters             ! Number of Iterations for one Sampled Value (Sampling Period)
INTEGER                           :: HistTime                   ! Counter for Sampled Values in History
INTEGER                           :: nTime                      ! Length of History of Sampled Values
                                                                ! (Determines Sample Size for Statistical Tests)
REAL, ALLOCATABLE                 :: CheckHistory(:,:)          ! History Array for Detection Algorithm
                                                                ! (number of Elements, number of Samples)
INTEGER, ALLOCATABLE              :: SteadyIdentGlobal(:,:)     ! Identifier if Domain ist stationary (number of Species, Value)
INTEGER, ALLOCATABLE              :: SteadyIdent(:,:,:)         ! Identifier if Cell is stationary
                                                                ! (number of Elements, number of Species, Value)
REAL                              :: Critical(2)                ! Critical Values for the Von-Neumann-Ratio
REAL, ALLOCATABLE                 :: RValue(:)                  ! Von-Neumann-Ratio (number of Elements)
REAL                              :: Epsilon1, Epsilon2         ! Parameters for the Critical Values of
                                                                ! the Euclidean Distance method
REAL, ALLOCATABLE                 :: ED_Delta(:)    ! Offset of Euclidian Distance Statistic to stationary
                                                                ! value (number of Elements)
REAL                              :: StudCrit                   ! Critical Value for the Student-t Test
REAL, ALLOCATABLE                 :: Stud_Indicator(:)    ! Stationary Index of the Student-t Test
                                                                ! (0...1, 1 = steady  state) (number of Elements)
REAL                              :: PITCrit                    ! Critical Value for the Polynomial Interpolation Test
REAL, ALLOCATABLE                 :: ConvCoeff(:)               ! Convolution Coefficients (Savizky-Golay-Filter)
                                                                ! for the Polynomial Interpolation Test
REAL, ALLOCATABLE                 :: PIT_Drift(:)    ! Relative Filtered Trend Index (<1 = steady state) (number of Elements)
REAL, ALLOCATABLE                 :: MK_Trend(:)    ! Normalized Trend Parameter for the Mann - Kendall - Test
                                                                ! (-1<x<1 = steady state) (number of Elements)
REAL, ALLOCATABLE                 :: HValue(:)                  ! Entropy Parameter (Boltzmann's H-Theorem) (number of Elements)
!-----------------------------------------------convergence criteria-------------------------------------------------
TYPE tSampleCartmesh_VolWe
  REAL                                  :: BGMdeltas(3)       ! Backgroundmesh size in x,y,z
  REAL                                  :: FactorBGM(3)       ! Divider for BGM (to allow real numbers)
  REAL                                  :: BGMVolume          ! Volume of a BGM Cell
  INTEGER,ALLOCATABLE               :: GaussBGMIndex(:,:,:,:,:) ! Background mesh index of gausspoints (1:3,PP_N,PP_N,PP_N,nElems)
  REAL,ALLOCATABLE                  :: GaussBGMFactor(:,:,:,:,:) ! BGM factor of gausspoints (1:3,PP_N,PP_N,PP_N,nElems)
  INTEGER                               :: BGMminX            ! Local minimum BGM Index in x
  INTEGER                               :: BGMminY            ! Local minimum BGM Index in y
  INTEGER                               :: BGMminZ            ! Local minimum BGM Index in z
  INTEGER                               :: BGMmaxX            ! Local maximum BGM Index in x
  INTEGER                               :: BGMmaxY            ! Local maximum BGM Index in y
  INTEGER                               :: BGMmaxZ            ! Local maximum BGM Index in z
  INTEGER, ALLOCATABLE                  :: PeriodicBGMVectors(:,:)           ! = periodic vectors in backgroundmesh coords
  LOGICAL                               :: SelfPeriodic
  REAL, ALLOCATABLE                    :: BGMVolumes(:,:,:)
  REAL, ALLOCATABLE                    :: BGMVolumes2(:,:,:)
  LOGICAL, ALLOCATABLE                 :: isBoundBGCell(:,:,:)
  INTEGER                               :: OrderVolInt
  REAL, ALLOCATABLE                    :: x_VolInt(:)
  REAL, ALLOCATABLE                    :: w_VolInt(:)
#if USE_MPI
  TYPE(tPartMPIConnect)        , ALLOCATABLE :: MPIConnect(:)             ! MPI connect for each process
#endif
END TYPE

TYPE (tSampleCartmesh_VolWe) DSMCSampVolWe

TYPE tDSMCSampNearInt
  REAL,ALLOCATABLE                      :: GaussBorder(:)     ! 1D coords of gauss points in -1|1 space
END TYPE

TYPE (tDSMCSampNearInt) DSMCSampNearInt

TYPE tDSMCSampCellVolW
  REAL,ALLOCATABLE                      :: xGP(:)
  REAL,ALLOCATABLE                      :: SubVolumes(:,:,:,:)
END TYPE

TYPE (tDSMCSampCellVolW) DSMCSampCellVolW

TYPE tAdaptedElem
  REAL                                   :: Volume
  REAL                                   :: AdaptNodePoints(3,8)
END TYPE

TYPE tDSMCSampAdaptCellVolW
  REAL,ALLOCATABLE                       :: xGP(:)
  LOGICAL, ALLOCATABLE                  :: IsAdaptedElem(:)
  TYPE(tAdaptedElem), ALLOCATABLE        :: AdaptedElem(:)
  INTEGER                                 :: AdaptPartNum
  INTEGER                                 :: AdaptIterNum
  LOGICAL                                 :: OnlyProcLocal
END TYPE

TYPE (tDSMCSampAdaptCellVolW) DSMCSampAdaptCellVolW

#if USE_MPI
TYPE tAdaptCellVolWRecvPart
  REAL,ALLOCATABLE                      :: PartState(:,:)
  REAL,ALLOCATABLE                      :: PartStateInt(:,:)
  INTEGER                                :: PartNum
  INTEGER,ALLOCATABLE                   :: PartSpec(:)
END TYPE

TYPE (tAdaptCellVolWRecvPart), ALLOCATABLE :: AdaptCellVolWRecvPart(:)
#endif

INTEGER, ALLOCATABLE      :: SymmetrySide(:,:)

TYPE tHODSMC
  LOGICAL                 :: HODSMCOutput         !High Order DSMC Output
  INTEGER                 :: nOutputDSMC          !HO DSMC output order
  REAL,ALLOCATABLE        :: DSMC_xGP(:,:,:,:,:)  ! XYZ positions (first index 1:3) of the volume Gauss Point
  REAL,ALLOCATABLE        :: DSMC_wGP(:)
  CHARACTER(LEN=256)      :: SampleType
  CHARACTER(LEN=256)      :: NodeType
  REAL,ALLOCATABLE        :: sJ(:,:,:,:)
  LOGICAL                 :: DoAdaptCellWMPI=.false.
END TYPE tHODSMC

TYPE(tHODSMC)             :: HODSMC
REAL,ALLOCATABLE          :: DSMC_HOSolution(:,:,:,:,:,:) !1:3 v, 4:6 v^2, 7 dens, 8 Evib, 9 erot, 10 eelec
REAL,ALLOCATABLE          :: DSMC_VolumeSample(:)         !sampnum samples of volume in element

LOGICAL                   :: ConsiderVolumePortions       ! Flag set in case volume portions are required, enables MC volume calc

TYPE tTreeNode
!  TYPE (tTreeNode), POINTER       :: One, Two, Three, Four, Five, Six, Seven, Eight !8 Childnodes of Octree Treenode
  TYPE (tTreeNode), POINTER       :: ChildNode       => null()       !8 Childnodes of Octree Treenode
  REAL                            :: MidPoint(1:3)          ! approx Middle Point of Treenode
  INTEGER                         :: PNum_Node              ! Particle Number of Treenode
  INTEGER, ALLOCATABLE            :: iPartIndx_Node(:)      ! Particle Index List of Treenode
  REAL, ALLOCATABLE               :: MappedPartStates(:,:)  ! PartPos in [-1,1] Space
  LOGICAL, ALLOCATABLE            :: MatchedPart(:)         ! Flag signaling that mapped particle is inside of macroparticle
  REAL                            :: NodeVolume(8)
  INTEGER                         :: NodeDepth
  REAL                            :: MPNodeVolumePortion(8)
END TYPE

TYPE tNodeVolume
    TYPE (tNodeVolume), POINTER             :: SubNode1 => null()
    TYPE (tNodeVolume), POINTER             :: SubNode2 => null()
    TYPE (tNodeVolume), POINTER             :: SubNode3 => null()
    TYPE (tNodeVolume), POINTER             :: SubNode4 => null()
    TYPE (tNodeVolume), POINTER             :: SubNode5 => null()
    TYPE (tNodeVolume), POINTER             :: SubNode6 => null()
    TYPE (tNodeVolume), POINTER             :: SubNode7 => null()
    TYPE (tNodeVolume), POINTER             :: SubNode8 => null()
    REAL                                    :: Volume
    REAL                                    :: MPVolumePortion
    LOGICAL                                 :: MPVolumeDone=.FALSE.
    REAL                                    :: Area
    REAL,ALLOCATABLE                        :: PartNum(:,:)
END TYPE

TYPE tElemNodeVolumes
    TYPE (tNodeVolume), POINTER             :: Root => null()
END TYPE

TYPE (tElemNodeVolumes), ALLOCATABLE        :: ElemNodeVol(:)

TYPE tOctreeVdm
  TYPE (tOctreeVdm), POINTER                :: SubVdm => null()
  REAL,ALLOCATABLE                          :: Vdm(:,:)
  REAL                                      :: wGP
  REAL,ALLOCATABLE                          :: xGP(:)
END TYPE

TYPE (tOctreeVdm), POINTER                  :: OctreeVdm => null()
!===================================================================================================================================
END MODULE MOD_DSMC_Vars
