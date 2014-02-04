!**********************************************************************************************************************************
! The HydroDyn and HydroDyn_Types modules make up a template for creating user-defined calculations in the FAST Modularization 
! Framework. HydroDyns_Types will be auto-generated based on a description of the variables for the module.
!
! "HydroDyn" should be replaced with the name of your module. Example: HydroDyn
! "HydroDyn" (in HydroDyn_*) should be replaced with the module name or an abbreviation of it. Example: HD
!..................................................................................................................................
! LICENSING
! Copyright (C) 2013  National Renewable Energy Laboratory
!
!    This file is part of HydroDyn.
!
! Licensed under the Apache License, Version 2.0 (the "License");
! you may not use this file except in compliance with the License.
! You may obtain a copy of the License at
!
!     http://www.apache.org/licenses/LICENSE-2.0
!
! Unless required by applicable law or agreed to in writing, software
! distributed under the License is distributed on an "AS IS" BASIS,
! WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
! See the License for the specific language governing permissions and
! limitations under the License.
!    
!**********************************************************************************************************************************
! File last committed: $Date: 2014-02-03 14:49:02 -0700 (Mon, 03 Feb 2014) $
! (File) Revision #: $Rev: 336 $
! URL: $HeadURL: https://windsvn.nrel.gov/HydroDyn/branches/HydroDyn_Modularization/Source/HydroDyn.f90 $
!**********************************************************************************************************************************
MODULE HydroDyn

   USE HydroDyn_Types   
   USE NWTC_Library
   USE WAMIT
   USE HydroDyn_Input
   USE HydroDyn_Output
   USE Current
      
   IMPLICIT NONE
   
   PRIVATE

  
   TYPE(ProgDesc), PARAMETER            :: HydroDyn_ProgDesc = ProgDesc( 'HydroDyn', 'v2.00.02d-gjh', '23-Jan-2014' )

   !TYPE, PUBLIC :: HD_ModuleMapType            
   !   TYPE(MeshMapType) ::           HD_P_2_WRP_P               !Map HD point mesh to WAMIT Reference Point, point mesh
   !   TYPE(MeshMapType) ::           M_P_2_WRP_P                !Map Morison point mesh to WAMIT Reference Point, point mesh
   !   TYPE(MeshMapType) ::           M_L_2_WRP_P                !Map Morison line2 mesh to WAMIT Reference Point, point mesh
   !END TYPE HD_ModuleMapType
   
   !HACK - HACK ALERT - HACK  TODO Remove this!!!!! GJH
   !TYPE(HD_ModuleMapType) :: HD_MeshMap
   ! End HACK ALERT
   
   
   
   
      ! ..... Public Subroutines ...................................................................................................

   PUBLIC :: HydroDyn_Init                           ! Initialization routine
   PUBLIC :: HydroDyn_End                            ! Ending routine (includes clean up)
   
   PUBLIC :: HydroDyn_UpdateStates                   ! Loose coupling routine for solving for constraint states, integrating 
                                                    !   continuous states, and updating discrete states
   PUBLIC :: HydroDyn_CalcOutput                     ! Routine for computing outputs
   
   PUBLIC :: HydroDyn_CalcConstrStateResidual        ! Tight coupling routine for returning the constraint state residual
   PUBLIC :: HydroDyn_CalcContStateDeriv             ! Tight coupling routine for computing derivatives of continuous states
   PUBLIC :: HydroDyn_UpdateDiscState                ! Tight coupling routine for updating discrete states
      
   !PUBLIC :: HydroDyn_JacobianPInput                 ! Routine to compute the Jacobians of the output (Y), continuous- (X), discrete-
   !                                                 !   (Xd), and constraint-state (Z) equations all with respect to the inputs (u)
   !PUBLIC :: HydroDyn_JacobianPContState             ! Routine to compute the Jacobians of the output (Y), continuous- (X), discrete-
   !                                                 !   (Xd), and constraint-state (Z) equations all with respect to the continuous 
   !                                                 !   states (x)
   !PUBLIC :: HydroDyn_JacobianPDiscState             ! Routine to compute the Jacobians of the output (Y), continuous- (X), discrete-
   !                                                 !   (Xd), and constraint-state (Z) equations all with respect to the discrete 
   !                                                 !   states (xd)
   !PUBLIC :: HydroDyn_JacobianPConstrState           ! Routine to compute the Jacobians of the output (Y), continuous- (X), discrete-
                                                    !   (Xd), and constraint-state (Z) equations all with respect to the constraint 
                                                    !   states (z)
   
 
CONTAINS
!----------------------------------------------------------------------------------------------------------------------------------
SUBROUTINE HydroDyn_Init( InitInp, u, p, x, xd, z, OtherState, y, Interval, InitOut, ErrStat, ErrMsg )
! This routine is called at the start of the simulation to perform initialization steps. 
! The parameters are set here and not changed during the simulation.
! The initial states and initial guess for the input are defined.
!..................................................................................................................................

      TYPE(HydroDyn_InitInputType),       INTENT(INOUT)  :: InitInp     ! Input data for initialization routine. TODO: This does not follow the template due to the interface of HydroDyn_CopyInitInput()
      TYPE(HydroDyn_InputType),           INTENT(  OUT)  :: u           ! An initial guess for the input; input mesh must be defined
      TYPE(HydroDyn_ParameterType),       INTENT(  OUT)  :: p           ! Parameters      
      TYPE(HydroDyn_ContinuousStateType), INTENT(  OUT)  :: x           ! Initial continuous states
      TYPE(HydroDyn_DiscreteStateType),   INTENT(  OUT)  :: xd          ! Initial discrete states
      TYPE(HydroDyn_ConstraintStateType), INTENT(  OUT)  :: z           ! Initial guess of the constraint states
      TYPE(HydroDyn_OtherStateType),      INTENT(  OUT)  :: OtherState  ! Initial other/optimization states            
      TYPE(HydroDyn_OutputType),          INTENT(INOUT)  :: y           ! Initial system outputs (outputs are not calculated; 
                                                                        !   only the output mesh is initialized)
      REAL(DbKi),                         INTENT(INOUT)  :: Interval    ! Coupling interval in seconds: the rate that 
                                                                        !   (1) HydroDyn_UpdateStates() is called in loose coupling &
                                                                        !   (2) HydroDyn_UpdateDiscState() is called in tight coupling.
                                                                        !   Input is the suggested time from the glue code; 
                                                                        !   Output is the actual coupling interval that will be used 
                                                                        !   by the glue code.
      TYPE(HydroDyn_InitOutputType),      INTENT(  OUT)  :: InitOut     ! Output for initialization routine
      INTEGER(IntKi),                     INTENT(  OUT)  :: ErrStat     ! Error status of the operation
      CHARACTER(*),                       INTENT(  OUT)  :: ErrMsg      ! Error message if ErrStat /= ErrID_None

      
         ! Local variables
         
      CHARACTER(1024)                        :: SummaryName                         ! name of the HydroDyn summary file   
      TYPE(HydroDyn_InitInputType)           :: InitLocal                           ! Local version of the initialization data, needed because the framework data (InitInp) is read-only
      TYPE(Waves_InitOutputType)             :: Waves_InitOut                       ! Initialization Outputs from the Waves module initialization
      TYPE(Current_InitOutputType)           :: Current_InitOut                     ! Initialization Outputs from the Current module initialization
      LOGICAL                                :: hasWAMITOuts                        ! Are there any WAMIT-related outputs
      LOGICAL                                :: hasMorisonOuts                      ! Are there any Morison-related outputs
      INTEGER                                :: numHydroOuts                        ! total number of WAMIT and Morison outputs
      INTEGER                                :: I, J                                ! Generic counters
      
         ! These are dummy variables to satisfy the framework, but are not used 
         
      TYPE(Waves_InputType)                  :: Waves_u                             ! Waves module initial guess for the input; the input mesh is not defined because it is not used by the waves module
      TYPE(Waves_ParameterType)              :: Waves_p                             ! Waves module parameters
      TYPE(Waves_ContinuousStateType)        :: Waves_x                             ! Waves module initial continuous states
      TYPE(Waves_DiscreteStateType)          :: Waves_xd                            ! Waves module discrete states
      TYPE(Waves_ConstraintStateType)        :: Waves_z                             ! Waves module initial guess of the constraint states
      TYPE(Waves_OtherStateType)             :: WavesOtherState                     ! Waves module other/optimization states 
      TYPE(Waves_OutputType)                 :: Waves_y                             ! Waves module outputs   
      TYPE(Current_InputType)                :: Current_u                           ! Current module initial guess for the input; the input mesh is not defined because it is not used by the Current module
      TYPE(Current_ParameterType)            :: Current_p                           ! Current module parameters
      TYPE(Current_ContinuousStateType)      :: Current_x                           ! Current module initial continuous states
      TYPE(Current_DiscreteStateType)        :: Current_xd                          ! Current module discrete states
      TYPE(Current_ConstraintStateType)      :: Current_z                           ! Current module initial guess of the constraint states
      TYPE(Current_OtherStateType)           :: CurrentOtherState                   ! Current module other/optimization states 
      TYPE(Current_OutputType)               :: Current_y                           ! Wave module outputs   
!bjj removed (see comments below):      TYPE(WAMIT_OutputType)                 :: WAMIT_y
      TYPE(WAMIT_ConstraintStateType)        :: WAMIT_z                             ! Initial guess of the constraint states
      TYPE(Morison_ContinuousStateType)      :: Morison_x                           ! Morison continuous states
      TYPE(Morison_DiscreteStateType)        :: Morison_xd                          ! Morison module discrete states
      TYPE(Morison_ConstraintStateType)      :: Morison_z                           ! Morison  of the constraint states
         
      
         ! Initialize ErrStat
         
      ErrStat = ErrID_None         
      ErrMsg  = ""               
      p%UnOutFile = -1 !bjj: this was being written to the screen when I had an error in my HD input file, so I'm going to initialize here.
      
      
         ! Copy the initialization input data to a local version because the framework states InitInp should have INTENT (IN), but due to an issue the the
         ! copy routine, we needed to make it (INOUT), which means we actually don't need this local version!!  I'm leaving this with the idea that the
         ! copy routine will get modified so that InitInp can have INTENT (IN) again.  GJH 4-Apr-2013
         
      CALL HydroDyn_CopyInitInput( InitInp, InitLocal, MESH_NEWCOPY, ErrStat, ErrMsg )   
      IF ( ErrStat > ErrID_Warn ) RETURN
      
      
         ! Initialize the NWTC Subroutine Library
         
      CALL NWTC_Init(  )
     
        
         ! Display the module information

      CALL DispNVD( HydroDyn_ProgDesc )        
      
      
      
      
      IF ( InitInp%UseInputFile ) THEN
         
                  
         ! Parse all HydroDyn-related input files and populate the *_InitInputType derived types
         
         CALL HydroDynInput_GetInput( InitLocal, ErrStat, ErrMsg )
         IF ( ErrStat > ErrID_Warn ) THEN
            RETURN
         END IF
         
      END IF
           
      
         ! Start with the glue code's timestep.  This may be altered in the Input file processing, and we will check that afterwards.
                 
      InitLocal%DT  = Interval
      
      
         ! Verify all the necessary initialization data. Do this at the HydroDynInput module-level 
         !   because the HydroDynInput module is also responsible for parsing all this 
         !   initialization data from a file
         
      CALL HydroDynInput_ProcessInitData( InitLocal, ErrStat, ErrMsg )     
      IF ( ErrStat > ErrID_Warn ) THEN      
         RETURN
      END IF
      
      
        ! Since the Convolution Radiation module is currently the only module which requires knowledge of the time step size, 
        !  we will set Hydrodyn's time step to be that of the Convolution radiation module if it is being used.  Otherwise, we
        !  will set it to be equal to the glue-codes
      IF ((Initlocal%HasWAMIT) .AND. (Initlocal%WAMIT%RdtnMod == 1) ) THEN
         p%DT = InitLocal%WAMIT%Conv_Rdtn%RdtnDT
      ELSE
         p%DT = Interval
      END IF  
      
         ! Open a summary of the HydroDyn Initialization. Note: OutRootName must be set by the caller because there may not be an input file to obtain this rootname from.
         
      IF ( InitLocal%HDSum ) THEN 
         
         SummaryName = TRIM(InitLocal%OutRootName)//'.HD.sum'
         CALL HDOut_OpenSum( InitLocal%UnSum, SummaryName, HydroDyn_ProgDesc, ErrStat, ErrMsg )    !this must be called before the Waves_Init() routine so that the appropriate wave data can be written to the summary file
         IF ( ErrStat > ErrID_Warn ) RETURN
      
      ELSE
         
         InitLocal%UnSum = -1
         
      END IF
      
         ! Copy Additional preload, stiffness, and damping to the parameters
      P%AddF0        = InitLocal%AddF0
      p%AddCLin      = InitLocal%AddCLin
      p%AddBLin      = InitLocal%AddBLin
      p%AddBQuad     = InitLocal%AddBQuad
      
      
         ! Set summary unit number in Waves, Radiation, and Morison initialization input data
         
      InitLocal%Waves%UnSum           = InitLocal%UnSum
      InitLocal%WAMIT%Conv_Rdtn%UnSum = InitLocal%UnSum
      InitLocal%Morison%UnSum         = InitLocal%UnSum      
    
      
         ! Now call each sub-module's *_Init subroutine
         ! to fully initialize each sub-module based on the necessary initialization data
      
         
         ! Initialize Current module
         
      CALL Current_Init(InitLocal%Current, Current_u, Current_p, Current_x, Current_xd, Current_z, CurrentOtherState, &
                                 Current_y, Interval, Current_InitOut, ErrStat, ErrMsg )   
      IF ( ErrStat > ErrID_Warn ) THEN      
         RETURN
      END IF 
      
      ! Verify that Current_Init() did not request a different Interval!
      
      IF ( p%DT /= Interval ) THEN
         ErrStat = ErrID_Fatal
         ErrMsg  = 'Current Module attempted to change timestep interval, but this is not allowed.  Current Module must use the HydroDyn Interval.'
      END IF
      
      
         ! Copy initialization output data from Current module into the initialization input data for the Waves module
         
      ALLOCATE ( InitLocal%Waves%CurrVxi(InitLocal%Current%NMorisonNodes), STAT = ErrStat )
      IF ( ErrStat /= 0 ) THEN 
         ErrMsg = ' Error allocating memory for the CurrVxi array.'
         RETURN
      END IF
      ALLOCATE ( InitLocal%Waves%CurrVyi(InitLocal%Current%NMorisonNodes), STAT = ErrStat )
      IF ( ErrStat /= 0 ) THEN 
         ErrMsg = ' Error allocating memory for the CurrVyi array.'
         RETURN
      END IF
      
      InitLocal%Waves%CurrVxi       = Current_InitOut%CurrVxi 
      InitLocal%Waves%CurrVyi       = Current_InitOut%CurrVyi 
      InitLocal%Waves%PCurrVxiPz0   = Current_InitOut%PCurrVxiPz0
      InitLocal%Waves%PCurrVyiPz0   = Current_InitOut%PCurrVyiPz0
         
      
      
      
         ! Initialize Waves module
          
      CALL Waves_Init(InitLocal%Waves, Waves_u, Waves_p, Waves_x, Waves_xd, Waves_z, WavesOtherState, &
                                 Waves_y, Interval, Waves_InitOut, ErrStat, ErrMsg )
      IF ( ErrStat > ErrID_Warn ) THEN      
         RETURN
      END IF
      
      
      ! Verify that Waves_Init() did not request a different Interval!
      
      IF ( p%DT /= Interval ) THEN
         ErrStat = ErrID_Fatal
         ErrMsg  = 'Waves Module attempted to change timestep interval, but this is not allowed.  Waves Module must use the HydroDyn Interval.'
      END IF
     
         ! Copy Waves initialization output into the initialization input type for the WAMIT module
         
      ALLOCATE ( p%WaveTime   (0:Waves_InitOut%NStepWave                    ) , STAT=ErrStat )
      IF ( ErrStat /= 0 )  THEN
         ErrMsg  = ' Error allocating memory for the WaveTime array.'
         ErrStat = ErrID_Fatal
         RETURN
      END IF
      ALLOCATE ( p%WaveElev   (0:Waves_InitOut%NStepWave,InitLocal%Waves%NWaveElev  ) , STAT=ErrStat )
      IF ( ErrStat /= 0 )  THEN
         ErrMsg  = ' Error allocating memory for the WaveElev array.'
         ErrStat = ErrID_Fatal
         RETURN
      END IF
      p%NWaveElev    = InitLocal%Waves%NWaveElev  
      p%NStepWave    = Waves_InitOut%NStepWave
      p%WaveTime     = Waves_InitOut%WaveTime
      p%WaveElev     = Waves_InitOut%WaveElev
      
      IF(ALLOCATED( Waves_InitOut%WaveElev   ))  DEALLOCATE( Waves_InitOut%WaveElev   )
      
      OtherState%LastIndWave = 1
      
         ! Is there a WAMIT body? 
      
      IF ( InitLocal%HasWAMIT ) THEN
         
            ! Copy Waves initialization output into the initialization input type for the WAMIT module
         
         ALLOCATE ( InitLocal%WAMIT%WaveTime   (0:Waves_InitOut%NStepWave                    ) , STAT=ErrStat )
         IF ( ErrStat /= 0 )  THEN
            ErrMsg  = ' Error allocating memory for the WaveTime array.'
            ErrStat = ErrID_Fatal
            RETURN
         END IF

         ALLOCATE ( InitLocal%WAMIT%WaveElevC0 (2, 0:Waves_InitOut%NStepWave2                  ) , STAT=ErrStat )
         IF ( ErrStat /= 0 )  THEN
            ErrMsg  = ' Error allocating memory for the WaveElevC0 array.'
            ErrStat = ErrID_Fatal
            RETURN
         END IF

      

         InitLocal%WAMIT%RhoXg        = Waves_InitOut%RhoXg
         InitLocal%WAMIT%NStepWave    = Waves_InitOut%NStepWave
         InitLocal%WAMIT%NStepWave2   = Waves_InitOut%NStepWave2
         InitLocal%WAMIT%WaveDOmega   = Waves_InitOut%WaveDOmega
         InitLocal%WAMIT%WaveElevC0   = Waves_InitOut%WaveElevC0
         InitLocal%WAMIT%WaveTime     = Waves_InitOut%WaveTime
         
            ! Deallocate this because it is not needed for the Morison_Init work
         IF(ALLOCATED( Waves_InitOut%WaveElevC0 ))  DEALLOCATE( Waves_InitOut%WaveElevC0 )
         
         
         
            ! Initialize the WAMIT Calculations 
           
         CALL WAMIT_Init(InitLocal%WAMIT, u%WAMIT, p%WAMIT, x%WAMIT, xd%WAMIT, WAMIT_z, OtherState%WAMIT, &
                                 y%WAMIT, Interval, InitOut%WAMIT, ErrStat, ErrMsg )
         IF ( ErrStat > ErrID_Warn ) THEN 
            RETURN
         END IF
         
         
            ! Verify that WAMIT_Init() did not request a different Interval!
      
         IF ( p%DT /= Interval ) THEN
            ErrStat = ErrID_Fatal
            ErrMsg  = 'WAMIT Module attempted to change timestep interval, but this is not allowed.  WAMIT Module must use the HydroDyn Interval.'
         END IF
      ELSE
            ! Deallocate this because it is not needed for the Morison_Init work
         IF(ALLOCATED( Waves_InitOut%WaveElevC0 ))  DEALLOCATE( Waves_InitOut%WaveElevC0 )
      END IF
      
!      CALL WAMIT_CopyOutput( WAMIT_y, y%WAMIT, MESH_NEWCOPY, ErrStat, ErrMsg )
!!bjj: added to avoid memory leak:      
!bjj: but then, it had an issue with the sibling mesh, so I just replaced WAMIT_y with y%WAMIT in WAMIT_Init, above
!call wamit_destroyoutput(wamit_y, ErrStat, ErrMsg, .TRUE.)

         ! Are there Morison elements?
       
      IF ( InitLocal%Morison%NMembers > 0 ) THEN
         
         
                ! Copy Waves initialization output into the initialization input type for the Morison module
         
         ALLOCATE ( InitLocal%Morison%WaveTime   (0:Waves_InitOut%NStepWave                    ) , STAT=ErrStat )
         IF ( ErrStat /= 0 )  THEN
            ErrMsg  = ' Error allocating memory for the WaveTime array.'
            ErrStat = ErrID_Fatal
            RETURN
         END IF
      
         ALLOCATE ( InitLocal%Morison%WaveVel0   (0:Waves_InitOut%NStepWave,InitLocal%Morison%NNodes,3) , STAT=ErrStat )
         IF ( ErrStat /= 0 )  THEN
            ErrMsg =' Error allocating memory for the WaveVel0 array.'
            ErrStat = ErrID_Fatal
            RETURN
         END IF
         
         ALLOCATE ( InitLocal%Morison%WaveAcc0   (0:Waves_InitOut%NStepWave,InitLocal%Morison%NNodes,3) , STAT=ErrStat )
         IF ( ErrStat /= 0 )  THEN
            ErrMsg =' Error allocating memory for the WaveAcc0 array.'
            ErrStat = ErrID_Fatal
            RETURN
         END IF
      
         ALLOCATE ( InitLocal%Morison%WaveDynP0   (0:Waves_InitOut%NStepWave,InitLocal%Morison%NNodes) , STAT=ErrStat )
         IF ( ErrStat /= 0 )  THEN
            ErrMsg =' Error allocating memory for the WaveDynP0 array.'
            ErrStat = ErrID_Fatal
            RETURN
         END IF
         
         
         
         InitLocal%Morison%NStepWave    = Waves_InitOut%NStepWave
         InitLocal%Morison%WaveAcc0     = Waves_InitOut%WaveAcc0
         InitLocal%Morison%WaveDynP0    = Waves_InitOut%WaveDynP0
         InitLocal%Morison%WaveTime     = Waves_InitOut%WaveTime
         InitLocal%Morison%WaveVel0     = Waves_InitOut%WaveVel0
         
         
            ! Clean up unneeded Waves_InitOut data
         IF(ALLOCATED( Waves_InitOut%WaveAcc0   ))  DEALLOCATE( Waves_InitOut%WaveAcc0   )
         IF(ALLOCATED( Waves_InitOut%WaveDynP0  ))  DEALLOCATE( Waves_InitOut%WaveDynP0  )
         IF(ALLOCATED( Waves_InitOut%WaveTime   ))  DEALLOCATE( Waves_InitOut%WaveTime   )
         IF(ALLOCATED( Waves_InitOut%WaveVel0   ))  DEALLOCATE( Waves_InitOut%WaveVel0   )
         
            
            ! Check the output switch to see if Morison is needing to send outputs back to HydroDyn via the WriteOutput array
            
         IF ( InitLocal%OutSwtch > 0 ) THEN
            InitLocal%Morison%OutSwtch     = 2  ! only HydroDyn or the Driver code will write outputs to the file
         END IF
        
      
            ! Initialize the Morison Element Calculations 
      
         CALL Morison_Init(InitLocal%Morison, u%Morison, p%Morison, Morison_x, Morison_xd, Morison_z, OtherState%Morison, &
                               y%Morison, Interval, InitOut%Morison, ErrStat, ErrMsg )
         IF ( ErrStat > ErrID_Warn ) THEN 
            RETURN
         END IF                   
         
         IF ( u%Morison%DistribMesh%Committed ) THEN
                  ! we need the translation displacement mesh for loads transfer:
            CALL MeshCopy ( SrcMesh  = u%Morison%DistribMesh            &
                    , DestMesh = OtherState%MrsnDistribMesh_position   &
                    , CtrlCode = MESH_NEWCOPY        &
                    , IOS      = COMPONENT_INPUT     &
                    , TranslationDisp = .TRUE.       &
                    , ErrStat  = ErrStat             &
                    , ErrMess  = ErrMsg              )  ! automatically sets    DestMesh%RemapFlag = .TRUE.
                    
            IF ( ErrStat /= ErrID_None ) RETURN
            OtherState%MrsnDistribMesh_position%TranslationDisp = 0.0  ! bjj: this is actually initialized in the ModMesh module, but I'll do it here anyway.
            
         END IF
         
         IF ( u%Morison%LumpedMesh%Committed ) THEN
                  ! we need the translation displacement mesh for loads transfer:
            CALL MeshCopy ( SrcMesh  = u%Morison%LumpedMesh            &
                    , DestMesh = OtherState%MrsnLumpedMesh_position   &
                    , CtrlCode = MESH_NEWCOPY        &
                    , IOS      = COMPONENT_INPUT     &
                    , TranslationDisp = .TRUE.       &
                    , ErrStat  = ErrStat             &
                    , ErrMess  = ErrMsg              )  ! automatically sets    DestMesh%RemapFlag = .TRUE.
                    
            IF ( ErrStat /= ErrID_None ) RETURN
            OtherState%MrsnLumpedMesh_position%TranslationDisp = 0.0  ! bjj: this is actually initialized in the ModMesh module, but I'll do it here anyway.
            
         END IF
            ! Verify that Morison_Init() did not request a different Interval!
      
         IF ( p%DT /= Interval ) THEN
            ErrStat = ErrID_Fatal
            ErrMsg  = 'Morison Module attempted to change timestep interval, but this is not allowed.  Morison Module must use the HydroDyn Interval.'
         END IF
         
      END IF  ! ( InitLocal%Morison%NMembers > 0 )
     
      
         ! Deallocate any remaining Waves Output data
      IF(ALLOCATED( Waves_InitOut%WaveAcc0   ))  DEALLOCATE( Waves_InitOut%WaveAcc0   )
      IF(ALLOCATED( Waves_InitOut%WaveDynP0  ))  DEALLOCATE( Waves_InitOut%WaveDynP0  )
      IF(ALLOCATED( Waves_InitOut%WaveTime   ))  DEALLOCATE( Waves_InitOut%WaveTime   )
      IF(ALLOCATED( Waves_InitOut%WaveVel0   ))  DEALLOCATE( Waves_InitOut%WaveVel0   )
      IF(ALLOCATED( Waves_InitOut%WaveElevC0 ))  DEALLOCATE( Waves_InitOut%WaveElevC0 )
         
      
         ! Close the summary file
         
      CALL HDOut_CloseSum( InitLocal%UnSum, ErrStat, ErrMsg )
      IF ( ErrStat > ErrID_Warn ) RETURN  
    
      
      ! Define system output initializations (set up mesh) here:
      
      
          ! Create the input and output meshes associated with lumped load at the WAMIT reference point (WRP)
      
      CALL MeshCreate( BlankMesh        = u%Mesh            &
                     ,IOS               = COMPONENT_INPUT   &
                     ,Nnodes            = 1                 &
                     ,ErrStat           = ErrStat           &
                     ,ErrMess           = ErrMsg            &
                     ,TranslationDisp   = .TRUE.            &
                     ,Orientation       = .TRUE.            &
                     ,TranslationVel    = .TRUE.            &
                     ,RotationVel       = .TRUE.            &
                     ,TranslationAcc    = .TRUE.            &
                     ,RotationAcc       = .TRUE.)
         ! Create the node on the mesh
            
      CALL MeshPositionNode (u%Mesh                                &
                              , 1                                  &
                              , (/0.0_ReKi, 0.0_ReKi, 0.0_ReKi/)   &  
                              , ErrStat                            &
                              , ErrMsg                             )
      
      IF ( ErrStat /= 0 ) RETURN
       
      
         ! Create the mesh element
      CALL MeshConstructElement (  u%Mesh              &
                                  , ELEMENT_POINT      &                         
                                  , ErrStat            &
                                  , ErrMsg             &
                                  , 1                  &
                                              )
      CALL MeshCommit ( u%Mesh   &
                      , ErrStat            &
                      , ErrMsg             )
   
      IF ( ErrStat /= 0 ) RETURN
      

         
      CALL MeshCopy (   SrcMesh      = u%Mesh               &
                     ,DestMesh     = y%Mesh                 &
                     ,CtrlCode     = MESH_SIBLING           &
                     ,IOS          = COMPONENT_OUTPUT       &
                     ,ErrStat      = ErrStat                &
                     ,ErrMess      = ErrMsg                 &
                     ,Force        = .TRUE.                 &
                     ,Moment       = .TRUE.                 )
     
      
      u%Mesh%RemapFlag  = .TRUE.
      y%Mesh%RemapFlag  = .TRUE.
     
     CALL MeshCopy (   SrcMesh     = y%Mesh                 &
                     ,DestMesh     = y%AllHdroOrigin        &
                     ,CtrlCode     = MESH_NEWCOPY           &
                     ,IOS          = COMPONENT_OUTPUT       &
                     ,ErrStat      = ErrStat                &
                     ,ErrMess      = ErrMsg                 &
                     ,Force        = .TRUE.                 &
                     ,Moment       = .TRUE.                 )
     
      
      y%AllHdroOrigin%RemapFlag  = .TRUE.
      
         ! we need the translation displacement mesh for loads transfer:
      CALL MeshCopy ( SrcMesh  = u%Mesh            &
                    , DestMesh = OtherState%AllHdroOrigin_position   &
                    , CtrlCode = MESH_NEWCOPY        &
                    , IOS      = COMPONENT_INPUT     &
                    , TranslationDisp = .TRUE.       &
                    , ErrStat  = ErrStat             &
                    , ErrMess  = ErrMsg              )  ! automatically sets    DestMesh%RemapFlag = .TRUE.
                    
      IF ( ErrStat /= ErrID_None ) RETURN
      OtherState%AllHdroOrigin_position%TranslationDisp = 0.0  ! bjj: this is actually initialized in the ModMesh module, but I'll do it here anyway.
      
     
         ! Create the Output file if requested
      
      p%OutSwtch      = InitLocal%OutSwtch 
      p%Delim         = ''
      !p%Morison%Delim = p%Delim  ! Need to set this from within Morison to follow framework
      !p%WAMIT%Delim   = p%Delim  ! Need to set this from within Morison to follow framework
      p%OutFmt        = InitLocal%OutFmt
      p%OutSFmt       = InitLocal%OutSFmt
      p%NumOuts       = InitLocal%NumOuts
      CALL HDOUT_Init( HydroDyn_ProgDesc, InitLocal, y,  p, InitOut, ErrStat, ErrMsg )
      

      
         ! Create some mesh mapping data
      CALL MeshCopy (   SrcMesh      = y%Mesh               &
                     ,DestMesh     = OtherState%y_mapped    &
                     ,CtrlCode     = MESH_NEWCOPY           &
                     ,IOS          = COMPONENT_OUTPUT       &
                     ,ErrStat      = ErrStat                &
                     ,ErrMess      = ErrMsg                 &
                     ,Force        = .TRUE.                 &
                     ,Moment       = .TRUE.                 )
          
      OtherState%y_mapped%RemapFlag  = .TRUE.
 
      CALL MeshMapCreate( y%Mesh,                OtherState%y_mapped, OtherState%HD_MeshMap%HD_P_2_WRP_P, ErrStat, ErrMsg  )
      CALL MeshMapCreate( y%Morison%LumpedMesh,  OtherState%y_mapped, OtherState%HD_MeshMap%M_P_2_WRP_P,  ErrStat, ErrMsg  )
      CALL MeshMapCreate( y%Morison%DistribMesh, OtherState%y_mapped, OtherState%HD_MeshMap%M_L_2_WRP_P,  ErrStat, ErrMsg  )
      
         ! Define initial guess for the system inputs here:

         ! Define system output initializations (set up mesh) here:
         
         InitOut%Ver = HydroDyn_ProgDesc
         
            ! These two come directly from processing the inputs, and so will exist even if not using Morison elements
         InitOut%WtrDens = InitLocal%Morison%WtrDens
         InitOut%WtrDpth = InitLocal%Morison%WtrDpth
         
         ! Define initialization-routine output here:
         
         
         ! Destroy the local initializatin data
         ! TODO: Verify that this is being done by the glue code.  GJH 6/18/13
!bjj: I uncommented this new source line because it was showing up as a memeory leak 7/26/2013
!bjj:   You should make sure this gets destroyed even if the routine returns early, though.
      CALL HydroDyn_DestroyInitInput( InitLocal,  ErrStat, ErrMsg )
                                        


END SUBROUTINE HydroDyn_Init
!----------------------------------------------------------------------------------------------------------------------------------
SUBROUTINE HydroDyn_End( u, p, x, xd, z, OtherState, y, ErrStat, ErrMsg )
! This routine is called at the end of the simulation.
!..................................................................................................................................

      TYPE(HydroDyn_InputType),           INTENT(INOUT)  :: u           ! System inputs
      TYPE(HydroDyn_ParameterType),       INTENT(INOUT)  :: p           ! Parameters     
      TYPE(HydroDyn_ContinuousStateType), INTENT(INOUT)  :: x           ! Continuous states
      TYPE(HydroDyn_DiscreteStateType),   INTENT(INOUT)  :: xd          ! Discrete states
      TYPE(HydroDyn_ConstraintStateType), INTENT(INOUT)  :: z           ! Constraint states
      TYPE(HydroDyn_OtherStateType),      INTENT(INOUT)  :: OtherState  ! Other/optimization states            
      TYPE(HydroDyn_OutputType),          INTENT(INOUT)  :: y           ! System outputs
      INTEGER(IntKi),                    INTENT(  OUT)  :: ErrStat      ! Error status of the operation
      CHARACTER(*),                      INTENT(  OUT)  :: ErrMsg       ! Error message if ErrStat /= ErrID_None



         ! Initialize ErrStat
         
      ErrStat = ErrID_None         
      ErrMsg  = ""               
      
      
         ! Place any last minute operations or calculations here:


         ! Close files here:     
                  
          CALL HDOut_CloseOutput( p, ErrStat, ErrMsg )           
          

         ! Destroy the input data:
         
      CALL HydroDyn_DestroyInput( u, ErrStat, ErrMsg )


         ! Destroy the parameter data:
      
      CALL HydroDyn_DestroyParam( p, ErrStat, ErrMsg )


         ! Destroy the state data:
         
      CALL HydroDyn_DestroyContState(   x,           ErrStat, ErrMsg )
      CALL HydroDyn_DestroyDiscState(   xd,          ErrStat, ErrMsg )
      CALL HydroDyn_DestroyConstrState( z,           ErrStat, ErrMsg )
      CALL HydroDyn_DestroyOtherState(  OtherState,  ErrStat, ErrMsg )
         

         ! Destroy the output data:
         
      CALL HydroDyn_DestroyOutput( y, ErrStat, ErrMsg )

!bjj: this is done in HydroDyn_DestroyOtherState now:
         ! Destroy mesh mapping data
      CALL MeshMapDestroy( OtherState%HD_MeshMap%HD_P_2_WRP_P, ErrStat, ErrMsg ); IF ( ErrStat /= ErrID_None ) CALL WrScr(TRIM(ErrMsg))
      CALL MeshMapDestroy( OtherState%HD_MeshMap%M_P_2_WRP_P,  ErrStat, ErrMsg ); IF ( ErrStat /= ErrID_None ) CALL WrScr(TRIM(ErrMsg))
      CALL MeshMapDestroy( OtherState%HD_MeshMap%M_L_2_WRP_P,  ErrStat, ErrMsg ); IF ( ErrStat /= ErrID_None ) CALL WrScr(TRIM(ErrMsg))
      

END SUBROUTINE HydroDyn_End


!----------------------------------------------------------------------------------------------------------------------------------
SUBROUTINE HydroDyn_UpdateStates( t, n, Inputs, InputTimes, p, x, xd, z, OtherState, ErrStat, ErrMsg )
! Loose coupling routine for solving constraint states, integrating continuous states, and updating discrete states.
! Continuous, constraint, and discrete states are updated to values at t + Interval.
!..................................................................................................................................

      REAL(DbKi),                         INTENT(IN   )  :: t               ! Current simulation time in seconds
      INTEGER(IntKi),                     INTENT(IN   )  :: n               ! Current step of the simulation: t = n*Interval
      TYPE(HydroDyn_InputType),           INTENT(INOUT ) :: Inputs(:)       ! Inputs at InputTimes
      REAL(DbKi),                         INTENT(IN   )  :: InputTimes(:)   ! Times in seconds associated with Inputs
      TYPE(HydroDyn_ParameterType),       INTENT(IN   )  :: p               ! Parameters
      TYPE(HydroDyn_ContinuousStateType), INTENT(INOUT)  :: x               ! Input: Continuous states at t;
                                                                            !   Output: Continuous states at t + Interval
      TYPE(HydroDyn_DiscreteStateType),   INTENT(INOUT)  :: xd              ! Input: Discrete states at t;
                                                                            !   Output: Discrete states at t + Interval
      TYPE(HydroDyn_ConstraintStateType), INTENT(INOUT)  :: z               ! Input: Constraint states at t;
                                                                            !   Output: Constraint states at t + Interval
      TYPE(HydroDyn_OtherStateType),      INTENT(INOUT)  :: OtherState      ! Other/optimization states
      INTEGER(IntKi),                     INTENT(  OUT)  :: ErrStat         ! Error status of the operation
      CHARACTER(*),                       INTENT(  OUT)  :: ErrMsg          ! Error message if ErrStat /= ErrID_None

         ! Local variables
      INTEGER                                            :: I               ! Generic loop counter
      TYPE(HydroDyn_ContinuousStateType)                 :: dxdt            ! Continuous state derivatives at t
      TYPE(HydroDyn_DiscreteStateType)                   :: xd_t            ! Discrete states at t (copy)
      TYPE(HydroDyn_ConstraintStateType)                 :: z_Residual      ! Residual of the constraint state functions (Z)
      TYPE(HydroDyn_InputType)                           :: u               ! Instantaneous inputs
      INTEGER(IntKi)                                     :: ErrStat2        ! Error status of the operation (secondary error)
      CHARACTER(LEN(ErrMsg))                             :: ErrMsg2         ! Error message if ErrStat2 /= ErrID_None
      INTEGER                                            :: nTime           ! number of inputs 
!BJJ: I'd probably make this (below) an OtherState variable so you don't have to allocate/deallocate each time 
      TYPE(WAMIT_InputType), ALLOCATABLE                 :: Inputs_WAMIT(:)  
      
      
          ! Create dummy variables required by framework but which are not used by the module
      
      TYPE(WAMIT_ConstraintStateType)    :: WAMIT_z            ! constraint states
      
      
         ! Initialize variables

      ErrStat   = ErrID_None           ! no error has occurred
      ErrMsg    = ""
      
      
         ! Return without doing any work if the input mesh is not initialized (NOT USING WAMIT)
      
      IF ( .NOT. Inputs(1)%WAMIT%Mesh%Initialized  ) RETURN
      
      nTime = size(Inputs)   
      
      
         ! Allocate array of WAMIT inputs
         ! TODO: We should avoid allocating this at each time step if we can!
         
      ALLOCATE( Inputs_WAMIT(nTime), STAT = ErrStat )
      IF (ErrStat /=0) THEN
         ErrMsg = ' Failed to allocate array Inputs_WAMIT.'
         RETURN
      END IF

         
         ! Loop over number of inputs and copy them into an array of WAMIT inputs
      
      DO I=1,nTime
         CALL WAMIT_CopyInput( Inputs(I)%WAMIT, Inputs_WAMIT(I), MESH_NEWCOPY, ErrStat, ErrMsg )     
      END DO
      
         
         
         ! Update the WAMIT module states
      
      CALL WAMIT_UpdateStates( t, n, Inputs_WAMIT, InputTimes, p%WAMIT, x%WAMIT, xd%WAMIT, WAMIT_z, OtherState%WAMIT, ErrStat, ErrMsg )
     

      DO I=1,nTime
         CALL WAMIT_DestroyInput( Inputs_WAMIT(I), ErrStat, ErrMsg )     
      END DO
      
      DEALLOCATE(Inputs_WAMIT)
     
      
END SUBROUTINE HydroDyn_UpdateStates


!----------------------------------------------------------------------------------------------------------------------------------
SUBROUTINE HydroDyn_CalcOutput( Time, u, p, x, xd, z, OtherState, y, ErrStat, ErrMsg )   
! Routine for computing outputs, used in both loose and tight coupling.
!..................................................................................................................................
   
      REAL(DbKi),                         INTENT(IN   )  :: Time        ! Current simulation time in seconds
      TYPE(HydroDyn_InputType),           INTENT(INOUT)  :: u           ! Inputs at Time
      TYPE(HydroDyn_ParameterType),       INTENT(IN   )  :: p           ! Parameters
      TYPE(HydroDyn_ContinuousStateType), INTENT(IN   )  :: x           ! Continuous states at Time
      TYPE(HydroDyn_DiscreteStateType),   INTENT(IN   )  :: xd          ! Discrete states at Time
      TYPE(HydroDyn_ConstraintStateType), INTENT(IN   )  :: z           ! Constraint states at Time
      TYPE(HydroDyn_OtherStateType),      INTENT(INOUT)  :: OtherState  ! Other/optimization states
      TYPE(HydroDyn_OutputType),          INTENT(INOUT)  :: y           ! Outputs computed at Time (Input only so that mesh con-
                                                                        !   nectivity information does not have to be recalculated)
      INTEGER(IntKi),                     INTENT(  OUT)  :: ErrStat     ! Error status of the operation
      CHARACTER(*),                       INTENT(  OUT)  :: ErrMsg      ! Error message if ErrStat /= ErrID_None

      INTEGER                                            :: I, J        ! Generic counters
      
      REAL(ReKi)                           :: WaveElev (p%NWaveElev)                  ! Instantaneous elevation of incident waves at each of the NWaveElev points where the incident wave elevations can be output (meters)
      
      REAL(ReKi)                           :: q(6), qdot(6), qdotsq(6), qdotdot(6)
      REAL(ReKi)                           :: rotdisp(3)                              ! small angle rotational displacements
      REAL(ReKi)                           :: AllOuts(MaxHDOutputs)  
      
      TYPE(WAMIT_InputType)             :: uLocal           ! Local copy of WAMIT inputs 
         ! Create dummy variables required by framework but which are not used by the module
         
      !TYPE(WAMIT_ContinuousStateType) :: WAMIT_x           ! Initial continuous states
      TYPE(WAMIT_ConstraintStateType) :: WAMIT_z           ! Initial guess of the constraint states
      !TYPE(WAMIT_OtherStateType)      :: WAMITOtherState  ! Initial other/optimization states            
     
      TYPE(Morison_ContinuousStateType) :: Morison_x           ! Initial continuous states
      TYPE(Morison_DiscreteStateType)   :: Morison_xd           ! Initial discrete states
      TYPE(Morison_ConstraintStateType) :: Morison_z           ! Initial guess of the constraint states
      
         ! Initialize ErrStat
         
      ErrStat = ErrID_None         
      ErrMsg  = ""               
      
      
         ! Compute outputs here:
         
         
         !-------------------------------------------------------------------
         ! Additional stiffness, damping forces.  These need to be placed on a point mesh which is located at the WAMIT reference point (WRP).
         ! This mesh will need to get mapped by the glue code for use by either ElastoDyn or SubDyn.
         !-------------------------------------------------------------------
         
         ! Determine the rotational angles from the direction-cosine matrix
      rotdisp = GetSmllRotAngs ( u%Mesh%Orientation(:,:,1), ErrStat, ErrMsg )

      q         = reshape((/u%Mesh%TranslationDisp(:,1),rotdisp(:)/),(/6/))
      qdot      = reshape((/u%Mesh%TranslationVel(:,1),u%Mesh%RotationVel(:,1)/),(/6/))
      qdotsq    = abs(qdot)*qdot
      qdotdot   = reshape((/u%Mesh%TranslationAcc(:,1),u%Mesh%RotationAcc(:,1)/),(/6/))
      
      
         ! Compute the load contirbution from user-supplied added stiffness and damping
         
      OtherState%F_PtfmAdd = p%AddF0 - matmul(p%AddCLin, q) - matmul(p%AddBLin, qdot) - matmul(p%AddBQuad, qdotsq)
      
         ! Attach to the output point mesh
      y%Mesh%Force (:,1) = OtherState%F_PtfmAdd(1:3)
      y%Mesh%Moment(:,1) = OtherState%F_PtfmAdd(4:6)
      
      
      IF ( u%WAMIT%Mesh%Initialized ) THEN  ! Make sure we are using WAMIT / there is a valid mesh
         
            ! Copy the inputs from the HD mesh into the WAMIT mesh
         CALL MeshCopy( u%Mesh, u%WAMIT%Mesh, MESH_UPDATECOPY, ErrStat, ErrMsg )   
            IF ( ErrStat > ErrID_Warn ) RETURN
         
         
         CALL WAMIT_CalcOutput( Time, u%WAMIT, p%WAMIT, x%WAMIT, xd%WAMIT,  &
                                WAMIT_z, OtherState%WAMIT, y%WAMIT, ErrStat, ErrMsg )
         
            ! Add WAMIT forces to the HydroDyn output mesh
         y%Mesh%Force (:,1) = y%Mesh%Force (:,1) + y%WAMIT%Mesh%Force (:,1)
         y%Mesh%Moment(:,1) = y%Mesh%Moment(:,1) + y%WAMIT%Mesh%Moment(:,1)
         
            ! Destroy local inputs
         CALL WAMIT_DestroyInput( uLocal,  ErrStat, ErrMsg )
         
      END IF
      
      IF ( u%Morison%LumpedMesh%Initialized ) THEN  ! Make sure we are using Morison / there is a valid mesh
         CALL Morison_CalcOutput( Time, u%Morison, p%Morison, Morison_x, Morison_xd,  &
                                Morison_z, OtherState%Morison, y%Morison, ErrStat, ErrMsg )
      END IF
      
      
         ! Integrate all the mesh loads onto the WAMIT reference Point (WRP) at (0,0,0)
      OtherState%F_Hydro = CalcLoadsAtWRP( y, u, OtherState%y_mapped, OtherState%AllHdroOrigin_position, OtherState%MrsnLumpedMesh_position, OtherState%MrsnDistribMesh_position, OtherState%HD_MeshMap, ErrStat, ErrMsg )
      
      
         ! Compute the wave elevations at the requested output locations for this time
         
      DO I=1,p%NWaveElev   
         WaveElev(I) = InterpWrappedStpReal ( REAL(Time, ReKi), p%WaveTime(:), p%WaveElev(:,I), &
                                    OtherState%LastIndWave, p%NStepWave + 1       )
      END DO
      
      
         ! Map calculated results into the AllOuts Array
         
      CALL HDOut_MapOutputs( Time, y, p%NWaveElev, WaveElev, OtherState%F_PtfmAdd, OtherState%F_Hydro, AllOuts, ErrStat, ErrMsg )
      
      DO I = 1,p%NumOuts
            y%WriteOutput(I) = p%OutParam(I)%SignM * AllOuts( p%OutParam(I)%Indx )
      END DO        
      
         ! Write the HydroDyn-level output file data if the user requested module-level output
         
      IF ( p%OutSwtch == 1 .OR. p%OutSwtch == 3 ) THEN   
            
         CALL HDOut_WriteOutputs( Time, y, p, ErrStat, ErrMsg )         
      END IF
      
      
         ! Aggregate the sub-module outputs for the glue code
         
      IF ( p%OutSwtch == 2 .OR. p%OutSwtch == 3 ) THEN
         
         J = p%NumOuts + 1        
         
         IF (ALLOCATED( p%WAMIT%OutParam ) .AND. p%WAMIT%NumOuts > 0) THEN
            DO I=1, p%WAMIT%NumOuts
               y%WriteOutput(J) = y%WAMIT%WriteOutput(I)
               J = J + 1
            END DO
         END IF
         
         IF (ALLOCATED( p%Morison%OutParam ) .AND. p%Morison%NumOuts > 0) THEN
            DO I=1, p%Morison%NumOuts
               y%WriteOutput(J) = y%Morison%WriteOutput(I)
               J = J + 1
            END DO
         END IF
         
      END IF
      
END SUBROUTINE HydroDyn_CalcOutput


!----------------------------------------------------------------------------------------------------------------------------------
SUBROUTINE HydroDyn_CalcContStateDeriv( Time, u, p, x, xd, z, OtherState, dxdt, ErrStat, ErrMsg )  
! Tight coupling routine for computing derivatives of continuous states
!..................................................................................................................................
   
      REAL(DbKi),                         INTENT(IN   )  :: Time        ! Current simulation time in seconds
      TYPE(HydroDyn_InputType),           INTENT(IN   )  :: u           ! Inputs at Time                    
      TYPE(HydroDyn_ParameterType),       INTENT(IN   )  :: p           ! Parameters                             
      TYPE(HydroDyn_ContinuousStateType), INTENT(IN   )  :: x           ! Continuous states at Time
      TYPE(HydroDyn_DiscreteStateType),   INTENT(IN   )  :: xd          ! Discrete states at Time
      TYPE(HydroDyn_ConstraintStateType), INTENT(IN   )  :: z           ! Constraint states at Time
      TYPE(HydroDyn_OtherStateType),      INTENT(INOUT)  :: OtherState  ! Other/optimization states                    
      TYPE(HydroDyn_ContinuousStateType), INTENT(  OUT)  :: dxdt        ! Continuous state derivatives at Time
      INTEGER(IntKi),                     INTENT(  OUT)  :: ErrStat     ! Error status of the operation     
      CHARACTER(*),                       INTENT(  OUT)  :: ErrMsg      ! Error message if ErrStat /= ErrID_None

               
         ! Initialize ErrStat
         
      ErrStat = ErrID_None         
      ErrMsg  = ""               
      
      
         ! Compute the first time derivatives of the continuous states here:
      
    !  dxdt%DummyContState = 0
         

END SUBROUTINE HydroDyn_CalcContStateDeriv


!----------------------------------------------------------------------------------------------------------------------------------
SUBROUTINE HydroDyn_UpdateDiscState( Time, n, u, p, x, xd, z, OtherState, ErrStat, ErrMsg )   
! Tight coupling routine for updating discrete states
!..................................................................................................................................
   
      REAL(DbKi),                        INTENT(IN   )  :: Time        ! Current simulation time in seconds   
      INTEGER(IntKi),                     INTENT(IN   ) :: n               ! Current step of the simulation: t = n*Interval
      TYPE(HydroDyn_InputType),           INTENT(IN   )  :: u           ! Inputs at Time                       
      TYPE(HydroDyn_ParameterType),       INTENT(IN   )  :: p           ! Parameters                                 
      TYPE(HydroDyn_ContinuousStateType), INTENT(IN   )  :: x           ! Continuous states at Time
      TYPE(HydroDyn_DiscreteStateType),   INTENT(INOUT)  :: xd          ! Input: Discrete states at Time; 
                                                                       !   Output: Discrete states at Time + Interval
      TYPE(HydroDyn_ConstraintStateType), INTENT(IN   )  :: z           ! Constraint states at Time
      TYPE(HydroDyn_OtherStateType),      INTENT(INOUT)  :: OtherState  ! Other/optimization states           
      INTEGER(IntKi),                    INTENT(  OUT)  :: ErrStat     ! Error status of the operation
      CHARACTER(*),                      INTENT(  OUT)  :: ErrMsg      ! Error message if ErrStat /= ErrID_None

      
         ! Create dummy variables required by framework but which are not used by the module
         ! TODO: considering adding these to HydroDyn_ContinuousStateType, HydroDyn_ConstraintStateType, HydroDyn_OtherStateType
      TYPE(WAMIT_ContinuousStateType) :: WAMIT_x           ! Initial continuous states
      TYPE(WAMIT_ConstraintStateType) :: WAMIT_z           ! Initial guess of the constraint states
      TYPE(WAMIT_OtherStateType)      :: WAMITOtherState  ! Initial other/optimization states     
      
      
         ! Initialize ErrStat
         
      ErrStat = ErrID_None         
      ErrMsg  = ""               
      
      
         ! Update discrete states 
         
      IF ( u%WAMIT%Mesh%Initialized ) THEN    
         CALL WAMIT_UpdateDiscState( Time, n, u%WAMIT, p%WAMIT, WAMIT_x, xd%WAMIT, WAMIT_z, WAMITOtherState, ErrStat, ErrMsg )          
         IF ( ErrStat > ErrID_Warn )  RETURN
      END IF
      

END SUBROUTINE HydroDyn_UpdateDiscState


!----------------------------------------------------------------------------------------------------------------------------------
SUBROUTINE HydroDyn_CalcConstrStateResidual( Time, u, p, x, xd, z, OtherState, z_residual, ErrStat, ErrMsg )   
! Tight coupling routine for solving for the residual of the constraint state equations
!..................................................................................................................................
   
      REAL(DbKi),                        INTENT(IN   )  :: Time        ! Current simulation time in seconds   
      TYPE(HydroDyn_InputType),           INTENT(IN   )  :: u           ! Inputs at Time                       
      TYPE(HydroDyn_ParameterType),       INTENT(IN   )  :: p           ! Parameters                           
      TYPE(HydroDyn_ContinuousStateType), INTENT(IN   )  :: x           ! Continuous states at Time
      TYPE(HydroDyn_DiscreteStateType),   INTENT(IN   )  :: xd          ! Discrete states at Time
      TYPE(HydroDyn_ConstraintStateType), INTENT(IN   )  :: z           ! Constraint states at Time (possibly a guess)
      TYPE(HydroDyn_OtherStateType),      INTENT(INOUT)  :: OtherState  ! Other/optimization states                    
      TYPE(HydroDyn_ConstraintStateType), INTENT(  OUT)  :: z_residual  ! Residual of the constraint state equations using  
                                                                       !     the input values described above      
      INTEGER(IntKi),                    INTENT(  OUT)  :: ErrStat     ! Error status of the operation
      CHARACTER(*),                      INTENT(  OUT)  :: ErrMsg      ! Error message if ErrStat /= ErrID_None

               
         ! Initialize ErrStat
         
      ErrStat = ErrID_None         
      ErrMsg  = ""               
      
      
         ! Solve for the constraint states here:
      
      

END SUBROUTINE HydroDyn_CalcConstrStateResidual


FUNCTION CalcLoadsAtWRP( y, u, y_mapped, AllHdroOrigin_position, MrsnLumpedMesh_Postion, MrsnDistribMesh_Position, MeshMapData, ErrStat, ErrMsg )

   TYPE(HydroDyn_OutputType),  INTENT(INOUT)  :: y                   ! Hydrodyn outputs
   TYPE(HydroDyn_InputType),   INTENT(IN   )  :: u                   ! Hydrodyn inputs
   TYPE(MeshType),             INTENT(INOUT)  :: y_mapped            ! This is the mesh which data is mapped onto.  We pass it in to avoid allocating it at each call
   TYPE(MeshType),             INTENT(IN   )  :: AllHdroOrigin_position            ! This is the mesh which data is mapped onto.  We pass it in to avoid allocating it at each call
   TYPE(MeshType),             INTENT(IN   )  :: MrsnLumpedMesh_Postion            ! This is the mesh which data is mapped onto.  We pass it in to avoid allocating it at each call 
   TYPE(MeshType),             INTENT(IN   )  :: MrsnDistribMesh_Position            ! This is the mesh which data is mapped onto.  We pass it in to avoid allocating it at each call
   TYPE(HD_ModuleMapType),     INTENT(INOUT)  :: MeshMapData         ! Map  data structures 
   INTEGER(IntKi),             INTENT(  OUT)  :: ErrStat             ! Error status of the operation
   CHARACTER(*),               INTENT(  OUT)  :: ErrMsg              ! Error message if ErrStat /= ErrID_None                                                         
   REAL(ReKi)                                 :: CalcLoadsAtWRP(6)

      ! local variables
   INTEGER(IntKi)                                 :: ErrStat2                  ! temporary Error status of the operation
   CHARACTER(LEN(ErrMsg))                         :: ErrMsg2                   ! temporary Error message if ErrStat /= ErrID_None
   
   y%AllHdroOrigin%Force = 0.0
   y%AllHdroOrigin%Moment= 0.0
   
   IF ( y%Mesh%Committed  ) THEN

      ! Just transfer the loads because the meshes are at the same location (0,0,0)

      y%AllHdroOrigin%Force  =  y%Mesh%Force
      y%AllHdroOrigin%Moment =  y%Mesh%Moment

   END IF      
      
   IF ( y%Morison%LumpedMesh%Committed ) THEN 

         ! This is viscous drag associate with the WAMIT body and/or filled/flooded forces of the WAMIT body

      CALL Transfer_Point_to_Point( y%Morison%LumpedMesh, y_mapped, MeshMapData%M_P_2_WRP_P, ErrStat2, ErrMsg2, MrsnLumpedMesh_Postion, AllHdroOrigin_position )
         CALL CheckError( ErrStat2, ErrMsg2 )
         IF (ErrStat >= AbortErrLev) RETURN
            
      y%AllHdroOrigin%Force  = y%AllHdroOrigin%Force  + y_mapped%Force
      y%AllHdroOrigin%Moment = y%AllHdroOrigin%Moment + y_mapped%Moment

   END IF
   
   IF ( y%Morison%DistribMesh%Committed ) THEN 

      CALL Transfer_Line2_to_Point( y%Morison%DistribMesh, y_mapped, MeshMapData%M_L_2_WRP_P, ErrStat2, ErrMsg2,  MrsnDistribMesh_Position, AllHdroOrigin_position )
         CALL CheckError( ErrStat2, ErrMsg2 )
         IF (ErrStat >= AbortErrLev) RETURN
 
      y%AllHdroOrigin%Force  = y%AllHdroOrigin%Force  + y_mapped%Force
      y%AllHdroOrigin%Moment = y%AllHdroOrigin%Moment + y_mapped%Moment
         
   END IF
   
   CalcLoadsAtWRP(1:3) = y%AllHdroOrigin%Force(:,1)
   CalcLoadsAtWRP(4:6) = y%AllHdroOrigin%Moment(:,1)

CONTAINS   
   !...............................................................................................................................
   SUBROUTINE CheckError(ErrID,Msg)
   ! This subroutine sets the error message and level and cleans up if the error is >= AbortErrLev
   !...............................................................................................................................

         ! Passed arguments
      INTEGER(IntKi), INTENT(IN) :: ErrID       ! The error identifier (ErrStat)
      CHARACTER(*),   INTENT(IN) :: Msg         ! The error message (ErrMsg)

      INTEGER(IntKi)             :: ErrStat3    ! The error identifier (ErrStat)
      CHARACTER(1024)            :: ErrMsg3     ! The error message (ErrMsg)

      !............................................................................................................................
      ! Set error status/message;
      !............................................................................................................................
      
      IF ( ErrID /= ErrID_None ) THEN

         IF ( LEN_TRIM(ErrMsg) > 0 ) ErrMsg = TRIM(ErrMsg)//NewLine
         ErrMsg = TRIM(ErrMsg)//' CalcLoadsAtWRP:'//TRIM(Msg)
         ErrStat = MAX(ErrStat, ErrID)
         
         !.........................................................................................................................
         ! Clean up if we're going to return on error: close files, deallocate local arrays
         !.........................................................................................................................
      END IF

   END SUBROUTINE CheckError
END FUNCTION CalcLoadsAtWRP
!----------------------------------------------------------------------------------------------------------------------------------
   
END MODULE HydroDyn
!**********************************************************************************************************************************
