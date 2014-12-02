!------------------------------------------------------------------------------
!                  Harvard-NASA Emissions Component (HEMCO)                   !
!------------------------------------------------------------------------------
!BOP
!
! !MODULE: emissions_mod.F90
!
! !DESCRIPTION: Module emissions\_mod.F90 is a wrapper module to interface
! GEOS-Chem and HEMCO. It basically just calls the GEOS-Chem - HEMCO interface
! routines. For some specialty sims, a few additional steps are required that
! are also executed here.
!\\
!\\
! !INTERFACE:
!
MODULE EMISSIONS_MOD
!
! !USES:
!
  IMPLICIT NONE
  PRIVATE
!
! !PUBLIC MEMBER FUNCTIONS:
!
  PUBLIC :: EMISSIONS_INIT
  PUBLIC :: EMISSIONS_RUN
  PUBLIC :: EMISSIONS_FINAL
!
! !PRIVATE MEMBER FUNCTIONS:
!
  PRIVATE :: EMISSVOC
!
! !REVISION HISTORY:
!  27 Aug 2014 - C. Keller   - Initial version. 
!EOP
!------------------------------------------------------------------------------
!BOC
CONTAINS
!EOC
!------------------------------------------------------------------------------
!                  Harvard-NASA Emissions Component (HEMCO)                   !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: EMISSIONS_INIT
!
! !DESCRIPTION: Subroutine EMISSIONS\_INIT calls the HEMCO - GEOS-Chem
! interface initialization routines.
!\\
!\\
! !INTERFACE:
!
  SUBROUTINE EMISSIONS_INIT( am_I_Root, Input_Opt, State_Met, State_Chm, RC ) 
!
! !USES:
!
    USE GIGC_ErrCode_Mod
    USE GIGC_Input_Opt_Mod, ONLY : OptInput
    USE GIGC_State_Met_Mod, ONLY : MetState
    USE GIGC_State_Chm_Mod, ONLY : ChmState
    USE ERROR_MOD,          ONLY : ERROR_STOP
    USE HCOI_GC_MAIN_MOD,   ONLY : HCOI_GC_INIT
!
! !INPUT PARAMETERS:
!
    LOGICAL,          INTENT(IN   )  :: am_I_Root  ! root CPU?
    TYPE(MetState),   INTENT(IN   )  :: State_Met  ! Met state
    TYPE(ChmState),   INTENT(IN   )  :: State_Chm  ! Chemistry state 
!
! !INPUT/OUTPUT PARAMETERS:
!
    TYPE(OptInput),   INTENT(INOUT)  :: Input_Opt  ! Input opts
    INTEGER,          INTENT(INOUT)  :: RC         ! Failure or success
!
! !REVISION HISTORY: 
!  27 Aug 2014 - C. Keller    - Initial version 
!EOP
!------------------------------------------------------------------------------
!BOC

    !=================================================================
    ! EMISSIONS_INIT begins here!
    !=================================================================

    ! Assume success
    RC = GIGC_SUCCESS

    ! Initialize the HEMCO environment for this GEOS-Chem run.
    CALL HCOI_GC_Init( am_I_Root, Input_Opt, State_Met, State_Chm, RC ) 
    IF ( RC/=GIGC_SUCCESS ) RETURN 

  END SUBROUTINE EMISSIONS_INIT
!EOC
!------------------------------------------------------------------------------
!                  Harvard-NASA Emissions Component (HEMCO)                   !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: EMISSIONS_RUN
!
! !DESCRIPTION: Subroutine EMISSIONS\_RUN calls the HEMCO - GEOS-Chem
! interface run routines.
!\\
!\\
! !INTERFACE:
!
  SUBROUTINE EMISSIONS_RUN( am_I_Root, Input_Opt, State_Met, State_Chm, RC ) 
!
! !USES:
!
    USE GIGC_ErrCode_Mod
    USE GIGC_Input_Opt_Mod, ONLY : OptInput
    USE GIGC_State_Met_Mod, ONLY : MetState
    USE GIGC_State_Chm_Mod, ONLY : ChmState
    USE ERROR_MOD,          ONLY : ERROR_STOP
    USE HCOI_GC_MAIN_MOD,   ONLY : HCOI_GC_RUN
    USE DUST_MOD,           ONLY : DUSTMIX
    USE CARBON_MOD,         ONLY : EMISSCARBON
    USE CO2_MOD,            ONLY : EMISSCO2
    USE GLOBAL_CH4_MOD,     ONLY : EMISSCH4
    USE TRACERID_MOD,       ONLY : IDTCH4

    ! Use old mercury code for now (ckeller, 09/23/2014)
    USE MERCURY_MOD,        ONLY : EMISSMERCURY

    ! For UCX, use Seb's routines for now
#if defined( UCX )
    USE UCX_MOD,            ONLY : EMISS_BASIC
#endif
!
! !INPUT PARAMETERS:
!
    LOGICAL,          INTENT(IN   )  :: am_I_Root  ! root CPU?
    TYPE(MetState),   INTENT(IN   )  :: State_Met  ! Met state
!
! !INPUT/OUTPUT PARAMETERS:
!
    TYPE(ChmState),   INTENT(INOUT)  :: State_Chm  ! Chemistry state 
    TYPE(OptInput),   INTENT(INOUT)  :: Input_Opt  ! Input opts
    INTEGER,          INTENT(INOUT)  :: RC         ! Failure or success
!
! !REVISION HISTORY: 
!  27 Aug 2014 - C. Keller    - Initial version 
!  13 Nov 2014 - C. Keller    - Added EMISSCARBON (for SESQ and POA)
!  21 Nov 2014 - C. Keller    - Added EMISSVOC to prevent VOC build-up
!                               above tropopause
!EOP
!------------------------------------------------------------------------------
!BOC
 
    !=================================================================
    ! EMISSIONS_RUN begins here!
    !=================================================================

    ! Assume success
    RC = GIGC_SUCCESS

    ! Run HEMCO
    CALL HCOI_GC_RUN( am_I_Root, Input_Opt, State_Met, State_Chm, RC ) 
    IF ( RC /= GIGC_SUCCESS ) RETURN 
  
    ! PBL mixing is not applied to dust emissions. Instead, they become 
    ! directly added to the tracer arrays.
    CALL DUSTMIX( am_I_Root, Input_Opt, State_Met, State_Chm, RC )
    IF ( RC /= GIGC_SUCCESS ) RETURN 

    ! Call carbon emissions module to make sure that sesquiterpene
    ! emissions calculated in HEMCO (SESQ) are passed to the internal
    ! species array in carbon, as well as to ensure that POA emissions
    ! are correctly treated.
    CALL EMISSCARBON( am_I_Root, Input_Opt, State_Met, State_Chm, RC )
    IF ( RC /= GIGC_SUCCESS ) RETURN 

    ! Aircraft emissions may go beyond the tropopause, which may cause 
    ! a build up of VOCs in the  
    CALL EMISSVOC( am_I_Root, Input_Opt, State_Met, State_Chm, RC )
    IF ( RC /= GIGC_SUCCESS ) RETURN 

    ! For CO2 simulation, emissions are not added to Trac_Tend and hence
    ! not passed to the Tracers array during PBL mixing. Thus, need to add 
    ! emissions explicitly to the tracers array here.
    IF ( Input_Opt%ITS_A_CO2_SIM ) THEN
       CALL EMISSCO2( am_I_Root, Input_Opt, State_Met, State_Chm, RC )
       IF ( RC /= GIGC_SUCCESS ) RETURN 
    ENDIF

    ! For CH4 simulation or if CH4 is defined, call EMISSCH4. 
    ! This will get the individual CH4 emission terms (gas, coal, wetlands, 
    ! ...) and write them into the individual emissions arrays defined in
    ! global_ch4_mod (CH4_EMIS), from where the final emission array is
    ! assembled and passed to STT or Trac_Tend.
    ! This is a wrapper for backwards consistency, in particular for the
    ! ND58 diagnostics.
    IF ( Input_Opt%ITS_A_CH4_SIM .OR.            &
       ( IDTCH4 > 0 .and. Input_Opt%LCH4EMIS ) ) THEN
       CALL EMISSCH4( am_I_Root, Input_Opt, State_Met, State_Chm, RC )
       IF ( RC /= GIGC_SUCCESS ) RETURN 
    ENDIF

    ! For UCX, use Seb's routines for stratospheric species for now.
#if defined( UCX )
    IF ( Input_Opt%LBASICEMIS ) THEN
       CALL EMISS_BASIC( am_I_Root, Input_Opt, State_Met, State_Chm )
    ENDIF
#endif

    ! For mercury, use old emissions code for now
    IF ( Input_Opt%ITS_A_MERCURY_SIM ) THEN
       CALL EMISSMERCURY ( am_I_Root, Input_Opt, State_Met, State_Chm, RC )
    ENDIF

    ! Return w/ success
    RC = GIGC_SUCCESS

  END SUBROUTINE EMISSIONS_RUN
!EOC
!------------------------------------------------------------------------------
!                  Harvard-NASA Emissions Component (HEMCO)                   !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: EMISSIONS_FINAL
!
! !DESCRIPTION: Subroutine EMISSIONS\_FINAL calls the HEMCO - GEOS-Chem
! interface finalization routines.
!\\
!\\
! !INTERFACE:
!
  SUBROUTINE EMISSIONS_FINAL( am_I_Root )
!
! !USES:
!
    USE HCOI_GC_MAIN_MOD, ONLY : HCOI_GC_FINAL
!
! !INPUT PARAMETERS:
!
    LOGICAL,          INTENT(IN   )  :: am_I_Root  ! root CPU?
!
! !REVISION HISTORY: 
!  27 Aug 2014 - C. Keller    - Initial version 
!EOP
!------------------------------------------------------------------------------
!BOC
 
    !=================================================================
    ! EMISSIONS_FINAL begins here!
    !=================================================================

    CALL HCOI_GC_Final( am_I_Root )

  END SUBROUTINE EMISSIONS_FINAL
!EOC
!------------------------------------------------------------------------------
!                  GEOS-Chem Global Chemical Transport Model                  !
!------------------------------------------------------------------------------
!BOP
!
! !IROUTINE: emissvoc
!
! !DESCRIPTION: Subroutine EMISSVOC makes sure that VOCs are not emitted 
! above the tropopause to prevent build up of VOC in the stratosphere.
!\\
!\\
! !INTERFACE:
!
      SUBROUTINE EMISSVOC( am_I_Root, Input_Opt, State_Met, State_Chm, RC )
!
! !USES:
!
      USE GIGC_ErrCode_Mod
      USE GIGC_Input_Opt_Mod,    ONLY : OptInput
      USE GIGC_State_Chm_Mod,    ONLY : ChmState
      USE GIGC_State_Met_Mod,    ONLY : MetState
      USE CHEMGRID_MOD,          ONLY : GET_CHEMGRID_LEVEL
      USE CMN_SIZE_MOD,          ONLY : IIPAR, JJPAR, LLPAR
      USE TRACERID_MOD,          ONLY : IDTMACR, IDTRCHO, IDTACET
      USE TRACERID_MOD,          ONLY : IDTALD2, IDTALK4, IDTC2H6
      USE TRACERID_MOD,          ONLY : IDTC3H8, IDTCH2O, IDTPRPE
      USE HCOI_GC_MAIN_MOD,      ONLY : GetHcoState, GetHcoID
      USE HCO_STATE_MOD,         ONLY : HCO_STATE
      USE HCO_ERROR_MOD
!
! !INPUT PARAMETERS:
!      
      LOGICAL,         INTENT(IN   )  :: am_I_Root   ! Root CPU?
      TYPE(OptInput),  INTENT(IN   )  :: Input_Opt   ! Input Options object
      TYPE(MetState),  INTENT(IN   )  :: State_Met   ! Meteorology State object
!
! !INPUT/OUTPUT PARAMETERS:
!
      TYPE(ChmState),  INTENT(INOUT)  :: State_Chm   ! Chemistry State object
      INTEGER,         INTENT(INOUT)  :: RC          ! Failure?
! 
! !REVISION HISTORY:
!  11 Nov 2014 - C. Keller   - Initial version
!EOP
!------------------------------------------------------------------------------
!BOC
!
! !LOCAL VARIABLES:
!
      TYPE(HCO_STATE), POINTER :: HcoState => NULL()
      INTEGER                  :: I, J, N, LMAX
      INTEGER                  :: ID, HcoID

      !=================================================================
      ! EMISSVOC begins here!
      !=================================================================

      ! Get HEMCO state object
      CALL GetHcoState( HcoState )

!$OMP PARALLEL DO DEFAULT( SHARED )      &
!$OMP PRIVATE( I, J, LMAX, N, ID, HcoID )
      DO J = 1, JJPAR
      DO I = 1, IIPAR

         ! Highest level w/ emissions
         LMAX = GET_CHEMGRID_LEVEL( I, J, State_Met )

         ! We want to zero emissions above LMAX 
         LMAX = MIN(LLPAR,LMAX+1)

         ! Set emissions of the following VOCs to zero above LMAX
         ! Adopted from aeic_mod.F
         DO N = 1, 9
            SELECT CASE ( N ) 
               CASE ( 1 )
                  ID = IDTMACR
               CASE ( 2 )
                  ID = IDTRCHO
               CASE ( 3 )
                  ID = IDTACET
               CASE ( 4 )
                  ID = IDTALD2
               CASE ( 5 )
                  ID = IDTALK4
               CASE ( 6 )
                  ID = IDTC2H6
               CASE ( 7 )
                  ID = IDTC3H8
               CASE ( 8 )
                  ID = IDTCH2O
               CASE ( 9 )
                  ID = IDTPRPE
               CASE DEFAULT
                  ID = -1
            END SELECT
            IF ( ID <= 0 ) CYCLE

            ! Does corresponding HEMCO tracer exist?
            HcoID = GetHcoID( TrcID=ID )
            IF ( HcoID <= 0 ) CYCLE

            ! Make sure all emissions above LMAX are zero
            IF ( ASSOCIATED( HcoState%Spc(HcoID)%Emis%Val) ) THEN
               HcoState%Spc(HcoID)%Emis%Val(I,J,LMAX:LLPAR) = 0.0_hp
            ENDIF
         ENDDO !N

      ENDDO !I
      ENDDO !J
!$OMP END PARALLEL DO

      ! Return w/ success
      HcoState => NULL()
      RC = GIGC_SUCCESS

      END SUBROUTINE EMISSVOC
!EOC
END MODULE EMISSIONS_MOD