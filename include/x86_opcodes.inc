; Conway - RISC-V to x86-64 Binary Translator
; x86_opcodes.inc - x86-64 opcode definitions
;
; Machine code bytes for x86-64 instruction emission

; =============================================================================
; REX Prefixes
; =============================================================================
REX_BASE        equ 0x40        ; REX prefix base
REX_W           equ 0x48        ; 64-bit operand size
REX_R           equ 0x44        ; Extension of ModRM reg field
REX_X           equ 0x42        ; Extension of SIB index field
REX_B           equ 0x41        ; Extension of ModRM r/m, SIB base, or opcode reg

; Combined REX prefixes
REX_WR          equ 0x4C        ; REX.W + REX.R
REX_WX          equ 0x4A        ; REX.W + REX.X
REX_WB          equ 0x49        ; REX.W + REX.B
REX_WRB         equ 0x4D        ; REX.W + REX.R + REX.B
REX_WRX         equ 0x4E        ; REX.W + REX.R + REX.X
REX_WRXB        equ 0x4F        ; All REX bits set

; =============================================================================
; Primary Opcodes - Arithmetic
; =============================================================================
X86_ADD_RM_R    equ 0x01        ; ADD r/m64, r64
X86_ADD_R_RM    equ 0x03        ; ADD r64, r/m64
X86_ADD_RAX_IMM equ 0x05        ; ADD RAX, imm32
X86_ADD_RM_IMM  equ 0x81        ; ADD r/m64, imm32 (with /0)

X86_SUB_RM_R    equ 0x29        ; SUB r/m64, r64
X86_SUB_R_RM    equ 0x2B        ; SUB r64, r/m64
X86_SUB_RAX_IMM equ 0x2D        ; SUB RAX, imm32
X86_SUB_RM_IMM  equ 0x81        ; SUB r/m64, imm32 (with /5)

X86_AND_RM_R    equ 0x21        ; AND r/m64, r64
X86_AND_R_RM    equ 0x23        ; AND r64, r/m64
X86_AND_RAX_IMM equ 0x25        ; AND RAX, imm32

X86_OR_RM_R     equ 0x09        ; OR r/m64, r64
X86_OR_R_RM     equ 0x0B        ; OR r64, r/m64
X86_OR_RAX_IMM  equ 0x0D        ; OR RAX, imm32

X86_XOR_RM_R    equ 0x31        ; XOR r/m64, r64
X86_XOR_R_RM    equ 0x33        ; XOR r64, r/m64
X86_XOR_RAX_IMM equ 0x35        ; XOR RAX, imm32

X86_CMP_RM_R    equ 0x39        ; CMP r/m64, r64
X86_CMP_R_RM    equ 0x3B        ; CMP r64, r/m64
X86_CMP_RAX_IMM equ 0x3D        ; CMP RAX, imm32

X86_IMUL_R_RM   equ 0xAF        ; IMUL r64, r/m64 (0F prefix)
X86_IDIV_RM     equ 0xF7        ; IDIV r/m64 (with /7)

; =============================================================================
; Primary Opcodes - Data Movement
; =============================================================================
X86_MOV_RM_R    equ 0x89        ; MOV r/m64, r64
X86_MOV_R_RM    equ 0x8B        ; MOV r64, r/m64
X86_MOV_R_IMM   equ 0xB8        ; MOV r64, imm64 (+ reg in low 3 bits)
X86_MOV_RM_IMM  equ 0xC7        ; MOV r/m64, imm32 (sign-extended)

X86_MOVSX_R_RM8 equ 0xBE        ; MOVSX r64, r/m8 (0F prefix)
X86_MOVSX_R_RM16 equ 0xBF       ; MOVSX r64, r/m16 (0F prefix)
X86_MOVSXD_R_RM equ 0x63        ; MOVSXD r64, r/m32

X86_MOVZX_R_RM8 equ 0xB6        ; MOVZX r64, r/m8 (0F prefix)
X86_MOVZX_R_RM16 equ 0xB7      ; MOVZX r64, r/m16 (0F prefix)

X86_LEA         equ 0x8D        ; LEA r64, m

; =============================================================================
; Primary Opcodes - Shifts
; =============================================================================
X86_SHL_RM_1    equ 0xD1        ; SHL r/m64, 1 (with /4)
X86_SHL_RM_CL   equ 0xD3        ; SHL r/m64, CL (with /4)
X86_SHL_RM_IMM  equ 0xC1        ; SHL r/m64, imm8 (with /4)

X86_SHR_RM_1    equ 0xD1        ; SHR r/m64, 1 (with /5)
X86_SHR_RM_CL   equ 0xD3        ; SHR r/m64, CL (with /5)
X86_SHR_RM_IMM  equ 0xC1        ; SHR r/m64, imm8 (with /5)

X86_SAR_RM_1    equ 0xD1        ; SAR r/m64, 1 (with /7)
X86_SAR_RM_CL   equ 0xD3        ; SAR r/m64, CL (with /7)
X86_SAR_RM_IMM  equ 0xC1        ; SAR r/m64, imm8 (with /7)

; =============================================================================
; Primary Opcodes - Control Flow
; =============================================================================
X86_JMP_REL8    equ 0xEB        ; JMP rel8
X86_JMP_REL32   equ 0xE9        ; JMP rel32
X86_JMP_RM      equ 0xFF        ; JMP r/m64 (with /4)

X86_CALL_REL32  equ 0xE8        ; CALL rel32
X86_CALL_RM     equ 0xFF        ; CALL r/m64 (with /2)

X86_RET         equ 0xC3        ; RET
X86_RET_IMM16   equ 0xC2        ; RET imm16

; =============================================================================
; Primary Opcodes - Conditional Jumps (0F prefix required)
; =============================================================================
X86_JO_REL32    equ 0x80        ; JO rel32
X86_JNO_REL32   equ 0x81        ; JNO rel32
X86_JB_REL32    equ 0x82        ; JB/JNAE/JC rel32
X86_JAE_REL32   equ 0x83        ; JAE/JNB/JNC rel32
X86_JE_REL32    equ 0x84        ; JE/JZ rel32
X86_JNE_REL32   equ 0x85        ; JNE/JNZ rel32
X86_JBE_REL32   equ 0x86        ; JBE/JNA rel32
X86_JA_REL32    equ 0x87        ; JA/JNBE rel32
X86_JS_REL32    equ 0x88        ; JS rel32
X86_JNS_REL32   equ 0x89        ; JNS rel32
X86_JL_REL32    equ 0x8C        ; JL/JNGE rel32
X86_JGE_REL32   equ 0x8D        ; JGE/JNL rel32
X86_JLE_REL32   equ 0x8E        ; JLE/JNG rel32
X86_JG_REL32    equ 0x8F        ; JG/JNLE rel32

; Short conditional jumps (no prefix)
X86_JO_REL8     equ 0x70        ; JO rel8
X86_JNO_REL8    equ 0x71        ; JNO rel8
X86_JB_REL8     equ 0x72        ; JB rel8
X86_JAE_REL8    equ 0x73        ; JAE rel8
X86_JE_REL8     equ 0x74        ; JE rel8
X86_JNE_REL8    equ 0x75        ; JNE rel8
X86_JBE_REL8    equ 0x76        ; JBE rel8
X86_JA_REL8     equ 0x77        ; JA rel8
X86_JS_REL8     equ 0x78        ; JS rel8
X86_JNS_REL8    equ 0x79        ; JNS rel8
X86_JL_REL8     equ 0x7C        ; JL rel8
X86_JGE_REL8    equ 0x7D        ; JGE rel8
X86_JLE_REL8    equ 0x7E        ; JLE rel8
X86_JG_REL8     equ 0x7F        ; JG rel8

; =============================================================================
; Primary Opcodes - Stack Operations
; =============================================================================
X86_PUSH_R      equ 0x50        ; PUSH r64 (+ reg in low 3 bits)
X86_POP_R       equ 0x58        ; POP r64 (+ reg in low 3 bits)
X86_PUSH_IMM32  equ 0x68        ; PUSH imm32
X86_PUSH_IMM8   equ 0x6A        ; PUSH imm8

; =============================================================================
; Primary Opcodes - Miscellaneous
; =============================================================================
X86_NOP         equ 0x90        ; NOP
X86_INT3        equ 0xCC        ; INT 3 (breakpoint)
X86_SYSCALL     equ 0x05        ; SYSCALL (0F prefix)

X86_TEST_RM_R   equ 0x85        ; TEST r/m64, r64
X86_TEST_RAX_IMM equ 0xA9       ; TEST RAX, imm32

; =============================================================================
; Setcc Instructions (0F prefix required)
; =============================================================================
X86_SETO        equ 0x90        ; SETO r/m8
X86_SETNO       equ 0x91        ; SETNO r/m8
X86_SETB        equ 0x92        ; SETB r/m8
X86_SETAE       equ 0x93        ; SETAE r/m8
X86_SETE        equ 0x94        ; SETE r/m8
X86_SETNE       equ 0x95        ; SETNE r/m8
X86_SETBE       equ 0x96        ; SETBE r/m8
X86_SETA        equ 0x97        ; SETA r/m8
X86_SETS        equ 0x98        ; SETS r/m8
X86_SETNS       equ 0x99        ; SETNS r/m8
X86_SETL        equ 0x9C        ; SETL r/m8
X86_SETGE       equ 0x9D        ; SETGE r/m8
X86_SETLE       equ 0x9E        ; SETLE r/m8
X86_SETG        equ 0x9F        ; SETG r/m8

; =============================================================================
; Prefix Bytes
; =============================================================================
X86_PREFIX_LOCK     equ 0xF0    ; LOCK prefix
X86_PREFIX_REPNE    equ 0xF2    ; REPNE/REPNZ prefix
X86_PREFIX_REP      equ 0xF3    ; REP/REPE/REPZ prefix
X86_PREFIX_OPSZ     equ 0x66    ; Operand size override
X86_PREFIX_ADDRSZ   equ 0x67    ; Address size override
X86_PREFIX_2BYTE    equ 0x0F    ; Two-byte opcode escape

; =============================================================================
; ModRM Byte Construction
; =============================================================================
; ModRM = (mod << 6) | (reg << 3) | rm
MODRM_MOD_MEM       equ 0x00    ; [r/m]
MODRM_MOD_DISP8     equ 0x40    ; [r/m + disp8]
MODRM_MOD_DISP32    equ 0x80    ; [r/m + disp32]
MODRM_MOD_REG       equ 0xC0    ; r/m is register

; =============================================================================
; x86-64 Register Encoding
; =============================================================================
X86_REG_RAX     equ 0
X86_REG_RCX     equ 1
X86_REG_RDX     equ 2
X86_REG_RBX     equ 3
X86_REG_RSP     equ 4
X86_REG_RBP     equ 5
X86_REG_RSI     equ 6
X86_REG_RDI     equ 7
X86_REG_R8      equ 0           ; Requires REX.B
X86_REG_R9      equ 1           ; Requires REX.B
X86_REG_R10     equ 2           ; Requires REX.B
X86_REG_R11     equ 3           ; Requires REX.B
X86_REG_R12     equ 4           ; Requires REX.B
X86_REG_R13     equ 5           ; Requires REX.B
X86_REG_R14     equ 6           ; Requires REX.B
X86_REG_R15     equ 7           ; Requires REX.B
