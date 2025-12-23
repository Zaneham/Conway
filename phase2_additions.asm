; Phase 2 additions - paste after existing constants

; RISC-V opcodes for memory operations
RV_OP_LOAD      equ 0x03        ; Load instructions
RV_OP_STORE     equ 0x23        ; Store instructions

; Funct3 values for loads
RV_F3_LB        equ 0x0         ; Load Byte (sign-extended)
RV_F3_LH        equ 0x1         ; Load Halfword (sign-extended)
RV_F3_LW        equ 0x2         ; Load Word (sign-extended)
RV_F3_LD        equ 0x3         ; Load Doubleword
RV_F3_LBU       equ 0x4         ; Load Byte Unsigned
RV_F3_LHU       equ 0x5         ; Load Halfword Unsigned
RV_F3_LWU       equ 0x6         ; Load Word Unsigned

; Funct3 values for stores
RV_F3_SB        equ 0x0         ; Store Byte
RV_F3_SH        equ 0x1         ; Store Halfword
RV_F3_SW        equ 0x2         ; Store Word
RV_F3_SD        equ 0x3         ; Store Doubleword
