.include "asm/ucf/slippi_common.s"

.set	InputIndex,HSD_PadLibData
.set	InputArray,lbl_8046B108
.set	PlayerBlock_LoadPlayerGObj,Player_GetEntityAtIndex

# NTSC102:
# todo: version symbols
	.set	OFST_PlCo,-0x514C
/*
NTSC101:
	.set	OFST_PlCo,-0x514C
NTSC100:
	.set	OFST_PlCo,-0x514C
PAL100:
	.set	OFST_PlCo,-0x4F0C
*/