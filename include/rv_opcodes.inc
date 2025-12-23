; Conway - RISC-V to x86-64 Binary Translator
; rv_opcodes.inc - RISC-V opcode definitions
;
; RV64I Base Integer Instruction Set opcodes and constants

; =============================================================================
; Instruction Types
; =============================================================================
INSTR_TYPE_R    equ 0           ; Register-register
INSTR_TYPE_I    equ 1           ; Immediate
INSTR_TYPE_S    equ 2           ; Store
INSTR_TYPE_B    equ 3           ; Branch
INSTR_TYPE_U    equ 4           ; Upper immediate
INSTR_TYPE_J    equ 5           ; Jump

; =============================================================================
; Base Opcodes (bits 6:0)
; =============================================================================
RV_OP_LOAD      equ 0b0000011   ; Load instructions
RV_OP_LOAD_FP   equ 0b0000111   ; Floating-point loads
RV_OP_MISC_MEM  equ 0b0001111   ; Memory ordering (FENCE)
RV_OP_OP_IMM    equ 0b0010011   ; Integer register-immediate
RV_OP_AUIPC     equ 0b0010111   ; Add upper immediate to PC
RV_OP_OP_IMM_32 equ 0b0011011   ; 32-bit register-immediate (RV64I)
RV_OP_STORE     equ 0b0100011   ; Store instructions
RV_OP_STORE_FP  equ 0b0100111   ; Floating-point stores
RV_OP_AMO       equ 0b0101111   ; Atomic memory operations
RV_OP_OP        equ 0b0110011   ; Integer register-register
RV_OP_LUI       equ 0b0110111   ; Load upper immediate
RV_OP_OP_32     equ 0b0111011   ; 32-bit register-register (RV64I)
RV_OP_MADD      equ 0b1000011   ; Fused multiply-add
RV_OP_MSUB      equ 0b1000111   ; Fused multiply-subtract
RV_OP_NMSUB     equ 0b1001011   ; Negated fused multiply-subtract
RV_OP_NMADD     equ 0b1001111   ; Negated fused multiply-add
RV_OP_OP_FP     equ 0b1010011   ; Floating-point operations
RV_OP_BRANCH    equ 0b1100011   ; Conditional branches
RV_OP_JALR      equ 0b1100111   ; Jump and link register
RV_OP_JAL       equ 0b1101111   ; Jump and link
RV_OP_SYSTEM    equ 0b1110011   ; System instructions

; =============================================================================
; funct3 values for Integer Register-Immediate (OP-IMM)
; =============================================================================
RV_FUNCT3_ADDI  equ 0b000       ; Add immediate
RV_FUNCT3_SLLI  equ 0b001       ; Shift left logical immediate
RV_FUNCT3_SLTI  equ 0b010       ; Set less than immediate (signed)
RV_FUNCT3_SLTIU equ 0b011       ; Set less than immediate (unsigned)
RV_FUNCT3_XORI  equ 0b100       ; XOR immediate
RV_FUNCT3_SRLI  equ 0b101       ; Shift right logical immediate
RV_FUNCT3_SRAI  equ 0b101       ; Shift right arithmetic immediate (funct7 differs)
RV_FUNCT3_ORI   equ 0b110       ; OR immediate
RV_FUNCT3_ANDI  equ 0b111       ; AND immediate

; =============================================================================
; funct3 values for Integer Register-Register (OP)
; =============================================================================
RV_FUNCT3_ADD   equ 0b000       ; Add
RV_FUNCT3_SUB   equ 0b000       ; Subtract (funct7 differs)
RV_FUNCT3_SLL   equ 0b001       ; Shift left logical
RV_FUNCT3_SLT   equ 0b010       ; Set less than (signed)
RV_FUNCT3_SLTU  equ 0b011       ; Set less than (unsigned)
RV_FUNCT3_XOR   equ 0b100       ; XOR
RV_FUNCT3_SRL   equ 0b101       ; Shift right logical
RV_FUNCT3_SRA   equ 0b101       ; Shift right arithmetic (funct7 differs)
RV_FUNCT3_OR    equ 0b110       ; OR
RV_FUNCT3_AND   equ 0b111       ; AND

; =============================================================================
; funct7 values
; =============================================================================
RV_FUNCT7_NORM  equ 0b0000000   ; Normal operation (ADD, SRL, etc.)
RV_FUNCT7_ALT   equ 0b0100000   ; Alternate operation (SUB, SRA)

; =============================================================================
; funct3 values for Branches
; =============================================================================
RV_FUNCT3_BEQ   equ 0b000       ; Branch if equal
RV_FUNCT3_BNE   equ 0b001       ; Branch if not equal
RV_FUNCT3_BLT   equ 0b100       ; Branch if less than (signed)
RV_FUNCT3_BGE   equ 0b101       ; Branch if greater or equal (signed)
RV_FUNCT3_BLTU  equ 0b110       ; Branch if less than (unsigned)
RV_FUNCT3_BGEU  equ 0b111       ; Branch if greater or equal (unsigned)

; =============================================================================
; funct3 values for Loads
; =============================================================================
RV_FUNCT3_LB    equ 0b000       ; Load byte (sign-extended)
RV_FUNCT3_LH    equ 0b001       ; Load halfword (sign-extended)
RV_FUNCT3_LW    equ 0b010       ; Load word (sign-extended in RV64I)
RV_FUNCT3_LD    equ 0b011       ; Load doubleword (RV64I)
RV_FUNCT3_LBU   equ 0b100       ; Load byte (zero-extended)
RV_FUNCT3_LHU   equ 0b101       ; Load halfword (zero-extended)
RV_FUNCT3_LWU   equ 0b110       ; Load word (zero-extended, RV64I)

; =============================================================================
; funct3 values for Stores
; =============================================================================
RV_FUNCT3_SB    equ 0b000       ; Store byte
RV_FUNCT3_SH    equ 0b001       ; Store halfword
RV_FUNCT3_SW    equ 0b010       ; Store word
RV_FUNCT3_SD    equ 0b011       ; Store doubleword (RV64I)

; =============================================================================
; Register ABI Names
; =============================================================================
RV_REG_ZERO     equ 0           ; x0  - Hardwired zero
RV_REG_RA       equ 1           ; x1  - Return address
RV_REG_SP       equ 2           ; x2  - Stack pointer
RV_REG_GP       equ 3           ; x3  - Global pointer
RV_REG_TP       equ 4           ; x4  - Thread pointer
RV_REG_T0       equ 5           ; x5  - Temporary
RV_REG_T1       equ 6           ; x6  - Temporary
RV_REG_T2       equ 7           ; x7  - Temporary
RV_REG_S0       equ 8           ; x8  - Saved register / frame pointer
RV_REG_FP       equ 8           ; x8  - Frame pointer (alias)
RV_REG_S1       equ 9           ; x9  - Saved register
RV_REG_A0       equ 10          ; x10 - Function argument / return value
RV_REG_A1       equ 11          ; x11 - Function argument / return value
RV_REG_A2       equ 12          ; x12 - Function argument
RV_REG_A3       equ 13          ; x13 - Function argument
RV_REG_A4       equ 14          ; x14 - Function argument
RV_REG_A5       equ 15          ; x15 - Function argument
RV_REG_A6       equ 16          ; x16 - Function argument
RV_REG_A7       equ 17          ; x17 - Function argument
RV_REG_S2       equ 18          ; x18 - Saved register
RV_REG_S3       equ 19          ; x19 - Saved register
RV_REG_S4       equ 20          ; x20 - Saved register
RV_REG_S5       equ 21          ; x21 - Saved register
RV_REG_S6       equ 22          ; x22 - Saved register
RV_REG_S7       equ 23          ; x23 - Saved register
RV_REG_S8       equ 24          ; x24 - Saved register
RV_REG_S9       equ 25          ; x25 - Saved register
RV_REG_S10      equ 26          ; x26 - Saved register
RV_REG_S11      equ 27          ; x27 - Saved register
RV_REG_T3       equ 28          ; x28 - Temporary
RV_REG_T4       equ 29          ; x29 - Temporary
RV_REG_T5       equ 30          ; x30 - Temporary
RV_REG_T6       equ 31          ; x31 - Temporary
