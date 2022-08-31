.include "macros.inc"

.set sp, r1

################################################################################
# Macros
################################################################################
.macro branchl reg, address
lis \reg, \address @h
ori \reg,\reg,\address @l
mtctr \reg
bctrl
.endm

.macro branch reg, address
lis \reg, \address @h
ori \reg,\reg,\address @l
mtctr \reg
bctr
.endm

.macro load reg, address
lis \reg, \address @h
ori \reg, \reg, \address @l
.endm

.macro loadf regf,reg,address
lis \reg, \address @h
ori \reg, \reg, \address @l
stw \reg,-0x4(sp)
lfs \regf,-0x4(sp)
.endm

.macro loadwz reg, address
lis \reg, \address @h
ori \reg, \reg, \address @l
lwz \reg, 0(\reg)
.endm

.macro loadbz reg, address
lis \reg, \address @h
ori \reg, \reg, \address @l
lbz \reg, 0(\reg)
.endm

.macro incrementByteInBuf reg, reg_address, offset, limit
lbz \reg, \offset(\reg_address)
addi \reg, \reg, 1
cmpwi \reg, \limit
blt 0f
li \reg, 0
0:
stb \reg, \offset(\reg_address)
.endm

# Compiled from the following:
# int func(int current, int change, int limit) {
#     return (((current + change) % limit) + limit) % limit;
# }
.macro adjustCircularIndex reg, reg_current, reg_change, reg_limit, reg_temp=r0
add \reg, \reg_current, \reg_change
divw \reg_temp, \reg, \reg_limit
mullw \reg_temp, \reg_temp, \reg_limit
subf \reg_temp, \reg_temp, \reg
add \reg, \reg_limit, \reg_temp
divw \reg_temp, \reg, \reg_limit
mullw \reg_temp, \reg_temp, \reg_limit
subf \reg, \reg_temp, \reg
.endm

.macro bp
branchl r12, lbl_8021B2D8
.endm

.set BKP_FREE_SPACE_OFFSET, 0x38 # This is where the free space in our stack starts

.macro backup space=0x78
mflr r0
stw r0, 0x4(r1)
# Stack allocation has to be 4-byte aligned otherwise it crashes on console
.if \space % 4 == 0
  stwu r1,-(BKP_FREE_SPACE_OFFSET + \space)(r1)	# make space for 12 registers
.else
  stwu r1,-(BKP_FREE_SPACE_OFFSET + \space + (4 - \space % 4))(r1)	# make space for 12 registers
.endif
stmw r20,0x8(r1)
.endm

.macro restore space=0x78
lmw r20,0x8(r1)
# Stack allocation has to be 4-byte aligned otherwise it crashes on console
.if \space % 4 == 0
  lwz r0, (BKP_FREE_SPACE_OFFSET + 0x4 + \space)(r1)
  addi r1,r1,BKP_FREE_SPACE_OFFSET + \space	# release the space
.else
  lwz r0, (BKP_FREE_SPACE_OFFSET + 0x4 + \space + (4 - \space % 4))(r1)
  addi r1,r1,BKP_FREE_SPACE_OFFSET + \space + (4 - \space % 4)	# release the space
.endif
mtlr r0
.endm

.macro byteAlign32 reg
addi \reg, \reg, 31
rlwinm \reg, \reg, 0, 0xFFFFFFE0
.endm

.macro backupall
mflr r0
stw r0, 0x4(r1)
stwu r1,-0x100(r1)
stmw r3,0x8(r1)
.endm

.macro restoreall
lmw r3,0x8(r1)
lwz r0, 0x104(r1)
addi r1,r1,0x100
mtlr r0
.endm

.macro logf level, str, arg1="nop", arg2="nop", arg3="nop", arg4="nop", arg5="nop", arg6="nop"
b 1f
0:
blrl
.string "\str"
.align 2

1:
backupall

# Set up args to log
\arg1
\arg2
\arg3
\arg4
\arg5
\arg6

lwz r3, OFST_R13_SB_ADDR(r13) # Buf to use as EXI buf
addi r3, r3, 3
bl 0b
mflr r4
crset 6
branchl r12, sprintf

lwz r3, OFST_R13_SB_ADDR(r13) # Buf to use as EXI buf

li r4, 0xD0
stb r4, 0(r3)
li r4, 0 # Do not request time to be logged
stb r4, 1(r3)
li r4, \level
stb r4, 2(r3)

li r4, 128 # Length of buf
li r5, CONST_ExiWrite
branchl r12, FN_EXITransferBuffer

restoreall
.endm

.macro oslogf str, arg1="nop", arg2="nop", arg3="nop", arg4="nop", arg5="nop"
b 1f
0:
blrl
.string "\str"
.align 2

1:
backupall

# Set up args to log
\arg1
\arg2
\arg3
\arg4
\arg5

# Call OSReport
bl 0b
mflr r3
branchl r12, OSReport

restoreall
.endm

.macro getMinorMajor reg
lis \reg, lbl_80479D30@ha # load address to offset from for scene controller
lwz \reg, lbl_80479D30@l(\reg) # Load from 0x80479D30 (scene controller)
rlwinm \reg, \reg, 8, 0xFFFF # Loads major and minor scene into bottom of reg
.endm

.macro getMajorId reg
lis \reg, lbl_80479D30@ha # load address to offset from for scene controller
lbz \reg, lbl_80479D30@l(\reg) # Load byte from 0x80479D30 (major ID)
.endm

.macro loadGlobalFrame reg
.set lbl_80479D60, lbl_80479D30 + 0x30
lis \reg, lbl_80479D60@ha
lwz \reg, lbl_80479D60@l(\reg)
.endm

# This macro takes in an address that is expected to have a branch instruction. It will set
# r3 to the address being branched to. This will overwrite r3 and r4
.macro computeBranchTargetAddress reg address
load r3, \address
lwz r4, 0(r3) # Get branch instruction which contains offset

# Process 3rd byte and extend sign to handle negative branches
rlwinm r5, r4, 16, 0xFF
extsb r5, r5
rlwinm r5, r5, 16, 0xFFFF0000

# Extract last 2 bytes, combine with top half, and then add to base address to get result
rlwinm r4, r4, 0, 0xFFFC # Use 0xFFFC because the last bit is used for link
or r4, r4, r5
add \reg, r3, r4
.endm

################################################################################
# Settings
################################################################################
# STG_EXIIndex is now set during build with arg -defsym STG_EXIIndex=1
#.set STG_EXIIndex, 1 # 0 is SlotA, 1 is SlotB. Indicates which slot to use

.set STG_DesyncDebug, 0 # Prod: 0 | Debug flag for OSReporting desyncs

################################################################################
# Static Function Locations
################################################################################
# Local functions (added by us)
.set FN_EXITransferBuffer,GeckoHeapPtr - 0x10
.set FN_GetIsFollower,GeckoHeapPtr - 0x8
.set FN_ProcessGecko,GeckoHeapPtr - 0x4
.set FN_MultiplyRWithF,GeckoHeapPtr - 0x14
.set FN_IntToFloat,GeckoHeapPtr - 0xC
.set FG_CreateSubtext,GeckoHeapPtr + 0xB4
.set FN_LoadChatMessageProperties,GeckoHeapPtr + 0xAC
.set FN_GetTeamCostumeIndex,GeckoHeapPtr + 0xB0
.set FN_GetCSSIconData,GeckoHeapPtr + 0xB8
.set FN_AdjustNullID,GeckoHeapPtr + 0x94
.set FN_CheckAltStageName,GeckoHeapPtr + 0x90
.set FN_GetCSSIconNum,GeckoHeapPtr + 0x98
.set FN_LoadPremadeText,GeckoHeapPtr + 0xA4
.set FN_GetSSMIndex,GeckoHeapPtr + 0xA0
.set FN_GetFighterNum,GeckoHeapPtr + 0x9C
.set FN_CSSUpdateCSP,GeckoHeapPtr + 0xBC
.set FN_RequestSSM,GeckoHeapPtr + 0xA8
.set FN_GetCommonMinorID,GeckoHeapPtr + 0x1C

# Online static functions
.set FN_CaptureSavestate,GeckoHeapPtr + 0x8
.set FN_LoadSavestate,GeckoHeapPtr + 0xC
.set FN_LoadMatchState,GeckoHeapPtr + 0x10
.set FG_UserDisplay,GeckoHeapPtr + 0x18

# The rest of these are NTSC v1.02 functions
## HSD functions
.set HSD_PadFlushQueue,func_80376D04
.set HSD_VICopyXFBASync,func_803761C0
.set HSD_PadRumbleActiveID,func_80378430

## GObj functions
.set GObj_Create,func_803901F0 #(obj_type,subclass,priority)
.set GObj_AddUserData,GObj_InitUserData #void (*GObj_AddUserData)(GOBJ *gobj, int userDataKind, void *destructor, void *userData) = (void *)GObj_InitUserData;
.set GObj_Destroy,func_80390228
.set GObj_AddProc,func_8038FD54 # (obj,func,priority)
.set GObj_RemoveProc,func_8038FED4
.set GObj_AddToObj,func_80390A70 #(gboj,obj_kind,obj_ptr)

## JObj Functions
.set JObj_GetJObjChild,func_80011E24
.set JObj_RemoveAnimAll,HSD_JObjRemoveAnimAll
.set JObj_ClearFlags, HSD_JObjClearFlags #(jobj,flags)
.set JObj_SetFlagsAll, HSD_JObjSetFlagsAll # (jobj,flags)

## Text functions
.set Text_AllocateMenuTextMemory,func_803A5798
.set Text_FreeMenuTextMemory,func_80390228 # Not sure about this one, but it has a similar behavior to the Allocate
.set Text_CreateStruct,func_803A6754
.set Text_AllocateTextObject,func_803A5ACC
.set Text_CopyPremadeTextDataToStruct,func_803A6368# (text struct, index on open menu file, cannot be used, jackpot=will change to memory address we want)
.set Text_InitializeSubtext,func_803A6B98
.set Text_UpdateSubtextSize,func_803A7548
.set Text_ChangeTextColor,func_803A74F0
.set Text_DrawEachFrame,func_803A84BC
.set Text_UpdateSubtextContents,func_803A70A0
.set Text_RemoveText,func_803A5CC4

## Nametag data functions
.set Nametag_LoadSlotText,func_8023754C
.set Nametag_SetNameAsInUse,func_80237A04
.set Nametag_GetNametagBlock,func_8015CC9C

## Common/memory management
.set Zero_AreaLength,func_8000C160
.set FileLoad_ToPreAllocatedSpace,func_80016580
.set DiscError_ResumeGame,func_80024F6C

## PlayerBlock/game-state related functions
.set PlayerBlock_LoadStaticBlock,Player_GetPtrForSlot
.set PlayerBlock_UpdateCoords,Player_80032828
.set PlayerBlock_LoadExternalCharID,Player_GetPlayerCharacter
.set PlayerBlock_LoadRemainingStocks,Player_GetStocks
.set PlayerBlock_LoadSlotType,Player_GetPlayerSlotType
.set PlayerBlock_LoadDataOffsetStart,Player_GetEntityAtIndex
.set PlayerBlock_LoadTeamID,Player_GetTeam
.set PlayerBlock_StoreInitialCoords,Player_80032768
.set PlayerBlock_LoadPlayerXPosition,Player_LoadPlayerCoords
.set PlayerBlock_UpdateFacingDirection,Player_SetFacingDirection
.set PlayerBlock_LoadMainCharDataOffset,Player_GetEntity
.set SpawnPoint_GetXYZFromSpawnID,Stage_80224E64
.set Damage_UpdatePercent,Fighter_TakeDamage_8006CC7C
.set MatchEnd_GetWinningTeam,func_801654A0

## Camera functions
.set Camera_UpdatePlayerCameraBox,func_800761C8
.set Camera_CorrectPosition,func_8002F3AC

## Audio/SFX functions
.set SFX_StopSFXInstance, func_800236B8
.set Audio_AdjustMusicSFXVolume,func_80025064
.set SFX_Menu_CommonSound,func_80024030
.set SFX_PlaySoundAtFullVolume, func_800237A8 #SFX_PlaySoundAtFullVolume(r3=soundid,r4=volume?,r5=priority)

## Scene/input-related functions
.set NoContestOrRetry_,func_8016CF4C
.set fetchAnimationHeader,func_80085FD4
.set Damage_UpdatePercent,Fighter_TakeDamage_8006CC7C
.set Obj_ChangeRotation_Yaw,func_8007592C
.set MenuController_ChangeScreenMinor,func_801A4B60
.set SinglePlayerModeCheck,func_8016B41C
.set CheckIfGameEnginePaused,func_801A45E8
.set Inputs_GetPlayerHeldInputs,func_801A3680
.set Inputs_GetPlayerInstantInputs,func_801A36A0
.set Rumble_StoreRumbleFlag,func_8015ED4C
.set Audio_AdjustMusicSFXVolume,func_80025064
.set DiscError_ResumeGame,func_80024F6C
.set RenewInputs_Prefunction,func_800195FC
.set PadAlarmCheck,func_80019894
.set Event_StoreSceneNumber,func_80229860
.set EventMatch_Store,func_801BEB74
.set PadRead,PADRead

## Miscellenia/Unsorted
.set fetchAnimationHeader,func_80085FD4
.set Obj_ChangeRotation_Yaw,func_8007592C
.set Character_GetMaxCostumeCount,func_80169238


################################################################################
# Const Definitions
################################################################################
# For EXI transfers
.set CONST_ExiRead, 0 # arg value to make an EXI read
.set CONST_ExiWrite, 1 # arg value to make an EXI write

# For Slippi communication
.set CONST_SlippiCmdGetFrame, 0x76
.set CONST_SlippiCmdCheckForReplay, 0x88
.set CONST_SlippiCmdCheckForStockSteal,0x89
.set CONST_SlippiCmdSendOnlineFrame,0xB0
.set CONST_SlippiCmdCaptureSavestate,0xB1
.set CONST_SlippiCmdLoadSavestate,0xB2
.set CONST_SlippiCmdGetMatchState,0xB3
.set CONST_SlippiCmdFindOpponent,0xB4
.set CONST_SlippiCmdSetMatchSelections,0xB5
.set CONST_SlippiCmdOpenLogIn,0xB6
.set CONST_SlippiCmdLogOut,0xB7
.set CONST_SlippiCmdUpdateApp,0xB8
.set CONST_SlippiCmdGetOnlineStatus,0xB9
.set CONST_SlippiCmdCleanupConnections,0xBA
.set CONST_SlippiCmdSendChatMessage,0xBB
.set CONST_SlippiCmdGetNewSeed,0xBC
.set CONST_SlippiCmdReportMatch,0xBD
.set CONST_SlippiCmdSendNameEntryIndex,0xBE
.set CONST_SlippiCmdNameEntryAutoComplete,0xBF
# For Slippi file loads
.set CONST_SlippiCmdFileLength, 0xD1
.set CONST_SlippiCmdFileLoad, 0xD2
.set CONST_SlippiCmdGctLength, 0xD3
.set CONST_SlippiCmdGctLoad, 0xD4

# Misc
.set CONST_SlippiCmdGetDelay, 0xD5

# For Slippi Premade Texts
.set CONST_SlippiCmdGetPremadeTextLength, 0xE1
.set CONST_SlippiCmdGetPremadeText, 0xE2
.set CONST_TextDolphin, 0x765 # Flag identifying that Text_CopyPremadeTextDataToStruct needs to load from dolphin

.set CONST_FirstFrameIdx, -123

.set RtocAddress, _SDA2_BASE_

.set ControllerFixOptions,0xDD8 # Each byte at offset is a player's setting
.set UCFTextPointers,0x4fa0

.set DashbackOptions,0xDD4 # Offset for dashback-specific settings (playback)
.set ShieldDropOptions,0xDD0 # Offset for shielddrop-specific settings (playback)

.set PALToggle,-0xDCC   #offset for whether or not the replay is played with PAL modifications
.set PSPreloadToggle,-0xDC8   #offset for whether or not the replay is played with PS Preload Behavior
.set FSToggle,-0xDC4    #offset for whether or not the replay is played with the Frozen PS toggle
.set HideWaitingForGame,-0xDC0   #offset for whether or not to display the waiting for game text

.set PALToggleAddr, RtocAddress + PALToggle
.set PSPreloadToggleAddr, RtocAddress + PSPreloadToggle
.set FSToggleAddr, RtocAddress + FSToggle
.set HideWaitingForGameAddress, RtocAddress + HideWaitingForGame
.set CFOptionsAddress, RtocAddress - ControllerFixOptions
.set GeckoHeapPtr, lbl_80005600

# Internal scenes
.set SCENE_TRAINING_CSS, 0x001C
.set SCENE_TRAINING_SSS, 0x011C
.set SCENE_TRAINING_IN_GAME, 0x021C

.set SCENE_VERSUS_CSS, 0x0002
.set SCENE_VERSUS_SSS, 0x0102
.set SCENE_VERSUS_IN_GAME, 0x0202
.set SCENE_VERSUS_SUDDEN_DEATH, 0x0302

.set SCENE_TARGETS_CSS, 0x000F
.set SCENE_TARGETS_IN_GAME, 0x010F

.set SCENE_HOMERUN_CSS, 0x0020
.set SCENE_HOMERUN_IN_GAME, 0x0120

# Playback scene
.set SCENE_PLAYBACK_IN_GAME, 0x010E

################################################################################
# Offsets from r13
################################################################################
.set primaryDataBuffer,-0x49b4
.set secondaryDmaBuffer,-0x49b0
.set archiveDataBuffer, -0x4AE8
.set bufferOffset,-0x49b0
.set frameIndex,-0x49ac
.set textStructDescriptorBuffer,-0x3D24
.set isWidescreen,-0x5020

################################################################################
# Log levels
################################################################################
.set LOG_LEVEL_INFO, 4
.set LOG_LEVEL_WARN, 3
.set LOG_LEVEL_ERROR, 2
.set LOG_LEVEL_NOTICE, 1
