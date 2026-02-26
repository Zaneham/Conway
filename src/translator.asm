; translator.asm
; Conway translator - library version (no main)
; Just the translate_instruction function for linking with test harnesses
;
; Build for Windows: nasm -f win64 translator.asm  (or add -DWINDOWS)
; Build for Linux:   nasm -f elf64 -DLINUX translator.asm

bits 64
default rel

; Default to Windows if no platform specified
%ifndef LINUX
%define WINDOWS
%endif

; External from elf_loader.asm
extern elf_brk_base

%ifdef WINDOWS
; External Windows API functions (only for debug output)
extern Sleep
extern GetTickCount
extern GetStdHandle
extern WriteFile
extern CreateFileA
extern ReadFile
extern CloseHandle
extern SetFilePointer
extern GetLastError
extern ExitProcess
; These are provided by platform_win.asm
extern stdout_handle
extern bytes_written
%else
; Linux: debug output is disabled, but code still references these
; Define local stubs that just return (debug blocks are skipped anyway)
%define GetStdHandle debug_stub
%define WriteFile debug_stub
%define ExitProcess debug_stub
%define GetTickCount debug_stub
%define Sleep debug_stub
%define CreateFileA debug_stub
%define ReadFile debug_stub
%define CloseHandle debug_stub
%define SetFilePointer debug_stub
%endif

; Windows file I/O constants
GENERIC_READ            equ 0x80000000
GENERIC_WRITE           equ 0x40000000
FILE_SHARE_READ         equ 1
FILE_SHARE_WRITE        equ 2
OPEN_EXISTING           equ 3
CREATE_ALWAYS           equ 2
OPEN_ALWAYS             equ 4
FILE_ATTRIBUTE_NORMAL   equ 0x80
INVALID_HANDLE_VALUE    equ -1
FILE_BEGIN              equ 0
FILE_CURRENT            equ 1
FILE_END                equ 2

; File table constants
MAX_OPEN_FILES          equ 16
FD_OFFSET               equ 3       ; First allocatable fd (0,1,2 reserved)

;==============================================================================
; Constants
;==============================================================================

; RISC-V opcodes
RV_OP_LUI       equ 0x37
RV_OP_AUIPC     equ 0x17
RV_OP_OP_IMM    equ 0x13
RV_OP_OP_IMM_32 equ 0x1B        ; 32-bit immediate ops (addiw, slliw, etc.)
RV_OP_OP        equ 0x33
RV_OP_OP_32     equ 0x3B        ; 32-bit register ops (addw, subw, etc.)
RV_OP_LOAD      equ 0x03
RV_OP_STORE     equ 0x23
RV_OP_JAL       equ 0x6F        ; Jump and Link
RV_OP_JALR      equ 0x67        ; Jump and Link Register
RV_OP_BRANCH    equ 0x63        ; Conditional branches
RV_OP_SYSTEM    equ 0x73        ; ECALL, EBREAK, CSR instructions
RV_OP_MISC_MEM  equ 0x0F        ; FENCE, FENCE.I

; Floating-point opcodes (F/D extensions)
RV_OP_LOAD_FP   equ 0x07        ; FLW, FLD
RV_OP_STORE_FP  equ 0x27        ; FSW, FSD
RV_OP_MADD      equ 0x43        ; FMADD.S/D
RV_OP_MSUB      equ 0x47        ; FMSUB.S/D
RV_OP_NMSUB     equ 0x4B        ; FNMSUB.S/D
RV_OP_NMADD     equ 0x4F        ; FNMADD.S/D
RV_OP_OP_FP     equ 0x53        ; Floating-point operations

; Atomic operations (A extension)
RV_OP_AMO       equ 0x2F        ; Atomic Memory Operations

; AMO funct5 values (bits 31:27)
AMO_LR          equ 0x02        ; Load-Reserved
AMO_SC          equ 0x03        ; Store-Conditional  
AMO_SWAP        equ 0x01        ; AMOSWAP
AMO_ADD         equ 0x00        ; AMOADD
AMO_XOR         equ 0x04        ; AMOXOR
AMO_AND         equ 0x0C        ; AMOAND
AMO_OR          equ 0x08        ; AMOOR
AMO_MIN         equ 0x10        ; AMOMIN
AMO_MAX         equ 0x14        ; AMOMAX
AMO_MINU        equ 0x18        ; AMOMINU
AMO_MAXU        equ 0x1C        ; AMOMAXU

; Funct3 for OP-IMM
RV_F3_ADDI      equ 0x0
RV_F3_SLTI      equ 0x2
RV_F3_SLTIU     equ 0x3
RV_F3_XORI      equ 0x4
RV_F3_ORI       equ 0x6
RV_F3_ANDI      equ 0x7
RV_F3_SLLI      equ 0x1
RV_F3_SRLI_SRAI equ 0x5

; Funct3 for OP
RV_F3_ADD_SUB   equ 0x0
RV_F3_SLL       equ 0x1
RV_F3_SLT       equ 0x2
RV_F3_SLTU      equ 0x3
RV_F3_XOR       equ 0x4
RV_F3_SRL_SRA   equ 0x5
RV_F3_OR        equ 0x6
RV_F3_AND       equ 0x7

; Funct7 values
RV_F7_NORMAL    equ 0x00
RV_F7_ALT       equ 0x20

; Funct3 for loads
RV_F3_LB        equ 0x0
RV_F3_LH        equ 0x1
RV_F3_LW        equ 0x2
RV_F3_LD        equ 0x3
RV_F3_LBU       equ 0x4
RV_F3_LHU       equ 0x5
RV_F3_LWU       equ 0x6

; Funct3 for stores
RV_F3_SB        equ 0x0
RV_F3_SH        equ 0x1
RV_F3_SW        equ 0x2
RV_F3_SD        equ 0x3

; Funct3 for branches
RV_F3_BEQ       equ 0x0         ; Branch if Equal
RV_F3_BNE       equ 0x1         ; Branch if Not Equal
RV_F3_BLT       equ 0x4         ; Branch if Less Than (signed)
RV_F3_BGE       equ 0x5         ; Branch if Greater or Equal (signed)
RV_F3_BLTU      equ 0x6         ; Branch if Less Than Unsigned
RV_F3_BGEU      equ 0x7         ; Branch if Greater or Equal Unsigned

; Funct3 for SYSTEM (CSR instructions)
RV_F3_PRIV      equ 0x0         ; ECALL, EBREAK, etc.
RV_F3_CSRRW     equ 0x1         ; CSR Read/Write
RV_F3_CSRRS     equ 0x2         ; CSR Read/Set
RV_F3_CSRRC     equ 0x3         ; CSR Read/Clear
RV_F3_CSRRWI    equ 0x5         ; CSR Read/Write Immediate
RV_F3_CSRRSI    equ 0x6         ; CSR Read/Set Immediate
RV_F3_CSRRCI    equ 0x7         ; CSR Read/Clear Immediate

; SYSTEM instruction immediate values (bits 31:20)
RV_SYS_ECALL    equ 0x000       ; Environment call
RV_SYS_EBREAK   equ 0x001       ; Breakpoint

section .data
    msg_exit        db "Exit: ", 0
    msg_done_debug  db "DONE", 13, 10, 0
    msg_syscall     db "Syscall: ", 0
    msg_newline     db 13, 10, 0
    msg_frame       db "F", 0
    wad_search_path db "C:\dev\conway\test\", 0    ; Search path for WAD files

section .text

%ifndef WINDOWS
; Stub for debug functions on non-Windows platforms
; These are never actually called (debug is disabled), but need to exist
debug_stub:
    ret
%endif

    global translate_instruction
    global translate_block
    global lookup_block
    global init_block_cache
    global execute_blocks
    global link_block
    global block_cache
    global code_buffer

;==============================================================================
; Block Cache Constants
;==============================================================================
BLOCK_CACHE_SIZE    equ 1024            ; Number of cache entries
BLOCK_ENTRY_SIZE    equ 64              ; Bytes per entry
CODE_BUFFER_SIZE    equ 16777216        ; 16MB code buffer (Doom needs space!)

; Block entry offsets
BLOCK_VALID         equ 0               ; 1 byte: is entry valid?
BLOCK_START_PC      equ 8               ; 8 bytes: RISC-V start PC
BLOCK_CODE_PTR      equ 16              ; 8 bytes: pointer to x86 code
BLOCK_CODE_SIZE     equ 24              ; 4 bytes: size of x86 code
BLOCK_EXIT_TYPE     equ 28              ; 4 bytes: how block exits
BLOCK_NEXT_PC       equ 32              ; 8 bytes: unconditional target
BLOCK_TAKEN_PC      equ 40              ; 8 bytes: branch taken target
BLOCK_NOT_TAKEN_PC  equ 48              ; 8 bytes: branch not-taken target
BLOCK_LINK_ADDR     equ 56              ; 8 bytes: address of jmp instruction for linking

; Exit types
EXIT_NONE           equ 0               ; Block doesn't exit (incomplete)
EXIT_JUMP           equ 1               ; Unconditional jump (JAL/JALR)
EXIT_BRANCH         equ 2               ; Conditional branch
EXIT_INDIRECT       equ 3               ; Indirect jump (JALR with register)
EXIT_ECALL          equ 4               ; System call (needs handler)

section .bss
    alignb 4096
    block_cache:    resb BLOCK_CACHE_SIZE * BLOCK_ENTRY_SIZE    ; 64KB cache
    code_buffer:    resb CODE_BUFFER_SIZE                        ; 16MB code
    global code_buf_ptr
    code_buf_ptr:   resq 1                                       ; Allocation pointer
    ecall_pending:  resb 1                                       ; Set by ECALL blocks at runtime
    s4_reported:    resb 1                                       ; Debug flag for s4 corruption
    alignb 8
    last_s4_value:  resq 1                                       ; Track s4 changes
    last_a0_value:  resq 1                                       ; Track a0 changes
    last_ra_value:  resq 1                                       ; Track ra changes
    block_2425_execcount: resd 1                                 ; Count executions of block 2425
    alignb 8
%ifndef WINDOWS
    ; On Linux these are local (debug code is stubbed anyway)
    stdout_handle:  resq 1
    bytes_written:  resq 1
%endif
    bytes_read_tmp: resq 1                                       ; Temp for ReadFile
    file_table:     resq MAX_OPEN_FILES                          ; fd -> Windows HANDLE
    path_buffer:    resb 260                                     ; MAX_PATH for filename conversion
    path_buffer_ptr: resq 1                                      ; Pointer to path_buffer (for reliable access)
    wad_path_buffer: resb 280                                    ; Buffer for WAD path with prefix
    openat_src_addr: resq 1                                      ; Source pathname host address for openat
    num_buffer:     resb 256                                     ; Temp for number conversion (enlarged for debug)
    global debug_block_count
    debug_block_count: resq 1                                    ; Debug: block counter
    global debug_last_pc
    debug_last_pc:  resq 1                                       ; Debug: last PC before crash
    pc_history:     resq 8                                       ; Circular buffer of last 8 PCs
    pc_history_idx: resq 1                                       ; Current index into pc_history
    frame_count:    resq 1                                       ; DG_DrawFrame counter
    start_ticks:    resq 1                                       ; Start time for ticks
    syscall_count:  resq 1                                       ; Syscall counter for debug
    stdout_written: resq 1                                       ; Bytes written (unused)
    store_debug_count: resq 1                                    ; Count stores for debug
    global store_debug_count
    lbu_count: resq 1                                            ; LBU translation count
    sb_count: resq 1                                             ; SB translation count
    sh_count: resq 1                                             ; SH translation count
    sw_count: resq 1                                             ; SW translation count
    sd_count: resq 1                                             ; SD translation count
    c_sw_count: resq 1                                           ; C.SW translation count
    c_sd_count: resq 1                                           ; C.SD translation count
    c_swsp_count: resq 1                                         ; C.SWSP translation count
    c_sdsp_count: resq 1                                         ; C.SDSP translation count
    sb_exec_count: resq 1                                        ; SB runtime execution count
    global sb_exec_count
    sb_debug_addrs: resq 8                                       ; First 8 SB target addresses
    sb_debug_vals: resb 8                                        ; First 8 SB values
    sb_debug_r14: resq 8                                         ; r14 values at store time
    first_sb_r14: resq 1                                         ; r14 from very first SB store
    first_sb_addr: resq 1                                        ; Address from very first SB store
    first_sb_val: resb 1                                         ; Value (cl) from very first SB store
    first_sb_readback: resb 1                                    ; Read back immediately after store
    first_sb_before: resb 1                                      ; Value at address BEFORE store
    first_sb_captured: resb 1                                    ; Flag: 1 if first already captured
    first_sb_readback_done: resb 1                               ; Flag: 1 if readback captured
    ; Capture first SB to high heap (>= 0x12E000)
    nz_sb_addr: resq 1                                           ; Address of first high-heap SB
    nz_sb_val: resb 1                                            ; Value of first high-heap SB
    nz_sb_readback: resb 1                                       ; Readback after store
    nz_sb_captured: resb 1                                       ; Flag: 1 if captured
    ; Capture first SD to high heap (>= 0x12E000)
    heap_sd_addr: resq 1                                         ; Address of first high-heap SD
    heap_sd_val: resq 1                                          ; Value stored
    heap_sd_readback: resq 1                                     ; Readback after store
    heap_sd_captured: resb 1                                     ; Flag: 1 if captured
    ; Count SB stores to 0x12EE00-0x12EF00 range
    strdup_region_count: resq 1                                  ; Count of stores to strdup region
    ; Capture first store to exact strdup dest (>= 0x12EEF0)
    exact_sb_addr: resq 1
    exact_sb_val: resb 1
    exact_sb_readback: resb 1
    exact_sb_captured: resb 1
    ; Count stores to exact address 0x12EEF0
    exact_0_count: resq 1                                        ; Count of stores that wrote 0
    exact_nz_count: resq 1                                       ; Count of stores that wrote non-zero
    ; Second capture: store near openat path (0x6FE000-0x6FF000)
    path_sb_r14: resq 1
    path_sb_addr: resq 1
    path_sb_val: resb 1
    path_sb_captured: resb 1
    ; Count stores to path region (0x6FE000-0x6FFFFF)
    path_region_count: resq 1
    ; First LBU debug capture
    first_lbu_addr: resq 1
    first_lbu_val: resb 1
    first_lbu_captured: resb 1
    ; LBU from doom1.wad string area (0x3ae00-0x3af00)
    global doom_lbu_addr
    global doom_lbu_val
    global doom_lbu_captured
    doom_lbu_addr: resq 1
    doom_lbu_val: resb 1
    doom_lbu_captured: resb 1
    ; Array to capture first 8 LBU values and addresses
    global lbu_debug_count
    global lbu_debug_addrs
    global lbu_debug_vals
    lbu_debug_count: resq 1
    lbu_debug_addrs: resq 8
    lbu_debug_vals: resb 8
    ; SB store of 'C' (0x43) - track when this value is stored
    global sb_c_addr
    global sb_c_captured
    sb_c_addr: resq 1
    sb_c_captured: resb 1
    ; Track any store to 0x6FFA4F
    global sb_target_val
    global sb_target_captured
    sb_target_val: resb 1
    sb_target_captured: resb 1
    ; SW corruption detection - track when SW stored != readback
    global sw_corrupt_addr
    global sw_corrupt_stored
    global sw_corrupt_readback
    global sw_corrupt_captured
    sw_corrupt_addr: resq 1
    sw_corrupt_stored: resd 1
    sw_corrupt_readback: resd 1
    sw_corrupt_captured: resb 1
    ; SD corruption detection - track when SD stored != readback
    global sd_corrupt_addr
    global sd_corrupt_stored
    global sd_corrupt_readback
    global sd_corrupt_captured
    sd_corrupt_addr: resq 1
    sd_corrupt_stored: resq 1
    sd_corrupt_readback: resq 1
    sd_corrupt_captured: resb 1
    ; BRK syscall debug
    brk_debug_done: resb 1
    ; High address store tracking (addresses > 0x700000)
    global high_store_count
    high_store_count: resq 1
    ; C.SW corruption detection - track when C.SW stored != readback
    global csw_corrupt_addr
    global csw_corrupt_stored
    global csw_corrupt_readback
    global csw_corrupt_captured
    csw_corrupt_addr: resq 1
    csw_corrupt_stored: resd 1
    csw_corrupt_readback: resd 1
    csw_corrupt_captured: resb 1

    ; CSR (Control and Status Register) storage
    alignb 8
    csr_cycle:      resq 1                  ; 0xC00 - Cycle counter
    csr_time:       resq 1                  ; 0xC01 - Time
    csr_instret:    resq 1                  ; 0xC02 - Instructions retired
    csr_mstatus:    resq 1                  ; 0x300 - Machine status
    csr_misa:       resq 1                  ; 0x301 - ISA and extensions
    csr_mtvec:      resq 1                  ; 0x305 - Trap vector base
    csr_mepc:       resq 1                  ; 0x341 - Exception PC
    csr_mcause:     resq 1                  ; 0x342 - Exception cause
    csr_mtval:      resq 1                  ; 0x343 - Trap value
    csr_mvendorid:  resq 1                  ; 0xF11 - Vendor ID (0 = non-commercial)
    csr_marchid:    resq 1                  ; 0xF12 - Architecture ID
    csr_mimpid:     resq 1                  ; 0xF13 - Implementation ID
    csr_mhartid:    resq 1                  ; 0xF14 - Hart ID (0 for single-core)

    ; Floating-point register storage (f0-f31)
    ; Using 64-bit slots for D extension support
    alignb 16                               ; SSE requires 16-byte alignment
    global fp_registers
    fp_registers:   resq 32                 ; 32 x 64-bit = 256 bytes

    ; Floating-point Control and Status Register
    ; Bits 7:5 = frm (rounding mode), bits 4:0 = fflags (exception flags)
    global fcsr
    fcsr:           resd 1

section .text

;==============================================================================
; translate_instruction
; Input:  EDI = 32-bit RISC-V instruction
;         RSI = output buffer pointer
; Output: RAX = bytes written
;==============================================================================
translate_instruction:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rsi                ; r12 = output pointer
    mov r13d, edi               ; r13d = instruction
    mov r14, rsi                ; r14 = buffer start for size calc
    mov r15, rdx                ; r15 = current PC (for AUIPC)

    ; Extract opcode
    mov eax, edi
    and eax, 0x7F

    cmp eax, RV_OP_LUI
    je .lui

    cmp eax, RV_OP_AUIPC
    je .auipc

    cmp eax, RV_OP_OP_IMM
    je .op_imm

    cmp eax, RV_OP_OP_IMM_32
    je .op_imm_32

    cmp eax, RV_OP_OP
    je .op_reg

    cmp eax, RV_OP_OP_32
    je .op_reg_32

    cmp eax, RV_OP_LOAD
    je .load

    cmp eax, RV_OP_STORE
    je .store

    cmp eax, RV_OP_JAL
    je .jal

    cmp eax, RV_OP_JALR
    je .jalr

    cmp eax, RV_OP_BRANCH
    je .branch

    cmp eax, RV_OP_SYSTEM
    je .system

    cmp eax, RV_OP_MISC_MEM
    je .fence

    ; Floating-point opcodes (F/D extensions)
    cmp eax, RV_OP_LOAD_FP
    je .load_fp

    cmp eax, RV_OP_STORE_FP
    je .store_fp

    cmp eax, RV_OP_OP_FP
    je .op_fp

    cmp eax, RV_OP_MADD
    je .fmadd

    cmp eax, RV_OP_MSUB
    je .fmsub

    cmp eax, RV_OP_NMSUB
    je .fnmsub

    cmp eax, RV_OP_NMADD
    je .fnmadd

    ; Atomic operations (A extension)
    cmp eax, RV_OP_AMO
    je .amo

    ; Unknown opcode - print helpful error and emit INT3
    push rax
    push r12
    push r13
    sub rsp, 48

    ; Format: "ERR: PC=XXXXXXXX inst=XXXXXXXX op=XX\n"
    mov byte [num_buffer], 'E'
    mov byte [num_buffer+1], 'R'
    mov byte [num_buffer+2], 'R'
    mov byte [num_buffer+3], ':'
    mov byte [num_buffer+4], ' '
    mov byte [num_buffer+5], 'P'
    mov byte [num_buffer+6], 'C'
    mov byte [num_buffer+7], '='

    ; Print PC (r15) as 8 hex digits at offset 8
    mov eax, r15d
    mov ecx, 8
    lea rsi, [num_buffer+15]
.unk_pc_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .unk_pc_dig
    add dl, 'A' - 10
    jmp .unk_pc_st
.unk_pc_dig:
    add dl, '0'
.unk_pc_st:
    mov [rsi], dl
    dec rsi
    shr eax, 4
    dec ecx
    jnz .unk_pc_hex

    mov byte [num_buffer+16], ' '
    mov byte [num_buffer+17], 'i'
    mov byte [num_buffer+18], 'n'
    mov byte [num_buffer+19], 's'
    mov byte [num_buffer+20], 't'
    mov byte [num_buffer+21], '='

    ; Print instruction (r13d) as 8 hex digits at offset 22
    mov eax, r13d
    mov ecx, 8
    lea rsi, [num_buffer+29]
.unk_inst_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .unk_inst_dig
    add dl, 'A' - 10
    jmp .unk_inst_st
.unk_inst_dig:
    add dl, '0'
.unk_inst_st:
    mov [rsi], dl
    dec rsi
    shr eax, 4
    dec ecx
    jnz .unk_inst_hex

    mov byte [num_buffer+30], ' '
    mov byte [num_buffer+31], 'o'
    mov byte [num_buffer+32], 'p'
    mov byte [num_buffer+33], '='

    ; Print opcode (low 7 bits) as 2 hex digits at offset 34
    mov eax, r13d
    and eax, 0x7F
    mov edx, eax
    shr edx, 4
    cmp dl, 10
    jb .unk_op_d1
    add dl, 'A' - 10
    jmp .unk_op_s1
.unk_op_d1:
    add dl, '0'
.unk_op_s1:
    mov [num_buffer+34], dl
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .unk_op_d2
    add dl, 'A' - 10
    jmp .unk_op_s2
.unk_op_d2:
    add dl, '0'
.unk_op_s2:
    mov [num_buffer+35], dl
    mov byte [num_buffer+36], 10

    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 37
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop r13
    pop r12
    pop rax

    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

;==============================================================================
; LUI
;==============================================================================
.lui:
    call extract_u_type

    test ecx, ecx
    jz .emit_nop

    ; Generate: movabs rax, imm64 (10 bytes)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xB8
    cdqe
    mov [r12+2], rax

    ; Generate: mov [rbx + rd*8], rax
    ; Need disp32 for rd >= 16 (displacement >= 128)
    mov eax, ecx
    shl eax, 3              ; eax = rd * 8
    cmp eax, 127
    jg .lui_disp32

    ; disp8 path: mov [rbx + disp8], rax (4 bytes)
    mov byte [r12+10], 0x48
    mov byte [r12+11], 0x89
    mov byte [r12+12], 0x43     ; ModRM: mod=01, reg=0, r/m=3
    mov [r12+13], al
    mov rax, 14
    jmp .done

.lui_disp32:
    ; disp32 path: mov [rbx + disp32], rax (7 bytes)
    mov byte [r12+10], 0x48
    mov byte [r12+11], 0x89
    mov byte [r12+12], 0x83     ; ModRM: mod=10, reg=0, r/m=3
    mov [r12+13], eax
    mov rax, 17
    jmp .done

;==============================================================================
; AUIPC
;==============================================================================
.auipc:
    call extract_u_type

    test ecx, ecx
    jz .emit_nop

    ; AUIPC: rd = PC + (imm20 << 12)
    ; eax = imm20 << 12 (from extract_u_type)
    ; r15 = current PC (passed from translate_block)
    ; Generate: movabs rax, imm64 (10 bytes)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xB8
    cdqe                        ; Sign-extend imm to 64 bits
    add rax, r15                ; Add PC to get final value
    mov [r12+2], rax

    ; Generate: mov [rbx + rd*8], rax
    ; Need disp32 for rd >= 16 (displacement >= 128)
    mov eax, ecx
    shl eax, 3              ; eax = rd * 8
    cmp eax, 127
    jg .auipc_disp32

    ; disp8 path: mov [rbx + disp8], rax (4 bytes)
    mov byte [r12+10], 0x48
    mov byte [r12+11], 0x89
    mov byte [r12+12], 0x43     ; ModRM: mod=01, reg=0, r/m=3
    mov [r12+13], al
    mov rax, 14
    jmp .done

.auipc_disp32:
    ; disp32 path: mov [rbx + disp32], rax (7 bytes)
    mov byte [r12+10], 0x48
    mov byte [r12+11], 0x89
    mov byte [r12+12], 0x83     ; ModRM: mod=10, reg=0, r/m=3
    mov [r12+13], eax
    mov rax, 17
    jmp .done

;==============================================================================
; OP-IMM dispatch
;==============================================================================
.op_imm:
    mov eax, r13d
    shr eax, 12
    and eax, 0x7

    cmp eax, RV_F3_ADDI
    je .addi
    cmp eax, RV_F3_SLTI
    je .slti
    cmp eax, RV_F3_SLTIU
    je .sltiu
    cmp eax, RV_F3_XORI
    je .xori
    cmp eax, RV_F3_ORI
    je .ori
    cmp eax, RV_F3_ANDI
    je .andi
    cmp eax, RV_F3_SLLI
    je .slli
    cmp eax, RV_F3_SRLI_SRAI
    je .srli_srai

    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

;==============================================================================
; ADDI
;==============================================================================
.addi:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    test ebx, ebx
    jz .emit_li

    push rax                    ; Save immediate (emit_load_rs1 clobbers EAX)
    call emit_load_rs1
    pop rax                     ; Restore immediate

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], eax
    add r12, 6

    call emit_store_rd
    jmp .calc_size

.emit_li:
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0xC0
    mov [r12+3], eax
    add r12, 7

    call emit_store_rd
    jmp .calc_size

;==============================================================================
; SLTI
;==============================================================================
.slti:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rax
    call emit_load_rs1
    pop rax

    mov byte [r12], 0x48
    mov byte [r12+1], 0x3D
    mov [r12+2], eax
    add r12, 6

    mov byte [r12], 0x0F
    mov byte [r12+1], 0x9C
    mov byte [r12+2], 0xC0
    add r12, 3

    mov byte [r12], 0x48
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB6
    mov byte [r12+3], 0xC0
    add r12, 4

    call emit_store_rd
    jmp .calc_size

;==============================================================================
; SLTIU
;==============================================================================
.sltiu:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rax
    call emit_load_rs1
    pop rax

    mov byte [r12], 0x48
    mov byte [r12+1], 0x3D
    mov [r12+2], eax
    add r12, 6

    mov byte [r12], 0x0F
    mov byte [r12+1], 0x92
    mov byte [r12+2], 0xC0
    add r12, 3

    mov byte [r12], 0x48
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB6
    mov byte [r12+3], 0xC0
    add r12, 4

    call emit_store_rd
    jmp .calc_size

;==============================================================================
; XORI
;==============================================================================
.xori:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    test ebx, ebx
    jnz .xori_general
    jmp .emit_li

.xori_general:
    push rax                    ; Save immediate
    call emit_load_rs1
    pop rax                     ; Restore immediate

    mov byte [r12], 0x48
    mov byte [r12+1], 0x35
    mov [r12+2], eax
    add r12, 6

    call emit_store_rd
    jmp .calc_size

;==============================================================================
; ORI
;==============================================================================
.ori:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    test ebx, ebx
    jnz .ori_general
    jmp .emit_li

.ori_general:
    push rax                    ; Save immediate
    call emit_load_rs1
    pop rax                     ; Restore immediate

    mov byte [r12], 0x48
    mov byte [r12+1], 0x0D
    mov [r12+2], eax
    add r12, 6

    call emit_store_rd
    jmp .calc_size

;==============================================================================
; ANDI
;==============================================================================
.andi:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    test ebx, ebx
    jnz .andi_general

    xor eax, eax
    jmp .emit_li

.andi_general:
    push rax                    ; Save immediate
    call emit_load_rs1
    pop rax                     ; Restore immediate

    mov byte [r12], 0x48
    mov byte [r12+1], 0x25
    mov [r12+2], eax
    add r12, 6

    call emit_store_rd
    jmp .calc_size

;==============================================================================
; SLLI
;==============================================================================
.slli:
    call extract_i_type
    and eax, 0x3F

    test ecx, ecx
    jz .emit_nop

    test ebx, ebx
    jnz .slli_general

    xor eax, eax
    jmp .emit_li

.slli_general:
    push rcx                    ; Save rd
    push rax                    ; Save shamt
    call emit_load_rs1
    pop rcx                     ; Restore shamt to cl

    mov byte [r12], 0x48
    mov byte [r12+1], 0xC1
    mov byte [r12+2], 0xE0
    mov [r12+3], cl
    add r12, 4

    pop rcx                     ; Restore rd
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; SRLI/SRAI
;==============================================================================
.srli_srai:
    call extract_i_type

    mov r15d, r13d
    shr r15d, 30
    and r15d, 1

    and eax, 0x3F

    test ecx, ecx
    jz .emit_nop

    test ebx, ebx
    jnz .srxi_general

    xor eax, eax
    jmp .emit_li

.srxi_general:
    push rax
    push r15
    call emit_load_rs1
    pop r15
    pop rcx

    test r15d, r15d
    jnz .emit_sra

    mov byte [r12], 0x48
    mov byte [r12+1], 0xC1
    mov byte [r12+2], 0xE8
    mov [r12+3], cl
    add r12, 4
    jmp .srxi_store

.emit_sra:
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC1
    mov byte [r12+2], 0xF8
    mov [r12+3], cl
    add r12, 4

.srxi_store:
    mov eax, r13d
    shr eax, 7
    and eax, 0x1F
    mov ecx, eax
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; OP-IMM-32 (32-bit immediate operations)
; addiw, slliw, srliw, sraiw
; These operate on 32-bit values and sign-extend the result to 64-bit
;==============================================================================
.op_imm_32:
    call extract_i_type
    ; ECX = rd, EBX = rs1, EAX = imm12 (sign-extended)

    push rcx                    ; Save rd
    push rax                    ; Save imm12

    test ebx, ebx               ; Test rs1
    jnz .op_imm_32_load_rs1

    ; rs1 is x0, just use 0
    ; xor eax, eax
    mov byte [r12], 0x31
    mov byte [r12+1], 0xC0
    add r12, 2
    jmp .op_imm_32_dispatch

.op_imm_32_load_rs1:
    ; Load rs1 into RAX (then we use lower 32 bits via EAX)
    ; EBX already has rs1 from extract_i_type
    call emit_load_rs1

.op_imm_32_dispatch:
    ; Get funct3
    mov eax, r13d
    shr eax, 12
    and eax, 0x7

    cmp eax, RV_F3_ADDI
    je .addiw
    cmp eax, RV_F3_SLLI
    je .slliw
    cmp eax, RV_F3_SRLI_SRAI
    je .srxiw

    ; Unknown funct3 - treat as NOP
    pop rdx
    pop rcx
    jmp .emit_nop

.addiw:
    ; add eax, imm32
    pop rdx                     ; Restore imm12
    mov ecx, edx                ; imm12 already sign-extended
    cmp ecx, -128
    jl .addiw_32bit
    cmp ecx, 127
    jg .addiw_32bit

    ; 8-bit immediate: add eax, imm8
    mov byte [r12], 0x83
    mov byte [r12+1], 0xC0
    mov [r12+2], cl
    add r12, 3
    jmp .addiw_signext

.addiw_32bit:
    ; 32-bit immediate: add eax, imm32
    mov byte [r12], 0x05
    mov [r12+1], ecx
    add r12, 5

.addiw_signext:
    ; Sign-extend eax to rax: movsxd rax, eax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3
    jmp .op_imm_32_store

.slliw:
    ; shl eax, shamt (shamt in bits 24:20)
    pop rdx                     ; Pop imm (not used for shifts, shamt is in instruction)
    mov ecx, r13d
    shr ecx, 20
    and ecx, 0x1F
    mov byte [r12], 0xC1
    mov byte [r12+1], 0xE0
    mov [r12+2], cl
    add r12, 3
    jmp .addiw_signext          ; Sign-extend after shift

.srxiw:
    pop rdx                     ; Pop imm (not used)
    ; Check funct7 bit to distinguish srliw/sraiw
    mov eax, r13d
    shr eax, 30
    and eax, 1

    mov ecx, r13d
    shr ecx, 20
    and ecx, 0x1F               ; shamt

    test ebx, ebx               ; Test rs1
    jnz .sraiw

    ; srliw: shr eax, shamt
    mov byte [r12], 0xC1
    mov byte [r12+1], 0xE8
    mov [r12+2], cl
    add r12, 3
    jmp .addiw_signext

.sraiw:
    ; sraiw: sar eax, shamt
    mov byte [r12], 0xC1
    mov byte [r12+1], 0xF8
    mov [r12+2], cl
    add r12, 3
    jmp .addiw_signext

.op_imm_32_store:
    pop rcx                     ; Restore rd
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; OP (register-register) dispatch
;==============================================================================
.op_reg:
    mov eax, r13d
    shr eax, 12
    and eax, 0x7

    mov r15d, r13d
    shr r15d, 25
    and r15d, 0x7F

    ; Check for M extension (funct7 = 0x01)
    cmp r15d, 0x01
    je .m_extension

    cmp eax, RV_F3_ADD_SUB
    je .add_sub
    cmp eax, RV_F3_SLL
    je .sll
    cmp eax, RV_F3_SLT
    je .slt
    cmp eax, RV_F3_SLTU
    je .sltu
    cmp eax, RV_F3_XOR
    je .xor_reg
    cmp eax, RV_F3_SRL_SRA
    je .srl_sra
    cmp eax, RV_F3_OR
    je .or_reg
    cmp eax, RV_F3_AND
    je .and_reg

    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

;==============================================================================
; M Extension (funct7 = 0x01): MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU
;==============================================================================
.m_extension:
    ; EAX = funct3 (0-7 determines operation)
    cmp eax, 0
    je .mul
    cmp eax, 1
    je .mulh
    cmp eax, 2
    je .mulhsu
    cmp eax, 3
    je .mulhu
    cmp eax, 4
    je .div
    cmp eax, 5
    je .divu
    cmp eax, 6
    je .rem
    cmp eax, 7
    je .remu

    mov byte [r12], 0xCC        ; Unknown M-extension op
    mov rax, 1
    jmp .done

;------------------------------------------------------------------------------
; MUL: rd = (rs1 * rs2)[63:0]
;------------------------------------------------------------------------------
.mul:
    call extract_r_type
    test ecx, ecx
    jz .emit_nop

    ; Load rs1 into RAX
    push rcx
    push rax
    mov ecx, ebx                ; rs1
    call emit_load_reg_to_rax
    pop rax

    ; Load rs2 into RCX
    push rax
    mov ecx, eax                ; rs2
    call emit_load_reg_to_rcx
    pop rax
    pop rcx

    ; Emit: imul rax, rcx (signed multiply, low 64 bits)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xAF
    mov byte [r12+3], 0xC1      ; ModRM: rax, rcx
    add r12, 4

    ; Store RAX to rd
    call emit_store_rax_to_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; MULH: rd = (signed(rs1) * signed(rs2))[127:64]
;------------------------------------------------------------------------------
.mulh:
    call extract_r_type
    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax

    ; Load rs1 into RAX
    mov ecx, ebx
    call emit_load_reg_to_rax

    ; Load rs2 into RCX
    mov eax, [rsp]
    mov ecx, eax
    call emit_load_reg_to_rcx

    ; Emit: imul rcx (signed multiply RAX*RCX -> RDX:RAX)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xF7
    mov byte [r12+2], 0xE9      ; ModRM: imul rcx
    add r12, 3

    ; Result high bits in RDX, move to RAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xD0      ; mov rax, rdx
    add r12, 3

    pop rax
    pop rcx
    call emit_store_rax_to_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; MULHSU: rd = (signed(rs1) * unsigned(rs2))[127:64]
; This is tricky - x86 doesn't have mixed-sign multiply
;------------------------------------------------------------------------------
.mulhsu:
    ; For now, treat as unsigned (not perfectly correct but functional)
    jmp .mulhu

;------------------------------------------------------------------------------
; MULHU: rd = (unsigned(rs1) * unsigned(rs2))[127:64]
;------------------------------------------------------------------------------
.mulhu:
    call extract_r_type
    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax

    ; Load rs1 into RAX
    mov ecx, ebx
    call emit_load_reg_to_rax

    ; Load rs2 into RCX
    mov eax, [rsp]
    mov ecx, eax
    call emit_load_reg_to_rcx

    ; Emit: mul rcx (unsigned multiply RAX*RCX -> RDX:RAX)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xF7
    mov byte [r12+2], 0xE1      ; ModRM: mul rcx
    add r12, 3

    ; Result high bits in RDX, move to RAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xD0      ; mov rax, rdx
    add r12, 3

    pop rax
    pop rcx
    call emit_store_rax_to_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; DIV: rd = signed(rs1) / signed(rs2)
;------------------------------------------------------------------------------
.div:
    call extract_r_type
    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax

    ; Load rs1 into RAX
    mov ecx, ebx
    call emit_load_reg_to_rax

    ; Sign-extend RAX into RDX:RAX (cqo)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x99      ; cqo
    add r12, 2

    ; Load rs2 into RCX
    mov eax, [rsp]
    mov ecx, eax
    call emit_load_reg_to_rcx

    ; RISC-V: signed division by zero returns -1
    ; Emit: test rcx, rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x85
    mov byte [r12+2], 0xC9      ; test rcx, rcx
    add r12, 3

    ; Emit: jnz .check_overflow (+9 to skip div-by-zero handling)
    mov byte [r12], 0x75        ; jnz rel8
    mov byte [r12+1], 9         ; skip 9 bytes
    add r12, 2

    ; Emit: mov rax, -1 (RISC-V div-by-zero result)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0xC0      ; mov rax, imm32 (sign-extended)
    mov dword [r12+3], 0xFFFFFFFF
    add r12, 7

    ; Emit: jmp .done (+26 to skip overflow check and idiv)
    mov byte [r12], 0xEB        ; jmp rel8
    mov byte [r12+1], 24        ; skip overflow check + idiv
    add r12, 2

    ; .check_overflow:
    ; RISC-V: -2^63 / -1 returns -2^63 (overflow case, x86 would fault)
    ; Emit: cmp rcx, -1 (check if divisor is -1)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x83
    mov byte [r12+2], 0xF9      ; cmp rcx, imm8
    mov byte [r12+3], 0xFF      ; -1
    add r12, 4

    ; Emit: jne .do_idiv (+15 to skip overflow handling)
    mov byte [r12], 0x75        ; jne rel8
    mov byte [r12+1], 15        ; skip to idiv (10+3+2 = 15 bytes)
    add r12, 2

    ; Check if dividend is -2^63 (0x8000000000000000)
    ; Emit: mov r11, 0x8000000000000000
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0xBB      ; mov r11, imm64
    mov dword [r12+2], 0        ; low 32 bits
    mov dword [r12+6], 0x80000000  ; high 32 bits
    add r12, 10

    ; Emit: cmp rax, r11
    mov byte [r12], 0x4C
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xD8      ; cmp rax, r11
    add r12, 3

    ; Emit: je .done (+3 to skip idiv - rax already has -2^63)
    mov byte [r12], 0x74        ; je rel8
    mov byte [r12+1], 3         ; skip idiv
    add r12, 2

    ; .do_idiv:
    ; Emit: idiv rcx (signed divide RDX:RAX / RCX -> RAX=quotient, RDX=remainder)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xF7
    mov byte [r12+2], 0xF9      ; ModRM: idiv rcx
    add r12, 3

    ; .done:
    pop rax
    pop rcx
    call emit_store_rax_to_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; DIVU: rd = unsigned(rs1) / unsigned(rs2)
;------------------------------------------------------------------------------
.divu:
    call extract_r_type
    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax

    ; Load rs1 into RAX
    mov ecx, ebx
    call emit_load_reg_to_rax

    ; Zero-extend RAX into RDX:RAX (xor rdx, rdx)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x31
    mov byte [r12+2], 0xD2      ; xor rdx, rdx
    add r12, 3

    ; Load rs2 into RCX
    mov eax, [rsp]
    mov ecx, eax
    call emit_load_reg_to_rcx

    ; RISC-V: division by zero returns all 1s
    ; Emit: test rcx, rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x85
    mov byte [r12+2], 0xC9      ; test rcx, rcx
    add r12, 3

    ; Emit: jnz +5 (skip over mov rax, -1 which is 7 bytes? No, let's use jnz +10 to skip mov rax,-1 + jmp)
    ; Actually: jnz .do_div (skip mov rax,-1 and jmp .done)
    ; mov rax, -1 is 10 bytes: 48 C7 C0 FF FF FF FF (mov eax,-1 sign-ext) or 48 B8 ... (movabs)
    ; Let's use: mov rax, -1 → 48 C7 C0 FF FF FF FF (7 bytes, sign-extended)
    ; jmp .done → EB 03 (2 bytes, skip div rcx which is 3 bytes)
    ; Total to skip: 7 + 2 = 9 bytes
    mov byte [r12], 0x75        ; jnz rel8
    mov byte [r12+1], 9         ; skip 9 bytes (mov rax,-1 + jmp)
    add r12, 2

    ; Emit: mov rax, -1 (RISC-V div-by-zero result)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0xC0      ; mov rax, imm32 (sign-extended)
    mov dword [r12+3], 0xFFFFFFFF
    add r12, 7

    ; Emit: jmp +3 (skip div rcx)
    mov byte [r12], 0xEB        ; jmp rel8
    mov byte [r12+1], 3         ; skip 3 bytes (div rcx)
    add r12, 2

    ; Emit: div rcx (unsigned divide RDX:RAX / RCX -> RAX=quotient, RDX=remainder)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xF7
    mov byte [r12+2], 0xF1      ; ModRM: div rcx
    add r12, 3

    pop rax
    pop rcx
    call emit_store_rax_to_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; REM: rd = signed(rs1) % signed(rs2)
; RISC-V: remainder by zero returns dividend (rs1)
; RISC-V: -2^63 % -1 = 0 (overflow case, x86 would fault)
;------------------------------------------------------------------------------
.rem:
    call extract_r_type
    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax

    ; Load rs1 into RAX
    mov ecx, ebx
    call emit_load_reg_to_rax

    ; Sign-extend RAX into RDX:RAX (cqo)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x99
    add r12, 2

    ; Load rs2 into RCX
    mov eax, [rsp]
    mov ecx, eax
    call emit_load_reg_to_rcx

    ; Check for zero divisor - return dividend
    ; Emit: test rcx, rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x85
    mov byte [r12+2], 0xC9
    add r12, 3

    ; Emit: jnz .check_overflow (+2 to skip the jmp)
    mov byte [r12], 0x75        ; jnz rel8
    mov byte [r12+1], 2         ; skip 2 bytes (jmp)
    add r12, 2

    ; Emit: jmp .done (+27 to skip overflow check and idiv)
    mov byte [r12], 0xEB        ; jmp rel8
    mov byte [r12+1], 32        ; skip to done (rax has dividend)
    add r12, 2

    ; .check_overflow:
    ; RISC-V: -2^63 % -1 = 0 (overflow case)
    ; Emit: cmp rcx, -1
    mov byte [r12], 0x48
    mov byte [r12+1], 0x83
    mov byte [r12+2], 0xF9
    mov byte [r12+3], 0xFF      ; -1
    add r12, 4

    ; Emit: jne .do_idiv (+20 to skip overflow handling)
    mov byte [r12], 0x75        ; jne rel8
    mov byte [r12+1], 20        ; skip to idiv (10+3+2+3+2 = 20 bytes)
    add r12, 2

    ; Check if dividend is -2^63
    ; Emit: mov r11, 0x8000000000000000
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0xBB      ; mov r11, imm64
    mov dword [r12+2], 0
    mov dword [r12+6], 0x80000000
    add r12, 10

    ; Emit: cmp rax, r11
    mov byte [r12], 0x4C
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xD8
    add r12, 3

    ; Emit: jne .do_idiv (+5 to skip xor rax,rax + jmp)
    mov byte [r12], 0x75        ; jne rel8
    mov byte [r12+1], 5         ; skip to idiv
    add r12, 2

    ; Emit: xor rax, rax (result is 0 for overflow case)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x31
    mov byte [r12+2], 0xC0
    add r12, 3

    ; Emit: jmp .done (+6)
    mov byte [r12], 0xEB
    mov byte [r12+1], 6
    add r12, 2

    ; .do_idiv:
    ; Emit: idiv rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0xF7
    mov byte [r12+2], 0xF9
    add r12, 3

    ; Remainder is in RDX, move to RAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xD0      ; mov rax, rdx
    add r12, 3

    ; .done:
    pop rax
    pop rcx
    call emit_store_rax_to_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; REMU: rd = unsigned(rs1) % unsigned(rs2)
; RISC-V: remainder by zero returns dividend (rs1)
;------------------------------------------------------------------------------
.remu:
    call extract_r_type
    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax

    ; Load rs1 into RAX
    mov ecx, ebx
    call emit_load_reg_to_rax

    ; Zero-extend RAX into RDX:RAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x31
    mov byte [r12+2], 0xD2      ; xor rdx, rdx
    add r12, 3

    ; Load rs2 into RCX
    mov eax, [rsp]
    mov ecx, eax
    call emit_load_reg_to_rcx

    ; Check for zero divisor
    ; Emit: test rcx, rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x85
    mov byte [r12+2], 0xC9
    add r12, 3

    ; Emit: jz +6 (skip div + mov rdx to rax = 3 + 3 bytes)
    mov byte [r12], 0x74        ; jz rel8
    mov byte [r12+1], 6         ; skip 6 bytes
    add r12, 2

    ; Emit: div rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0xF7
    mov byte [r12+2], 0xF1
    add r12, 3

    ; Remainder is in RDX, move to RAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xD0      ; mov rax, rdx
    add r12, 3

    ; If divisor was zero, RAX still has rs1 (dividend) which is correct

    pop rax
    pop rcx
    call emit_store_rax_to_rd
    jmp .calc_size

;==============================================================================
; ADD/SUB
;==============================================================================
.add_sub:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rax
    call emit_load_rs1
    pop rax

    push rcx
    ; Load rs2 into RCX - use helper for proper disp8/disp32
    mov ecx, eax                ; rs2
    call emit_load_reg_to_rcx

    cmp r15d, RV_F7_ALT
    je .emit_sub

    mov byte [r12], 0x48
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xC8
    add r12, 3
    jmp .add_sub_store

.emit_sub:
    mov byte [r12], 0x48
    mov byte [r12+1], 0x29
    mov byte [r12+2], 0xC8
    add r12, 3

.add_sub_store:
    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; SLL
;==============================================================================
.sll:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1

    pop rax
    ; Load rs2 into RCX - use helper for proper disp8/disp32
    mov ecx, eax                ; rs2
    call emit_load_reg_to_rcx

    mov byte [r12], 0x48
    mov byte [r12+1], 0xD3
    mov byte [r12+2], 0xE0
    add r12, 3

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; SLT
;==============================================================================
.slt:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1

    ; Load rs2 into RCX - use helper for proper disp8/disp32
    pop rax
    mov ecx, eax
    call emit_load_reg_to_rcx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xC8
    add r12, 3

    mov byte [r12], 0x0F
    mov byte [r12+1], 0x9C
    mov byte [r12+2], 0xC0
    add r12, 3

    mov byte [r12], 0x48
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB6
    mov byte [r12+3], 0xC0
    add r12, 4

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; SLTU
;==============================================================================
.sltu:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1

    ; Load rs2 into RCX - use helper for proper disp8/disp32
    pop rax
    mov ecx, eax
    call emit_load_reg_to_rcx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xC8
    add r12, 3

    mov byte [r12], 0x0F
    mov byte [r12+1], 0x92
    mov byte [r12+2], 0xC0
    add r12, 3

    mov byte [r12], 0x48
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB6
    mov byte [r12+3], 0xC0
    add r12, 4

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; XOR (register)
;==============================================================================
.xor_reg:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1

    ; Load rs2 into RCX - use helper for proper disp8/disp32
    pop rax
    mov ecx, eax
    call emit_load_reg_to_rcx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x31
    mov byte [r12+2], 0xC8
    add r12, 3

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; SRL/SRA
;==============================================================================
.srl_sra:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1

    ; Load rs2 into RCX - use helper for proper disp8/disp32
    pop rax
    mov ecx, eax
    call emit_load_reg_to_rcx

    cmp r15d, RV_F7_ALT
    je .emit_sra_reg

    mov byte [r12], 0x48
    mov byte [r12+1], 0xD3
    mov byte [r12+2], 0xE8
    add r12, 3
    jmp .srl_sra_store

.emit_sra_reg:
    mov byte [r12], 0x48
    mov byte [r12+1], 0xD3
    mov byte [r12+2], 0xF8
    add r12, 3

.srl_sra_store:
    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; OR (register)
;==============================================================================
.or_reg:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1

    ; Load rs2 into RCX - use helper for proper disp8/disp32
    pop rax
    mov ecx, eax
    call emit_load_reg_to_rcx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x09
    mov byte [r12+2], 0xC8
    add r12, 3

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; AND (register)
;==============================================================================
.and_reg:
    call extract_r_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1

    ; Load rs2 into RCX - use helper for proper disp8/disp32
    pop rax
    mov ecx, eax
    call emit_load_reg_to_rcx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x21
    mov byte [r12+2], 0xC8
    add r12, 3

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; OP-32 (32-bit register operations: addw, subw, sllw, srlw, sraw, etc.)
; Same as OP but result is sign-extended 32-bit
;==============================================================================
.op_reg_32:
    ; Extract funct3 and funct7
    mov eax, r13d
    shr eax, 12
    and eax, 0x7                ; funct3

    mov ecx, r13d
    shr ecx, 25                 ; funct7

    ; Dispatch based on funct3 and funct7
    cmp eax, 0                  ; addw/subw/mulw
    jne .op32_check_sll
    cmp ecx, 0
    je .addw
    cmp ecx, 0x20
    je .subw
    cmp ecx, 1
    je .mulw
    jmp .op32_unsupported

.op32_check_sll:
    cmp eax, 1                  ; sllw
    jne .op32_check_srl
    cmp ecx, 0
    je .sllw
    jmp .op32_unsupported

.op32_check_srl:
    cmp eax, 5                  ; srlw/sraw/divuw
    jne .op32_check_div
    cmp ecx, 0
    je .srlw
    cmp ecx, 0x20
    je .sraw
    cmp ecx, 1
    je .divuw
    jmp .op32_unsupported

.op32_check_div:
    cmp eax, 4                  ; divw
    jne .op32_check_rem
    cmp ecx, 1
    je .divw
    jmp .op32_unsupported

.op32_check_rem:
    cmp eax, 6                  ; remw
    jne .op32_check_remu
    cmp ecx, 1
    je .remw
    jmp .op32_unsupported

.op32_check_remu:
    cmp eax, 7                  ; remuw
    jne .op32_unsupported
    cmp ecx, 1
    je .remuw

.op32_unsupported:
    mov byte [r12], 0xCC        ; INT3 for debugging
    mov rax, 1
    jmp .done

;------------------------------------------------------------------------------
; ADDW - Add word (32-bit, sign-extend result)
;------------------------------------------------------------------------------
.addw:
    call extract_r_type         ; ECX=rd, EBX=rs1, EAX=rs2

    test ecx, ecx
    jz .emit_nop

    push rcx                    ; Save rd
    push rax                    ; Save rs2
    call emit_load_rs1          ; Load rs1 into RAX
    pop rdx                     ; Restore rs2 into RDX
    pop rcx                     ; Restore rd

    ; Load rs2 to RCX (use helper for proper disp8/disp32)
    push rcx
    mov ecx, edx                ; rs2 register number (now in EDX)
    call emit_load_reg_to_rcx
    pop rcx

    ; ADD EAX, ECX (32-bit add)
    mov byte [r12], 0x01
    mov byte [r12+1], 0xC8      ; ADD EAX, ECX
    add r12, 2

    ; Sign-extend EAX to RAX: MOVSXD RAX, EAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    call emit_store_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; SUBW - Subtract word (32-bit, sign-extend result)
;------------------------------------------------------------------------------
.subw:
    call extract_r_type         ; ECX=rd, EBX=rs1, EAX=rs2

    test ecx, ecx
    jz .emit_nop

    push rcx                    ; Save rd
    push rax                    ; Save rs2
    call emit_load_rs1          ; Load rs1 into RAX
    pop rdx                     ; Restore rs2 into RDX
    pop rcx                     ; Restore rd

    ; Load rs2 to RCX (use helper for proper disp8/disp32)
    push rcx
    mov ecx, edx                ; rs2 register number (now in EDX)
    call emit_load_reg_to_rcx
    pop rcx

    ; SUB EAX, ECX
    mov byte [r12], 0x29
    mov byte [r12+1], 0xC8      ; SUB EAX, ECX
    add r12, 2

    ; MOVSXD RAX, EAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    call emit_store_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; SLLW - Shift left logical word
;------------------------------------------------------------------------------
.sllw:
    call extract_r_type         ; ECX=rd, EBX=rs1, EAX=rs2

    test ecx, ecx
    jz .emit_nop

    push rcx                    ; Save rd
    push rax                    ; Save rs2 (NOT rdx!)
    call emit_load_rs1          ; EAX = rs1
    pop rdx                     ; Restore rs2 into RDX
    pop rcx                     ; Restore rd

    ; Load rs2 to ECX (for shift amount) - use proper disp8/disp32
    push rcx
    mov ecx, edx                ; rs2 now in EDX
    call emit_load_reg_to_rcx
    pop rcx

    ; SHL EAX, CL
    mov byte [r12], 0xD3
    mov byte [r12+1], 0xE0
    add r12, 2

    ; MOVSXD RAX, EAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    push rcx
    call emit_store_rd
    pop rcx
    jmp .calc_size

;------------------------------------------------------------------------------
; SRLW - Shift right logical word
;------------------------------------------------------------------------------
.srlw:
    call extract_r_type         ; ECX=rd, EBX=rs1, EAX=rs2

    test ecx, ecx
    jz .emit_nop

    push rcx                    ; Save rd
    push rax                    ; Save rs2 (NOT rdx!)
    call emit_load_rs1
    pop rdx                     ; Restore rs2 into RDX
    pop rcx                     ; Restore rd

    ; Load rs2 to ECX - use proper disp8/disp32
    push rcx
    mov ecx, edx                ; rs2 now in EDX
    call emit_load_reg_to_rcx
    pop rcx

    ; SHR EAX, CL
    mov byte [r12], 0xD3
    mov byte [r12+1], 0xE8
    add r12, 2

    ; MOVSXD RAX, EAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    push rcx
    call emit_store_rd
    pop rcx
    jmp .calc_size

;------------------------------------------------------------------------------
; SRAW - Shift right arithmetic word
;------------------------------------------------------------------------------
.sraw:
    call extract_r_type         ; ECX=rd, EBX=rs1, EAX=rs2

    test ecx, ecx
    jz .emit_nop

    push rcx                    ; Save rd
    push rax                    ; Save rs2 (NOT rdx!)
    call emit_load_rs1
    pop rdx                     ; Restore rs2 into RDX
    pop rcx                     ; Restore rd

    ; Load rs2 to ECX - use proper disp8/disp32
    push rcx
    mov ecx, edx                ; rs2 now in EDX
    call emit_load_reg_to_rcx
    pop rcx

    ; SAR EAX, CL
    mov byte [r12], 0xD3
    mov byte [r12+1], 0xF8
    add r12, 2

    ; MOVSXD RAX, EAX (already sign-extended by SAR on 32-bit)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    push rcx
    call emit_store_rd
    pop rcx
    jmp .calc_size

;------------------------------------------------------------------------------
; MULW - Multiply word (32-bit, sign-extend result)
;------------------------------------------------------------------------------
.mulw:
    call extract_r_type
    ; After extract_r_type: ecx=rd, ebx=rs1, eax=rs2

    test ecx, ecx
    jz .emit_nop

    push rcx                    ; save rd
    push rax                    ; save rs2 (NOT rdx - rs2 is in eax!)
    call emit_load_rs1          ; EAX = rs1
    pop rax                     ; restore rs2 to eax
    mov edx, eax                ; move rs2 to edx for emit_load_reg_to_rdx
    pop rcx                     ; restore rd

    ; Load rs2 to RDX (use helper for proper disp8/disp32)
    push rcx
    mov ecx, edx            ; rs2 register number (now correct!)
    call emit_load_reg_to_rdx

    ; IMUL EAX, EDX (result in EAX, ignore overflow to EDX)
    mov byte [r12], 0x0F
    mov byte [r12+1], 0xAF
    mov byte [r12+2], 0xC2      ; IMUL EAX, EDX
    add r12, 3

    ; MOVSXD RAX, EAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    pop rcx
    call emit_store_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; DIVW - Divide word (signed)
; RISC-V: division by zero returns -1
; RISC-V: -2^31 / -1 returns -2^31 (overflow case)
;------------------------------------------------------------------------------
.divw:
    call extract_r_type
    ; After extract_r_type: ecx=rd, ebx=rs1, eax=rs2

    test ecx, ecx
    jz .emit_nop

    push rcx                    ; save rd
    push rax                    ; save rs2 (was incorrectly using rdx!)
    call emit_load_rs1          ; EAX = rs1
    pop rax                     ; restore rs2 into eax
    mov edx, eax                ; move rs2 to edx for later use
    pop rcx                     ; restore rd

    ; Sign-extend EAX to EDX:EAX using CDQ
    mov byte [r12], 0x99        ; CDQ
    add r12, 1

    ; Load rs2 to RCX (use helper for proper disp8/disp32)
    push rcx
    mov ecx, edx            ; rs2 register number
    call emit_load_reg_to_rcx

    ; Check for zero divisor
    ; Emit: test ecx, ecx
    mov byte [r12], 0x85
    mov byte [r12+1], 0xC9      ; test ecx, ecx
    add r12, 2

    ; Emit: jnz .check_overflow (+7)
    mov byte [r12], 0x75        ; jnz rel8
    mov byte [r12+1], 7         ; skip to overflow check
    add r12, 2

    ; Emit: mov eax, -1
    mov byte [r12], 0xB8        ; mov eax, imm32
    mov dword [r12+1], 0xFFFFFFFF
    add r12, 5

    ; Emit: jmp .done (+15 to skip overflow check and idiv)
    mov byte [r12], 0xEB        ; jmp rel8
    mov byte [r12+1], 15        ; skip to done
    add r12, 2

    ; .check_overflow: Check for -2^31 / -1
    ; Emit: cmp ecx, -1
    mov byte [r12], 0x83
    mov byte [r12+1], 0xF9      ; cmp ecx, imm8
    mov byte [r12+2], 0xFF      ; -1
    add r12, 3

    ; Emit: jne .do_idiv (+7)
    mov byte [r12], 0x75        ; jne rel8
    mov byte [r12+1], 7         ; skip 5 (cmp eax,imm32) + 2 (je) = 7 bytes to idiv
    add r12, 2

    ; Emit: cmp eax, 0x80000000
    mov byte [r12], 0x3D        ; cmp eax, imm32
    mov dword [r12+1], 0x80000000
    add r12, 5

    ; Emit: je .done (+2) - eax already has -2^31
    mov byte [r12], 0x74        ; je rel8
    mov byte [r12+1], 2         ; skip idiv
    add r12, 2

    ; .do_idiv:
    ; IDIV ECX (EAX = EDX:EAX / ECX)
    mov byte [r12], 0xF7
    mov byte [r12+1], 0xF9      ; IDIV ECX
    add r12, 2

    ; .done:
    ; MOVSXD RAX, EAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    pop rcx
    call emit_store_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; DIVUW - Divide word (unsigned)
; RISC-V: division by zero returns all 1s
;------------------------------------------------------------------------------
.divuw:
    call extract_r_type
    ; After extract_r_type: ecx=rd, ebx=rs1, eax=rs2

    test ecx, ecx
    jz .emit_nop

    push rcx                    ; save rd
    push rax                    ; save rs2 (was incorrectly using rdx!)
    call emit_load_rs1

    ; Zero-extend EAX to EDX:EAX
    mov byte [r12], 0x31
    mov byte [r12+1], 0xD2      ; XOR EDX, EDX
    add r12, 2

    pop rax                     ; restore rs2 into eax
    mov edx, eax                ; move rs2 to edx for later use
    pop rcx                     ; restore rd

    ; Load rs2 to RCX (use helper for proper disp8/disp32)
    push rcx
    mov ecx, edx            ; rs2 register number
    call emit_load_reg_to_rcx

    ; Check for zero divisor
    ; Emit: test ecx, ecx
    mov byte [r12], 0x85
    mov byte [r12+1], 0xC9
    add r12, 2

    ; Emit: jnz .do_div (+7)
    mov byte [r12], 0x75
    mov byte [r12+1], 7
    add r12, 2

    ; Emit: mov eax, -1
    mov byte [r12], 0xB8
    mov dword [r12+1], 0xFFFFFFFF
    add r12, 5

    ; Emit: jmp .done (+2)
    mov byte [r12], 0xEB
    mov byte [r12+1], 2
    add r12, 2

    ; .do_div:
    ; DIV ECX
    mov byte [r12], 0xF7
    mov byte [r12+1], 0xF1      ; DIV ECX
    add r12, 2

    ; .done:
    ; MOVSXD RAX, EAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    pop rcx
    call emit_store_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; REMW - Remainder word (signed)
; RISC-V: remainder by zero returns dividend
; RISC-V: -2^31 % -1 = 0 (overflow case)
;------------------------------------------------------------------------------
.remw:
    call extract_r_type
    ; After extract_r_type: ecx=rd, ebx=rs1, eax=rs2

    test ecx, ecx
    jz .emit_nop

    push rcx                    ; save rd
    push rax                    ; save rs2 (was incorrectly using rdx!)
    call emit_load_rs1

    ; CDQ
    mov byte [r12], 0x99
    add r12, 1

    pop rax                     ; restore rs2 into eax
    mov edx, eax                ; move rs2 to edx for later use
    pop rcx                     ; restore rd

    ; Load rs2 to RCX (use helper for proper disp8/disp32)
    push rcx
    mov ecx, edx            ; rs2 register number
    call emit_load_reg_to_rcx

    ; Check for zero divisor - return dividend
    ; Emit: test ecx, ecx
    mov byte [r12], 0x85
    mov byte [r12+1], 0xC9
    add r12, 2

    ; Emit: jnz .check_overflow (+2)
    mov byte [r12], 0x75
    mov byte [r12+1], 2
    add r12, 2

    ; Emit: jmp .done (+19 - eax has dividend)
    mov byte [r12], 0xEB
    mov byte [r12+1], 20
    add r12, 2

    ; .check_overflow: Check for -2^31 % -1 = 0
    ; Emit: cmp ecx, -1
    mov byte [r12], 0x83
    mov byte [r12+1], 0xF9
    mov byte [r12+2], 0xFF
    add r12, 3

    ; Emit: jne .do_idiv (+11)
    ; Skip: 5 (cmp eax,imm32) + 2 (jne) + 2 (xor) + 2 (jmp) = 11 bytes
    mov byte [r12], 0x75
    mov byte [r12+1], 11
    add r12, 2

    ; Emit: cmp eax, 0x80000000
    mov byte [r12], 0x3D
    mov dword [r12+1], 0x80000000
    add r12, 5

    ; Emit: jne .do_idiv (+4)
    mov byte [r12], 0x75
    mov byte [r12+1], 4
    add r12, 2

    ; Emit: xor eax, eax (result is 0 for overflow case)
    mov byte [r12], 0x31
    mov byte [r12+1], 0xC0
    add r12, 2

    ; Emit: jmp .done (+4)
    mov byte [r12], 0xEB
    mov byte [r12+1], 4
    add r12, 2

    ; .do_idiv:
    ; IDIV ECX
    mov byte [r12], 0xF7
    mov byte [r12+1], 0xF9
    add r12, 2

    ; MOV EAX, EDX (remainder is in EDX)
    mov byte [r12], 0x89
    mov byte [r12+1], 0xD0
    add r12, 2

    ; .done:
    ; MOVSXD RAX, EAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    pop rcx
    call emit_store_rd
    jmp .calc_size

;------------------------------------------------------------------------------
; REMUW - Remainder word (unsigned)
; RISC-V: remainder by zero returns dividend
;------------------------------------------------------------------------------
.remuw:
    call extract_r_type
    ; After extract_r_type: ecx=rd, ebx=rs1, eax=rs2

    test ecx, ecx
    jz .emit_nop

    push rcx                    ; save rd
    push rax                    ; save rs2 (was incorrectly using rdx!)
    call emit_load_rs1

    ; XOR EDX, EDX
    mov byte [r12], 0x31
    mov byte [r12+1], 0xD2
    add r12, 2

    pop rax                     ; restore rs2 into eax
    mov edx, eax                ; move rs2 to edx for later use
    pop rcx                     ; restore rd

    ; Load rs2 to RCX (use helper for proper disp8/disp32)
    push rcx
    mov ecx, edx            ; rs2 register number
    call emit_load_reg_to_rcx

    ; Check for zero divisor - return dividend
    ; Emit: test ecx, ecx
    mov byte [r12], 0x85
    mov byte [r12+1], 0xC9
    add r12, 2

    ; Emit: jnz .do_div (+2)
    mov byte [r12], 0x75
    mov byte [r12+1], 2
    add r12, 2

    ; Emit: jmp .done (+4 - skip div+mov, eax has dividend)
    mov byte [r12], 0xEB
    mov byte [r12+1], 4
    add r12, 2

    ; .do_div:
    ; DIV ECX
    mov byte [r12], 0xF7
    mov byte [r12+1], 0xF1
    add r12, 2

    ; MOV EAX, EDX (remainder is in EDX)
    mov byte [r12], 0x89
    mov byte [r12+1], 0xD0
    add r12, 2

    ; .done:
    ; MOVSXD RAX, EAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; LOAD dispatch
;==============================================================================
.load:
    mov eax, r13d
    shr eax, 12
    and eax, 0x7

    cmp eax, RV_F3_LB
    je .lb
    cmp eax, RV_F3_LH
    je .lh
    cmp eax, RV_F3_LW
    je .lw
    cmp eax, RV_F3_LD
    je .ld
    cmp eax, RV_F3_LBU
    je .lbu
    cmp eax, RV_F3_LHU
    je .lhu
    cmp eax, RV_F3_LWU
    je .lwu

    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

;==============================================================================
; LB - Load Byte (sign-extended)
;==============================================================================
.lb:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    mov byte [r12], 0x49
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xBE
    mov byte [r12+3], 0x04
    mov byte [r12+4], 0x06
    add r12, 5

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; LH - Load Halfword (sign-extended)
;==============================================================================
.lh:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    mov byte [r12], 0x49
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xBF
    mov byte [r12+3], 0x04
    mov byte [r12+4], 0x06
    add r12, 5

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; LW - Load Word (sign-extended) - WITH BOUNDS CHECK
;==============================================================================
.lw:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    ; add rax, imm (6 bytes)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    ; Bounds check: if rax >= 0x8000000 (128MB), return 0
    ; Use: mov rcx, 0x7FFFFFC; cmp rax, rcx; jae skip_load
    ; mov rcx, imm64 (10 bytes): 48 B9 xx xx xx xx xx xx xx xx
    mov byte [r12], 0x48
    mov byte [r12+1], 0xB9
    mov dword [r12+2], 0x07FFFFFC    ; low 32 bits
    mov dword [r12+6], 0             ; high 32 bits
    add r12, 10
    ; cmp rax, rcx (3 bytes): 48 39 C8
    mov byte [r12], 0x48
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xC8
    add r12, 3
    ; jae +6 (2 bytes): 73 06 - skip to xor if out of bounds
    mov byte [r12], 0x73
    mov byte [r12+1], 0x06
    add r12, 2
    ; movsxd rax, [r14+rax] (4 bytes): 49 63 04 06
    mov byte [r12], 0x49
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0x04
    mov byte [r12+3], 0x06
    add r12, 4
    ; jmp +2 (2 bytes): EB 02 - skip xor
    mov byte [r12], 0xEB
    mov byte [r12+1], 0x02
    add r12, 2
    ; xor eax, eax (2 bytes): 31 C0 - return 0 for OOB
    mov byte [r12], 0x31
    mov byte [r12+1], 0xC0
    add r12, 2

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; LD - Load Doubleword - WITH BOUNDS CHECK
;==============================================================================
.ld:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    ; add rax, imm (6 bytes)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    ; Bounds check: mov rcx, limit; cmp rax, rcx; jae skip
    mov byte [r12], 0x48
    mov byte [r12+1], 0xB9
    mov dword [r12+2], 0x07FFFFF8    ; 128MB - 8
    mov dword [r12+6], 0
    add r12, 10
    mov byte [r12], 0x48
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xC8           ; cmp rax, rcx
    add r12, 3
    mov byte [r12], 0x73             ; jae +6
    mov byte [r12+1], 0x06
    add r12, 2
    ; mov rax, [r14+rax] (4 bytes)
    mov byte [r12], 0x49
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x04
    mov byte [r12+3], 0x06
    add r12, 4
    mov byte [r12], 0xEB             ; jmp +2
    mov byte [r12+1], 0x02
    add r12, 2
    mov byte [r12], 0x31             ; xor eax, eax
    mov byte [r12+1], 0xC0
    add r12, 2

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; LBU - Load Byte Unsigned
;==============================================================================
.lbu:
    inc qword [lbu_count]
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    ; Before the load, save address to temp register (r10)
    ; mov r10, rax (49 89 C2) - save address before load clobbers rax
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xC2
    add r12, 3

    ; movzx rax, byte [r14+rax]
    mov byte [r12], 0x49
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB6
    mov byte [r12+3], 0x04
    mov byte [r12+4], 0x06
    add r12, 5

    ; Debug: capture first LBU address and value
    ; Check if already captured: mov r11, first_lbu_captured
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBB
    lea rdx, [first_lbu_captured]
    mov [r12+2], rdx
    add r12, 10
    ; cmp byte [r11], 0
    mov byte [r12], 0x41
    mov byte [r12+1], 0x80
    mov byte [r12+2], 0x3B
    mov byte [r12+3], 0x00
    add r12, 4
    ; jne skip (75 XX)
    mov byte [r12], 0x75
    mov byte [r12+1], 0
    lea rdi, [r12+1]      ; save patch location
    add r12, 2
    ; Set captured flag: mov byte [r11], 1
    mov byte [r12], 0x41
    mov byte [r12+1], 0xC6
    mov byte [r12+2], 0x03
    mov byte [r12+3], 0x01
    add r12, 4
    ; Save address: mov [first_lbu_addr], r10
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBB
    lea rdx, [first_lbu_addr]
    mov [r12+2], rdx
    add r12, 10
    mov byte [r12], 0x4D
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x13
    add r12, 3
    ; Save value: mov [first_lbu_val], al
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBB
    lea rdx, [first_lbu_val]
    mov [r12+2], rdx
    add r12, 10
    mov byte [r12], 0x41
    mov byte [r12+1], 0x88
    mov byte [r12+2], 0x03
    add r12, 3
    ; Patch jne offset
    mov rax, r12
    sub rax, rdi
    dec rax
    mov [rdi], al

    ; Debug: capture LBU from doom1.wad area (0x3ae00-0x3af00)
    ; Check if already captured: mov r11, doom_lbu_captured
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBB
    lea rdx, [doom_lbu_captured]
    mov [r12+2], rdx
    add r12, 10
    ; cmp byte [r11], 0
    mov byte [r12], 0x41
    mov byte [r12+1], 0x80
    mov byte [r12+2], 0x3B
    mov byte [r12+3], 0x00
    add r12, 4
    ; jne skip_doom (75 XX)
    mov byte [r12], 0x75
    mov byte [r12+1], 0
    lea rdi, [r12+1]      ; save patch location for skip_doom
    add r12, 2

    ; Check if address (r10) in range 0x3ae00-0x3af00 (doom1.wad string area)
    ; 49 81 FA 00 AE 03 00 = cmp r10, 0x3ae00
    mov byte [r12], 0x49
    mov byte [r12+1], 0x81
    mov byte [r12+2], 0xFA
    mov dword [r12+3], 0x0003ae00
    add r12, 7
    ; jb skip_doom (72 XX)
    mov byte [r12], 0x72
    mov byte [r12+1], 0
    lea r8, [r12+1]       ; save second patch location
    add r12, 2
    ; cmp r10, 0x3af00
    mov byte [r12], 0x49
    mov byte [r12+1], 0x81
    mov byte [r12+2], 0xFA
    mov dword [r12+3], 0x0003af00
    add r12, 7
    ; jae skip_doom (73 XX)
    mov byte [r12], 0x73
    mov byte [r12+1], 0
    lea r9, [r12+1]       ; save third patch location
    add r12, 2

    ; Set captured flag: mov byte [r11], 1
    mov byte [r12], 0x41
    mov byte [r12+1], 0xC6
    mov byte [r12+2], 0x03
    mov byte [r12+3], 0x01
    add r12, 4
    ; Save address: mov r11, doom_lbu_addr; mov [r11], r10
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBB
    lea rdx, [doom_lbu_addr]
    mov [r12+2], rdx
    add r12, 10
    mov byte [r12], 0x4D
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x13
    add r12, 3
    ; Save value: mov r11, doom_lbu_val; mov [r11], al
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBB
    lea rdx, [doom_lbu_val]
    mov [r12+2], rdx
    add r12, 10
    mov byte [r12], 0x41
    mov byte [r12+1], 0x88
    mov byte [r12+2], 0x03
    add r12, 3

    ; Patch all skip offsets (first jne, second jb, third jae)
    mov rax, r12
    sub rax, rdi
    dec rax
    mov [rdi], al
    mov rax, r12
    sub rax, r8
    dec rax
    mov [r8], al
    mov rax, r12
    sub rax, r9
    dec rax
    mov [r9], al

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; LHU - Load Halfword Unsigned
;==============================================================================
.lhu:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    mov byte [r12], 0x49
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB7
    mov byte [r12+3], 0x04
    mov byte [r12+4], 0x06
    add r12, 5

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; LWU - Load Word Unsigned
;==============================================================================
.lwu:
    call extract_i_type

    test ecx, ecx
    jz .emit_nop

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    mov byte [r12], 0x41
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x04
    mov byte [r12+3], 0x06
    add r12, 4

    pop rcx
    call emit_store_rd
    jmp .calc_size

;==============================================================================
; STORE dispatch
;==============================================================================
.store:
    mov eax, r13d
    shr eax, 12
    and eax, 0x7

    cmp eax, RV_F3_SB
    je .sb
    cmp eax, RV_F3_SH
    je .sh
    cmp eax, RV_F3_SW
    je .sw
    cmp eax, RV_F3_SD
    je .sd

    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

;==============================================================================
; SB - Store Byte
;==============================================================================
.sb:
    inc qword [sb_count]
    call extract_s_type

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    ; Load rs2 to rcx - handle disp8/disp32
    pop rdx                     ; rdx = rs2
    mov eax, edx
    shl eax, 3                  ; eax = rs2 * 8
    cmp eax, 127
    jg .sb_rs2_disp32

    ; disp8 path: mov rcx, [rbx + disp8]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov [r12+3], al
    add r12, 4
    jmp .sb_store

.sb_rs2_disp32:
    ; disp32 path: mov rcx, [rbx + disp32]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x8B
    mov [r12+3], eax
    add r12, 7

.sb_store:
    ; Simple debug: capture r14 and address for FIRST store only
    ; Check if already captured: cmp byte [first_sb_captured], 0 / jne skip
    ; mov r10, first_sb_captured (49 BA <8 bytes>)
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [first_sb_captured]
    mov [r12+2], rax
    add r12, 10
    ; cmp byte [r10], 0 (41 80 3A 00)
    mov byte [r12], 0x41
    mov byte [r12+1], 0x80
    mov byte [r12+2], 0x3A
    mov byte [r12+3], 0x00
    add r12, 4
    ; jne skip (75 XX) - patch later
    mov byte [r12], 0x75
    mov byte [r12+1], 0   ; placeholder
    lea r11, [r12+1]      ; save patch location
    add r12, 2

    ; Set captured flag: mov byte [r10], 1 (41 C6 02 01)
    mov byte [r12], 0x41
    mov byte [r12+1], 0xC6
    mov byte [r12+2], 0x02
    mov byte [r12+3], 0x01
    add r12, 4

    ; Save r14: mov [first_sb_r14], r14
    ; mov r10, first_sb_r14 (49 BA <8 bytes>)
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [first_sb_r14]
    mov [r12+2], rax
    add r12, 10
    ; mov [r10], r14 (4D 89 32)
    mov byte [r12], 0x4D
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x32
    add r12, 3

    ; Save address: mov [first_sb_addr], rax
    ; mov r10, first_sb_addr (49 BA <8 bytes>)
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [first_sb_addr]
    mov [r12+2], rax
    add r12, 10
    ; mov [r10], rax (49 89 02)
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x02
    add r12, 3

    ; Save cl value: mov [first_sb_val], cl
    ; mov r10, first_sb_val (49 BA <8 bytes>)
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [first_sb_val]
    mov [r12+2], rax
    add r12, 10
    ; mov [r10], cl (41 88 0A)
    mov byte [r12], 0x41
    mov byte [r12+1], 0x88
    mov byte [r12+2], 0x0A
    add r12, 3

    ; Capture value at address BEFORE store
    ; movzx r11, byte [r14+rax] (45 0F B6 1C 06)
    mov byte [r12], 0x45
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB6
    mov byte [r12+3], 0x1C
    mov byte [r12+4], 0x06
    add r12, 5
    ; mov r10, &first_sb_before (49 BA <8 bytes>)
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [first_sb_before]
    mov [r12+2], rax
    add r12, 10
    ; mov [r10], r11b (45 88 1A)
    mov byte [r12], 0x45
    mov byte [r12+1], 0x88
    mov byte [r12+2], 0x1A
    add r12, 3

    ; Patch jne offset
    mov rax, r12
    sub rax, r11
    dec rax
    mov [r11], al

    ; .skip:
    ; Now emit the actual store: mov [r14 + rax], cl (41 88 0C 06)
    mov byte [r12], 0x41
    mov byte [r12+1], 0x88
    mov byte [r12+2], 0x0C
    mov byte [r12+3], 0x06
    add r12, 4

    ; === DEBUG: Track stores to high addresses (>0x700000) ===
    ; At runtime: rax = guest address
    ; Check if rax > 0x700000 and if so, increment a counter
    ; cmp rax, 0x700000 (48 3D 00 00 70 00)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x3D
    mov dword [r12+2], 0x700000
    add r12, 6
    ; jb skip_high_store_debug (72 XX)
    mov byte [r12], 0x72
    mov byte [r12+1], 10      ; Skip 10 bytes
    add r12, 2
    ; inc qword [high_store_count] (48 FF 05 XX XX XX XX) - need absolute
    ; mov r10, &high_store_count (49 BA <8 bytes>)
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [high_store_count]
    mov [r12+2], rax
    add r12, 10
    ; inc qword [r10] (49 FF 02) - WRONG, need inc qword [r10]
    ; Actually: lock inc qword [r10] would be F0 49 FF 02
    ; But simpler: add qword [r10], 1 (49 83 02 01)
    mov byte [r12], 0x49
    mov byte [r12+1], 0x83
    mov byte [r12+2], 0x02
    mov byte [r12+3], 0x01
    add r12, 4
    ; .skip_high_store_debug:
    ; Total skip = 10 + 4 = 14 bytes, so jb offset should be 14

    ; Fix the jb offset (it was 10, should be 14)
    mov byte [r12-18], 14

    ; === Count stores to strdup region (0x12EE00 <= addr < 0x12F000) ===
    ; cmp eax, 0x12EE00 (3D 00 EE 12 00)
    mov byte [r12], 0x3D
    mov dword [r12+1], 0x12EE00
    add r12, 5
    ; jb skip_strdup_count (72 XX)
    mov byte [r12], 0x72
    mov byte [r12+1], 0
    lea r10, [r12+1]      ; save patch location
    add r12, 2
    ; cmp eax, 0x12F000 (3D 00 F0 12 00)
    mov byte [r12], 0x3D
    mov dword [r12+1], 0x12F000
    add r12, 5
    ; jae skip_strdup_count (73 XX)
    mov byte [r12], 0x73
    mov byte [r12+1], 0
    lea r11, [r12+1]      ; save second patch location
    add r12, 2
    ; In range - increment counter
    ; mov rdi, &strdup_region_count (48 BF <8 bytes>)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xBF
    lea rax, [strdup_region_count]
    mov [r12+2], rax
    add r12, 10
    ; add qword [rdi], 1 (48 83 07 01)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x83
    mov byte [r12+2], 0x07
    mov byte [r12+3], 0x01
    add r12, 4
    ; Patch both jumps
    mov rax, r12
    sub rax, r10
    dec rax
    mov [r10], al
    mov rax, r12
    sub rax, r11
    dec rax
    mov [r11], al
    ; .skip_strdup_count:

    ; === Capture first store to exact strdup dest (addr >= 0x12EEF0 && addr < 0x12F000) ===
    ; cmp eax, 0x12EEF0 (3D F0 EE 12 00)
    mov byte [r12], 0x3D
    mov dword [r12+1], 0x12EEF0
    add r12, 5
    ; jb skip_exact (72 XX)
    mov byte [r12], 0x72
    mov byte [r12+1], 0
    push r12
    inc r12
    add r12, 1
    ; cmp eax, 0x12F000 (3D 00 F0 12 00)
    mov byte [r12], 0x3D
    mov dword [r12+1], 0x12F000
    add r12, 5
    ; jae skip_exact (73 XX)
    mov byte [r12], 0x73
    mov byte [r12+1], 0
    lea r10, [r12+1]
    add r12, 2
    ; Check if already captured
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [exact_sb_captured]
    mov [r12+2], rax
    add r12, 10
    mov byte [r12], 0x41
    mov byte [r12+1], 0x80
    mov byte [r12+2], 0x3A
    mov byte [r12+3], 0x00
    add r12, 4
    mov byte [r12], 0x75
    mov byte [r12+1], 0
    lea rsi, [r12+1]
    add r12, 2
    ; Set captured
    mov byte [r12], 0x41
    mov byte [r12+1], 0xC6
    mov byte [r12+2], 0x02
    mov byte [r12+3], 0x01
    add r12, 4
    ; Save address (rax has guest addr at runtime)
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [exact_sb_addr]
    mov [r12+2], rax
    add r12, 10
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x02
    add r12, 3
    ; Save value (cl)
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [exact_sb_val]
    mov [r12+2], rax
    add r12, 10
    mov byte [r12], 0x41
    mov byte [r12+1], 0x88
    mov byte [r12+2], 0x0A
    add r12, 3
    ; Read back
    mov byte [r12], 0x45
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB6
    mov byte [r12+3], 0x1C
    mov byte [r12+4], 0x06
    add r12, 5
    ; Save readback
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [exact_sb_readback]
    mov [r12+2], rax
    add r12, 10
    mov byte [r12], 0x45
    mov byte [r12+1], 0x88
    mov byte [r12+2], 0x1A
    add r12, 3
    ; Patch inner jne
    mov rax, r12
    sub rax, rsi
    dec rax
    mov [rsi], al
    ; Patch jae (r10)
    mov rax, r12
    sub rax, r10
    dec rax
    mov [r10], al
    ; Patch jb (on stack - we pushed position of opcode, need to write to offset position)
    pop rax             ; rax = position of opcode
    inc rax             ; rax = position of offset byte
    mov rdi, r12        ; rdi = current position
    sub rdi, rax        ; rdi = current - offset_position
    dec rdi             ; rdi = offset value
    mov [rax], dil      ; Write offset
    ; .skip_exact:

    ; === Count stores to exactly 0x12EEF0 ===
    ; cmp eax, 0x12EEF0 (3D F0 EE 12 00)
    mov byte [r12], 0x3D
    mov dword [r12+1], 0x12EEF0
    add r12, 5
    ; jne skip_exact_count (75 XX)
    mov byte [r12], 0x75
    mov byte [r12+1], 0
    lea r8, [r12+1]
    add r12, 2
    ; Address matches - check if value is zero
    ; test cl, cl (84 C9)
    mov byte [r12], 0x84
    mov byte [r12+1], 0xC9
    add r12, 2
    ; je inc_zero_count (74 XX)
    mov byte [r12], 0x74
    mov byte [r12+1], 0
    lea r9, [r12+1]
    add r12, 2
    ; Value is non-zero - increment nz count
    mov byte [r12], 0x48
    mov byte [r12+1], 0xBF
    lea rax, [exact_nz_count]
    mov [r12+2], rax
    add r12, 10
    mov byte [r12], 0x48
    mov byte [r12+1], 0x83
    mov byte [r12+2], 0x07
    mov byte [r12+3], 0x01
    add r12, 4
    ; jmp end_exact_count (EB XX)
    mov byte [r12], 0xEB
    mov byte [r12+1], 0
    lea r10, [r12+1]
    add r12, 2
    ; .inc_zero_count:
    ; Patch je
    mov rax, r12
    sub rax, r9
    dec rax
    mov [r9], al
    ; Value is zero - increment zero count
    mov byte [r12], 0x48
    mov byte [r12+1], 0xBF
    lea rax, [exact_0_count]
    mov [r12+2], rax
    add r12, 10
    mov byte [r12], 0x48
    mov byte [r12+1], 0x83
    mov byte [r12+2], 0x07
    mov byte [r12+3], 0x01
    add r12, 4
    ; .end_exact_count:
    ; Patch jmp
    mov rax, r12
    sub rax, r10
    dec rax
    mov [r10], al
    ; Patch jne (skip if addr != 0x12EEF0)
    mov rax, r12
    sub rax, r8
    dec rax
    mov [r8], al
    ; .skip_exact_count:

    ; === Capture first NONZERO SB to heap region (0x12E000 <= addr < 0x200000) ===
    ; test cl, cl (84 C9) - skip if value is zero
    mov byte [r12], 0x84
    mov byte [r12+1], 0xC9
    add r12, 2
    ; je skip_heap_capture (74 XX)
    mov byte [r12], 0x74
    mov byte [r12+1], 0
    lea rdi, [r12+1]       ; save zero-check patch location in rdi
    add r12, 2
    ; cmp eax, 0x12E000 (3D 00 E0 12 00)
    mov byte [r12], 0x3D
    mov dword [r12+1], 0x12E000
    add r12, 5
    ; jb skip_heap_capture (72 XX) - skip if addr < 0x12E000
    mov byte [r12], 0x72
    mov byte [r12+1], 0
    lea r8, [r12+1]       ; save offset patch location in r8 (first jump)
    add r12, 2
    ; cmp eax, 0x200000 (3D 00 00 20 00)
    mov byte [r12], 0x3D
    mov dword [r12+1], 0x200000
    add r12, 5
    ; jae skip_heap_capture (73 XX) - skip if addr >= 0x200000
    mov byte [r12], 0x73
    mov byte [r12+1], 0
    lea r9, [r12+1]       ; save second patch location in r9
    add r12, 2
    ; mov r10, &nz_sb_captured (49 BA <8 bytes>)
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [nz_sb_captured]
    mov [r12+2], rax
    add r12, 10
    ; cmp byte [r10], 0 (41 80 3A 00)
    mov byte [r12], 0x41
    mov byte [r12+1], 0x80
    mov byte [r12+2], 0x3A
    mov byte [r12+3], 0x00
    add r12, 4
    ; jne skip_nz_inner (75 XX)
    mov byte [r12], 0x75
    mov byte [r12+1], 0
    lea rsi, [r12+1]      ; save inner patch location
    add r12, 2
    ; Set captured: mov byte [r10], 1 (41 C6 02 01)
    mov byte [r12], 0x41
    mov byte [r12+1], 0xC6
    mov byte [r12+2], 0x02
    mov byte [r12+3], 0x01
    add r12, 4
    ; Save address: mov r10, &nz_sb_addr / mov [r10], rax
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [nz_sb_addr]
    mov [r12+2], rax
    add r12, 10
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x02
    add r12, 3
    ; Save value: mov r10, &nz_sb_val / mov [r10], cl
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [nz_sb_val]
    mov [r12+2], rax
    add r12, 10
    mov byte [r12], 0x41
    mov byte [r12+1], 0x88
    mov byte [r12+2], 0x0A
    add r12, 3
    ; Read back: movzx r11, byte [r14+rax] (45 0F B6 1C 06)
    mov byte [r12], 0x45
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB6
    mov byte [r12+3], 0x1C
    mov byte [r12+4], 0x06
    add r12, 5
    ; Save readback: mov r10, &nz_sb_readback / mov [r10], r11b
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [nz_sb_readback]
    mov [r12+2], rax
    add r12, 10
    mov byte [r12], 0x45
    mov byte [r12+1], 0x88
    mov byte [r12+2], 0x1A
    add r12, 3
    ; Patch inner jne
    mov rax, r12
    sub rax, rsi
    dec rax
    mov [rsi], al
    ; .skip_nz_inner:
    ; Patch all outer jumps: je (rdi), jb (r8), jae (r9)
    mov rax, r12
    sub rax, rdi
    dec rax
    mov [rdi], al
    mov rax, r12
    sub rax, r8
    dec rax
    mov [r8], al
    mov rax, r12
    sub rax, r9
    dec rax
    mov [r9], al
    ; .skip_nz_capture:

    ; Debug: detect corruption - after store, check if [r14+rax] == cl
    ; If not equal, capture the mismatch (first occurrence only)
    ; movzx r11, byte [r14+rax] (45 0F B6 1C 06)
    mov byte [r12], 0x45
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB6
    mov byte [r12+3], 0x1C
    mov byte [r12+4], 0x06
    add r12, 5
    ; cmp r11b, cl (44 38 D9)
    mov byte [r12], 0x44
    mov byte [r12+1], 0x38
    mov byte [r12+2], 0xD9
    add r12, 3
    ; je skip (74 XX) - no corruption, skip
    mov byte [r12], 0x74
    mov byte [r12+1], 0
    lea rdi, [r12+1]          ; save patch location
    add r12, 2
    ; Mismatch detected! Check if already captured
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rdx, [sb_target_captured]
    mov [r12+2], rdx
    add r12, 10
    ; cmp byte [r10], 0
    mov byte [r12], 0x41
    mov byte [r12+1], 0x80
    mov byte [r12+2], 0x3A
    mov byte [r12+3], 0x00
    add r12, 4
    ; jne skip (75 XX)
    mov byte [r12], 0x75
    mov byte [r12+1], 0
    lea r8, [r12+1]           ; save second patch location
    add r12, 2
    ; Set captured: mov byte [r10], 1
    mov byte [r12], 0x41
    mov byte [r12+1], 0xC6
    mov byte [r12+2], 0x02
    mov byte [r12+3], 0x01
    add r12, 4
    ; Save expected value (cl): mov [sb_target_val], cl
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rdx, [sb_target_val]
    mov [r12+2], rdx
    add r12, 10
    mov byte [r12], 0x41
    mov byte [r12+1], 0x88
    mov byte [r12+2], 0x0A
    add r12, 3
    ; Patch both jumps
    mov rax, r12
    sub rax, rdi
    dec rax
    mov [rdi], al
    mov rax, r12
    sub rax, r8
    dec rax
    mov [r8], al

    ; Emit immediate readback for FIRST store only
    ; Check first_sb_readback_done flag (not the value itself!)
    ; mov r10, &first_sb_readback_done (49 BA <8 bytes>)
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [first_sb_readback_done]
    mov [r12+2], rax
    add r12, 10
    ; cmp byte [r10], 0 (41 80 3A 00)
    mov byte [r12], 0x41
    mov byte [r12+1], 0x80
    mov byte [r12+2], 0x3A
    mov byte [r12+3], 0x00
    add r12, 4
    ; jne skip_readback (75 XX)
    mov byte [r12], 0x75
    mov byte [r12+1], 0
    lea r11, [r12+1]
    add r12, 2
    ; Set flag: mov byte [r10], 1 (41 C6 02 01)
    mov byte [r12], 0x41
    mov byte [r12+1], 0xC6
    mov byte [r12+2], 0x02
    mov byte [r12+3], 0x01
    add r12, 4
    ; Now load address of first_sb_readback
    ; mov r10, &first_sb_readback (49 BA <8 bytes>)
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [first_sb_readback]
    mov [r12+2], rax
    add r12, 10
    ; movzx ecx, byte [r14 + rax] (41 0F B6 0C 06)
    mov byte [r12], 0x41
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xB6
    mov byte [r12+3], 0x0C
    mov byte [r12+4], 0x06
    add r12, 5
    ; mov [r10], cl (41 88 0A)
    mov byte [r12], 0x41
    mov byte [r12+1], 0x88
    mov byte [r12+2], 0x0A
    add r12, 3
    ; Patch jne offset
    mov rax, r12
    sub rax, r11
    dec rax
    mov [r11], al

    jmp .calc_size

;==============================================================================
; SH - Store Halfword
;==============================================================================
.sh:
    inc qword [sh_count]
    call extract_s_type

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    ; Load rs2 to rcx - handle disp8/disp32
    pop rdx                     ; rdx = rs2
    mov eax, edx
    shl eax, 3                  ; eax = rs2 * 8
    cmp eax, 127
    jg .sh_rs2_disp32

    ; disp8 path: mov rcx, [rbx + disp8]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov [r12+3], al
    add r12, 4
    jmp .sh_store

.sh_rs2_disp32:
    ; disp32 path: mov rcx, [rbx + disp32]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x8B
    mov [r12+3], eax
    add r12, 7

.sh_store:
    mov byte [r12], 0x66
    mov byte [r12+1], 0x41
    mov byte [r12+2], 0x89
    mov byte [r12+3], 0x0C
    mov byte [r12+4], 0x06
    add r12, 5

    jmp .calc_size

;==============================================================================
; SW - Store Word
;==============================================================================
.sw:
    inc qword [sw_count]
    call extract_s_type

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    ; Load rs2 to rcx - handle disp8/disp32
    pop rdx                     ; rdx = rs2
    mov eax, edx
    shl eax, 3                  ; eax = rs2 * 8
    cmp eax, 127
    jg .sw_rs2_disp32

    ; disp8 path: mov rcx, [rbx + disp8]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov [r12+3], al
    add r12, 4
    jmp .sw_store

.sw_rs2_disp32:
    ; disp32 path: mov rcx, [rbx + disp32]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x8B
    mov [r12+3], eax
    add r12, 7

.sw_store:
    ; Emit: mov [r14+rax], ecx (41 89 0C 06)
    mov byte [r12], 0x41
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x0C
    mov byte [r12+3], 0x06
    add r12, 4

    ; === SW Corruption detection ===
    ; Read back: mov r11d, [r14+rax] (45 8B 1C 06)
    mov byte [r12], 0x45
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x1C
    mov byte [r12+3], 0x06
    add r12, 4

    ; Compare: cmp r11d, ecx (44 39 D9)
    mov byte [r12], 0x44
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xD9
    add r12, 3

    ; je skip (74 XX) - no corruption, skip capture
    mov byte [r12], 0x74
    mov byte [r12+1], 0       ; placeholder for offset
    lea r11, [r12+1]          ; save patch location
    add r12, 2

    ; Check if already captured: mov r10, sw_corrupt_captured
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [sw_corrupt_captured]
    mov [r12+2], rax
    add r12, 10
    ; cmp byte [r10], 0 (41 80 3A 00)
    mov byte [r12], 0x41
    mov byte [r12+1], 0x80
    mov byte [r12+2], 0x3A
    mov byte [r12+3], 0x00
    add r12, 4
    ; jne skip2 (75 XX)
    mov byte [r12], 0x75
    mov byte [r12+1], 0       ; placeholder
    push r11                  ; save first patch
    lea r11, [r12+1]          ; save second patch location
    add r12, 2

    ; Set captured: mov byte [r10], 1 (41 C6 02 01)
    mov byte [r12], 0x41
    mov byte [r12+1], 0xC6
    mov byte [r12+2], 0x02
    mov byte [r12+3], 0x01
    add r12, 4

    ; Save address: mov [sw_corrupt_addr], rax
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [sw_corrupt_addr]
    mov [r12+2], rax
    add r12, 10
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x02
    add r12, 3

    ; Save stored value: mov [sw_corrupt_stored], ecx
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [sw_corrupt_stored]
    mov [r12+2], rax
    add r12, 10
    mov byte [r12], 0x41
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x0A
    add r12, 3

    ; Save readback: mov [sw_corrupt_readback], r11d
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [sw_corrupt_readback]
    mov [r12+2], rax
    add r12, 10
    mov byte [r12], 0x45
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x1A
    add r12, 3

    ; Patch second jne
    mov rax, r12
    sub rax, r11
    dec rax
    mov [r11], al
    pop r11                   ; restore first patch location

    ; .skip2:
    ; Patch first je
    mov rax, r12
    sub rax, r11
    dec rax
    mov [r11], al

    ; .skip:

    jmp .calc_size

;==============================================================================
; SD - Store Doubleword
;==============================================================================
.sd:
    inc qword [sd_count]
    call extract_s_type

    push rcx
    push rax
    call emit_load_rs1
    pop rdx

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], edx
    add r12, 6

    ; Load rs2 to rcx - handle disp8/disp32
    pop rdx                     ; rdx = rs2
    mov eax, edx
    shl eax, 3                  ; eax = rs2 * 8
    cmp eax, 127
    jg .sd_rs2_disp32

    ; disp8 path: mov rcx, [rbx + disp8]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B      ; ModRM: [rbx + disp8], reg=rcx
    mov [r12+3], al
    add r12, 4
    jmp .sd_store

.sd_rs2_disp32:
    ; disp32 path: mov rcx, [rbx + disp32]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x8B      ; ModRM: [rbx + disp32], reg=rcx
    mov [r12+3], eax
    add r12, 7

.sd_store:
    ; Store: mov [r14 + rax], rcx (49 89 0C 06)
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x0C
    mov byte [r12+3], 0x06
    add r12, 4

    ; === Capture first SD to heap region (0x12E000 <= addr < 0x200000) ===
    ; cmp eax, 0x12E000 (3D 00 E0 12 00)
    mov byte [r12], 0x3D
    mov dword [r12+1], 0x12E000
    add r12, 5
    ; jb skip_heap_sd (72 XX)
    mov byte [r12], 0x72
    mov byte [r12+1], 0
    lea r8, [r12+1]
    add r12, 2
    ; cmp eax, 0x200000 (3D 00 00 20 00)
    mov byte [r12], 0x3D
    mov dword [r12+1], 0x200000
    add r12, 5
    ; jae skip_heap_sd (73 XX)
    mov byte [r12], 0x73
    mov byte [r12+1], 0
    lea r9, [r12+1]       ; use r9 for second jump patch
    add r12, 2
    ; mov r10, &heap_sd_captured (49 BA <8 bytes>)
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [heap_sd_captured]
    mov [r12+2], rax
    add r12, 10
    ; cmp byte [r10], 0 (41 80 3A 00)
    mov byte [r12], 0x41
    mov byte [r12+1], 0x80
    mov byte [r12+2], 0x3A
    mov byte [r12+3], 0x00
    add r12, 4
    ; jne skip_heap_sd_inner (75 XX)
    mov byte [r12], 0x75
    mov byte [r12+1], 0
    lea rsi, [r12+1]
    add r12, 2
    ; Set captured: mov byte [r10], 1 (41 C6 02 01)
    mov byte [r12], 0x41
    mov byte [r12+1], 0xC6
    mov byte [r12+2], 0x02
    mov byte [r12+3], 0x01
    add r12, 4
    ; Save address: mov r10, &heap_sd_addr / mov [r10], rax
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [heap_sd_addr]
    mov [r12+2], rax
    add r12, 10
    ; Need to get guest addr back - it's in... wait, we just clobbered rax!
    ; The guest addr was in rax before we did lea rax. We need to save it first.
    ; Actually, the runtime code flow has rax = guest addr. The lea is translator code.
    ; At runtime: rax = guest address, rcx = value to store
    ; mov [r10], rax (49 89 02) - save guest addr to heap_sd_addr
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x02
    add r12, 3
    ; Save value: mov r10, &heap_sd_val / mov [r10], rcx
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [heap_sd_val]
    mov [r12+2], rax
    add r12, 10
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x0A
    add r12, 3
    ; Read back: mov r11, [r14+rax] (4D 8B 1C 06) - rax still has guest addr at runtime
    mov byte [r12], 0x4D
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x1C
    mov byte [r12+3], 0x06
    add r12, 4
    ; Save readback: mov r10, &heap_sd_readback / mov [r10], r11
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [heap_sd_readback]
    mov [r12+2], rax
    add r12, 10
    mov byte [r12], 0x4D
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x1A
    add r12, 3
    ; Patch inner jne
    mov rax, r12
    sub rax, rsi
    dec rax
    mov [rsi], al
    ; Patch outer jb (r8) and jae (r9)
    mov rax, r12
    sub rax, r8
    dec rax
    mov [r8], al
    mov rax, r12
    sub rax, r9
    dec rax
    mov [r9], al
    ; .skip_heap_sd:

    ; === SD Corruption detection ===
    ; Read back: mov r11, [r14+rax] (4D 8B 1C 06)
    mov byte [r12], 0x4D
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x1C
    mov byte [r12+3], 0x06
    add r12, 4

    ; Compare: cmp r11, rcx (4C 39 D9)
    mov byte [r12], 0x4C
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xD9
    add r12, 3

    ; je skip (74 XX) - no corruption, skip capture
    mov byte [r12], 0x74
    mov byte [r12+1], 0       ; placeholder for offset
    lea r11, [r12+1]          ; save patch location
    add r12, 2

    ; Check if already captured: mov r10, sd_corrupt_captured
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [sd_corrupt_captured]
    mov [r12+2], rax
    add r12, 10
    ; cmp byte [r10], 0 (41 80 3A 00)
    mov byte [r12], 0x41
    mov byte [r12+1], 0x80
    mov byte [r12+2], 0x3A
    mov byte [r12+3], 0x00
    add r12, 4
    ; jne skip2 (75 XX)
    mov byte [r12], 0x75
    mov byte [r12+1], 0       ; placeholder
    push r11                  ; save first patch
    lea r11, [r12+1]          ; save second patch location
    add r12, 2

    ; Set captured: mov byte [r10], 1 (41 C6 02 01)
    mov byte [r12], 0x41
    mov byte [r12+1], 0xC6
    mov byte [r12+2], 0x02
    mov byte [r12+3], 0x01
    add r12, 4

    ; Save address: mov [sd_corrupt_addr], rax
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [sd_corrupt_addr]
    mov [r12+2], rax
    add r12, 10
    ; Need to restore RAX from somewhere... RAX has guest addr
    ; Actually RAX is still the guest address from earlier
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x02          ; mov [r10], rax
    add r12, 3

    ; Save stored value: mov [sd_corrupt_stored], rcx
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [sd_corrupt_stored]
    mov [r12+2], rax
    add r12, 10
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x0A          ; mov [r10], rcx
    add r12, 3

    ; Reload readback: mov r11, [r14+rax] - rax is still guest addr
    ; First reload rax from the computation above
    ; Actually, we need to preserve rax earlier... this is getting complex
    ; Let's just save the current r11 which was the readback
    ; Wait, r11 was clobbered as patch location. Let me re-read:
    ; mov r10, addr; mov r11, [r14+rax] earlier gave readback in r11
    ; But then we used r11 for patching
    ; We need to reload or save differently
    ; Simpler: just re-read after saving other values
    ; Re-read: need address still in some reg... this is messy

    ; Actually let me simplify: read back again into r11
    ; First restore the address into rax
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [sd_corrupt_addr]
    mov [r12+2], rax
    add r12, 10
    ; mov rax, [r10] (49 8B 02)
    mov byte [r12], 0x49
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x02
    add r12, 3
    ; mov r11, [r14+rax] (4D 8B 1C 06)
    mov byte [r12], 0x4D
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x1C
    mov byte [r12+3], 0x06
    add r12, 4
    ; Save readback: mov [sd_corrupt_readback], r11
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [sd_corrupt_readback]
    mov [r12+2], rax
    add r12, 10
    mov byte [r12], 0x4D
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x1A          ; mov [r10], r11
    add r12, 3

    ; Patch second jne
    mov rax, r12
    sub rax, r11
    dec rax
    mov [r11], al
    pop r11                   ; restore first patch location

    ; .skip2:
    ; Patch first je
    mov rax, r12
    sub rax, r11
    dec rax
    mov [r11], al

    ; .skip:

    jmp .calc_size

;==============================================================================
; JAL - Jump and Link (J-type)
; rd = PC + 4; PC = PC + imm
; "Sometimes you just need to take a leap of faith" - but save where you were
;
; Calling convention: R15 = pointer to rv_pc
;==============================================================================
.jal:
    call extract_j_type         ; ECX = rd, EAX = imm (sign-extended)

    ; First, save the return address (PC + 4) to rd if rd != x0
    test ecx, ecx
    jz .jal_skip_rd

    ; Emit: mov rax, [r15]      ; Load current PC
    mov byte [r12], 0x49
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x07      ; ModRM: [r15]
    add r12, 3

    ; Emit: add rax, 4          ; PC + 4
    mov byte [r12], 0x48
    mov byte [r12+1], 0x83
    mov byte [r12+2], 0xC0
    mov byte [r12+3], 0x04
    add r12, 4

    ; Emit: mov [rbx + rd*8], rax - use helper for proper disp8/disp32
    push rax                    ; Save imm
    call emit_store_rax_to_rd   ; ECX = rd, stores rax to [rbx + rd*8]
    pop rax                     ; Restore imm

.jal_skip_rd:
    ; Now update PC = PC + imm
    ; Emit: mov rcx, [r15]      ; Load current PC
    mov byte [r12], 0x49
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x0F
    add r12, 3

    ; Emit: add rcx, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x81
    mov byte [r12+2], 0xC1
    mov [r12+3], eax
    add r12, 7

    ; Emit: mov [r15], rcx      ; Store new PC
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x0F
    add r12, 3

    jmp .calc_size

;==============================================================================
; JALR - Jump and Link Register (I-type)
; rd = PC + 4; PC = (rs1 + imm) & ~1
;==============================================================================
.jalr:
    call extract_i_type         ; ECX = rd, EBX = rs1, EAX = imm

    push rcx                    ; Save rd
    push rax                    ; Save imm

    ; Save return address (PC + 4) to rd if rd != x0
    test ecx, ecx
    jz .jalr_skip_rd

    ; Emit: mov rax, [r15]
    mov byte [r12], 0x49
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x07
    add r12, 3

    ; Emit: add rax, 4
    mov byte [r12], 0x48
    mov byte [r12+1], 0x83
    mov byte [r12+2], 0xC0
    mov byte [r12+3], 0x04
    add r12, 4

    ; Emit: mov [rbx + rd*8], rax - use helper for proper disp8/disp32
    mov ecx, [rsp+8]            ; Get rd from stack
    call emit_store_rax_to_rd

.jalr_skip_rd:
    ; Compute target: (rs1 + imm) & ~1
    ; Emit: mov rcx, [rbx + rs1*8] - use helper for proper disp8/disp32
    mov ecx, ebx                ; rs1
    call emit_load_reg_to_rcx

    ; Emit: add rcx, imm32
    pop rax                     ; Get imm
    mov byte [r12], 0x48
    mov byte [r12+1], 0x81
    mov byte [r12+2], 0xC1
    mov [r12+3], eax
    add r12, 7

    ; Emit: and rcx, ~1 (clear lowest bit)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x83
    mov byte [r12+2], 0xE1
    mov byte [r12+3], 0xFE      ; -2 = ~1
    add r12, 4

    ; Emit: mov [r15], rcx
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x0F
    add r12, 3

    pop rcx                     ; Clean up stack (rd)
    jmp .calc_size

;==============================================================================
; BRANCH - Conditional branches (B-type)
; if (condition) PC = PC + imm else PC = PC + 4
; "To branch, or not to branch, that is the question"
;==============================================================================
.branch:
    ; Extract funct3 to determine branch type
    mov eax, r13d
    shr eax, 12
    and eax, 0x7
    push rax                    ; Save funct3

    call extract_b_type         ; ECX = rs2, EBX = rs1, EAX = imm

    push rax                    ; Save imm
    push rcx                    ; Save rs2

    ; Emit: mov rax, [rbx + rs1*8] - use emit_load_rs1 for proper disp32 handling
    call emit_load_rs1

    pop rcx                     ; Restore rs2

    ; Emit: mov rcx, [rbx + rs2*8]
    mov eax, ecx
    shl eax, 3
    cmp eax, 127
    jg .branch_rs2_disp32

    ; 8-bit displacement
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B      ; ModRM: rcx, [rbx + disp8]
    mov [r12+3], al
    add r12, 4
    jmp .branch_cmp

.branch_rs2_disp32:
    ; 32-bit displacement
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x8B      ; ModRM: rcx, [rbx + disp32]
    mov [r12+3], eax
    add r12, 7

.branch_cmp:
    ; Emit: cmp rax, rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xC8
    add r12, 3

    ; Now emit conditional jump based on funct3
    ; We'll emit: jCC taken; mov rdx, 4; jmp done; taken: mov rdx, imm; done: ...
    pop rax                     ; imm
    pop rdx                     ; funct3

    ; Emit conditional jump to taken (short jump, 2 bytes)
    ; The "not taken" path is 10 bytes: mov rdx,4 (7) + jmp +3 (2) + nop (1)
    cmp edx, RV_F3_BEQ
    je .emit_beq
    cmp edx, RV_F3_BNE
    je .emit_bne
    cmp edx, RV_F3_BLT
    je .emit_blt
    cmp edx, RV_F3_BGE
    je .emit_bge
    cmp edx, RV_F3_BLTU
    je .emit_bltu
    cmp edx, RV_F3_BGEU
    je .emit_bgeu

    ; Unknown branch - INT3
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

.emit_beq:
    mov byte [r12], 0x74        ; JE rel8
    jmp .branch_common
.emit_bne:
    mov byte [r12], 0x75        ; JNE rel8
    jmp .branch_common
.emit_blt:
    mov byte [r12], 0x7C        ; JL rel8 (signed)
    jmp .branch_common
.emit_bge:
    mov byte [r12], 0x7D        ; JGE rel8 (signed)
    jmp .branch_common
.emit_bltu:
    mov byte [r12], 0x72        ; JB rel8 (unsigned)
    jmp .branch_common
.emit_bgeu:
    mov byte [r12], 0x73        ; JAE rel8 (unsigned)
    jmp .branch_common

.branch_common:
    ; Jcc +10 (skip not-taken path)
    mov byte [r12+1], 10
    add r12, 2

    ; Not taken: mov rdx, 4
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0xC2
    mov dword [r12+3], 4
    add r12, 7

    ; jmp +8 (skip taken path - nop is 1 byte + mov rdx,imm is 7 bytes = 8)
    mov byte [r12], 0xEB
    mov byte [r12+1], 8
    add r12, 2

    ; nop for alignment
    mov byte [r12], 0x90
    add r12, 1

    ; Taken: mov rdx, imm
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0xC2
    mov [r12+3], eax            ; imm
    add r12, 7

    ; Done: update PC
    ; Emit: mov rax, [r15]      ; Current PC
    mov byte [r12], 0x49
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x07
    add r12, 3

    ; Emit: add rax, rdx        ; PC + offset (4 or imm)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xD0
    add r12, 3

    ; Emit: mov [r15], rax      ; Store new PC
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x07
    add r12, 3

    jmp .calc_size

;==============================================================================
; SYSTEM (ECALL, EBREAK, CSR)
;==============================================================================
.system:
    ; Extract funct3
    mov eax, r13d
    shr eax, 12
    and eax, 0x7

    cmp eax, RV_F3_PRIV
    je .system_priv

    ; CSR instructions - dispatch by funct3
    cmp eax, RV_F3_CSRRW
    je .csrrw
    cmp eax, RV_F3_CSRRS
    je .csrrs
    cmp eax, RV_F3_CSRRC
    je .csrrc
    cmp eax, RV_F3_CSRRWI
    je .csrrwi
    cmp eax, RV_F3_CSRRSI
    je .csrrsi
    cmp eax, RV_F3_CSRRCI
    je .csrrci

    ; Unknown SYSTEM instruction
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

.system_priv:
    ; Check immediate field for ECALL vs EBREAK
    mov eax, r13d
    shr eax, 20
    and eax, 0xFFF

    cmp eax, RV_SYS_ECALL
    je .ecall
    cmp eax, RV_SYS_EBREAK
    je .ebreak

    ; Unknown privileged instruction - emit INT3
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

.ecall:
    ; ECALL - System call
    ; The syscall number is in a7 (x17), args in a0-a5 (x10-x15)
    ; We just return to the executor which will handle it
    ; NOTE: PC update is handled by translate_block's .is_ecall, not here
    ; (translate_instruction doesn't have access to the current PC)

    ; Emit code to set ecall_pending = 1 at runtime (for block linking)
    ; Emit: movabs rax, ecall_pending (48 B8 <8 bytes>)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xB8
    lea rax, [ecall_pending]
    mov [r12+2], rax
    add r12, 10

    ; Emit: mov byte [rax], 1 (C6 00 01)
    mov byte [r12], 0xC6
    mov byte [r12+1], 0x00
    mov byte [r12+2], 0x01
    add r12, 3

    ; Emit RET to return from block to executor
    mov byte [r12], 0xC3
    add r12, 1

    ; Return - the executor will check ecall_pending flag
    jmp .calc_size

.ebreak:
    ; EBREAK - Debugger breakpoint
    ; Emit INT3 for debugging
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

;==============================================================================
; CSR Instructions - Proper Implementation
; Supports: cycle, time, instret, misa, mstatus, vendor/arch/imp/hart IDs
; CSR address is in bits [31:20], rd in [11:7], rs1/uimm in [19:15]
;==============================================================================

;------------------------------------------------------------------------------
; CSRRW rd, csr, rs1 - Atomic Read/Write CSR
;------------------------------------------------------------------------------
.csrrw:
    ; Extract CSR address into ECX
    mov ecx, r13d
    shr ecx, 20
    and ecx, 0xFFF

    ; Extract rd into EAX
    mov eax, r13d
    shr eax, 7
    and eax, 0x1F

    ; Save rd for later (on stack)
    push rax

    ; Emit CSR read based on address
    cmp ecx, 0xC00
    je .csrrw_rdtsc
    cmp ecx, 0xC01
    je .csrrw_rdtsc
    cmp ecx, 0x301
    je .csrrw_misa
    ; Default: emit xor eax, eax (return 0)
    mov byte [r12], 0x31
    mov byte [r12+1], 0xC0
    add r12, 2
    jmp .csrrw_emit_store

.csrrw_rdtsc:
    ; Emit: rdtsc; shl rdx, 32; or rax, rdx
    mov byte [r12], 0x0F
    mov byte [r12+1], 0x31
    mov byte [r12+2], 0x48
    mov byte [r12+3], 0xC1
    mov byte [r12+4], 0xE2
    mov byte [r12+5], 0x20
    mov byte [r12+6], 0x48
    mov byte [r12+7], 0x09
    mov byte [r12+8], 0xD0
    add r12, 9
    jmp .csrrw_emit_store

.csrrw_misa:
    ; Emit: movabs rax, 0x8000000000001105
    mov byte [r12], 0x48
    mov byte [r12+1], 0xB8
    mov dword [r12+2], 0x00001105
    mov dword [r12+6], 0x80000000
    add r12, 10
    jmp .csrrw_emit_store

.csrrw_emit_store:
    pop rax
    test eax, eax
    jz .csrrw_done

    ; Emit: mov [rbx + rd*8], rax - use helper for proper disp8/disp32
    mov ecx, eax                ; rd
    call emit_store_rax_to_rd

.csrrw_done:
    jmp .calc_size

;------------------------------------------------------------------------------
; CSRRS rd, csr, rs1 - Atomic Read and Set Bits in CSR
; This is the most commonly used (csrr rd, csr = csrrs rd, csr, x0)
;------------------------------------------------------------------------------
.csrrs:
    ; Extract CSR address into ECX
    mov ecx, r13d
    shr ecx, 20
    and ecx, 0xFFF

    ; Extract rd into EAX
    mov eax, r13d
    shr eax, 7
    and eax, 0x1F

    ; Save rd for later
    push rax

    ; Emit CSR read based on address
    cmp ecx, 0xC00
    je .csrrs_rdtsc
    cmp ecx, 0xC01
    je .csrrs_rdtsc
    cmp ecx, 0x301
    je .csrrs_misa
    ; Default: emit xor eax, eax (return 0)
    mov byte [r12], 0x31
    mov byte [r12+1], 0xC0
    add r12, 2
    jmp .csrrs_emit_store

.csrrs_rdtsc:
    ; Emit: rdtsc; shl rdx, 32; or rax, rdx
    mov byte [r12], 0x0F
    mov byte [r12+1], 0x31
    mov byte [r12+2], 0x48
    mov byte [r12+3], 0xC1
    mov byte [r12+4], 0xE2
    mov byte [r12+5], 0x20
    mov byte [r12+6], 0x48
    mov byte [r12+7], 0x09
    mov byte [r12+8], 0xD0
    add r12, 9
    jmp .csrrs_emit_store

.csrrs_misa:
    ; Emit: movabs rax, 0x8000000000001105
    mov byte [r12], 0x48
    mov byte [r12+1], 0xB8
    mov dword [r12+2], 0x00001105
    mov dword [r12+6], 0x80000000
    add r12, 10
    jmp .csrrs_emit_store

.csrrs_emit_store:
    pop rax
    test eax, eax
    jz .csrrs_done

    ; Emit: mov [rbx + rd*8], rax - use helper for proper disp8/disp32
    mov ecx, eax                ; rd
    call emit_store_rax_to_rd

.csrrs_done:
    jmp .calc_size

;------------------------------------------------------------------------------
; CSRRC rd, csr, rs1 - Atomic Read and Clear Bits in CSR
;------------------------------------------------------------------------------
.csrrc:
    ; Same as CSRRS for read (we don't implement write)
    jmp .csrrs

;------------------------------------------------------------------------------
; CSRRWI rd, csr, uimm - Immediate versions (same read behavior)
;------------------------------------------------------------------------------
.csrrwi:
    jmp .csrrw

.csrrsi:
    jmp .csrrs

.csrrci:
    jmp .csrrs

;==============================================================================
; FENCE - Memory ordering (NOP on x86)
;==============================================================================
.fence:
    ; x86 has strong memory ordering, so FENCE is a NOP
    ; Just emit a NOP for clarity
    mov byte [r12], 0x90
    mov rax, 1
    jmp .done

;==============================================================================
; Floating-Point Load (FLW/FLD)
; Opcode 0x07, width in funct3: 010=FLW, 011=FLD
;==============================================================================
.load_fp:
    mov eax, edi
    shr eax, 7
    and eax, 0x1F
    mov ecx, eax            ; ECX = rd (FP register index)

    mov eax, edi
    shr eax, 15
    and eax, 0x1F
    mov ebx, eax            ; EBX = rs1 (integer register for base address)

    mov eax, edi
    shr eax, 20
    movsx eax, ax           ; Sign-extend to 32 bits
    mov r10d, eax           ; R10D = sign-extended offset

    mov eax, edi
    shr eax, 12
    and eax, 0x7
    cmp eax, 3
    je .load_fp_double

    ; FLW - Load 32-bit float
    test ebx, ebx
    jz .load_fp_single_zero_base

    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    cmp ebx, 16
    jge .load_fp_single_large_rs1

    mov byte [r12+2], 0x43
    shl ebx, 3
    mov byte [r12+3], bl
    add r12, 4
    jmp .load_fp_single_add_offset

.load_fp_single_large_rs1:
    mov byte [r12+2], 0x83
    shl ebx, 3
    mov dword [r12+3], ebx
    add r12, 7
    jmp .load_fp_single_add_offset

.load_fp_single_zero_base:
    mov byte [r12], 0x48
    mov byte [r12+1], 0xB8
    mov dword [r12+2], r10d
    mov dword [r12+6], 0
    add r12, 10
    jmp .load_fp_single_movss

.load_fp_single_add_offset:
    test r10d, r10d
    jz .load_fp_single_movss

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov dword [r12+2], r10d
    add r12, 6

.load_fp_single_movss:
    ; Add guest memory base: add rax, r14
    mov byte [r12], 0x4C
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xF0
    add r12, 3

    ; movss xmm0, [rax] - F3 0F 10 00
    mov byte [r12], 0xF3
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x10
    mov byte [r12+3], 0x00
    add r12, 4

    ; Store to FP reg: movss [r13 + rd*8], xmm0
    mov byte [r12], 0xF3
    mov byte [r12+1], 0x41
    mov byte [r12+2], 0x0F
    mov byte [r12+3], 0x11

    shl ecx, 3
    cmp ecx, 127
    jg .load_fp_single_store_large

    mov byte [r12+4], 0x45
    mov byte [r12+5], cl
    add r12, 6
    jmp .calc_size

.load_fp_single_store_large:
    mov byte [r12+4], 0x85
    mov dword [r12+5], ecx
    add r12, 9
    jmp .calc_size

.load_fp_double:
    test ebx, ebx
    jz .load_fp_double_zero_base

    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    cmp ebx, 16
    jge .load_fp_double_large_rs1

    mov byte [r12+2], 0x43
    shl ebx, 3
    mov byte [r12+3], bl
    add r12, 4
    jmp .load_fp_double_add_offset

.load_fp_double_large_rs1:
    mov byte [r12+2], 0x83
    shl ebx, 3
    mov dword [r12+3], ebx
    add r12, 7
    jmp .load_fp_double_add_offset

.load_fp_double_zero_base:
    mov byte [r12], 0x48
    mov byte [r12+1], 0xB8
    mov dword [r12+2], r10d
    mov dword [r12+6], 0
    add r12, 10
    jmp .load_fp_double_movsd

.load_fp_double_add_offset:
    test r10d, r10d
    jz .load_fp_double_movsd

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov dword [r12+2], r10d
    add r12, 6

.load_fp_double_movsd:
    ; Add guest memory base: add rax, r14
    mov byte [r12], 0x4C
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xF0
    add r12, 3

    ; movsd xmm0, [rax] - F2 0F 10 00
    mov byte [r12], 0xF2
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x10
    mov byte [r12+3], 0x00
    add r12, 4

    ; Store to FP reg: movsd [r13 + rd*8], xmm0
    mov byte [r12], 0xF2
    mov byte [r12+1], 0x41
    mov byte [r12+2], 0x0F
    mov byte [r12+3], 0x11

    shl ecx, 3
    cmp ecx, 127
    jg .load_fp_double_store_large

    mov byte [r12+4], 0x45
    mov byte [r12+5], cl
    add r12, 6
    jmp .calc_size

.load_fp_double_store_large:
    mov byte [r12+4], 0x85
    mov dword [r12+5], ecx
    add r12, 9
    jmp .calc_size

;==============================================================================
; Floating-Point Store (FSW/FSD)
;==============================================================================
.store_fp:
    mov eax, edi
    shr eax, 15
    and eax, 0x1F
    mov ebx, eax

    mov eax, edi
    shr eax, 20
    and eax, 0x1F
    mov ecx, eax

    mov eax, edi
    shr eax, 7
    and eax, 0x1F
    mov r10d, eax

    mov eax, edi
    shr eax, 25
    shl eax, 5
    or r10d, eax

    shl r10d, 20
    sar r10d, 20

    mov eax, edi
    shr eax, 12
    and eax, 0x7
    cmp eax, 3
    je .store_fp_double

    mov byte [r12], 0xF3
    mov byte [r12+1], 0x41
    mov byte [r12+2], 0x0F
    mov byte [r12+3], 0x10

    shl ecx, 3
    cmp ecx, 127
    jg .store_fp_single_load_large

    mov byte [r12+4], 0x45
    mov byte [r12+5], cl
    add r12, 6
    jmp .store_fp_single_calc_addr

.store_fp_single_load_large:
    mov byte [r12+4], 0x85
    mov dword [r12+5], ecx
    add r12, 9

.store_fp_single_calc_addr:
    test ebx, ebx
    jz .store_fp_single_zero_base

    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    cmp ebx, 16
    jge .store_fp_single_large_rs1

    mov byte [r12+2], 0x43
    shl ebx, 3
    mov byte [r12+3], bl
    add r12, 4
    jmp .store_fp_single_add_offset

.store_fp_single_large_rs1:
    mov byte [r12+2], 0x83
    shl ebx, 3
    mov dword [r12+3], ebx
    add r12, 7
    jmp .store_fp_single_add_offset

.store_fp_single_zero_base:
    mov byte [r12], 0x48
    mov byte [r12+1], 0xB8
    mov dword [r12+2], r10d
    mov dword [r12+6], 0
    add r12, 10
    jmp .store_fp_single_movss

.store_fp_single_add_offset:
    test r10d, r10d
    jz .store_fp_single_movss

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov dword [r12+2], r10d
    add r12, 6

.store_fp_single_movss:
    ; Add guest memory base: add rax, r14
    mov byte [r12], 0x4C
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xF0
    add r12, 3

    ; movss [rax], xmm0 - F3 0F 11 00
    mov byte [r12], 0xF3
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x11
    mov byte [r12+3], 0x00
    add r12, 4
    jmp .calc_size

.store_fp_double:
    mov byte [r12], 0xF2
    mov byte [r12+1], 0x41
    mov byte [r12+2], 0x0F
    mov byte [r12+3], 0x10

    shl ecx, 3
    cmp ecx, 127
    jg .store_fp_double_load_large

    mov byte [r12+4], 0x45
    mov byte [r12+5], cl
    add r12, 6
    jmp .store_fp_double_calc_addr

.store_fp_double_load_large:
    mov byte [r12+4], 0x85
    mov dword [r12+5], ecx
    add r12, 9

.store_fp_double_calc_addr:
    test ebx, ebx
    jz .store_fp_double_zero_base

    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    cmp ebx, 16
    jge .store_fp_double_large_rs1

    mov byte [r12+2], 0x43
    shl ebx, 3
    mov byte [r12+3], bl
    add r12, 4
    jmp .store_fp_double_add_offset

.store_fp_double_large_rs1:
    mov byte [r12+2], 0x83
    shl ebx, 3
    mov dword [r12+3], ebx
    add r12, 7
    jmp .store_fp_double_add_offset

.store_fp_double_zero_base:
    mov byte [r12], 0x48
    mov byte [r12+1], 0xB8
    mov dword [r12+2], r10d
    mov dword [r12+6], 0
    add r12, 10
    jmp .store_fp_double_movsd

.store_fp_double_add_offset:
    test r10d, r10d
    jz .store_fp_double_movsd

    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov dword [r12+2], r10d
    add r12, 6

.store_fp_double_movsd:
    ; Add guest memory base: add rax, r14
    mov byte [r12], 0x4C
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xF0
    add r12, 3

    ; movsd [rax], xmm0 - F2 0F 11 00
    mov byte [r12], 0xF2
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x11
    mov byte [r12+3], 0x00
    add r12, 4
    jmp .calc_size

;==============================================================================
; Floating-Point Operations (OP-FP, opcode 0x53)
;==============================================================================
.op_fp:
    mov eax, edi
    shr eax, 7
    and eax, 0x1F
    mov r8d, eax

    mov eax, edi
    shr eax, 15
    and eax, 0x1F
    mov ebx, eax

    mov eax, edi
    shr eax, 20
    and eax, 0x1F
    mov ecx, eax

    mov eax, edi
    shr eax, 25
    and eax, 0x3
    mov r9d, eax

    mov eax, edi
    shr eax, 27

    cmp eax, 0
    je .fp_add
    cmp eax, 1
    je .fp_sub
    cmp eax, 2
    je .fp_mul
    cmp eax, 3
    je .fp_div
    cmp eax, 0x0B
    je .fp_sqrt
    cmp eax, 0x05
    je .fp_minmax
    cmp eax, 0x14
    je .fp_compare
    cmp eax, 0x18
    je .fp_cvt_to_int
    cmp eax, 0x1A
    je .fp_cvt_from_int
    cmp eax, 0x04
    je .fp_sgnj
    cmp eax, 0x08
    je .fp_cvt_s_d          ; FCVT.S.D (narrow double to single)
    cmp eax, 0x09
    je .fp_cvt_d_s          ; FCVT.D.S (widen single to double)
    cmp eax, 0x1C
    je .fp_fmv_x            ; FMV.X.W/FMV.X.D (move FP bits to int)
    cmp eax, 0x1E
    je .fp_fmv_to_fp        ; FMV.W.X/FMV.D.X (move int bits to FP)

    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

.fp_add:
    call .fp_load_rs1_xmm0
    call .fp_load_rs2_xmm1

    test r9d, r9d
    jnz .fp_add_double

    mov byte [r12], 0xF3
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x58
    mov byte [r12+3], 0xC1
    add r12, 4
    jmp .fp_store_xmm0_rd

.fp_add_double:
    mov byte [r12], 0xF2
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x58
    mov byte [r12+3], 0xC1
    add r12, 4
    jmp .fp_store_xmm0_rd

.fp_sub:
    call .fp_load_rs1_xmm0
    call .fp_load_rs2_xmm1

    test r9d, r9d
    jnz .fp_sub_double

    mov byte [r12], 0xF3
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x5C
    mov byte [r12+3], 0xC1
    add r12, 4
    jmp .fp_store_xmm0_rd

.fp_sub_double:
    mov byte [r12], 0xF2
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x5C
    mov byte [r12+3], 0xC1
    add r12, 4
    jmp .fp_store_xmm0_rd

.fp_mul:
    call .fp_load_rs1_xmm0
    call .fp_load_rs2_xmm1

    test r9d, r9d
    jnz .fp_mul_double

    mov byte [r12], 0xF3
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x59
    mov byte [r12+3], 0xC1
    add r12, 4
    jmp .fp_store_xmm0_rd

.fp_mul_double:
    mov byte [r12], 0xF2
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x59
    mov byte [r12+3], 0xC1
    add r12, 4
    jmp .fp_store_xmm0_rd

.fp_div:
    call .fp_load_rs1_xmm0
    call .fp_load_rs2_xmm1

    test r9d, r9d
    jnz .fp_div_double

    mov byte [r12], 0xF3
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x5E
    mov byte [r12+3], 0xC1
    add r12, 4
    jmp .fp_store_xmm0_rd

.fp_div_double:
    mov byte [r12], 0xF2
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x5E
    mov byte [r12+3], 0xC1
    add r12, 4
    jmp .fp_store_xmm0_rd

.fp_sqrt:
    call .fp_load_rs1_xmm0

    test r9d, r9d
    jnz .fp_sqrt_double

    mov byte [r12], 0xF3
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x51
    mov byte [r12+3], 0xC0
    add r12, 4
    jmp .fp_store_xmm0_rd

.fp_sqrt_double:
    mov byte [r12], 0xF2
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x51
    mov byte [r12+3], 0xC0
    add r12, 4
    jmp .fp_store_xmm0_rd

.fp_minmax:
    mov eax, edi
    shr eax, 12
    and eax, 0x7
    push rax

    call .fp_load_rs1_xmm0
    call .fp_load_rs2_xmm1

    pop rax
    test eax, eax
    jnz .fp_max

    test r9d, r9d
    jnz .fp_min_double

    mov byte [r12], 0xF3
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x5D
    mov byte [r12+3], 0xC1
    add r12, 4
    jmp .fp_store_xmm0_rd

.fp_min_double:
    mov byte [r12], 0xF2
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x5D
    mov byte [r12+3], 0xC1
    add r12, 4
    jmp .fp_store_xmm0_rd

.fp_max:
    test r9d, r9d
    jnz .fp_max_double

    mov byte [r12], 0xF3
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x5F
    mov byte [r12+3], 0xC1
    add r12, 4
    jmp .fp_store_xmm0_rd

.fp_max_double:
    mov byte [r12], 0xF2
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x5F
    mov byte [r12+3], 0xC1
    add r12, 4
    jmp .fp_store_xmm0_rd

.fp_compare:
    call .fp_load_rs1_xmm0
    call .fp_load_rs2_xmm1

    test r9d, r9d
    jnz .fp_compare_double

    mov byte [r12], 0x0F
    mov byte [r12+1], 0x2E
    mov byte [r12+2], 0xC1
    add r12, 3
    jmp .fp_compare_setcc

.fp_compare_double:
    mov byte [r12], 0x66
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x2E
    mov byte [r12+3], 0xC1
    add r12, 4

.fp_compare_setcc:
    mov byte [r12], 0x31
    mov byte [r12+1], 0xC0
    add r12, 2

    mov byte [r12], 0x0F
    mov byte [r12+1], 0x93
    mov byte [r12+2], 0xC0
    add r12, 3

    mov byte [r12], 0x0F
    mov byte [r12+1], 0xB6
    mov byte [r12+2], 0xC0
    add r12, 3

    jmp .fp_store_rax_to_int_rd

.fp_cvt_to_int:
    ; rs2 (in ecx) determines integer type:
    ; 0 = W (32-bit signed), 1 = WU (32-bit unsigned)
    ; 2 = L (64-bit signed), 3 = LU (64-bit unsigned)
    call .fp_load_rs1_xmm0

    ; Check if 64-bit (rs2 bit 1 set)
    test ecx, 2
    jnz .fp_cvt_to_int_64

    ; 32-bit conversion (W or WU)
    ; cvttss2si/cvttsd2si eax, xmm0
    test r9d, r9d
    jnz .fp_cvt_w_double
    mov byte [r12], 0xF3          ; cvttss2si eax, xmm0
    jmp .fp_cvt_w_common
.fp_cvt_w_double:
    mov byte [r12], 0xF2          ; cvttsd2si eax, xmm0
.fp_cvt_w_common:
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x2C
    mov byte [r12+3], 0xC0
    add r12, 4
    ; For WU (unsigned), need to zero-extend; for W (signed), sign-extend
    test ecx, 1
    jnz .fp_cvt_wu_extend
    ; W: sign-extend eax to rax: movsxd rax, eax = 48 63 C0
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3
    jmp .fp_store_rax_to_int_rd
.fp_cvt_wu_extend:
    ; WU: zero-extend eax to rax: mov eax, eax (implicit zero-extend in 64-bit mode)
    ; Actually, just use the 32-bit result in eax, already zero-extended
    jmp .fp_store_rax_to_int_rd

.fp_cvt_to_int_64:
    ; 64-bit conversion (L or LU)
    ; cvttss2si/cvttsd2si rax, xmm0 (with REX.W)
    test r9d, r9d
    jnz .fp_cvt_l_double
    mov byte [r12], 0xF3          ; cvttss2si rax, xmm0
    jmp .fp_cvt_l_common
.fp_cvt_l_double:
    mov byte [r12], 0xF2          ; cvttsd2si rax, xmm0
.fp_cvt_l_common:
    mov byte [r12+1], 0x48        ; REX.W for 64-bit
    mov byte [r12+2], 0x0F
    mov byte [r12+3], 0x2C
    mov byte [r12+4], 0xC0
    add r12, 5
    ; For LU (unsigned) with negative float, x86 returns 0x8000000000000000
    ; which is the RISC-V defined behavior for out-of-range
    jmp .fp_store_rax_to_int_rd

.fp_cvt_from_int:
    ; rs2 (in ecx) determines source integer type:
    ; 0 = W (32-bit signed), 1 = WU (32-bit unsigned)
    ; 2 = L (64-bit signed), 3 = LU (64-bit unsigned)
    call .fp_load_int_rs1_rax

    ; Check if 64-bit source (rs2 bit 1 set)
    test ecx, 2
    jnz .fp_cvt_from_int_64

    ; 32-bit source (W or WU)
    test ecx, 1
    jnz .fp_cvt_from_wu
    ; W: sign-extend eax to rax first (already done by load_int_rs1)
    jmp .fp_cvt_from_32_emit
.fp_cvt_from_wu:
    ; WU: zero-extend eax to rax: mov eax, eax
    mov byte [r12], 0x89
    mov byte [r12+1], 0xC0        ; mov eax, eax (clears upper 32 bits)
    add r12, 2
.fp_cvt_from_32_emit:
    ; cvtsi2ss/cvtsi2sd xmm0, eax (32-bit)
    test r9d, r9d
    jnz .fp_cvt_from_w_double
    mov byte [r12], 0xF3          ; cvtsi2ss xmm0, eax
    jmp .fp_cvt_from_w_common
.fp_cvt_from_w_double:
    mov byte [r12], 0xF2          ; cvtsi2sd xmm0, eax
.fp_cvt_from_w_common:
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x2A
    mov byte [r12+3], 0xC0
    add r12, 4
    jmp .fp_store_xmm0_rd

.fp_cvt_from_int_64:
    ; 64-bit source (L or LU)
    ; cvtsi2ss/cvtsi2sd xmm0, rax (with REX.W)
    test r9d, r9d
    jnz .fp_cvt_from_l_double
    mov byte [r12], 0xF3          ; cvtsi2ss xmm0, rax
    jmp .fp_cvt_from_l_common
.fp_cvt_from_l_double:
    mov byte [r12], 0xF2          ; cvtsi2sd xmm0, rax
.fp_cvt_from_l_common:
    mov byte [r12+1], 0x48        ; REX.W for 64-bit
    mov byte [r12+2], 0x0F
    mov byte [r12+3], 0x2A
    mov byte [r12+4], 0xC0
    add r12, 5
    jmp .fp_store_xmm0_rd

;------------------------------------------------------------------------------
; FSGNJ/FSGNJN/FSGNJX - Sign injection
; funct3 = 0: FSGNJ (copy sign from rs2)
; funct3 = 1: FSGNJN (copy negated sign from rs2)
; funct3 = 2: FSGNJX (xor signs)
;------------------------------------------------------------------------------
.fp_sgnj:
    ; Get funct3 from bits 12-14
    mov eax, edi
    shr eax, 12
    and eax, 0x7
    push rax                    ; Save funct3

    ; Load both operands
    call .fp_load_rs1_xmm0
    call .fp_load_rs2_xmm1

    pop rax                     ; Restore funct3

    ; For FSGNJ with rs1==rs2, this is FMV (just store rs1)
    ; For simplicity, implement proper sign manipulation
    test eax, eax
    jz .fp_sgnj_copy
    cmp eax, 1
    je .fp_sgnj_neg
    ; funct3 = 2: FSGNJX (xor)
    jmp .fp_sgnj_xor

.fp_sgnj_copy:
    ; FSGNJ: rd = |rs1| with sign of rs2
    ; For now, just copy if rs1==rs2 (FMV.S/FMV.D pseudo)
    ; Full impl would extract sign bit
    jmp .fp_store_xmm0_rd

.fp_sgnj_neg:
    ; FSGNJN: rd = |rs1| with negated sign of rs2
    ; Common use: FNEG when rs1==rs2
    test r9d, r9d
    jnz .fp_sgnj_neg_double

    ; Single: xorps xmm0, [sign_mask] - flip sign bit
    ; Emit: mov eax, 0x80000000; movd xmm1, eax; xorps xmm0, xmm1
    mov byte [r12], 0xB8          ; mov eax, imm32
    mov dword [r12+1], 0x80000000
    mov byte [r12+5], 0x66        ; movd xmm1, eax
    mov byte [r12+6], 0x0F
    mov byte [r12+7], 0x6E
    mov byte [r12+8], 0xC8
    mov byte [r12+9], 0x0F        ; xorps xmm0, xmm1
    mov byte [r12+10], 0x57
    mov byte [r12+11], 0xC1
    add r12, 12
    jmp .fp_store_xmm0_rd

.fp_sgnj_neg_double:
    ; Double: flip sign bit (bit 63)
    ; mov rax, 0x8000000000000000; movq xmm1, rax; xorpd xmm0, xmm1
    mov byte [r12], 0x48          ; mov rax, imm64
    mov byte [r12+1], 0xB8
    mov dword [r12+2], 0
    mov dword [r12+6], 0x80000000
    mov byte [r12+10], 0x66       ; movq xmm1, rax
    mov byte [r12+11], 0x48
    mov byte [r12+12], 0x0F
    mov byte [r12+13], 0x6E
    mov byte [r12+14], 0xC8
    mov byte [r12+15], 0x66       ; xorpd xmm0, xmm1
    mov byte [r12+16], 0x0F
    mov byte [r12+17], 0x57
    mov byte [r12+18], 0xC1
    add r12, 19
    jmp .fp_store_xmm0_rd

.fp_sgnj_xor:
    ; FSGNJX: xor signs - common for FABS when rs1==rs2
    ; Just pass through for now (xor same sign = positive)
    jmp .fp_store_xmm0_rd

;------------------------------------------------------------------------------
; FCVT.S.D - Convert double to single precision
;------------------------------------------------------------------------------
.fp_cvt_s_d:
    call .fp_load_rs1_xmm0

    ; cvtsd2ss xmm0, xmm0 = F2 0F 5A C0
    mov byte [r12], 0xF2
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x5A
    mov byte [r12+3], 0xC0
    add r12, 4

    ; Store as single (force r9=0 for single store)
    push r9
    xor r9d, r9d
    call .fp_store_xmm0_rd_internal
    pop r9
    jmp .calc_size

;------------------------------------------------------------------------------
; FCVT.D.S - Convert single to double precision
;------------------------------------------------------------------------------
.fp_cvt_d_s:
    ; Load as single (force r9=0)
    push r9
    xor r9d, r9d
    call .fp_load_rs1_xmm0
    pop r9

    ; cvtss2sd xmm0, xmm0 = F3 0F 5A C0
    mov byte [r12], 0xF3
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x5A
    mov byte [r12+3], 0xC0
    add r12, 4

    ; Store as double (force r9=1)
    push r9
    mov r9d, 1
    call .fp_store_xmm0_rd_internal
    pop r9
    jmp .calc_size

;------------------------------------------------------------------------------
; FMV.X.W / FMV.X.D - Move FP bits to integer register
; funct7 = 0x1C, rs2 = 0
;------------------------------------------------------------------------------
.fp_fmv_x:
    ; Load FP reg into xmm0
    call .fp_load_rs1_xmm0

    ; Move to integer register
    test r9d, r9d
    jnz .fp_fmv_x_double

    ; FMV.X.W: movd eax, xmm0 = 66 0F 7E C0
    ; Then sign-extend to 64-bit
    mov byte [r12], 0x66
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x7E
    mov byte [r12+3], 0xC0
    add r12, 4
    ; movsxd rax, eax = 48 63 C0
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3
    jmp .fp_store_rax_to_int_rd

.fp_fmv_x_double:
    ; FMV.X.D: movq rax, xmm0 = 66 48 0F 7E C0
    mov byte [r12], 0x66
    mov byte [r12+1], 0x48
    mov byte [r12+2], 0x0F
    mov byte [r12+3], 0x7E
    mov byte [r12+4], 0xC0
    add r12, 5
    jmp .fp_store_rax_to_int_rd

;------------------------------------------------------------------------------
; FMV.W.X / FMV.D.X - Move integer bits to FP register
; funct7 = 0x1E, rs2 = 0
;------------------------------------------------------------------------------
.fp_fmv_to_fp:
    ; Load integer reg into rax
    call .fp_load_int_rs1_rax

    test r9d, r9d
    jnz .fp_fmv_to_fp_double

    ; FMV.W.X: movd xmm0, eax = 66 0F 6E C0
    mov byte [r12], 0x66
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x6E
    mov byte [r12+3], 0xC0
    add r12, 4
    jmp .fp_store_xmm0_rd

.fp_fmv_to_fp_double:
    ; FMV.D.X: movq xmm0, rax = 66 48 0F 6E C0
    mov byte [r12], 0x66
    mov byte [r12+1], 0x48
    mov byte [r12+2], 0x0F
    mov byte [r12+3], 0x6E
    mov byte [r12+4], 0xC0
    add r12, 5
    jmp .fp_store_xmm0_rd

;------------------------------------------------------------------------------
; FP Helpers
;------------------------------------------------------------------------------
.fp_load_rs1_xmm0:
    push rbx
    shl ebx, 3

    test r9d, r9d
    jnz .fp_load_rs1_double

    mov byte [r12], 0xF3
    mov byte [r12+1], 0x41
    mov byte [r12+2], 0x0F
    mov byte [r12+3], 0x10
    jmp .fp_load_rs1_disp

.fp_load_rs1_double:
    mov byte [r12], 0xF2
    mov byte [r12+1], 0x41
    mov byte [r12+2], 0x0F
    mov byte [r12+3], 0x10

.fp_load_rs1_disp:
    cmp ebx, 127
    jg .fp_load_rs1_large

    mov byte [r12+4], 0x45
    mov byte [r12+5], bl
    add r12, 6
    pop rbx
    ret

.fp_load_rs1_large:
    mov byte [r12+4], 0x85
    mov dword [r12+5], ebx
    add r12, 9
    pop rbx
    ret

.fp_load_rs2_xmm1:
    push rcx
    shl ecx, 3

    test r9d, r9d
    jnz .fp_load_rs2_double

    mov byte [r12], 0xF3
    mov byte [r12+1], 0x41
    mov byte [r12+2], 0x0F
    mov byte [r12+3], 0x10
    jmp .fp_load_rs2_disp

.fp_load_rs2_double:
    mov byte [r12], 0xF2
    mov byte [r12+1], 0x41
    mov byte [r12+2], 0x0F
    mov byte [r12+3], 0x10

.fp_load_rs2_disp:
    cmp ecx, 127
    jg .fp_load_rs2_large

    mov byte [r12+4], 0x4D
    mov byte [r12+5], cl
    add r12, 6
    pop rcx
    ret

.fp_load_rs2_large:
    mov byte [r12+4], 0x8D
    mov dword [r12+5], ecx
    add r12, 9
    pop rcx
    ret

.fp_store_xmm0_rd:
    push r8
    shl r8d, 3

    test r9d, r9d
    jnz .fp_store_double

    mov byte [r12], 0xF3
    mov byte [r12+1], 0x41
    mov byte [r12+2], 0x0F
    mov byte [r12+3], 0x11
    jmp .fp_store_disp

.fp_store_double:
    mov byte [r12], 0xF2
    mov byte [r12+1], 0x41
    mov byte [r12+2], 0x0F
    mov byte [r12+3], 0x11

.fp_store_disp:
    cmp r8d, 127
    jg .fp_store_large

    mov byte [r12+4], 0x45
    mov byte [r12+5], r8b
    add r12, 6
    pop r8
    jmp .calc_size

.fp_store_large:
    mov byte [r12+4], 0x85
    mov dword [r12+5], r8d
    add r12, 9
    pop r8
    jmp .calc_size

; Internal version that returns instead of jumping to calc_size
.fp_store_xmm0_rd_internal:
    push r8
    shl r8d, 3

    test r9d, r9d
    jnz .fp_store_double_int

    mov byte [r12], 0xF3
    mov byte [r12+1], 0x41
    mov byte [r12+2], 0x0F
    mov byte [r12+3], 0x11
    jmp .fp_store_disp_int

.fp_store_double_int:
    mov byte [r12], 0xF2
    mov byte [r12+1], 0x41
    mov byte [r12+2], 0x0F
    mov byte [r12+3], 0x11

.fp_store_disp_int:
    cmp r8d, 127
    jg .fp_store_large_int

    mov byte [r12+4], 0x45
    mov byte [r12+5], r8b
    add r12, 6
    pop r8
    ret

.fp_store_large_int:
    mov byte [r12+4], 0x85
    mov dword [r12+5], r8d
    add r12, 9
    pop r8
    ret

.fp_store_rax_to_int_rd:
    test r8d, r8d
    jz .fp_store_int_done

    push r8
    shl r8d, 3

    mov byte [r12], 0x48
    mov byte [r12+1], 0x89

    cmp r8d, 127
    jg .fp_store_int_large

    mov byte [r12+2], 0x43
    mov byte [r12+3], r8b
    add r12, 4
    pop r8
    jmp .calc_size

.fp_store_int_large:
    mov byte [r12+2], 0x83
    mov dword [r12+3], r8d
    add r12, 7
    pop r8
    jmp .calc_size

.fp_store_int_done:
    jmp .calc_size

.fp_load_int_rs1_rax:
    push rbx
    test ebx, ebx
    jz .fp_load_int_zero

    shl ebx, 3

    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B

    cmp ebx, 127
    jg .fp_load_int_large

    mov byte [r12+2], 0x43
    mov byte [r12+3], bl
    add r12, 4
    pop rbx
    ret

.fp_load_int_large:
    mov byte [r12+2], 0x83
    mov dword [r12+3], ebx
    add r12, 7
    pop rbx
    ret

.fp_load_int_zero:
    mov byte [r12], 0x31
    mov byte [r12+1], 0xC0
    add r12, 2
    pop rbx
    ret

;==============================================================================
; Fused Multiply-Add (stubs using mul+add)
;==============================================================================
.fmadd:
.fmsub:
.fnmsub:
.fnmadd:
    ; FMA not fully implemented - emit INT3
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

;==============================================================================
; AMO - Atomic Memory Operations (A extension)
; R-type format: rd = bits 11:7, rs1 = bits 19:15, rs2 = bits 24:20
; funct5 = bits 31:27, width = bits 14:12 (2=W, 3=D)
;
; Runtime registers: rbx = rv_regs, r14 = guest_memory_base
; We use rcx for address, rax for operand/result, rdx as scratch
;==============================================================================
.amo:
    ; Extract funct5 (operation type)
    mov eax, edi
    shr eax, 27
    and eax, 0x1F
    mov r10d, eax           ; r10 = funct5

    ; Extract width (2=W, 3=D)
    mov eax, edi
    shr eax, 12
    and eax, 7
    mov r11d, eax           ; r11 = width (2 or 3)

    cmp r10d, AMO_LR
    je .amo_lr
    cmp r10d, AMO_SC
    je .amo_sc
    cmp r10d, AMO_SWAP
    je .amo_swap
    cmp r10d, AMO_ADD
    je .amo_add
    cmp r10d, AMO_XOR
    je .amo_xor
    cmp r10d, AMO_AND
    je .amo_and
    cmp r10d, AMO_OR
    je .amo_or
    cmp r10d, AMO_MIN
    je .amo_min
    cmp r10d, AMO_MAX
    je .amo_max
    cmp r10d, AMO_MINU
    je .amo_minu
    cmp r10d, AMO_MAXU
    je .amo_maxu

    ; Unknown AMO operation
    mov byte [r12], 0xCC
    mov rax, 1
    jmp .done

;------------------------------------------------------------------------------
; LR.W/LR.D - Load Reserved
; rd = [rs1], set reservation (for single-threaded, just load)
;------------------------------------------------------------------------------
.amo_lr:
    call extract_r_type     ; ECX=rd, EBX=rs1, EAX=rs2 (unused)
    push rcx                ; save rd
    push r11                ; save width

    ; Emit: mov rax, [rbx + rs1*8]  (load address from rs1)
    call emit_load_rs1

    ; Emit: add rax, r14  (convert to host address)
    ; 4C 01 F0 = add rax, r14
    mov byte [r12], 0x4C
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xF0
    add r12, 3

    pop r11                 ; restore width
    pop rcx                 ; restore rd

    cmp r11d, 3
    je .amo_lr_d

    ; LR.W: mov eax, [rax] then sign-extend
    ; 8B 00 = mov eax, [rax]
    mov byte [r12], 0x8B
    mov byte [r12+1], 0x00
    add r12, 2
    ; 48 63 C0 = movsxd rax, eax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3
    jmp .amo_lr_store

.amo_lr_d:
    ; LR.D: mov rax, [rax]
    ; 48 8B 00 = mov rax, [rax]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x00
    add r12, 3

.amo_lr_store:
    test ecx, ecx
    jz .amo_lr_done
    call emit_store_rd
.amo_lr_done:
    jmp .calc_size

;------------------------------------------------------------------------------
; SC.W/SC.D - Store Conditional
; [rs1] = rs2, rd = 0 (success) - always succeeds in single-threaded
;------------------------------------------------------------------------------
.amo_sc:
    call extract_r_type     ; ECX=rd, EBX=rs1, EAX=rs2
    push rcx                ; save rd
    push r11                ; save width
    mov r10d, eax           ; save rs2 reg number

    ; Emit: mov rcx, [rbx + rs1*8]  (load address from rs1)
    ; Using emit_load_rs1 which loads into rax, then move to rcx
    call emit_load_rs1

    ; Emit: add rax, r14  (convert to host address)
    mov byte [r12], 0x4C
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xF0
    add r12, 3

    ; Emit: mov rcx, rax  (save host address in rcx)
    ; 48 89 C1 = mov rcx, rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xC1
    add r12, 3

    ; Emit: mov rax, [rbx + rs2*8]  (load value from rs2)
    mov ebx, r10d           ; rs2 reg number
    call emit_load_rs1      ; reusing for rs2

    pop r11                 ; restore width

    cmp r11d, 3
    je .amo_sc_d

    ; SC.W: mov [rcx], eax
    ; 89 01 = mov [rcx], eax
    mov byte [r12], 0x89
    mov byte [r12+1], 0x01
    add r12, 2
    jmp .amo_sc_result

.amo_sc_d:
    ; SC.D: mov [rcx], rax
    ; 48 89 01 = mov [rcx], rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x01
    add r12, 3

.amo_sc_result:
    pop rcx                 ; restore rd
    test ecx, ecx
    jz .amo_sc_done

    ; rd = 0 (success)
    ; 31 C0 = xor eax, eax
    mov byte [r12], 0x31
    mov byte [r12+1], 0xC0
    add r12, 2
    call emit_store_rd

.amo_sc_done:
    jmp .calc_size

;------------------------------------------------------------------------------
; AMOSWAP.W/D - Atomic Swap: rd = [rs1], [rs1] = rs2
;------------------------------------------------------------------------------
.amo_swap:
    call extract_r_type     ; ECX=rd, EBX=rs1, EAX=rs2
    push rcx                ; save rd
    push r11                ; save width
    mov r10d, eax           ; save rs2 reg number

    ; Load address from rs1
    call emit_load_rs1

    ; Add guest memory base: add rax, r14
    mov byte [r12], 0x4C
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xF0
    add r12, 3

    ; Save host address in rcx: mov rcx, rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xC1
    add r12, 3

    ; Load rs2 value into rax
    mov ebx, r10d
    call emit_load_rs1

    pop r11                 ; restore width

    cmp r11d, 3
    je .amo_swap_d

    ; AMOSWAP.W: xchg [rcx], eax then sign-extend
    ; 87 01 = xchg [rcx], eax
    mov byte [r12], 0x87
    mov byte [r12+1], 0x01
    add r12, 2
    ; Sign-extend: movsxd rax, eax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3
    jmp .amo_swap_store

.amo_swap_d:
    ; AMOSWAP.D: xchg [rcx], rax
    ; 48 87 01 = xchg [rcx], rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x87
    mov byte [r12+2], 0x01
    add r12, 3

.amo_swap_store:
    pop rcx                 ; restore rd
    test ecx, ecx
    jz .amo_swap_done
    call emit_store_rd
.amo_swap_done:
    jmp .calc_size

;------------------------------------------------------------------------------
; AMOADD.W/D - Atomic Add: rd = old [rs1], [rs1] = old + rs2
; Uses LOCK XADD which atomically adds and returns old value
;------------------------------------------------------------------------------
.amo_add:
    call extract_r_type     ; ECX=rd, EBX=rs1, EAX=rs2
    push rcx                ; save rd
    push r11                ; save width
    mov r10d, eax           ; save rs2 reg number

    ; Load address from rs1
    call emit_load_rs1

    ; Add guest memory base: add rax, r14
    mov byte [r12], 0x4C
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xF0
    add r12, 3

    ; Save host address in rcx: mov rcx, rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xC1
    add r12, 3

    ; Load rs2 value into rax
    mov ebx, r10d
    call emit_load_rs1

    pop r11                 ; restore width

    cmp r11d, 3
    je .amo_add_d

    ; AMOADD.W: lock xadd [rcx], eax then sign-extend
    ; F0 0F C1 01 = lock xadd [rcx], eax
    mov byte [r12], 0xF0
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0xC1
    mov byte [r12+3], 0x01
    add r12, 4
    ; Sign-extend: movsxd rax, eax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3
    jmp .amo_add_store

.amo_add_d:
    ; AMOADD.D: lock xadd [rcx], rax
    ; F0 48 0F C1 01 = lock xadd [rcx], rax
    mov byte [r12], 0xF0
    mov byte [r12+1], 0x48
    mov byte [r12+2], 0x0F
    mov byte [r12+3], 0xC1
    mov byte [r12+4], 0x01
    add r12, 5

.amo_add_store:
    pop rcx                 ; restore rd
    test ecx, ecx
    jz .amo_add_done
    call emit_store_rd
.amo_add_done:
    jmp .calc_size

;------------------------------------------------------------------------------
; AMOXOR.W/D - Atomic XOR: rd = old [rs1], [rs1] = old XOR rs2
; Pattern: load old, compute new, store new (single-threaded safe)
;------------------------------------------------------------------------------
.amo_xor:
    call extract_r_type     ; ECX=rd, EBX=rs1, EAX=rs2
    push rcx                ; save rd
    push r11                ; save width
    mov r10d, eax           ; save rs2 reg number

    ; Load address from rs1 -> rcx (host address)
    call emit_load_rs1
    mov byte [r12], 0x4C    ; add rax, r14
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xF0
    add r12, 3
    mov byte [r12], 0x48    ; mov rcx, rax
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xC1
    add r12, 3

    ; Load rs2 value into rdx
    mov ebx, r10d
    call emit_load_rs1
    mov byte [r12], 0x48    ; mov rdx, rax
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xC2
    add r12, 3

    pop r11                 ; restore width

    cmp r11d, 3
    je .amo_xor_d

    ; AMOXOR.W: load dword, xor, store dword, sign-extend result
    ; mov eax, [rcx] = 8B 01
    mov byte [r12], 0x8B
    mov byte [r12+1], 0x01
    add r12, 2
    ; push rax (save old value)
    mov byte [r12], 0x50
    add r12, 1
    ; xor eax, edx = 31 D0
    mov byte [r12], 0x31
    mov byte [r12+1], 0xD0
    add r12, 2
    ; mov [rcx], eax = 89 01
    mov byte [r12], 0x89
    mov byte [r12+1], 0x01
    add r12, 2
    ; pop rax (restore old value)
    mov byte [r12], 0x58
    add r12, 1
    ; movsxd rax, eax = 48 63 C0
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3
    jmp .amo_xor_store

.amo_xor_d:
    ; AMOXOR.D: load qword, xor, store qword
    ; mov rax, [rcx] = 48 8B 01
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x01
    add r12, 3
    ; push rax
    mov byte [r12], 0x50
    add r12, 1
    ; xor rax, rdx = 48 31 D0
    mov byte [r12], 0x48
    mov byte [r12+1], 0x31
    mov byte [r12+2], 0xD0
    add r12, 3
    ; mov [rcx], rax = 48 89 01
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x01
    add r12, 3
    ; pop rax
    mov byte [r12], 0x58
    add r12, 1

.amo_xor_store:
    pop rcx                 ; restore rd
    test ecx, ecx
    jz .amo_xor_done
    call emit_store_rd
.amo_xor_done:
    jmp .calc_size

;------------------------------------------------------------------------------
; AMOAND.W/D - Atomic AND: rd = old [rs1], [rs1] = old AND rs2
;------------------------------------------------------------------------------
.amo_and:
    call extract_r_type
    push rcx
    push r11
    mov r10d, eax

    call emit_load_rs1
    mov byte [r12], 0x4C
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xF0
    add r12, 3
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xC1
    add r12, 3

    mov ebx, r10d
    call emit_load_rs1
    mov byte [r12], 0x48    ; mov rdx, rax
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xC2
    add r12, 3

    pop r11
    cmp r11d, 3
    je .amo_and_d

    ; AMOAND.W
    mov byte [r12], 0x8B    ; mov eax, [rcx]
    mov byte [r12+1], 0x01
    add r12, 2
    mov byte [r12], 0x50    ; push rax
    add r12, 1
    mov byte [r12], 0x21    ; and eax, edx
    mov byte [r12+1], 0xD0
    add r12, 2
    mov byte [r12], 0x89    ; mov [rcx], eax
    mov byte [r12+1], 0x01
    add r12, 2
    mov byte [r12], 0x58    ; pop rax
    add r12, 1
    mov byte [r12], 0x48    ; movsxd rax, eax
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3
    jmp .amo_and_store

.amo_and_d:
    mov byte [r12], 0x48    ; mov rax, [rcx]
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x01
    add r12, 3
    mov byte [r12], 0x50    ; push rax
    add r12, 1
    mov byte [r12], 0x48    ; and rax, rdx
    mov byte [r12+1], 0x21
    mov byte [r12+2], 0xD0
    add r12, 3
    mov byte [r12], 0x48    ; mov [rcx], rax
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x01
    add r12, 3
    mov byte [r12], 0x58    ; pop rax
    add r12, 1

.amo_and_store:
    pop rcx
    test ecx, ecx
    jz .amo_and_done
    call emit_store_rd
.amo_and_done:
    jmp .calc_size

;------------------------------------------------------------------------------
; AMOOR.W/D - Atomic OR: rd = old [rs1], [rs1] = old OR rs2
;------------------------------------------------------------------------------
.amo_or:
    call extract_r_type
    push rcx
    push r11
    mov r10d, eax

    call emit_load_rs1
    mov byte [r12], 0x4C
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xF0
    add r12, 3
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xC1
    add r12, 3

    mov ebx, r10d
    call emit_load_rs1
    mov byte [r12], 0x48    ; mov rdx, rax
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xC2
    add r12, 3

    pop r11
    cmp r11d, 3
    je .amo_or_d

    ; AMOOR.W
    mov byte [r12], 0x8B    ; mov eax, [rcx]
    mov byte [r12+1], 0x01
    add r12, 2
    mov byte [r12], 0x50    ; push rax
    add r12, 1
    mov byte [r12], 0x09    ; or eax, edx
    mov byte [r12+1], 0xD0
    add r12, 2
    mov byte [r12], 0x89    ; mov [rcx], eax
    mov byte [r12+1], 0x01
    add r12, 2
    mov byte [r12], 0x58    ; pop rax
    add r12, 1
    mov byte [r12], 0x48    ; movsxd rax, eax
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3
    jmp .amo_or_store

.amo_or_d:
    mov byte [r12], 0x48    ; mov rax, [rcx]
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x01
    add r12, 3
    mov byte [r12], 0x50    ; push rax
    add r12, 1
    mov byte [r12], 0x48    ; or rax, rdx
    mov byte [r12+1], 0x09
    mov byte [r12+2], 0xD0
    add r12, 3
    mov byte [r12], 0x48    ; mov [rcx], rax
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x01
    add r12, 3
    mov byte [r12], 0x58    ; pop rax
    add r12, 1

.amo_or_store:
    pop rcx
    test ecx, ecx
    jz .amo_or_done
    call emit_store_rd
.amo_or_done:
    jmp .calc_size

;------------------------------------------------------------------------------
; AMOMIN.W/D - Atomic MIN (signed): rd = old, [rs1] = min(old, rs2)
;------------------------------------------------------------------------------
.amo_min:
    call extract_r_type
    push rcx
    push r11
    mov r10d, eax

    call emit_load_rs1
    mov byte [r12], 0x4C
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xF0
    add r12, 3
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xC1
    add r12, 3

    mov ebx, r10d
    call emit_load_rs1
    mov byte [r12], 0x48    ; mov rdx, rax (rdx = rs2)
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xC2
    add r12, 3

    pop r11
    cmp r11d, 3
    je .amo_min_d

    ; AMOMIN.W: load, compare, store min
    mov byte [r12], 0x8B    ; mov eax, [rcx]
    mov byte [r12+1], 0x01
    add r12, 2
    mov byte [r12], 0x50    ; push rax (save old)
    add r12, 1
    mov byte [r12], 0x39    ; cmp eax, edx
    mov byte [r12+1], 0xD0
    add r12, 2
    mov byte [r12], 0x0F    ; cmovg eax, edx (if old > rs2, use rs2)
    mov byte [r12+1], 0x4F
    mov byte [r12+2], 0xC2
    add r12, 3
    mov byte [r12], 0x89    ; mov [rcx], eax
    mov byte [r12+1], 0x01
    add r12, 2
    mov byte [r12], 0x58    ; pop rax
    add r12, 1
    mov byte [r12], 0x48    ; movsxd rax, eax
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3
    jmp .amo_min_store

.amo_min_d:
    mov byte [r12], 0x48    ; mov rax, [rcx]
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x01
    add r12, 3
    mov byte [r12], 0x50    ; push rax
    add r12, 1
    mov byte [r12], 0x48    ; cmp rax, rdx
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xD0
    add r12, 3
    mov byte [r12], 0x48    ; cmovg rax, rdx
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x4F
    mov byte [r12+3], 0xC2
    add r12, 4
    mov byte [r12], 0x48    ; mov [rcx], rax
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x01
    add r12, 3
    mov byte [r12], 0x58    ; pop rax
    add r12, 1

.amo_min_store:
    pop rcx
    test ecx, ecx
    jz .amo_min_done
    call emit_store_rd
.amo_min_done:
    jmp .calc_size

;------------------------------------------------------------------------------
; AMOMAX.W/D - Atomic MAX (signed): rd = old, [rs1] = max(old, rs2)
;------------------------------------------------------------------------------
.amo_max:
    call extract_r_type
    push rcx
    push r11
    mov r10d, eax

    call emit_load_rs1
    mov byte [r12], 0x4C
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xF0
    add r12, 3
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xC1
    add r12, 3

    mov ebx, r10d
    call emit_load_rs1
    mov byte [r12], 0x48    ; mov rdx, rax
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xC2
    add r12, 3

    pop r11
    cmp r11d, 3
    je .amo_max_d

    ; AMOMAX.W
    mov byte [r12], 0x8B    ; mov eax, [rcx]
    mov byte [r12+1], 0x01
    add r12, 2
    mov byte [r12], 0x50    ; push rax
    add r12, 1
    mov byte [r12], 0x39    ; cmp eax, edx
    mov byte [r12+1], 0xD0
    add r12, 2
    mov byte [r12], 0x0F    ; cmovl eax, edx (if old < rs2, use rs2)
    mov byte [r12+1], 0x4C
    mov byte [r12+2], 0xC2
    add r12, 3
    mov byte [r12], 0x89    ; mov [rcx], eax
    mov byte [r12+1], 0x01
    add r12, 2
    mov byte [r12], 0x58    ; pop rax
    add r12, 1
    mov byte [r12], 0x48    ; movsxd rax, eax
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3
    jmp .amo_max_store

.amo_max_d:
    mov byte [r12], 0x48    ; mov rax, [rcx]
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x01
    add r12, 3
    mov byte [r12], 0x50    ; push rax
    add r12, 1
    mov byte [r12], 0x48    ; cmp rax, rdx
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xD0
    add r12, 3
    mov byte [r12], 0x48    ; cmovl rax, rdx
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x4C
    mov byte [r12+3], 0xC2
    add r12, 4
    mov byte [r12], 0x48    ; mov [rcx], rax
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x01
    add r12, 3
    mov byte [r12], 0x58    ; pop rax
    add r12, 1

.amo_max_store:
    pop rcx
    test ecx, ecx
    jz .amo_max_done
    call emit_store_rd
.amo_max_done:
    jmp .calc_size

;------------------------------------------------------------------------------
; AMOMINU.W/D - Atomic MIN (unsigned): rd = old, [rs1] = min(old, rs2)
;------------------------------------------------------------------------------
.amo_minu:
    call extract_r_type
    push rcx
    push r11
    mov r10d, eax

    call emit_load_rs1
    mov byte [r12], 0x4C
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xF0
    add r12, 3
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xC1
    add r12, 3

    mov ebx, r10d
    call emit_load_rs1
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xC2
    add r12, 3

    pop r11
    cmp r11d, 3
    je .amo_minu_d

    ; AMOMINU.W
    mov byte [r12], 0x8B    ; mov eax, [rcx]
    mov byte [r12+1], 0x01
    add r12, 2
    mov byte [r12], 0x50    ; push rax
    add r12, 1
    mov byte [r12], 0x39    ; cmp eax, edx
    mov byte [r12+1], 0xD0
    add r12, 2
    mov byte [r12], 0x0F    ; cmova eax, edx (if old > rs2 unsigned, use rs2)
    mov byte [r12+1], 0x47
    mov byte [r12+2], 0xC2
    add r12, 3
    mov byte [r12], 0x89    ; mov [rcx], eax
    mov byte [r12+1], 0x01
    add r12, 2
    mov byte [r12], 0x58    ; pop rax
    add r12, 1
    mov byte [r12], 0x48    ; movsxd rax, eax
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3
    jmp .amo_minu_store

.amo_minu_d:
    mov byte [r12], 0x48    ; mov rax, [rcx]
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x01
    add r12, 3
    mov byte [r12], 0x50    ; push rax
    add r12, 1
    mov byte [r12], 0x48    ; cmp rax, rdx
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xD0
    add r12, 3
    mov byte [r12], 0x48    ; cmova rax, rdx
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x47
    mov byte [r12+3], 0xC2
    add r12, 4
    mov byte [r12], 0x48    ; mov [rcx], rax
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x01
    add r12, 3
    mov byte [r12], 0x58    ; pop rax
    add r12, 1

.amo_minu_store:
    pop rcx
    test ecx, ecx
    jz .amo_minu_done
    call emit_store_rd
.amo_minu_done:
    jmp .calc_size

;------------------------------------------------------------------------------
; AMOMAXU.W/D - Atomic MAX (unsigned): rd = old, [rs1] = max(old, rs2)
;------------------------------------------------------------------------------
.amo_maxu:
    call extract_r_type
    push rcx
    push r11
    mov r10d, eax

    call emit_load_rs1
    mov byte [r12], 0x4C
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xF0
    add r12, 3
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xC1
    add r12, 3

    mov ebx, r10d
    call emit_load_rs1
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0xC2
    add r12, 3

    pop r11
    cmp r11d, 3
    je .amo_maxu_d

    ; AMOMAXU.W
    mov byte [r12], 0x8B    ; mov eax, [rcx]
    mov byte [r12+1], 0x01
    add r12, 2
    mov byte [r12], 0x50    ; push rax
    add r12, 1
    mov byte [r12], 0x39    ; cmp eax, edx
    mov byte [r12+1], 0xD0
    add r12, 2
    mov byte [r12], 0x0F    ; cmovb eax, edx (if old < rs2 unsigned, use rs2)
    mov byte [r12+1], 0x42
    mov byte [r12+2], 0xC2
    add r12, 3
    mov byte [r12], 0x89    ; mov [rcx], eax
    mov byte [r12+1], 0x01
    add r12, 2
    mov byte [r12], 0x58    ; pop rax
    add r12, 1
    mov byte [r12], 0x48    ; movsxd rax, eax
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3
    jmp .amo_maxu_store

.amo_maxu_d:
    mov byte [r12], 0x48    ; mov rax, [rcx]
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x01
    add r12, 3
    mov byte [r12], 0x50    ; push rax
    add r12, 1
    mov byte [r12], 0x48    ; cmp rax, rdx
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xD0
    add r12, 3
    mov byte [r12], 0x48    ; cmovb rax, rdx
    mov byte [r12+1], 0x0F
    mov byte [r12+2], 0x42
    mov byte [r12+3], 0xC2
    add r12, 4
    mov byte [r12], 0x48    ; mov [rcx], rax
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x01
    add r12, 3
    mov byte [r12], 0x58    ; pop rax
    add r12, 1

.amo_maxu_store:
    pop rcx
    test ecx, ecx
    jz .amo_maxu_done
    call emit_store_rd
.amo_maxu_done:
    jmp .calc_size

;==============================================================================
; NOP
;==============================================================================
.emit_nop:
    mov byte [r12], 0x90
    mov rax, 1
    jmp .done

;==============================================================================
; Calculate bytes written
;==============================================================================
.calc_size:
    mov rax, r12
    sub rax, r14
    jmp .done

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

;==============================================================================
; translate_compressed
; Translate a 16-bit compressed RISC-V instruction to x86-64
; Input:  DI = 16-bit compressed instruction
;         RSI = output buffer pointer
;         RDX = current PC (for error messages)
; Output: RAX = bytes written
;==============================================================================
translate_compressed:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rsi                ; r12 = output pointer
    movzx r13d, di              ; r13d = instruction
    mov r14, rsi                ; r14 = buffer start for size calc
    mov r15, rdx                ; r15 = current PC

    ; Extract quadrant (bits 1:0)
    mov eax, r13d
    and eax, 0x3

    cmp eax, 0x0
    je .c_quadrant0

    cmp eax, 0x1
    je .c_quadrant1

    cmp eax, 0x2
    je .c_quadrant2

    ; Unknown quadrant (0x3 = 32-bit, shouldn't happen here)
    push rax
    push r12
    sub rsp, 48

    ; Format: "ERR: PC=XXXXXXXX Cinst=XXXX q=X\n"
    mov byte [num_buffer], 'E'
    mov byte [num_buffer+1], 'R'
    mov byte [num_buffer+2], 'R'
    mov byte [num_buffer+3], ':'
    mov byte [num_buffer+4], ' '
    mov byte [num_buffer+5], 'P'
    mov byte [num_buffer+6], 'C'
    mov byte [num_buffer+7], '='

    ; Print PC (r15) as 8 hex digits
    mov eax, r15d
    mov ecx, 8
    lea rsi, [num_buffer+15]
.c_unk_pc_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .c_unk_pc_dig
    add dl, 'A' - 10
    jmp .c_unk_pc_st
.c_unk_pc_dig:
    add dl, '0'
.c_unk_pc_st:
    mov [rsi], dl
    dec rsi
    shr eax, 4
    dec ecx
    jnz .c_unk_pc_hex

    mov byte [num_buffer+16], ' '
    mov byte [num_buffer+17], 'C'
    mov byte [num_buffer+18], 'i'
    mov byte [num_buffer+19], 'n'
    mov byte [num_buffer+20], 's'
    mov byte [num_buffer+21], 't'
    mov byte [num_buffer+22], '='

    ; Print compressed instruction (r13d) as 4 hex digits
    mov eax, r13d
    mov ecx, 4
    lea rsi, [num_buffer+26]
.c_unk_inst_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .c_unk_inst_dig
    add dl, 'A' - 10
    jmp .c_unk_inst_st
.c_unk_inst_dig:
    add dl, '0'
.c_unk_inst_st:
    mov [rsi], dl
    dec rsi
    shr eax, 4
    dec ecx
    jnz .c_unk_inst_hex

    mov byte [num_buffer+27], ' '
    mov byte [num_buffer+28], 'q'
    mov byte [num_buffer+29], '='
    mov eax, r13d
    and eax, 0x3
    add al, '0'
    mov [num_buffer+30], al
    mov byte [num_buffer+31], 10

    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 32
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop r12
    pop rax

    mov byte [r12], 0xCC
    mov rax, 1
    jmp .c_done

;------------------------------------------------------------------------------
; Quadrant 0: C.ADDI4SPN, C.LW, C.LD, C.SW, C.SD, etc.
;------------------------------------------------------------------------------
.c_quadrant0:
    mov eax, r13d
    shr eax, 13
    and eax, 0x7                ; funct3

    cmp eax, 0                  ; C.ADDI4SPN
    je .c_addi4spn

    cmp eax, 2                  ; C.LW
    je .c_lw

    cmp eax, 3                  ; C.LD (RV64) or C.FLW (RV32)
    je .c_ld

    cmp eax, 6                  ; C.SW
    je .c_sw

    cmp eax, 7                  ; C.SD (RV64) or C.FSW (RV32)
    je .c_sd

    ; Unsupported Q0 instruction
    jmp .c_emit_nop

;------------------------------------------------------------------------------
; Quadrant 1: C.ADDI, C.LI, C.LUI, C.ADDI16SP, C.J, C.BEQZ, C.BNEZ, ALU ops
;------------------------------------------------------------------------------
.c_quadrant1:
    mov eax, r13d
    shr eax, 13
    and eax, 0x7                ; funct3

    cmp eax, 0                  ; C.NOP / C.ADDI
    je .c_addi

    cmp eax, 1                  ; C.ADDIW (RV64) / C.JAL (RV32)
    je .c_addiw

    cmp eax, 2                  ; C.LI
    je .c_li

    cmp eax, 3                  ; C.LUI / C.ADDI16SP
    je .c_lui_addi16sp

    cmp eax, 4                  ; C.SRLI / C.SRAI / C.ANDI / C.SUB / C.XOR / C.OR / C.AND
    je .c_alu

    cmp eax, 5                  ; C.J
    je .c_j_impl

    cmp eax, 6                  ; C.BEQZ
    je .c_beqz

    cmp eax, 7                  ; C.BNEZ
    je .c_bnez

    jmp .c_emit_nop

;------------------------------------------------------------------------------
; Quadrant 2: C.SLLI, C.LWSP, C.LDSP, C.JR, C.MV, C.ADD, C.SWSP, C.SDSP
;------------------------------------------------------------------------------
.c_quadrant2:
    mov eax, r13d
    shr eax, 13
    and eax, 0x7                ; funct3

    cmp eax, 0                  ; C.SLLI
    je .c_slli

    cmp eax, 2                  ; C.LWSP
    je .c_lwsp

    cmp eax, 3                  ; C.LDSP (RV64) / C.FLWSP (RV32)
    je .c_ldsp

    cmp eax, 4                  ; C.JR / C.MV / C.EBREAK / C.JALR / C.ADD
    je .c_cr_format

    cmp eax, 6                  ; C.SWSP
    je .c_swsp

    cmp eax, 7                  ; C.SDSP (RV64) / C.FSWSP (RV32)
    je .c_sdsp

    jmp .c_emit_nop

;==============================================================================
; C Extension instruction implementations
;==============================================================================

;------------------------------------------------------------------------------
; C.ADDI4SPN: addi rd', x2, nzuimm
; Format: CIW - rd' in bits 4:2, immediate in bits 12:5
;------------------------------------------------------------------------------
.c_addi4spn:
    ; rd' = bits 4:2 (maps to x8-x15)
    mov ecx, r13d
    shr ecx, 2
    and ecx, 0x7
    add ecx, 8                  ; rd = rd' + 8

    ; Extract immediate: nzuimm[5:4|9:6|2|3]
    ; imm[5:4] = inst[12:11], imm[9:6] = inst[10:7], imm[2] = inst[6], imm[3] = inst[5]
    xor eax, eax

    ; imm[5:4] from inst[12:11]
    mov edx, r13d
    shr edx, 11
    and edx, 0x3
    shl edx, 4
    or eax, edx

    ; imm[9:6] from inst[10:7]
    mov edx, r13d
    shr edx, 7
    and edx, 0xF
    shl edx, 6
    or eax, edx

    ; imm[2] from inst[6]
    mov edx, r13d
    shr edx, 6
    and edx, 0x1
    shl edx, 2
    or eax, edx

    ; imm[3] from inst[5]
    mov edx, r13d
    shr edx, 5
    and edx, 0x1
    shl edx, 3
    or eax, edx

    ; Load sp (x2) into RAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov byte [r12+3], 16        ; x2 * 8 = 16
    add r12, 4

    ; Add immediate
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], eax
    add r12, 6

    ; Store to rd
    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.LW: lw rd', offset(rs1')
;------------------------------------------------------------------------------
.c_lw:
    ; rd' = bits 4:2, rs1' = bits 9:7
    mov ecx, r13d
    shr ecx, 2
    and ecx, 0x7
    add ecx, 8                  ; rd

    mov ebx, r13d
    shr ebx, 7
    and ebx, 0x7
    add ebx, 8                  ; rs1

    ; offset[5:3] = inst[12:10], offset[2|6] = inst[6:5]
    xor eax, eax

    mov edx, r13d
    shr edx, 10
    and edx, 0x7
    shl edx, 3
    or eax, edx

    mov edx, r13d
    shr edx, 6
    and edx, 0x1
    shl edx, 2
    or eax, edx

    mov edx, r13d
    shr edx, 5
    and edx, 0x1
    shl edx, 6
    or eax, edx

    ; Load rs1 into RAX
    push rcx
    push rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rax
    pop rcx

    ; Add offset
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], eax
    add r12, 6

    ; Bounds check for C.LW
    mov byte [r12], 0x48
    mov byte [r12+1], 0xB9
    mov dword [r12+2], 0x07FFFFFC
    mov dword [r12+6], 0
    add r12, 10
    mov byte [r12], 0x48
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xC8
    add r12, 3
    mov byte [r12], 0x73
    mov byte [r12+1], 0x06
    add r12, 2
    ; Load 32-bit sign-extended from [r14+rax]
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0x63      ; MOVSXD
    mov byte [r12+2], 0x04      ; ModRM: SIB mode
    mov byte [r12+3], 0x06      ; SIB: base=r14, index=rax
    add r12, 4
    mov byte [r12], 0xEB
    mov byte [r12+1], 0x02
    add r12, 2
    mov byte [r12], 0x31
    mov byte [r12+1], 0xC0
    add r12, 2

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.LD: ld rd', offset(rs1')
;------------------------------------------------------------------------------
.c_ld:
    mov ecx, r13d
    shr ecx, 2
    and ecx, 0x7
    add ecx, 8                  ; rd

    mov ebx, r13d
    shr ebx, 7
    and ebx, 0x7
    add ebx, 8                  ; rs1

    ; offset[5:3] = inst[12:10], offset[7:6] = inst[6:5]
    xor eax, eax

    mov edx, r13d
    shr edx, 10
    and edx, 0x7
    shl edx, 3
    or eax, edx

    mov edx, r13d
    shr edx, 5
    and edx, 0x3
    shl edx, 6
    or eax, edx

    ; Load rs1
    push rcx
    push rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rax
    pop rcx

    ; Add offset
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], eax
    add r12, 6

    ; Bounds check for C.LD
    mov byte [r12], 0x48
    mov byte [r12+1], 0xB9
    mov dword [r12+2], 0x07FFFFF8
    mov dword [r12+6], 0
    add r12, 10
    mov byte [r12], 0x48
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xC8
    add r12, 3
    mov byte [r12], 0x73
    mov byte [r12+1], 0x06
    add r12, 2
    ; Load 64-bit from [r14+rax]
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0x8B      ; MOV
    mov byte [r12+2], 0x04      ; ModRM: SIB mode
    mov byte [r12+3], 0x06      ; SIB: base=r14, index=rax
    add r12, 4
    mov byte [r12], 0xEB
    mov byte [r12+1], 0x02
    add r12, 2
    mov byte [r12], 0x31
    mov byte [r12+1], 0xC0
    add r12, 2

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.SW: sw rs2', offset(rs1')
;------------------------------------------------------------------------------
.c_sw:
    inc qword [c_sw_count]
    ; rs2' = bits 4:2, rs1' = bits 9:7
    mov edx, r13d
    shr edx, 2
    and edx, 0x7
    add edx, 8                  ; rs2

    mov ebx, r13d
    shr ebx, 7
    and ebx, 0x7
    add ebx, 8                  ; rs1

    ; offset[5:3] = inst[12:10], offset[2|6] = inst[6:5]
    xor eax, eax

    mov ecx, r13d
    shr ecx, 10
    and ecx, 0x7
    shl ecx, 3
    or eax, ecx

    mov ecx, r13d
    shr ecx, 6
    and ecx, 0x1
    shl ecx, 2
    or eax, ecx

    mov ecx, r13d
    shr ecx, 5
    and ecx, 0x1
    shl ecx, 6
    or eax, ecx

    push rax                    ; Save offset
    push rdx                    ; Save rs2

    ; Load rs1 into RCX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B      ; mov rcx, [rbx + disp8]
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4

    pop rdx                     ; Restore rs2

    ; Load rs2 into EAX
    mov byte [r12], 0x8B
    mov byte [r12+1], 0x43
    mov eax, edx
    shl eax, 3
    mov byte [r12+2], al
    add r12, 3

    pop rdx                     ; Restore offset (into edx)

    ; Add offset to RCX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x81
    mov byte [r12+2], 0xC1      ; add rcx, imm32
    mov [r12+3], edx
    add r12, 7

    ; Store to [r14+rcx]: mov [r14+rcx], eax
    mov byte [r12], 0x41        ; REX.B
    mov byte [r12+1], 0x89      ; MOV r/m32, r32
    mov byte [r12+2], 0x04      ; ModRM: SIB mode
    mov byte [r12+3], 0x0E      ; SIB: base=r14, index=rcx
    add r12, 4

    ; === C.SW Corruption detection ===
    ; Read back: mov r11d, [r14+rcx] (45 8B 1C 0E)
    mov byte [r12], 0x45
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x1C
    mov byte [r12+3], 0x0E
    add r12, 4

    ; Compare: cmp r11d, eax (44 39 D8)
    mov byte [r12], 0x44
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xD8
    add r12, 3

    ; je skip (74 XX) - no corruption, skip capture
    mov byte [r12], 0x74
    mov byte [r12+1], 0       ; placeholder for offset
    lea r11, [r12+1]          ; save patch location
    add r12, 2

    ; Check if already captured: mov r10, csw_corrupt_captured
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [csw_corrupt_captured]
    mov [r12+2], rax
    add r12, 10
    ; cmp byte [r10], 0 (41 80 3A 00)
    mov byte [r12], 0x41
    mov byte [r12+1], 0x80
    mov byte [r12+2], 0x3A
    mov byte [r12+3], 0x00
    add r12, 4
    ; jne skip2 (75 XX)
    mov byte [r12], 0x75
    mov byte [r12+1], 0       ; placeholder
    push r11                  ; save first patch
    lea r11, [r12+1]          ; save second patch location
    add r12, 2

    ; Set captured: mov byte [r10], 1 (41 C6 02 01)
    mov byte [r12], 0x41
    mov byte [r12+1], 0xC6
    mov byte [r12+2], 0x02
    mov byte [r12+3], 0x01
    add r12, 4

    ; Save address: mov [csw_corrupt_addr], rcx
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [csw_corrupt_addr]
    mov [r12+2], rax
    add r12, 10
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x0A          ; mov [r10], rcx
    add r12, 3

    ; Save stored value: mov [csw_corrupt_stored], eax
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [csw_corrupt_stored]
    mov [r12+2], rax
    add r12, 10
    mov byte [r12], 0x41
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x02          ; mov [r10], eax
    add r12, 3

    ; Save readback: re-read and save
    ; mov r11d, [r14+rcx] (45 8B 1C 0E)
    mov byte [r12], 0x45
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x1C
    mov byte [r12+3], 0x0E
    add r12, 4
    ; mov [csw_corrupt_readback], r11d
    mov byte [r12], 0x49
    mov byte [r12+1], 0xBA
    lea rax, [csw_corrupt_readback]
    mov [r12+2], rax
    add r12, 10
    mov byte [r12], 0x45
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x1A          ; mov [r10], r11d
    add r12, 3

    ; Patch second jne
    mov rax, r12
    sub rax, r11
    dec rax
    mov [r11], al
    pop r11                   ; restore first patch location

    ; .skip2:
    ; Patch first je
    mov rax, r12
    sub rax, r11
    dec rax
    mov [r11], al

    ; .skip:

    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.SD: sd rs2', offset(rs1')
;------------------------------------------------------------------------------
.c_sd:
    inc qword [c_sd_count]
    mov edx, r13d
    shr edx, 2
    and edx, 0x7
    add edx, 8                  ; rs2

    mov ebx, r13d
    shr ebx, 7
    and ebx, 0x7
    add ebx, 8                  ; rs1

    ; offset[5:3] = inst[12:10], offset[7:6] = inst[6:5]
    xor eax, eax

    mov ecx, r13d
    shr ecx, 10
    and ecx, 0x7
    shl ecx, 3
    or eax, ecx

    mov ecx, r13d
    shr ecx, 5
    and ecx, 0x3
    shl ecx, 6
    or eax, ecx

    push rax
    push rdx

    ; Load rs1 into RCX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4

    pop rdx

    ; Load rs2 into RAX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, edx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4

    pop rdx                     ; offset

    ; Add offset
    mov byte [r12], 0x48
    mov byte [r12+1], 0x81
    mov byte [r12+2], 0xC1
    mov [r12+3], edx
    add r12, 7

    ; Store to [r14+rcx]: mov [r14+rcx], rax
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0x89      ; MOV r/m64, r64
    mov byte [r12+2], 0x04      ; ModRM: SIB mode
    mov byte [r12+3], 0x0E      ; SIB: base=r14, index=rcx
    add r12, 4

    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.ADDI: addi rd, rd, imm (rd in bits 11:7, imm in bits 12|6:2)
;------------------------------------------------------------------------------
.c_addi:
    ; rd = bits 11:7
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x1F

    test ecx, ecx
    jz .c_emit_nop              ; C.NOP if rd == 0

    ; imm[5] = bit 12, imm[4:0] = bits 6:2
    mov eax, r13d
    shr eax, 2
    and eax, 0x1F               ; imm[4:0]

    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 5
    or eax, edx                 ; imm[5:0]

    ; Sign-extend from bit 5
    test eax, 0x20
    jz .c_addi_positive
    or eax, 0xFFFFFFC0
.c_addi_positive:

    ; Load rd into RAX (use helper for proper disp8/disp32)
    push rcx
    push rax
    call emit_load_reg_to_rax
    pop rax
    pop rcx

    ; Add immediate
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], eax
    add r12, 6

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.ADDIW: addiw rd, rd, imm (RV64 only)
;------------------------------------------------------------------------------
.c_addiw:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x1F

    test ecx, ecx
    jz .c_emit_nop

    ; imm same as C.ADDI
    mov eax, r13d
    shr eax, 2
    and eax, 0x1F

    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 5
    or eax, edx

    test eax, 0x20
    jz .c_addiw_positive
    or eax, 0xFFFFFFC0
.c_addiw_positive:

    ; Load rd into RAX (use helper for proper disp8/disp32)
    push rcx
    push rax
    call emit_load_reg_to_rax
    pop rax
    pop rcx

    ; Add immediate (32-bit)
    mov byte [r12], 0x05        ; add eax, imm32
    mov [r12+1], eax
    add r12, 5

    ; Sign-extend: movsxd rax, eax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.LI: addi rd, x0, imm
;------------------------------------------------------------------------------
.c_li:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x1F

    test ecx, ecx
    jz .c_emit_nop

    ; Extract immediate
    mov eax, r13d
    shr eax, 2
    and eax, 0x1F

    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 5
    or eax, edx

    ; Sign-extend
    test eax, 0x20
    jz .c_li_positive
    or eax, 0xFFFFFFC0
.c_li_positive:

    ; mov rax, imm32 (sign-extended)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0xC0      ; mov rax, imm32
    mov [r12+3], eax
    add r12, 7

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.LUI / C.ADDI16SP
;------------------------------------------------------------------------------
.c_lui_addi16sp:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x1F

    cmp ecx, 2
    je .c_addi16sp

    test ecx, ecx
    jz .c_emit_nop              ; Reserved

    ; C.LUI: lui rd, nzimm
    ; imm[17] = bit 12, imm[16:12] = bits 6:2
    mov eax, r13d
    shr eax, 2
    and eax, 0x1F
    shl eax, 12                 ; imm[16:12]

    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 17
    or eax, edx                 ; imm[17]

    ; Sign-extend from bit 17
    test eax, 0x20000
    jz .c_lui_no_sign
    or eax, 0xFFFC0000
.c_lui_no_sign:

    ; mov rax, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0xC0
    mov [r12+3], eax
    add r12, 7

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

.c_addi16sp:
    ; C.ADDI16SP: addi x2, x2, nzimm
    ; imm[9] = bit 12, imm[4|6|8:7|5] = bits 6:2
    xor eax, eax

    ; imm[5] = inst[2]
    mov edx, r13d
    shr edx, 2
    and edx, 0x1
    shl edx, 5
    or eax, edx

    ; imm[8:7] = inst[4:3]
    mov edx, r13d
    shr edx, 3
    and edx, 0x3
    shl edx, 7
    or eax, edx

    ; imm[6] = inst[5]
    mov edx, r13d
    shr edx, 5
    and edx, 0x1
    shl edx, 6
    or eax, edx

    ; imm[4] = inst[6]
    mov edx, r13d
    shr edx, 6
    and edx, 0x1
    shl edx, 4
    or eax, edx

    ; imm[9] = inst[12]
    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 9
    or eax, edx

    ; Sign-extend from bit 9
    test eax, 0x200
    jz .c_addi16sp_no_sign
    or eax, 0xFFFFFC00
.c_addi16sp_no_sign:

    ; Load sp (x2)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov byte [r12+3], 16        ; x2 * 8
    add r12, 4

    ; Add immediate
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], eax
    add r12, 6

    ; Store to x2
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x43
    mov byte [r12+3], 16
    add r12, 4

    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.ALU operations (funct3 = 100)
;------------------------------------------------------------------------------
.c_alu:
    ; bits 11:10 determine sub-operation
    mov eax, r13d
    shr eax, 10
    and eax, 0x3

    cmp eax, 0
    je .c_srli

    cmp eax, 1
    je .c_srai

    cmp eax, 2
    je .c_andi

    ; eax == 3: register-register ops
    ; bits 6:5 further distinguish
    mov eax, r13d
    shr eax, 5
    and eax, 0x3

    ; bit 12 distinguishes W-variants
    mov edx, r13d
    shr edx, 12
    and edx, 0x1

    test edx, edx
    jnz .c_alu_w_variants

    cmp eax, 0
    je .c_sub

    cmp eax, 1
    je .c_xor

    cmp eax, 2
    je .c_or

    cmp eax, 3
    je .c_and

    jmp .c_emit_nop

.c_alu_w_variants:
    cmp eax, 0
    je .c_subw

    cmp eax, 1
    je .c_addw

    jmp .c_emit_nop

;------------------------------------------------------------------------------
; C.SRLI: srli rd', rd', shamt
;------------------------------------------------------------------------------
.c_srli:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    add ecx, 8                  ; rd

    ; shamt[5] = bit 12, shamt[4:0] = bits 6:2
    mov eax, r13d
    shr eax, 2
    and eax, 0x1F

    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 5
    or eax, edx

    ; Load rd
    push rcx
    push rax
    mov ebx, ecx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rax
    pop rcx

    ; shr rax, imm8
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC1
    mov byte [r12+2], 0xE8      ; shr rax, imm8
    mov byte [r12+3], al
    add r12, 4

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.SRAI: srai rd', rd', shamt
;------------------------------------------------------------------------------
.c_srai:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    add ecx, 8

    mov eax, r13d
    shr eax, 2
    and eax, 0x1F

    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 5
    or eax, edx

    push rcx
    push rax
    mov ebx, ecx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rax
    pop rcx

    ; sar rax, imm8
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC1
    mov byte [r12+2], 0xF8
    mov byte [r12+3], al
    add r12, 4

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.ANDI: andi rd', rd', imm
;------------------------------------------------------------------------------
.c_andi:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    add ecx, 8

    mov eax, r13d
    shr eax, 2
    and eax, 0x1F

    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 5
    or eax, edx

    ; Sign-extend
    test eax, 0x20
    jz .c_andi_positive
    or eax, 0xFFFFFFC0
.c_andi_positive:

    push rcx
    push rax
    mov ebx, ecx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rax
    pop rcx

    ; and rax, imm32
    mov byte [r12], 0x48
    mov byte [r12+1], 0x25
    mov [r12+2], eax
    add r12, 6

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.SUB: sub rd', rd', rs2'
;------------------------------------------------------------------------------
.c_sub:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    add ecx, 8                  ; rd/rs1

    mov edx, r13d
    shr edx, 2
    and edx, 0x7
    add edx, 8                  ; rs2

    ; Load rd/rs1
    push rcx
    push rdx
    mov ebx, ecx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rdx
    pop rcx

    ; Load rs2 to temp
    push rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x53      ; mov rdx, [rbx + disp8]
    mov eax, edx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rcx

    ; sub rax, rdx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x29
    mov byte [r12+2], 0xD0
    add r12, 3

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.XOR: xor rd', rd', rs2'
;------------------------------------------------------------------------------
.c_xor:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    add ecx, 8

    mov edx, r13d
    shr edx, 2
    and edx, 0x7
    add edx, 8

    push rcx
    push rdx
    mov ebx, ecx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rdx
    pop rcx

    push rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x53
    mov eax, edx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rcx

    ; xor rax, rdx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x31
    mov byte [r12+2], 0xD0
    add r12, 3

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.OR: or rd', rd', rs2'
;------------------------------------------------------------------------------
.c_or:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    add ecx, 8

    mov edx, r13d
    shr edx, 2
    and edx, 0x7
    add edx, 8

    push rcx
    push rdx
    mov ebx, ecx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rdx
    pop rcx

    push rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x53
    mov eax, edx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rcx

    ; or rax, rdx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x09
    mov byte [r12+2], 0xD0
    add r12, 3

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.AND: and rd', rd', rs2'
;------------------------------------------------------------------------------
.c_and:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    add ecx, 8

    mov edx, r13d
    shr edx, 2
    and edx, 0x7
    add edx, 8

    push rcx
    push rdx
    mov ebx, ecx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rdx
    pop rcx

    push rcx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x53
    mov eax, edx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rcx

    ; and rax, rdx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x21
    mov byte [r12+2], 0xD0
    add r12, 3

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.SUBW: subw rd', rd', rs2' (RV64)
;------------------------------------------------------------------------------
.c_subw:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    add ecx, 8

    mov edx, r13d
    shr edx, 2
    and edx, 0x7
    add edx, 8

    push rcx
    push rdx
    mov ebx, ecx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4
    pop rdx
    pop rcx

    push rcx
    mov byte [r12], 0x8B        ; mov edx, [rbx + disp8] (32-bit)
    mov byte [r12+1], 0x53
    mov eax, edx
    shl eax, 3
    mov byte [r12+2], al
    add r12, 3
    pop rcx

    ; sub eax, edx
    mov byte [r12], 0x29
    mov byte [r12+1], 0xD0
    add r12, 2

    ; Sign-extend
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.ADDW: addw rd', rd', rs2' (RV64)
;------------------------------------------------------------------------------
.c_addw:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    add ecx, 8

    mov edx, r13d
    shr edx, 2
    and edx, 0x7
    add edx, 8

    push rcx
    push rdx
    mov ebx, ecx
    mov byte [r12], 0x8B        ; mov eax, [rbx + disp8]
    mov byte [r12+1], 0x43
    mov eax, ebx
    shl eax, 3
    mov byte [r12+2], al
    add r12, 3
    pop rdx
    pop rcx

    push rcx
    mov byte [r12], 0x8B
    mov byte [r12+1], 0x53
    mov eax, edx
    shl eax, 3
    mov byte [r12+2], al
    add r12, 3
    pop rcx

    ; add eax, edx
    mov byte [r12], 0x01
    mov byte [r12+1], 0xD0
    add r12, 2

    ; Sign-extend
    mov byte [r12], 0x48
    mov byte [r12+1], 0x63
    mov byte [r12+2], 0xC0
    add r12, 3

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.J: jal x0, offset (unconditional jump, no link)
;------------------------------------------------------------------------------
.c_j_impl:
    ; For block translation, this is handled specially
    ; Just emit NOP here - the block handler computes the target
    jmp .c_emit_nop

;------------------------------------------------------------------------------
; C.BEQZ / C.BNEZ
;------------------------------------------------------------------------------
.c_beqz:
.c_bnez:
    ; These are handled by the block-ending code
    ; Just emit the comparison and conditional code here
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    add ecx, 8                  ; rs1

    ; Load rs1
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov eax, ecx
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4

    ; test rax, rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x85
    mov byte [r12+2], 0xC0
    add r12, 3

    ; Check if BEQZ or BNEZ
    mov eax, r13d
    shr eax, 13
    and eax, 0x7

    cmp eax, 6
    jne .c_is_bnez

    ; BEQZ: jne .not_taken (skip if NZ)
    mov byte [r12], 0x0F
    mov byte [r12+1], 0x85      ; JNE rel32
    mov dword [r12+2], 0        ; Placeholder - will be fixed by linking
    add r12, 6
    jmp .c_calc_size

.c_is_bnez:
    ; BNEZ: je .not_taken (skip if Z)
    mov byte [r12], 0x0F
    mov byte [r12+1], 0x84      ; JE rel32
    mov dword [r12+2], 0
    add r12, 6
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.SLLI: slli rd, rd, shamt
;------------------------------------------------------------------------------
.c_slli:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x1F               ; rd (full 5 bits)

    test ecx, ecx
    jz .c_emit_nop

    ; shamt[5] = bit 12, shamt[4:0] = bits 6:2
    mov eax, r13d
    shr eax, 2
    and eax, 0x1F

    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 5
    or eax, edx

    ; Load rd into RAX (use helper for proper disp8/disp32)
    push rcx
    push rax
    call emit_load_reg_to_rax
    pop rax
    pop rcx

    ; shl rax, imm8
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC1
    mov byte [r12+2], 0xE0
    mov byte [r12+3], al
    add r12, 4

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.LWSP: lw rd, offset(sp)
;------------------------------------------------------------------------------
.c_lwsp:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x1F

    test ecx, ecx
    jz .c_emit_nop              ; Reserved

    ; offset[5] = bit 12, offset[4:2] = bits 6:4, offset[7:6] = bits 3:2
    xor eax, eax

    mov edx, r13d
    shr edx, 4
    and edx, 0x7
    shl edx, 2
    or eax, edx

    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 5
    or eax, edx

    mov edx, r13d
    shr edx, 2
    and edx, 0x3
    shl edx, 6
    or eax, edx

    ; Load sp
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov byte [r12+3], 16
    add r12, 4

    ; Add offset
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], eax
    add r12, 6

    ; Load 32-bit sign-extended from [r14+rax]
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0x63      ; MOVSXD
    mov byte [r12+2], 0x04      ; ModRM: SIB mode
    mov byte [r12+3], 0x06      ; SIB: base=r14, index=rax
    add r12, 4

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.LDSP: ld rd, offset(sp)
;------------------------------------------------------------------------------
.c_ldsp:
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x1F

    ; Debug: print when C.LDSP loads ra (DISABLED for perf)
    jmp .skip_ldsp_ra_debug
    cmp ecx, 1
    jne .skip_ldsp_ra_debug
    push rax
    push rcx
    push rdx
    sub rsp, 48
    mov byte [num_buffer], 'L'
    mov byte [num_buffer+1], 'D'
    mov byte [num_buffer+2], 'S'
    mov byte [num_buffer+3], 'P'
    mov byte [num_buffer+4], '_'
    mov byte [num_buffer+5], 'R'
    mov byte [num_buffer+6], 'A'
    mov byte [num_buffer+7], ' '
    mov byte [num_buffer+8], 'P'
    mov byte [num_buffer+9], 'C'
    mov byte [num_buffer+10], ':'
    mov rax, r13
    mov ecx, 6
    lea rsi, [num_buffer+16]
.ldsp_ra_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .ldsp_ra_d
    add dl, 'A' - 10
    jmp .ldsp_ra_s
.ldsp_ra_d:
    add dl, '0'
.ldsp_ra_s:
    mov [rsi], dl
    shr eax, 4
    dec rsi
    dec ecx
    jnz .ldsp_ra_hex
    mov byte [num_buffer+17], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 18
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rdx
    pop rcx
    pop rax
    ; Restore ecx (rd)
    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x1F
.skip_ldsp_ra_debug:

    test ecx, ecx
    jz .c_emit_nop

    ; offset[5] = bit 12, offset[4:3] = bits 6:5, offset[8:6] = bits 4:2
    xor eax, eax

    mov edx, r13d
    shr edx, 5
    and edx, 0x3
    shl edx, 3
    or eax, edx

    mov edx, r13d
    shr edx, 12
    and edx, 0x1
    shl edx, 5
    or eax, edx

    mov edx, r13d
    shr edx, 2
    and edx, 0x7
    shl edx, 6
    or eax, edx

    ; Load sp
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov byte [r12+3], 16
    add r12, 4

    ; Add offset
    mov byte [r12], 0x48
    mov byte [r12+1], 0x05
    mov [r12+2], eax
    add r12, 6

    ; Bounds check for C.LDSP
    mov byte [r12], 0x48
    mov byte [r12+1], 0xB9
    mov dword [r12+2], 0x07FFFFF8
    mov dword [r12+6], 0
    add r12, 10
    mov byte [r12], 0x48
    mov byte [r12+1], 0x39
    mov byte [r12+2], 0xC8
    add r12, 3
    mov byte [r12], 0x73
    mov byte [r12+1], 0x06
    add r12, 2
    ; Load 64-bit from [r14+rax] (r14 = guest memory base)
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0x8B      ; MOV
    mov byte [r12+2], 0x04      ; ModRM: SIB mode
    mov byte [r12+3], 0x06      ; SIB: base=r14, index=rax
    add r12, 4
    mov byte [r12], 0xEB
    mov byte [r12+1], 0x02
    add r12, 2
    mov byte [r12], 0x31
    mov byte [r12+1], 0xC0
    add r12, 2

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.CR format: C.JR, C.MV, C.EBREAK, C.JALR, C.ADD
;------------------------------------------------------------------------------
.c_cr_format:
    ; bit 12 and rs2 determine instruction
    mov eax, r13d
    shr eax, 12
    and eax, 0x1                ; bit 12

    mov edx, r13d
    shr edx, 2
    and edx, 0x1F               ; rs2

    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x1F               ; rd/rs1

    test eax, eax               ; Test bit 12
    jnz .c_cr_bit12_set

    ; bit 12 = 0: C.JR or C.MV
    test edx, edx
    jz .c_jr                    ; rs2 == 0: C.JR
    jmp .c_mv                   ; rs2 != 0: C.MV

.c_cr_bit12_set:
    ; bit 12 = 1: C.EBREAK, C.JALR, or C.ADD
    test ecx, ecx
    jnz .c_cr_rs1_nonzero       ; rs1 != 0: check for JALR or ADD

    ; rs1 == 0: check rs2 for EBREAK vs HINT
    test edx, edx
    jz .c_ebreak                ; rs1 == 0, rs2 == 0: C.EBREAK
    jmp .c_emit_nop             ; rs1 == 0, rs2 != 0: HINT (NOP)

.c_cr_rs1_nonzero:
    test edx, edx
    jz .c_jalr                  ; rs2 == 0: C.JALR
    jmp .c_add                  ; C.ADD

.c_jr:
    ; C.JR: jalr x0, rs1, 0
    test ecx, ecx
    jz .c_emit_nop              ; Reserved

    ; Load rs1 into RAX (use helper for proper disp8/disp32)
    call emit_load_reg_to_rax

    ; Store to PC (indirect jump target)
    ; mov [r15], rax
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x07
    add r12, 3

    jmp .c_calc_size

.c_mv:
    ; C.MV: add rd, x0, rs2
    ; Load rs2 - handle disp8/disp32
    push rcx
    mov eax, edx
    shl eax, 3              ; eax = rs2 * 8
    cmp eax, 127
    jg .c_mv_disp32

    ; disp8 path
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43      ; mov rax, [rbx + disp8]
    mov byte [r12+3], al
    add r12, 4
    jmp .c_mv_store
.c_mv_disp32:
    ; disp32 path
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x83      ; mov rax, [rbx + disp32]
    mov [r12+3], eax
    add r12, 7

.c_mv_store:
    pop rcx

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

.c_ebreak:
    ; C.EBREAK - emit INT3
    mov byte [r12], 0xCC
    add r12, 1
    jmp .c_calc_size

.c_jalr:
    ; C.JALR: jalr x1, rs1, 0
    ; Save return address (PC + 2) to ra (x1)
    ; Then jump to rs1

    push rcx                ; Save rs1

    ; First, save return address (PC + 2) to ra (x1)
    ; Load current PC from [r15], add 2, store to x1
    ; Emit: mov rcx, [r15]
    mov byte [r12], 0x49
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x0F
    add r12, 3
    ; Emit: add rcx, 2
    mov byte [r12], 0x48
    mov byte [r12+1], 0x83
    mov byte [r12+2], 0xC1
    mov byte [r12+3], 0x02
    add r12, 4
    ; Emit: mov [rbx + 8], rcx  (store to ra = x1, offset 8)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x4B
    mov byte [r12+3], 8
    add r12, 4

    pop rcx                 ; Restore rs1

    ; Load rs1 into RAX - handle disp8/disp32
    mov eax, ecx
    shl eax, 3              ; eax = rs1 * 8
    cmp eax, 127
    jg .c_jalr_disp32
    ; disp8 path
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov byte [r12+3], al
    add r12, 4
    jmp .c_jalr_store_pc
.c_jalr_disp32:
    ; disp32 path
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x83
    mov [r12+3], eax
    add r12, 7

.c_jalr_store_pc:
    ; Store to PC
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x07
    add r12, 3

    jmp .c_calc_size

.c_add:
    ; C.ADD: add rd, rd, rs2
    push rcx
    push rdx

    ; Load rd to rax - handle disp8/disp32
    mov eax, ecx
    shl eax, 3              ; eax = rd * 8
    cmp eax, 127
    jg .c_add_rd_disp32
    ; disp8 path
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43      ; mov rax, [rbx + disp8]
    mov byte [r12+3], al
    add r12, 4
    jmp .c_add_load_rs2
.c_add_rd_disp32:
    ; disp32 path
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x83      ; mov rax, [rbx + disp32]
    mov [r12+3], eax
    add r12, 7

.c_add_load_rs2:
    pop rdx
    pop rcx

    ; Load rs2 to rdx - handle disp8/disp32
    push rcx
    mov eax, edx
    shl eax, 3              ; eax = rs2 * 8
    cmp eax, 127
    jg .c_add_rs2_disp32
    ; disp8 path
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x53      ; mov rdx, [rbx + disp8]
    mov byte [r12+3], al
    add r12, 4
    jmp .c_add_do_add
.c_add_rs2_disp32:
    ; disp32 path
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x93      ; mov rdx, [rbx + disp32]
    mov [r12+3], eax
    add r12, 7

.c_add_do_add:
    pop rcx

    ; add rax, rdx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xD0
    add r12, 3

    push rcx
    call .c_emit_store_rd
    pop rcx
    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.SWSP: sw rs2, offset(sp)
;------------------------------------------------------------------------------
.c_swsp:
    inc qword [c_swsp_count]
    mov edx, r13d
    shr edx, 2
    and edx, 0x1F               ; rs2

    ; offset[5:2] = bits 12:9, offset[7:6] = bits 8:7
    xor eax, eax

    mov ecx, r13d
    shr ecx, 9
    and ecx, 0xF
    shl ecx, 2
    or eax, ecx

    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x3
    shl ecx, 6
    or eax, ecx

    push rax
    push rdx

    ; Load sp into RCX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov byte [r12+3], 16
    add r12, 4

    pop rdx

    ; Load rs2 into EAX - handle disp8/disp32
    mov ecx, edx
    shl ecx, 3              ; ecx = rs2 * 8
    cmp ecx, 127
    jg .c_swsp_disp32
    ; disp8 path
    mov byte [r12], 0x8B
    mov byte [r12+1], 0x43
    mov byte [r12+2], cl
    add r12, 3
    jmp .c_swsp_add_offset
.c_swsp_disp32:
    ; disp32 path
    mov byte [r12], 0x8B
    mov byte [r12+1], 0x83
    mov [r12+2], ecx
    add r12, 6

.c_swsp_add_offset:
    pop rdx                     ; offset

    ; Add offset
    mov byte [r12], 0x48
    mov byte [r12+1], 0x81
    mov byte [r12+2], 0xC1
    mov [r12+3], edx
    add r12, 7

    ; Store to [r14+rcx]: mov [r14+rcx], eax
    mov byte [r12], 0x41        ; REX.B
    mov byte [r12+1], 0x89      ; MOV r/m32, r32
    mov byte [r12+2], 0x04      ; ModRM: SIB mode
    mov byte [r12+3], 0x0E      ; SIB: base=r14, index=rcx
    add r12, 4

    jmp .c_calc_size

;------------------------------------------------------------------------------
; C.SDSP: sd rs2, offset(sp)
;------------------------------------------------------------------------------
.c_sdsp:
    inc qword [c_sdsp_count]
    mov edx, r13d
    shr edx, 2
    and edx, 0x1F

    ; offset[5:3] = bits 12:10, offset[8:6] = bits 9:7
    xor eax, eax

    mov ecx, r13d
    shr ecx, 10
    and ecx, 0x7
    shl ecx, 3
    or eax, ecx

    mov ecx, r13d
    shr ecx, 7
    and ecx, 0x7
    shl ecx, 6
    or eax, ecx

    push rax
    push rdx

    ; Load sp into RCX
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov byte [r12+3], 16
    add r12, 4

    pop rdx

    ; Load rs2 into RAX - handle disp8/disp32
    mov ecx, edx
    shl ecx, 3              ; ecx = rs2 * 8
    cmp ecx, 127
    jg .c_sdsp_disp32
    ; disp8 path
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov byte [r12+3], cl
    add r12, 4
    jmp .c_sdsp_add_offset
.c_sdsp_disp32:
    ; disp32 path
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x83
    mov [r12+3], ecx
    add r12, 7

.c_sdsp_add_offset:
    pop rdx

    ; Add offset
    mov byte [r12], 0x48
    mov byte [r12+1], 0x81
    mov byte [r12+2], 0xC1
    mov [r12+3], edx
    add r12, 7

    ; Store to [r14+rcx]: mov [r14+rcx], rax
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0x89      ; MOV r/m64, r64
    mov byte [r12+2], 0x04      ; ModRM: SIB mode
    mov byte [r12+3], 0x0E      ; SIB: base=r14, index=rcx
    add r12, 4

    jmp .c_calc_size

;------------------------------------------------------------------------------
; Helper: emit NOP
;------------------------------------------------------------------------------
.c_emit_nop:
    mov byte [r12], 0x90
    add r12, 1
    jmp .c_calc_size

;------------------------------------------------------------------------------
; Helper: store RAX to rd (ECX = rd)
;------------------------------------------------------------------------------
.c_emit_store_rd:
    test ecx, ecx
    jz .c_store_rd_skip         ; Don't store to x0

    ; Handle disp8/disp32 for high registers
    mov eax, ecx
    shl eax, 3              ; eax = rd * 8
    cmp eax, 127
    jg .c_store_rd_disp32

    ; disp8 path
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x43      ; mov [rbx + disp8], rax
    mov byte [r12+3], al
    add r12, 4
    ret

.c_store_rd_disp32:
    ; disp32 path
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x83      ; mov [rbx + disp32], rax
    mov [r12+3], eax
    add r12, 7

.c_store_rd_skip:
    ret

;------------------------------------------------------------------------------
; Calculate size and return
;------------------------------------------------------------------------------
.c_calc_size:
    mov rax, r12
    sub rax, r14

.c_done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

;==============================================================================
; emit_load_rs1 - Load rs1 into RAX
; Expects: EBX = rs1
;==============================================================================
emit_load_rs1:
    ; Load [RBX + rs1*8] into RAX
    ; EBX = rs1
    mov eax, ebx
    shl eax, 3              ; eax = rs1 * 8

    ; Check if displacement fits in 8 bits (signed: -128 to 127)
    cmp eax, 127
    jg .load_disp32

    ; 8-bit displacement: mov rax, [rbx + disp8]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43      ; ModRM: [rbx + disp8]
    mov [r12+3], al
    add r12, 4
    ret

.load_disp32:
    ; 32-bit displacement: mov rax, [rbx + disp32]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x83      ; ModRM: [rbx + disp32]
    mov [r12+3], eax
    add r12, 7
    ret

;==============================================================================
; emit_store_rd - Store RAX to rd
; Expects: ECX = rd
;==============================================================================
emit_store_rd:
    ; Store RAX to [RBX + rd*8]
    ; ECX = rd (preserved)
    ; Note: Do NOT clobber r15 - it holds the block cache pointer!
    mov eax, ecx
    shl eax, 3              ; eax = rd * 8

    ; Check if displacement fits in 8 bits (signed: -128 to 127)
    cmp eax, 127
    jg .store_disp32

    ; 8-bit displacement: mov [rbx + disp8], rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x43      ; ModRM: [rbx + disp8]
    mov [r12+3], al
    add r12, 4
    ret

.store_disp32:
    ; 32-bit displacement: mov [rbx + disp32], rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x83      ; ModRM: [rbx + disp32]
    mov [r12+3], eax
    add r12, 7
    ret

;==============================================================================
; emit_load_reg_to_rax - Load RISC-V register to RAX
; Input: ECX = register number
;==============================================================================
emit_load_reg_to_rax:
    test ecx, ecx
    jz .load_zero_rax
    mov eax, ecx
    shl eax, 3              ; offset = reg * 8

    cmp eax, 127
    jg .load_rax_disp32

    ; mov rax, [rbx + disp8]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    mov [r12+3], al
    add r12, 4
    ret

.load_rax_disp32:
    ; mov rax, [rbx + disp32]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x83
    mov [r12+3], eax
    add r12, 7
    ret

.load_zero_rax:
    ; xor rax, rax (x0 is always 0)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x31
    mov byte [r12+2], 0xC0
    add r12, 3
    ret

;==============================================================================
; emit_load_reg_to_rcx - Load RISC-V register to RCX
; Input: ECX = register number
;==============================================================================
emit_load_reg_to_rcx:
    test ecx, ecx
    jz .load_zero_rcx
    mov eax, ecx
    shl eax, 3              ; offset = reg * 8

    cmp eax, 127
    jg .load_rcx_disp32

    ; mov rcx, [rbx + disp8]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x4B
    mov [r12+3], al
    add r12, 4
    ret

.load_rcx_disp32:
    ; mov rcx, [rbx + disp32]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x8B
    mov [r12+3], eax
    add r12, 7
    ret

.load_zero_rcx:
    ; xor rcx, rcx (x0 is always 0)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x31
    mov byte [r12+2], 0xC9
    add r12, 3
    ret

;==============================================================================
; emit_load_reg_to_rdx - Emit code to load RISC-V register to RDX
; Input: ECX = register number (0-31)
; Clobbers: EAX
;==============================================================================
emit_load_reg_to_rdx:
    test ecx, ecx
    jz .load_zero_rdx
    mov eax, ecx
    shl eax, 3              ; offset = reg * 8

    cmp eax, 127
    jg .load_rdx_disp32

    ; mov rdx, [rbx + disp8]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x53
    mov [r12+3], al
    add r12, 4
    ret

.load_rdx_disp32:
    ; mov rdx, [rbx + disp32]
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x93
    mov [r12+3], eax
    add r12, 7
    ret

.load_zero_rdx:
    ; xor rdx, rdx (x0 is always 0)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x31
    mov byte [r12+2], 0xD2
    add r12, 3
    ret

;==============================================================================
; emit_store_rax_to_rd - Store RAX to rd (same as emit_store_rd)
; Input: ECX = rd
;==============================================================================
emit_store_rax_to_rd:
    jmp emit_store_rd

;==============================================================================
; extract_i_type
;==============================================================================
extract_i_type:
    mov eax, r13d
    shr eax, 7
    and eax, 0x1F
    mov ecx, eax

    mov eax, r13d
    shr eax, 15
    and eax, 0x1F
    mov ebx, eax

    mov eax, r13d
    sar eax, 20
    ret

;==============================================================================
; extract_r_type
;==============================================================================
extract_r_type:
    mov eax, r13d
    shr eax, 7
    and eax, 0x1F
    mov ecx, eax

    mov eax, r13d
    shr eax, 15
    and eax, 0x1F
    mov ebx, eax

    mov eax, r13d
    shr eax, 20
    and eax, 0x1F
    ret

;==============================================================================
; extract_u_type
;==============================================================================
extract_u_type:
    mov eax, r13d
    shr eax, 7
    and eax, 0x1F
    mov ecx, eax

    mov eax, r13d
    and eax, 0xFFFFF000
    ret

;==============================================================================
; extract_s_type
;==============================================================================
extract_s_type:
    mov eax, r13d
    shr eax, 15
    and eax, 0x1F
    mov ebx, eax

    mov eax, r13d
    shr eax, 20
    and eax, 0x1F
    mov ecx, eax

    mov eax, r13d
    shr eax, 7
    and eax, 0x1F
    mov edx, eax

    mov eax, r13d
    sar eax, 20
    and eax, 0xFFFFFFE0
    or eax, edx
    ret

;==============================================================================
; extract_j_type - J-type instruction format (JAL)
; Input:  R13D = instruction
; Output: ECX = rd, EAX = immediate (sign-extended, scaled by 2)
;
; J-type immediate: imm[20|10:1|11|19:12] - bits are scrambled!
; Final imm = {inst[31], inst[19:12], inst[20], inst[30:21], 0}
;==============================================================================
extract_j_type:
    ; rd = bits 11:7
    mov eax, r13d
    shr eax, 7
    and eax, 0x1F
    mov ecx, eax

    ; Build the immediate from its scattered bits
    ; imm[20]    = inst[31]
    ; imm[10:1]  = inst[30:21]
    ; imm[11]    = inst[20]
    ; imm[19:12] = inst[19:12]

    xor eax, eax

    ; imm[19:12] = inst[19:12]
    mov edx, r13d
    and edx, 0x000FF000          ; Bits 19:12
    or eax, edx

    ; imm[11] = inst[20]
    mov edx, r13d
    shr edx, 9                   ; Bit 20 -> bit 11
    and edx, 0x00000800
    or eax, edx

    ; imm[10:1] = inst[30:21]
    mov edx, r13d
    shr edx, 20                  ; Bits 30:21 -> bits 10:1
    and edx, 0x000007FE
    or eax, edx

    ; imm[20] = inst[31] (sign bit)
    mov edx, r13d
    sar edx, 11                  ; Bit 31 -> bit 20
    and edx, 0x00100000
    or eax, edx

    ; Sign-extend from bit 20
    shl eax, 11
    sar eax, 11

    ret

;==============================================================================
; extract_b_type - B-type instruction format (branches)
; Input:  R13D = instruction
; Output: ECX = rs2, EBX = rs1, EAX = immediate (sign-extended, scaled by 2)
;
; B-type immediate: imm[12|10:5] rs2 rs1 funct3 imm[4:1|11] opcode
; Final imm = {inst[31], inst[7], inst[30:25], inst[11:8], 0}
;==============================================================================
extract_b_type:
    ; rs1 = bits 19:15
    mov eax, r13d
    shr eax, 15
    and eax, 0x1F
    mov ebx, eax

    ; rs2 = bits 24:20
    mov eax, r13d
    shr eax, 20
    and eax, 0x1F
    mov ecx, eax

    ; Build the immediate
    xor eax, eax

    ; imm[4:1] = inst[11:8]
    mov edx, r13d
    shr edx, 7                   ; Bits 11:8 -> bits 4:1
    and edx, 0x0000001E
    or eax, edx

    ; imm[10:5] = inst[30:25]
    mov edx, r13d
    shr edx, 20                  ; Bits 30:25 -> bits 10:5
    and edx, 0x000007E0
    or eax, edx

    ; imm[11] = inst[7]
    mov edx, r13d
    shl edx, 4                   ; Bit 7 -> bit 11
    and edx, 0x00000800
    or eax, edx

    ; imm[12] = inst[31] (sign bit)
    mov edx, r13d
    sar edx, 19                  ; Bit 31 -> bit 12
    and edx, 0x00001000
    or eax, edx

    ; Sign-extend from bit 12
    shl eax, 19
    sar eax, 19

    ret

;==============================================================================
; init_block_cache
; Initialise the block cache - call once at startup
; Input:  none
; Output: none
; "Have you tried turning it off and on again?"
;==============================================================================
init_block_cache:
    push rbx
    push rcx
    push rdi                        ; Callee-saved on Windows
    sub rsp, 40                     ; Shadow space for Windows calls

    ; Initialize path_buffer_ptr
    lea rax, [path_buffer]
    mov [path_buffer_ptr], rax

    ; Zero out the block cache (mark all entries invalid)
    lea rdi, [block_cache]
    mov rcx, BLOCK_CACHE_SIZE * BLOCK_ENTRY_SIZE / 8
    xor eax, eax
    rep stosq

    ; Initialise code buffer pointer to start of buffer
    lea rax, [code_buffer]
    mov [code_buf_ptr], rax

    ; Get stdout handle for console output
    mov ecx, -11                    ; STD_OUTPUT_HANDLE
    call GetStdHandle
    mov [stdout_handle], rax

    add rsp, 40
    pop rdi
    pop rcx
    pop rbx
    ret

;==============================================================================
; link_trampoline
; Blocks jump here initially - just returns to the dispatch loop
; When blocks are linked, the jump is patched to skip this
; "A trampoline, but for code. Boing!"
;==============================================================================
link_trampoline:
    ret

;==============================================================================
; link_block
; Patch a block's exit to jump directly to another block
; Input:  RDI = pointer to source block entry
;         RSI = pointer to target block entry
; Output: RAX = 1 if linked successfully, 0 if failed
; "Making friends between blocks since 2024"
;==============================================================================
link_block:
    push rbx

    ; Get the address of the jmp instruction to patch
    mov rax, [rdi + BLOCK_LINK_ADDR]
    test rax, rax
    jz .link_fail                   ; No link address stored

    ; Get target code address
    mov rbx, [rsi + BLOCK_CODE_PTR]
    test rbx, rbx
    jz .link_fail                   ; No target code

    ; Calculate relative offset for jmp
    ; offset = target - (jmp_addr + 5)
    ; jmp rel32 is: E9 xx xx xx xx (5 bytes)
    lea rcx, [rax + 5]              ; Address after the jmp instruction
    sub rbx, rcx                    ; offset = target - (jmp + 5)

    ; Patch the jmp offset (it's at jmp_addr + 1)
    mov [rax + 1], ebx

    mov eax, 1
    pop rbx
    ret

.link_fail:
    xor eax, eax
    pop rbx
    ret

;==============================================================================
; lookup_block
; Find a cached block by PC
; Input:  RDI = RISC-V PC to look up
; Output: RAX = pointer to block entry, or 0 if not found
;==============================================================================
lookup_block:
    push rbx

    ; Hash: PC & (BLOCK_CACHE_SIZE - 1) = PC & 0x3FF
    mov rax, rdi
    and eax, (BLOCK_CACHE_SIZE - 1)

    ; Calculate entry address: block_cache + (hash * BLOCK_ENTRY_SIZE)
    shl eax, 6                      ; * 64
    lea rbx, [block_cache]
    add rbx, rax

    ; Check if valid and PC matches
    cmp byte [rbx + BLOCK_VALID], 1
    jne .not_found

    cmp [rbx + BLOCK_START_PC], rdi
    jne .not_found

    ; Found it!
    mov rax, rbx
    pop rbx
    ret

.not_found:
    xor eax, eax
    pop rbx
    ret

;==============================================================================
; translate_block
; Translate a basic block starting at given PC
; Input:  RDI = start PC
;         RSI = pointer to RISC-V memory (guest memory)
; Output: RAX = pointer to block entry
;
; Translates instructions until a branch/jump, caches the result
;==============================================================================
translate_block:
    push rbp
    mov rbp, rsp
    sub rsp, 64
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; DEBUG: Print "PC:XXXXXXXX" with entry PC (DISABLED)
    jmp .skip_pc_entry_debug
    push rdi
    push rsi
    sub rsp, 48
    mov byte [num_buffer], 'P'
    mov byte [num_buffer+1], 'C'
    mov byte [num_buffer+2], ':'
    ; Print rdi (entry PC) as 8 hex digits
    mov rax, rdi
    mov ecx, 8
    lea rsi, [num_buffer+10]
.pc_entry_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .pc_entry_d
    add dl, 'A' - 10
    jmp .pc_entry_s
.pc_entry_d:
    add dl, '0'
.pc_entry_s:
    mov [rsi], dl
    dec rsi
    shr eax, 4
    dec ecx
    jnz .pc_entry_hex
    mov byte [num_buffer+11], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 12
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rsi
    pop rdi
.skip_pc_entry_debug:
    ; END DEBUG

    mov [rbp-8], rdi                ; Save start PC
    mov [rbp-16], rsi               ; Save guest memory pointer

    ; First, check if already cached
    call lookup_block
    test rax, rax
    jnz .already_cached

    ; Not cached - need to translate
    mov rdi, [rbp-8]                ; Restore start PC
    mov rsi, [rbp-16]               ; Restore guest memory

    ; Get a cache slot (hash the PC)
    mov rax, rdi
    and eax, (BLOCK_CACHE_SIZE - 1)
    shl eax, 6
    lea r15, [block_cache]
    add r15, rax                    ; R15 = cache entry pointer

    ; Allocate space in code buffer
    mov r12, [code_buf_ptr]         ; R12 = output pointer (start of this block)
    mov [r15 + BLOCK_CODE_PTR], r12

    ; REGISTER CACHING PROLOGUE: DISABLED - adds overhead for loops not using a0-a3
    ; ; Emit: mov r8, [rbx + 80]   (4C 8B 43 50) - a0
    ; mov byte [r12], 0x4C
    ; mov byte [r12+1], 0x8B
    ; mov byte [r12+2], 0x43
    ; mov byte [r12+3], 0x50          ; x10 * 8 = 80
    ; ; etc... (disabled for now)

    ; Store start PC
    mov rax, [rbp-8]
    mov [r15 + BLOCK_START_PC], rax

    ; R13 = current PC, R14 = guest memory base
    mov r13, [rbp-8]
    mov r14, [rbp-16]

    ; R8 = instruction count (safety limit)
    xor r8d, r8d

.translate_loop:
    ; Safety: max 256 instructions per block
    cmp r8d, 256
    jge .end_block_fallthrough
    inc r8d

    ; Fetch instruction from guest memory at current PC
    mov eax, [r14 + r13]            ; Load 32-bit instruction
    mov [rbp-24], eax               ; Save instruction

    ; Debug: print instruction for key blocks (DISABLED for perf)
    jmp .skip_insn_debug
    cmp qword [rbp-8], 0x1A854
    je .do_insn_debug
    cmp qword [rbp-8], 0x107D4
    je .do_insn_debug
    cmp qword [rbp-8], 0x1A850
    je .do_insn_debug
    cmp qword [rbp-8], 0x10762
    je .do_insn_debug
    cmp qword [rbp-8], 0x1075C
    jne .skip_insn_debug
.do_insn_debug:
    cmp r8d, 10
    ja .skip_insn_debug
    ; Print "I:XXXXXX XXXXXXXX" (PC and instruction)
    push rax
    push rcx
    push r8
    sub rsp, 48
    mov byte [num_buffer], 'I'
    mov byte [num_buffer+1], ':'
    mov rax, r13                    ; Current PC
    mov ecx, 6
    lea rsi, [num_buffer+7]
.insn_pc_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .insn_pc_d
    add dl, 'A' - 10
    jmp .insn_pc_s
.insn_pc_d:
    add dl, '0'
.insn_pc_s:
    mov [rsi], dl
    shr eax, 4
    dec rsi
    dec ecx
    jnz .insn_pc_hex
    mov byte [num_buffer+8], ' '
    mov eax, [rbp-24]               ; Instruction
    mov ecx, 8
    lea rsi, [num_buffer+16]
.insn_val_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .insn_val_d
    add dl, 'A' - 10
    jmp .insn_val_s
.insn_val_d:
    add dl, '0'
.insn_val_s:
    mov [rsi], dl
    shr eax, 4
    dec rsi
    dec ecx
    jnz .insn_val_hex
    mov byte [num_buffer+17], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 18
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop r8
    pop rcx
    pop rax
.skip_insn_debug:

    ; Check if this is a compressed instruction (bits[1:0] != 11)
    mov ecx, eax
    and ecx, 0x3
    cmp ecx, 0x3
    jne .is_compressed

    ; --- 32-bit instruction path ---
    mov ecx, eax
    and ecx, 0x7F                   ; Extract opcode

    cmp ecx, RV_OP_JAL
    je .is_jal

    cmp ecx, RV_OP_JALR
    je .is_jalr

    cmp ecx, RV_OP_BRANCH
    je .is_branch

    cmp ecx, RV_OP_SYSTEM
    je .check_ecall

    ; Not a block-ender - translate normally
    mov edi, eax                    ; instruction
    mov rsi, r12                    ; output buffer
    mov rdx, r13                    ; current PC (for AUIPC)
    call translate_instruction
    add r12, rax                    ; Advance output pointer

    ; Advance PC by 4
    add r13, 4
    jmp .translate_loop

    ; --- 16-bit compressed instruction path ---
.is_compressed:
    ; Get just the 16-bit instruction
    movzx eax, word [r14 + r13]
    mov [rbp-24], eax               ; Save 16-bit instruction

    ; Check for compressed block-enders:
    ; Q1 (01): C.J (funct3=101), C.BEQZ (funct3=110), C.BNEZ (funct3=111)
    ; Q2 (10): C.JR/C.JALR (funct3=100, bit12 varies)

    mov ecx, eax
    and ecx, 0x3                    ; Quadrant

    cmp ecx, 0x1                    ; Quadrant 1?
    je .check_q1_block_ender

    cmp ecx, 0x2                    ; Quadrant 2?
    je .check_q2_block_ender

    ; Quadrant 0 has no block-enders, translate normally
    jmp .translate_compressed_normal

.check_q1_block_ender:
    ; Check funct3 (bits 15:13)
    mov ecx, eax
    shr ecx, 13
    and ecx, 0x7

    cmp ecx, 5                      ; C.J (funct3=101)
    je .is_c_j

    cmp ecx, 6                      ; C.BEQZ (funct3=110)
    je .is_c_branch

    cmp ecx, 7                      ; C.BNEZ (funct3=111)
    je .is_c_branch

    jmp .translate_compressed_normal

.check_q2_block_ender:
    ; Check funct3 (bits 15:13)
    mov ecx, eax
    shr ecx, 13
    and ecx, 0x7

    cmp ecx, 4                      ; C.JR/C.MV/C.JALR/C.ADD (funct3=100)
    jne .translate_compressed_normal

    ; Distinguish by bit 12 and rs2
    ; If rs2 == 0 (bits 6:2 == 0): C.JR (bit12=0) or C.JALR (bit12=1)
    ; If rs2 != 0: C.MV (bit12=0) or C.ADD (bit12=1)
    mov ecx, eax
    shr ecx, 2
    and ecx, 0x1F                   ; rs2 field
    test ecx, ecx
    jnz .translate_compressed_normal  ; C.MV or C.ADD - not block-enders

    ; rs2 == 0, so this is C.JR or C.JALR - block-enders
    jmp .is_c_jr_jalr

.translate_compressed_normal:
    ; Translate compressed instruction
    movzx edi, word [rbp-24]        ; 16-bit instruction
    mov rsi, r12                    ; output buffer
    mov rdx, r13                    ; current PC
    call translate_compressed
    add r12, rax                    ; Advance output pointer

    ; Advance PC by 2 (compressed)
    add r13, 2
    jmp .translate_loop

.is_jal:
    ; Debug: print when translating JAL at PC near 0x107DE (DISABLED for perf)
    jmp .skip_jal_debug
    cmp r13d, 0x107D0
    jb .skip_jal_debug
    cmp r13d, 0x107F0
    ja .skip_jal_debug
    push rax
    push rcx
    push rdx
    sub rsp, 48
    mov byte [num_buffer], 'J'
    mov byte [num_buffer+1], 'A'
    mov byte [num_buffer+2], 'L'
    mov byte [num_buffer+3], ':'
    mov eax, r13d
    mov ecx, 8
    lea rsi, [num_buffer+11]
.jal_dbg_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .jal_dbg_d
    add dl, 'A' - 10
    jmp .jal_dbg_s
.jal_dbg_d:
    add dl, '0'
.jal_dbg_s:
    mov [rsi], dl
    shr eax, 4
    dec rsi
    dec ecx
    jnz .jal_dbg_hex
    mov byte [num_buffer+12], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 13
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rdx
    pop rcx
    pop rax
.skip_jal_debug:
    ; JAL - unconditional jump
    ; First, emit code to store current PC to rv_pc
    ; Emit: mov qword [r15], current_pc
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0xC7      ; MOV r/m64, imm32
    mov byte [r12+2], 0x07      ; ModRM: [r15]
    mov [r12+3], r13d           ; Current PC (32-bit immediate)
    add r12, 7

    ; Now translate the JAL
    mov edi, [rbp-24]
    mov rsi, r12
    mov rdx, r13                    ; current PC
    call translate_instruction
    add r12, rax

    ; Extract the target PC (PC + imm)
    mov edi, [rbp-24]
    push r13
    mov r13d, edi                   ; Temporarily set R13D for extract_j_type
    call extract_j_type             ; EAX = immediate
    pop r13

    add rax, r13                    ; target = current_pc + imm
    mov [r15 + BLOCK_NEXT_PC], rax
    mov dword [r15 + BLOCK_EXIT_TYPE], EXIT_JUMP
    jmp .finish_block

.is_jalr:
    ; JALR - indirect jump (we can't know target statically)
    ; First, emit code to store current PC to rv_pc
    ; Emit: mov qword [r15], current_pc
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0xC7      ; MOV r/m64, imm32
    mov byte [r12+2], 0x07      ; ModRM: [r15]
    mov [r12+3], r13d           ; Current PC (32-bit immediate)
    add r12, 7

    ; Now translate the JALR
    mov edi, [rbp-24]
    mov rsi, r12
    mov rdx, r13                    ; current PC
    call translate_instruction
    add r12, rax

    mov dword [r15 + BLOCK_EXIT_TYPE], EXIT_INDIRECT
    mov qword [r15 + BLOCK_NEXT_PC], 0
    jmp .finish_block

.is_branch:
    ; Conditional branch
    ; First, emit code to store current PC to rv_pc
    ; Emit: mov qword [r15], current_pc
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0xC7      ; MOV r/m64, imm32
    mov byte [r12+2], 0x07      ; ModRM: [r15]
    mov [r12+3], r13d           ; Current PC (32-bit immediate)
    add r12, 7

    ; Now translate the branch
    mov edi, [rbp-24]
    mov rsi, r12
    mov rdx, r13                    ; current PC
    call translate_instruction
    add r12, rax

    ; Extract branch target
    mov edi, [rbp-24]
    push r13
    mov r13d, edi
    call extract_b_type             ; ECX = rs1, EBX = rs2, EAX = imm
    pop r13

    ; Taken target = PC + imm
    add rax, r13
    mov [r15 + BLOCK_TAKEN_PC], rax

    ; Not-taken target = PC + 4
    lea rax, [r13 + 4]
    mov [r15 + BLOCK_NOT_TAKEN_PC], rax

    mov dword [r15 + BLOCK_EXIT_TYPE], EXIT_BRANCH
    jmp .finish_block

.check_ecall:
    ; Check if this is actually ECALL (funct3=0, imm=0)
    ; or EBREAK (funct3=0, imm=1)
    ; CSR instructions (funct3 != 0) are NOT block-enders
    mov eax, [rbp-24]
    shr eax, 12
    and eax, 0x7                    ; funct3
    test eax, eax               ; Test funct3
    jnz .not_block_ender            ; CSR instructions (funct3 != 0) - not block-enders

    ; It's ECALL or EBREAK - these ARE block-enders
    jmp .is_ecall

.not_block_ender:
    ; This is a CSR instruction, translate normally
    mov edi, [rbp-24]
    mov rsi, r12
    mov rdx, r13                    ; current PC
    call translate_instruction
    add r12, rax
    add r13, 4
    jmp .translate_loop

.is_ecall:
    ; ECALL/EBREAK - block-ending instruction
    ; Emit code to store NEXT PC (after ECALL) to rv_pc
    ; This is r13 + 4 (ECALL is always 4 bytes)

    ; Debug: print "E:XXXXXXXX" for ECALL translation with next PC (DISABLED)
    jmp .skip_ecall_debug
    push r13
    push r12
    sub rsp, 48
    mov byte [num_buffer], 'E'
    mov byte [num_buffer+1], ':'
    lea eax, [r13 + 4]
    mov ecx, 8
    lea rsi, [num_buffer+9]
.dbg_ecall_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .dbg_ecall_dig
    add dl, 'A' - 10
    jmp .dbg_ecall_st
.dbg_ecall_dig:
    add dl, '0'
.dbg_ecall_st:
    mov [rsi], dl
    dec rsi
    shr eax, 4
    dec ecx
    jnz .dbg_ecall_hex
    mov byte [num_buffer+10], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 11
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop r12
    pop r13
.skip_ecall_debug:

    lea eax, [r13 + 4]          ; EAX = next PC
    mov byte [r12], 0x49        ; REX.WB
    mov byte [r12+1], 0xC7      ; MOV r/m64, imm32
    mov byte [r12+2], 0x07      ; ModRM: [r15]
    mov [r12+3], eax            ; Next PC (32-bit immediate)
    add r12, 7

    ; Translate the ECALL/EBREAK
    mov edi, [rbp-24]
    mov rsi, r12
    mov rdx, r13                    ; current PC
    call translate_instruction
    add r12, rax

    ; Next PC = current PC + 4
    lea rax, [r13 + 4]
    mov [r15 + BLOCK_NEXT_PC], rax

    mov dword [r15 + BLOCK_EXIT_TYPE], EXIT_ECALL
    jmp .finish_block

;------------------------------------------------------------------------------
; Compressed block-enders
;------------------------------------------------------------------------------
.is_c_j:
    ; C.J - unconditional jump (expands to jal x0, offset)
    ; Unlike JAL, C.J doesn't write a return address (rd=x0)
    ; We need to compute target and emit code to update PC

    ; Extract C.J target from CB format
    ; According to RISC-V spec:
    ; inst[12] = imm[11], inst[11] = imm[4], inst[10:9] = imm[9:8]
    ; inst[8] = imm[10], inst[7] = imm[6], inst[6] = imm[7]
    ; inst[5:3] = imm[3:1], inst[2] = imm[5]
    movzx eax, word [rbp-24]
    xor ecx, ecx                    ; Build immediate in ECX

    ; imm[11] = inst[12]
    mov edx, eax
    shr edx, 12
    and edx, 1
    shl edx, 11
    or ecx, edx

    ; imm[4] = inst[11]
    mov edx, eax
    shr edx, 11
    and edx, 1
    shl edx, 4
    or ecx, edx

    ; imm[9:8] = inst[10:9]
    mov edx, eax
    shr edx, 9
    and edx, 3
    shl edx, 8
    or ecx, edx

    ; imm[10] = inst[8]
    mov edx, eax
    shr edx, 8
    and edx, 1
    shl edx, 10
    or ecx, edx

    ; imm[6] = inst[7]
    mov edx, eax
    shr edx, 7
    and edx, 1
    shl edx, 6
    or ecx, edx

    ; imm[7] = inst[6]
    mov edx, eax
    shr edx, 6
    and edx, 1
    shl edx, 7
    or ecx, edx

    ; imm[3:1] = inst[5:3]
    mov edx, eax
    shr edx, 3
    and edx, 7
    shl edx, 1
    or ecx, edx

    ; imm[5] = inst[2]
    mov edx, eax
    shr edx, 2
    and edx, 1
    shl edx, 5
    or ecx, edx

    ; Sign-extend from bit 11
    test ecx, 0x800
    jz .c_j_no_sign
    or ecx, 0xFFFFF000
.c_j_no_sign:

    ; Target = PC + imm
    movsxd rax, ecx
    add rax, r13                    ; RAX = target PC

    ; Store target in block metadata
    mov [r15 + BLOCK_NEXT_PC], rax
    mov dword [r15 + BLOCK_EXIT_TYPE], EXIT_JUMP

    ; Now emit x86 code to write target PC to [r15]
    ; Emit: mov qword [r15], target_pc (immediate)
    mov byte [r12], 0x49            ; REX.WB
    mov byte [r12+1], 0xC7          ; MOV r/m64, imm32
    mov byte [r12+2], 0x07          ; ModRM: [r15]
    mov [r12+3], eax                ; Target PC (32-bit, sign-extended)
    add r12, 7

    jmp .finish_block

.is_c_branch:
    ; C.BEQZ/C.BNEZ - conditional branch
    ; Must emit code that properly updates PC based on branch outcome

    ; First, emit code to store current PC to [r15]
    mov byte [r12], 0x49
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0x07
    mov [r12+3], r13d
    add r12, 7

    ; Extract branch offset from CB format first (need it for code generation)
    ; imm[8|4:3] = inst[12|11:10], imm[7:6|2:1|5] = inst[6:5|4:3|2]
    movzx eax, word [rbp-24]
    xor ecx, ecx

    ; imm[8] = inst[12] (sign bit)
    mov edx, eax
    shr edx, 12
    and edx, 1
    shl edx, 8
    or ecx, edx

    ; imm[4:3] = inst[11:10]
    mov edx, eax
    shr edx, 10
    and edx, 3
    shl edx, 3
    or ecx, edx

    ; imm[7:6] = inst[6:5]
    mov edx, eax
    shr edx, 5
    and edx, 3
    shl edx, 6
    or ecx, edx

    ; imm[2:1] = inst[4:3]
    mov edx, eax
    shr edx, 3
    and edx, 3
    shl edx, 1
    or ecx, edx

    ; imm[5] = inst[2]
    mov edx, eax
    shr edx, 2
    and edx, 1
    shl edx, 5
    or ecx, edx

    ; Sign-extend from bit 8
    test ecx, 0x100
    jz .c_branch_no_sign
    or ecx, 0xFFFFFE00
.c_branch_no_sign:
    push rcx                    ; Save branch offset

    ; Store metadata for block cache
    movsxd rax, ecx
    add rax, r13
    mov [r15 + BLOCK_TAKEN_PC], rax
    lea rax, [r13 + 2]
    mov [r15 + BLOCK_NOT_TAKEN_PC], rax

    ; Now emit the actual branch code
    ; Get rs1' (in bits 9:7, add 8 for x8-x15)
    movzx eax, word [rbp-24]
    shr eax, 7
    and eax, 0x7
    add eax, 8                  ; rs1 = x8 + rs1'

    ; Emit: mov rax, [rbx + rs1*8]  (load rs1)
    mov byte [r12], 0x48
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x43
    shl eax, 3
    mov byte [r12+3], al
    add r12, 4

    ; Emit: test rax, rax
    mov byte [r12], 0x48
    mov byte [r12+1], 0x85
    mov byte [r12+2], 0xC0
    add r12, 3

    ; Check if BEQZ or BNEZ to emit correct conditional jump
    movzx eax, word [rbp-24]
    shr eax, 13
    and eax, 0x7
    cmp eax, 6
    jne .c_branch_is_bnez

    ; BEQZ: je taken (branch if zero)
    mov byte [r12], 0x74        ; JE rel8
    jmp .c_branch_emit_common

.c_branch_is_bnez:
    ; BNEZ: jne taken (branch if not zero)
    mov byte [r12], 0x75        ; JNE rel8

.c_branch_emit_common:
    ; Jcc +10 (skip not-taken path: mov rdx,2 is 7 bytes + jmp +8 is 2 bytes + nop is 1 byte = 10)
    mov byte [r12+1], 10
    add r12, 2

    ; Not taken: mov rdx, 2 (compressed instruction size)
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0xC2
    mov dword [r12+3], 2
    add r12, 7

    ; jmp +8 (skip taken path - nop is 1 byte + mov rdx,imm is 7 bytes = 8)
    mov byte [r12], 0xEB
    mov byte [r12+1], 8
    add r12, 2

    ; nop for alignment
    mov byte [r12], 0x90
    add r12, 1

    ; Taken: mov rdx, imm
    pop rcx                     ; Restore branch offset
    mov byte [r12], 0x48
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0xC2
    mov [r12+3], ecx            ; branch offset
    add r12, 7

    ; Common: update PC = [r15] + rdx
    ; Emit: mov rax, [r15]
    mov byte [r12], 0x49
    mov byte [r12+1], 0x8B
    mov byte [r12+2], 0x07
    add r12, 3

    ; Emit: add rax, rdx
    mov byte [r12], 0x48
    mov byte [r12+1], 0x01
    mov byte [r12+2], 0xD0
    add r12, 3

    ; Emit: mov [r15], rax
    mov byte [r12], 0x49
    mov byte [r12+1], 0x89
    mov byte [r12+2], 0x07
    add r12, 3

    mov dword [r15 + BLOCK_EXIT_TYPE], EXIT_BRANCH
    jmp .finish_block

.is_c_jr_jalr:
    ; C.JR/C.JALR - indirect jump
    ; Emit code to store current PC
    mov byte [r12], 0x49
    mov byte [r12+1], 0xC7
    mov byte [r12+2], 0x07
    mov [r12+3], r13d
    add r12, 7

    ; Translate the C.JR/C.JALR
    movzx edi, word [rbp-24]
    mov rsi, r12
    mov rdx, r13                    ; current PC
    call translate_compressed
    add r12, rax

    mov dword [r15 + BLOCK_EXIT_TYPE], EXIT_INDIRECT
    mov qword [r15 + BLOCK_NEXT_PC], 0
    jmp .finish_block

.end_block_fallthrough:
    ; Hit instruction limit - fall through to next instruction
    mov [r15 + BLOCK_NEXT_PC], r13
    mov dword [r15 + BLOCK_EXIT_TYPE], EXIT_JUMP

    ; BUG FIX: Emit x86 code to update rv_pc at runtime!
    ; Emit: mov qword [r15], next_pc
    ; REX.W prefix (48), MOV r/m64,imm64 (C7 /0), ModRM for [r15] (07)
    mov byte [r12], 0x49            ; REX.WB for 64-bit and r15
    mov byte [r12+1], 0xC7          ; MOV r/m64, imm32 (sign-extended)
    mov byte [r12+2], 0x07          ; ModRM: [r15]
    mov [r12+3], r13d               ; Store next PC (low 32 bits)
    add r12, 7

.finish_block:
    ; REGISTER CACHING EPILOGUE: DISABLED - adds overhead for loops not using a0-a3
    ; ; Emit: mov [rbx + 80], r8   (4C 89 43 50) - a0
    ; mov byte [r12], 0x4C
    ; ... (disabled for now)

    ; Emit block epilogue: JMP to link_trampoline (can be patched for linking)
    ; Store the jmp address so we can patch it later
    mov [r15 + BLOCK_LINK_ADDR], r12

    ; Emit: jmp rel32 (E9 xx xx xx xx)
    mov byte [r12], 0xE9

    ; Calculate offset: link_trampoline - (jmp_addr + 5)
    lea rax, [r12 + 5]              ; Address after jmp instruction
    lea rcx, [link_trampoline]
    sub rcx, rax                    ; offset = trampoline - (jmp + 5)
    mov [r12 + 1], ecx
    add r12, 5

    ; Calculate and store code size
    mov rax, r12
    sub rax, [r15 + BLOCK_CODE_PTR]
    mov [r15 + BLOCK_CODE_SIZE], eax

    ; Update code buffer allocation pointer
    mov [code_buf_ptr], r12

    ; Mark entry as valid
    mov byte [r15 + BLOCK_VALID], 1

    ; Return pointer to block entry
    mov rax, r15

.already_cached:
    ; RAX already has block pointer
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    add rsp, 64
    pop rbp
    ret

;==============================================================================
; execute_blocks
; Main execution loop - runs blocks until a stopping condition
; Input:  RDI = starting PC
;         RSI = pointer to guest memory
;         RDX = pointer to rv_regs array
;         RCX = pointer to rv_pc
;         R8  = max blocks to execute (0 = unlimited)
;         R9  = pointer to rv_fp_regs array (FP registers)
; Output: RAX = final PC value
;
; "Round and round the blocks we go, where we stop, nobody knows"
;==============================================================================
execute_blocks:
    push rbp
    mov rbp, rsp
    sub rsp, 96                     ; Increased for fp_regs
    push rbx
    push r12
    push r13
    push r14
    push r15

    ; Save parameters FIRST (before any function calls)
    mov [rbp-8], rdi            ; start PC
    mov [rbp-16], rsi           ; guest memory
    mov [rbp-24], rdx           ; rv_regs
    mov [rbp-32], rcx           ; rv_pc pointer
    mov [rbp-40], r8            ; max blocks
    mov [rbp-48], r9            ; fp_regs

    ; DEBUG: Print "EXE:" at entry (DISABLED)
    jmp .skip_exe_debug
    sub rsp, 48
    mov byte [num_buffer], 'E'
    mov byte [num_buffer+1], 'X'
    mov byte [num_buffer+2], 'E'
    mov byte [num_buffer+3], ':'
    mov byte [num_buffer+4], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 5
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
.skip_exe_debug:
    ; END DEBUG

    ; Set initial PC (use saved values after WriteFile)
    mov rax, [rbp-8]        ; start PC from saved
    mov rcx, [rbp-32]       ; rv_pc pointer from saved
    mov [rcx], rax

    ; R12 = block count
    xor r12d, r12d

    ; DEBUG: Print "LP:" before exec_loop (DISABLED)
    jmp .skip_lp_debug
    sub rsp, 48
    mov byte [num_buffer], 'L'
    mov byte [num_buffer+1], 'P'
    mov byte [num_buffer+2], ':'
    mov byte [num_buffer+3], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 4
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
.skip_lp_debug:
    ; END DEBUG

.exec_loop:
    ; Update debug counters
    mov [debug_block_count], r12
    mov rcx, [rbp-32]
    mov rax, [rcx]
    mov [debug_last_pc], rax

    ; Track PC history (circular buffer of last 8)
    mov rdx, [pc_history_idx]
    and rdx, 7                      ; Keep in range 0-7
    lea rcx, [pc_history]
    mov [rcx + rdx*8], rax
    inc qword [pc_history_idx]

    ; Debug: print at strdup return (0x12c28) to see what pointer is returned
    jmp .skip_1d318_debug       ; DISABLED
    cmp rax, 0x12c28              ; strdup return - s10 = a0 (strdup result)
    jne .skip_1d318_debug
.do_1d318_debug:
    push rax
    push rcx
    push rdx
    push rdi
    sub rsp, 48
    ; Print "PC:XXXXXXXX A0:XXXXXXXX A1:XXXXXXXX\n"
    mov byte [num_buffer], 'P'
    mov byte [num_buffer+1], 'C'
    mov byte [num_buffer+2], ':'
    ; Print PC (from stack - was in rax)
    mov rax, [rsp + 48 + 24]    ; Get saved rax (PC) from stack
    mov ecx, 8
    lea rsi, [num_buffer+10]
.zb_a0_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .zb_a0_dig
    add dl, 'A' - 10
    jmp .zb_a0_st
.zb_a0_dig:
    add dl, '0'
.zb_a0_st:
    mov [rsi], dl
    shr rax, 4
    dec rsi
    dec ecx
    jnz .zb_a0_hex
    mov byte [num_buffer+11], ' '
    ; Print a0 (x10)
    mov byte [num_buffer+12], 'A'
    mov byte [num_buffer+13], '0'
    mov byte [num_buffer+14], ':'
    mov rax, [rbp-24]
    mov rax, [rax + 80]         ; a0 = x10, offset 80
    mov ecx, 8
    lea rsi, [num_buffer+22]
.zb_a1_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .zb_a1_dig
    add dl, 'A' - 10
    jmp .zb_a1_st
.zb_a1_dig:
    add dl, '0'
.zb_a1_st:
    mov [rsi], dl
    shr rax, 4
    dec rsi
    dec ecx
    jnz .zb_a1_hex
    mov byte [num_buffer+23], ' '
    ; Print a1 (x11)
    mov byte [num_buffer+24], 'A'
    mov byte [num_buffer+25], '1'
    mov byte [num_buffer+26], ':'
    mov rax, [rbp-24]
    mov rax, [rax + 88]         ; a1 = x11, offset 88
    mov ecx, 8
    lea rsi, [num_buffer+34]
.zb_a2_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .zb_a2_dig
    add dl, 'A' - 10
    jmp .zb_a2_st
.zb_a2_dig:
    add dl, '0'
.zb_a2_st:
    mov [rsi], dl
    shr rax, 4
    dec rsi
    dec ecx
    jnz .zb_a2_hex
    mov byte [num_buffer+35], ' '
    ; Print s2 (x18)
    mov byte [num_buffer+36], 'S'
    mov byte [num_buffer+37], '2'
    mov byte [num_buffer+38], ':'
    mov rax, [rbp-24]
    mov rax, [rax + 144]        ; s2 = x18, offset 144
    mov ecx, 8
    lea rsi, [num_buffer+46]
.zb_s2_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .zb_s2_dig
    add dl, 'A' - 10
    jmp .zb_s2_st
.zb_s2_dig:
    add dl, '0'
.zb_s2_st:
    mov [rsi], dl
    shr rax, 4
    dec rsi
    dec ecx
    jnz .zb_s2_hex
    mov byte [num_buffer+47], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 48
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rdi
    pop rdx
    pop rcx
    pop rax
.skip_1d318_debug:
    ; Debug: print register values at printf entry (DISABLED)
    jmp .skip_1aca4_debug       ; DISABLED
    cmp rax, 0x10a02
    jne .skip_1aca4_debug
    push rax
    push rcx
    push rdx
    push rdi
    sub rsp, 48
    ; Print "PF A0:XXXXXXXX A1:XXXXXXXX A2:XXXXXXXX\n"
    mov byte [num_buffer], 'P'
    mov byte [num_buffer+1], 'F'
    mov byte [num_buffer+2], ' '
    mov byte [num_buffer+3], 'A'
    mov byte [num_buffer+4], '0'
    mov byte [num_buffer+5], ':'
    ; Print a0 (x10)
    mov rax, [rbp-24]           ; rv_regs pointer
    mov rax, [rax + 80]         ; a0 = x10, offset 80
    mov ecx, 8
    lea rsi, [num_buffer+13]
.pf_a0_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .pf_a0_dig
    add dl, 'A' - 10
    jmp .pf_a0_st
.pf_a0_dig:
    add dl, '0'
.pf_a0_st:
    mov [rsi], dl
    shr rax, 4
    dec rsi
    dec ecx
    jnz .pf_a0_hex
    mov byte [num_buffer+14], ' '
    ; Print a1 (x11)
    mov byte [num_buffer+15], 'A'
    mov byte [num_buffer+16], '1'
    mov byte [num_buffer+17], ':'
    mov rax, [rbp-24]
    mov rax, [rax + 88]         ; a1 = x11, offset 88
    mov ecx, 8
    lea rsi, [num_buffer+25]
.pf_a1_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .pf_a1_dig
    add dl, 'A' - 10
    jmp .pf_a1_st
.pf_a1_dig:
    add dl, '0'
.pf_a1_st:
    mov [rsi], dl
    shr rax, 4
    dec rsi
    dec ecx
    jnz .pf_a1_hex
    mov byte [num_buffer+26], ' '
    ; Print a2 (x12)
    mov byte [num_buffer+27], 'A'
    mov byte [num_buffer+28], '2'
    mov byte [num_buffer+29], ':'
    mov rax, [rbp-24]
    mov rax, [rax + 96]         ; a2 = x12, offset 96
    mov ecx, 8
    lea rsi, [num_buffer+37]
.pf_a2_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .pf_a2_dig
    add dl, 'A' - 10
    jmp .pf_a2_st
.pf_a2_dig:
    add dl, '0'
.pf_a2_st:
    mov [rsi], dl
    shr rax, 4
    dec rsi
    dec ecx
    jnz .pf_a2_hex
    mov byte [num_buffer+38], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 39
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rdi
    pop rdx
    pop rcx
    pop rax
.skip_1aca4_debug:
    ; Debug: print va_list pointer and contents at vfprintf entry (DISABLED)
    jmp .skip_vfprintf_debug    ; DISABLED
    cmp rax, 0x10814
    jne .skip_vfprintf_debug
    push rax
    push rcx
    push rdx
    push rdi
    push rsi
    sub rsp, 48
    ; Print "VL:XXXXXXXX V0:XXXXXXXX V1:XXXXXXXX\n"
    mov byte [num_buffer], 'V'
    mov byte [num_buffer+1], 'L'
    mov byte [num_buffer+2], ':'
    ; Get a2 (va_list pointer)
    mov rax, [rbp-24]           ; rv_regs pointer
    mov rsi, [rax + 96]         ; a2 = va_list pointer (guest addr)
    ; Print va_list pointer
    mov rax, rsi
    mov ecx, 8
    lea rdi, [num_buffer+10]
.vf_vl_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .vf_vl_dig
    add dl, 'A' - 10
    jmp .vf_vl_st
.vf_vl_dig:
    add dl, '0'
.vf_vl_st:
    mov [rdi], dl
    shr rax, 4
    dec rdi
    dec ecx
    jnz .vf_vl_hex
    mov byte [num_buffer+11], ' '
    ; Convert guest addr to host and dereference
    add rsi, [rbp-16]           ; + guest_memory base
    ; Print V0
    mov byte [num_buffer+12], 'V'
    mov byte [num_buffer+13], '0'
    mov byte [num_buffer+14], ':'
    mov rax, [rsi]              ; [va_list+0]
    mov ecx, 8
    lea rdi, [num_buffer+22]
.vf_v0_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .vf_v0_dig
    add dl, 'A' - 10
    jmp .vf_v0_st
.vf_v0_dig:
    add dl, '0'
.vf_v0_st:
    mov [rdi], dl
    shr rax, 4
    dec rdi
    dec ecx
    jnz .vf_v0_hex
    mov byte [num_buffer+23], ' '
    ; Print V1
    mov byte [num_buffer+24], 'V'
    mov byte [num_buffer+25], '1'
    mov byte [num_buffer+26], ':'
    mov rax, [rsi+8]            ; [va_list+8]
    mov ecx, 8
    lea rdi, [num_buffer+34]
.vf_v1_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .vf_v1_dig
    add dl, 'A' - 10
    jmp .vf_v1_st
.vf_v1_dig:
    add dl, '0'
.vf_v1_st:
    mov [rdi], dl
    shr rax, 4
    dec rdi
    dec ecx
    jnz .vf_v1_hex
    mov byte [num_buffer+35], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 36
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rax
.skip_vfprintf_debug:
    ; Debug: print a6 at %p handler (DISABLED)
    jmp .skip_ptr_debug         ; DISABLED
    cmp rax, 0x10988
    jne .skip_ptr_debug
    push rax
    push rcx
    push rdx
    push rdi
    push rsi
    sub rsp, 48
    ; Print "PTR A6:XXXXXXXX [A6]:XXXXXXXX\n"
    mov byte [num_buffer], 'P'
    mov byte [num_buffer+1], 'T'
    mov byte [num_buffer+2], 'R'
    mov byte [num_buffer+3], ' '
    mov byte [num_buffer+4], 'A'
    mov byte [num_buffer+5], '6'
    mov byte [num_buffer+6], ':'
    ; Get a6 (x16)
    mov rax, [rbp-24]           ; rv_regs pointer
    mov rsi, [rax + 128]        ; a6 = x16, offset 128
    ; Print a6
    mov rax, rsi
    mov ecx, 8
    lea rdi, [num_buffer+14]
.ptr_a6_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .ptr_a6_dig
    add dl, 'A' - 10
    jmp .ptr_a6_st
.ptr_a6_dig:
    add dl, '0'
.ptr_a6_st:
    mov [rdi], dl
    shr rax, 4
    dec rdi
    dec ecx
    jnz .ptr_a6_hex
    mov byte [num_buffer+15], ' '
    ; Dereference [a6] if valid
    mov byte [num_buffer+16], '['
    mov byte [num_buffer+17], 'A'
    mov byte [num_buffer+18], '6'
    mov byte [num_buffer+19], ']'
    mov byte [num_buffer+20], ':'
    add rsi, [rbp-16]           ; convert to host addr
    mov rax, [rsi]              ; load 64-bit value
    mov ecx, 8
    lea rdi, [num_buffer+28]
.ptr_val_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .ptr_val_dig
    add dl, 'A' - 10
    jmp .ptr_val_st
.ptr_val_dig:
    add dl, '0'
.ptr_val_st:
    mov [rdi], dl
    shr rax, 4
    dec rdi
    dec ecx
    jnz .ptr_val_hex
    mov byte [num_buffer+29], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 30
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rsi
    pop rdi
    pop rdx
    pop rcx
    pop rax
.skip_ptr_debug:
    ; Debug: print s9 after fputs returns (DISABLED)
    jmp .skip_s9_debug          ; DISABLED
    cmp rax, 0x1099a
    jne .skip_s9_debug
    push rax
    push rcx
    push rdx
    push rdi
    sub rsp, 48
    ; Print "S9:XXXXXXXX\n"
    mov byte [num_buffer], 'S'
    mov byte [num_buffer+1], '9'
    mov byte [num_buffer+2], ':'
    mov rax, [rbp-24]           ; rv_regs pointer
    mov rax, [rax + 200]        ; s9 = x25, offset 200
    mov ecx, 8
    lea rdi, [num_buffer+10]
.s9_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .s9_dig
    add dl, 'A' - 10
    jmp .s9_st
.s9_dig:
    add dl, '0'
.s9_st:
    mov [rdi], dl
    shr rax, 4
    dec rdi
    dec ecx
    jnz .s9_hex
    mov byte [num_buffer+11], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 12
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rdi
    pop rdx
    pop rcx
    pop rax
.skip_s9_debug:
    ; Debug: print a0 at print_uint entry (DISABLED)
    jmp .skip_pu_debug          ; DISABLED
    cmp rax, 0x10126
    jne .skip_pu_debug
    push rax
    push rcx
    push rdx
    push rdi
    sub rsp, 48
    ; Print "PU:XXXXXXXX\n"
    mov byte [num_buffer], 'P'
    mov byte [num_buffer+1], 'U'
    mov byte [num_buffer+2], ':'
    mov rax, [rbp-24]           ; rv_regs pointer
    mov rax, [rax + 80]         ; a0 = x10
    mov ecx, 8
    lea rdi, [num_buffer+10]
.pu_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .pu_dig
    add dl, 'A' - 10
    jmp .pu_st
.pu_dig:
    add dl, '0'
.pu_st:
    mov [rdi], dl
    shr rax, 4
    dec rdi
    dec ecx
    jnz .pu_hex
    mov byte [num_buffer+11], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 12
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rdi
    pop rdx
    pop rcx
    pop rax
.skip_pu_debug:
    ; Debug: print a0 at loop start (DISABLED)
    jmp .skip_remu_debug        ; DISABLED
    cmp rax, 0x1013a
    jne .skip_remu_debug
    push rax
    push rcx
    push rdx
    push rdi
    sub rsp, 48
    ; Print "RM:XXXXXXXX\n"
    mov byte [num_buffer], 'R'
    mov byte [num_buffer+1], 'M'
    mov byte [num_buffer+2], ':'
    mov rax, [rbp-24]           ; rv_regs pointer
    mov rax, [rax + 80]         ; a0 = x10
    mov ecx, 8
    lea rdi, [num_buffer+10]
.rm_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .rm_dig
    add dl, 'A' - 10
    jmp .rm_st
.rm_dig:
    add dl, '0'
.rm_st:
    mov [rdi], dl
    shr rax, 4
    dec rdi
    dec ecx
    jnz .rm_hex
    mov byte [num_buffer+11], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 12
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rdi
    pop rdx
    pop rcx
    pop rax
.skip_remu_debug:
    ; Debug: print PC, ra, sp for blocks 1-100 (ENABLED for debug)
    jmp .no_pc_print  ; DISABLED
    cmp r12, 1
    jb .no_pc_print
    cmp r12, 100
    ja .no_pc_print
    ; Print "BXXXX P:XXXXXX R:XXXXXXXX S:XXXXXXXX\n"
    push r12
    sub rsp, 48
    ; Block number first
    mov byte [num_buffer], 'B'
    mov eax, r12d
    mov edi, 4
    lea rsi, [num_buffer+4]
.bn_loop:
    mov ecx, eax
    and ecx, 0xF
    add cl, '0'
    cmp cl, '9'
    jbe .bn_ok
    add cl, 'A' - '0' - 10
.bn_ok:
    mov [rsi], cl
    dec rsi
    shr eax, 4
    dec edi
    jnz .bn_loop
    mov byte [num_buffer+5], ' '
    mov byte [num_buffer+6], 'P'
    mov byte [num_buffer+7], ':'
    mov rcx, [rbp-32]
    mov eax, [rcx]                  ; Get low 32 bits of PC
    ; Print 6 hex digits
    mov edi, 6
    lea rsi, [num_buffer+13]
.pc_hex_loop:
    mov ecx, eax
    and ecx, 0xF
    cmp cl, 10
    jb .pc_hex_digit
    add cl, 'A' - 10
    jmp .pc_hex_store
.pc_hex_digit:
    add cl, '0'
.pc_hex_store:
    mov [rsi], cl
    dec rsi
    shr eax, 4
    dec edi
    jnz .pc_hex_loop
    ; Add " R:" and ra value (8 hex digits)
    mov byte [num_buffer+14], ' '
    mov byte [num_buffer+15], 'R'
    mov byte [num_buffer+16], ':'
    mov rax, [rbp-24]               ; Get rv_regs pointer (saved earlier)
    mov rax, [rax + 8]              ; ra = x1, offset 8
    mov edi, 8
    lea rsi, [num_buffer+24]
.ra_hex_loop:
    mov ecx, eax
    and ecx, 0xF
    cmp cl, 10
    jb .ra_hex_digit
    add cl, 'A' - 10
    jmp .ra_hex_store
.ra_hex_digit:
    add cl, '0'
.ra_hex_store:
    mov [rsi], cl
    dec rsi
    shr eax, 4
    dec edi
    jnz .ra_hex_loop
    ; Add " S:" and sp value (8 hex digits)
    mov byte [num_buffer+25], ' '
    mov byte [num_buffer+26], 'S'
    mov byte [num_buffer+27], ':'
    mov rax, [rbp-24]               ; Get rv_regs pointer
    mov rax, [rax + 16]             ; sp = x2, offset 16
    mov edi, 8
    lea rsi, [num_buffer+35]
.sp_hex_loop:
    mov ecx, eax
    and ecx, 0xF
    cmp cl, 10
    jb .sp_hex_digit
    add cl, 'A' - 10
    jmp .sp_hex_store
.sp_hex_digit:
    add cl, '0'
.sp_hex_store:
    mov [rsi], cl
    dec rsi
    shr eax, 4
    dec edi
    jnz .sp_hex_loop
    mov byte [num_buffer+36], 10    ; newline
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 37
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop r12
.no_pc_print:

    ; Check block limit
    mov rax, [rbp-40]
    test rax, rax
    jz .no_limit
    cmp r12, rax
    jge .done
.no_limit:
    inc r12

    ; Clear ecall_pending flag before execution
    mov byte [ecall_pending], 0

    ; Get current PC
    mov rcx, [rbp-32]
    mov rdi, [rcx]              ; RDI = current PC

    ; Debug: print PC for block 9256
    cmp r12, 999999999
    jne .skip_pc_9256
    push rdi                    ; Save RDI (PC)
    sub rsp, 48
    mov byte [num_buffer], 'X'
    mov byte [num_buffer+1], ':'
    mov eax, edi                ; Low 32 bits of PC
    mov ecx, 8
    lea rsi, [num_buffer+9]
.pc9256_loop:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .pc9256_dig
    add dl, 'A' - 10
    jmp .pc9256_st
.pc9256_dig:
    add dl, '0'
.pc9256_st:
    mov [rsi], dl
    dec rsi
    shr eax, 4
    dec ecx
    jnz .pc9256_loop
    mov byte [num_buffer+10], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 11
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rdi                     ; Restore RDI (PC)
.skip_pc_9256:

    ; Check for NULL PC (bad return address)
    test rdi, rdi
    jz .null_pc_error

    ; Translate/lookup block
    mov rsi, [rbp-16]           ; guest memory
    call translate_block

    ; DEBUG: Print "TB:" after translate_block returns (DISABLED)
    jmp .skip_tb_debug
    push rax
    sub rsp, 48
    mov byte [num_buffer], 'T'
    mov byte [num_buffer+1], 'B'
    mov byte [num_buffer+2], ':'
    mov byte [num_buffer+3], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 4
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rax
.skip_tb_debug:
    ; END DEBUG

    test rax, rax
    jz .xlate_failed            ; No block = stop

    mov [rbp-56], rax           ; Save block pointer (was -48, moved to avoid fp_regs collision)

    ; Debug: for blocks 9253-9258, print exit type (DISABLED)
    jmp .skip_exit_debug
    cmp r12, 9253
    jb .skip_exit_debug
    cmp r12, 9258
    ja .skip_exit_debug
    ; Print "T:X" where X is exit type digit
    push rax
    sub rsp, 48
    mov byte [num_buffer], 'T'
    mov byte [num_buffer+1], ':'
    mov eax, [rax + BLOCK_EXIT_TYPE]
    add al, '0'
    mov [num_buffer+2], al
    mov byte [num_buffer+3], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 4
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rax
.skip_exit_debug:

    ; Set up execution state
    mov rbx, [rbp-24]           ; RBX = rv_regs
    mov r15, [rbp-32]           ; R15 = rv_pc pointer
    mov r14, [rbp-16]           ; R14 = guest memory (for loads/stores)
    mov r13, [rbp-48]           ; R13 = fp_regs (for FP operations)

    ; TEST 1: Verify store/load works with r14 at different offsets (DISABLED)
    jmp .skip_test1                     ; DISABLED
    ; Only do this once (check if already done)
    cmp byte [r14 + 0x100], 'T'         ; Check test marker at small offset
    je .skip_test1
    mov byte [r14 + 0x100], 'T'         ; Set test marker

    ; Test 1a: small offset (should work)
    mov byte [r14 + 0x1000], 'A'
    movzx eax, byte [r14 + 0x1000]
    mov [num_buffer+10], al             ; Should be 'A'

    ; Test 1b: medium offset
    mov byte [r14 + 0x50000], 'B'
    movzx eax, byte [r14 + 0x50000]
    mov [num_buffer+11], al             ; Should be 'B'

    ; Test 1c: exact address Doom uses (0x6FE020)
    mov byte [r14 + 0x6FE020], 'C'
    movzx eax, byte [r14 + 0x6FE020]
    mov [num_buffer+12], al             ; Should be 'C'

    ; Print result: "TS:ABC" where A=0x1000, B=0x50000, C=0x6FE020
    sub rsp, 48
    mov byte [num_buffer], 'T'
    mov byte [num_buffer+1], 'S'
    mov byte [num_buffer+2], ':'
    ; Results already at num_buffer+10,+11,+12,+13 (newline)
    ; Copy them to positions 3,4,5,6
    mov al, [num_buffer+10]
    mov [num_buffer+3], al
    mov al, [num_buffer+11]
    mov [num_buffer+4], al
    mov al, [num_buffer+12]
    mov [num_buffer+5], al
    mov byte [num_buffer+6], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 7
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
.skip_test1:

    ; TEST 2: Verify store via register (DISABLED)
    jmp .skip_store_test                ; DISABLED
    ; Only do this once - check if marker at 0x101 is set
    cmp byte [r14 + 0x101], 'R'
    je .skip_store_test

    mov byte [r14 + 0x101], 'R'         ; Set marker

    ; Set rv_regs[10] (x10) = 0x2000 (destination address)
    ; Set rv_regs[11] (x11) = 'D' (value to store)
    ; Then do what translated SB would: load x10 into rax, load x11 into rcx, store [r14+rax], cl
    mov qword [rbx + 10*8], 0x2000      ; x10 = address
    mov qword [rbx + 11*8], 'D'         ; x11 = value 'D'

    ; Simulate translated SB: sb x11, 0(x10)
    mov rax, [rbx + 10*8]               ; rax = x10 value = 0x2000
    ; add rax, 0                        ; immediate = 0 (skip since zero)
    mov rcx, [rbx + 11*8]               ; rcx = x11 value = 'D'
    mov [r14 + rax], cl                 ; store byte: [guest_mem + 0x2000] = 'D'

    ; Read it back and print "TR:D" if successful
    movzx eax, byte [r14 + 0x2000]
    mov [num_buffer+13], al             ; Save result

    sub rsp, 48
    mov byte [num_buffer], 'T'
    mov byte [num_buffer+1], 'R'
    mov byte [num_buffer+2], ':'
    mov al, [num_buffer+13]
    mov [num_buffer+3], al
    mov byte [num_buffer+4], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 5
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48

    ; Clean up x10/x11 (set back to 0)
    mov qword [rbx + 10*8], 0
    mov qword [rbx + 11*8], 0

.skip_store_test:

    ; DEBUG: Print "ST:" after setup (DISABLED)
    jmp .skip_st_debug
    push rax
    sub rsp, 48
    mov byte [num_buffer], 'S'
    mov byte [num_buffer+1], 'T'
    mov byte [num_buffer+2], ':'
    mov byte [num_buffer+3], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 4
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rax
.skip_st_debug:
    ; END DEBUG

    ; Debug: for block 9256, print r15 value
    cmp r12, 999999999
    jne .skip_r15_debug
    push rax
    sub rsp, 48
    mov byte [num_buffer], 'R'
    mov byte [num_buffer+1], ':'
    mov rax, r15
    mov ecx, 16
    lea rsi, [num_buffer+17]
.dbg_r15_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .dbg_r15_dig
    add dl, 'A' - 10
    jmp .dbg_r15_st
.dbg_r15_dig:
    add dl, '0'
.dbg_r15_st:
    mov [rsi], dl
    dec rsi
    shr rax, 4
    dec ecx
    jnz .dbg_r15_hex
    mov byte [num_buffer+18], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 19
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rax
.skip_r15_debug:

    ; Get code pointer and execute
    mov rax, [rbp-56]           ; Block pointer (was -48, moved to -56)
    mov rax, [rax + BLOCK_CODE_PTR]

    ; DEBUG: Print "CP:" after getting code pointer (DISABLED)
    jmp .skip_cp_debug
    push rax
    sub rsp, 48
    mov byte [num_buffer], 'C'
    mov byte [num_buffer+1], 'P'
    mov byte [num_buffer+2], ':'
    mov byte [num_buffer+3], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 4
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rax
.skip_cp_debug:
    ; END DEBUG

    ; Debug: print block count every 2000 blocks (DISABLED for performance)
    ; To re-enable: change jmp to jne below
    jmp .skip_blk_print
    push rax
    mov eax, r12d
    mov edx, 0
    mov ecx, 2000
    div ecx                     ; eax = r12 / 2000, edx = r12 % 2000
    test edx, edx
    jnz .skip_blk_print_inner
    ; Print block number
    sub rsp, 48
    mov byte [num_buffer], 'B'
    mov byte [num_buffer+1], ':'
    mov eax, r12d               ; Reload r12 for printing
    mov edi, 6
    lea rsi, [num_buffer+7]
.blk_hex:
    mov ecx, eax
    and ecx, 0xF
    add cl, '0'
    cmp cl, '9'
    jbe .blk_ok
    add cl, 'A' - '0' - 10
.blk_ok:
    mov [rsi], cl
    dec rsi
    shr eax, 4
    dec edi
    jnz .blk_hex
    mov byte [num_buffer+8], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 9
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
.skip_blk_print_inner:
    pop rax
.skip_blk_print:

    ; Debug: print block# and PC for blocks 2424-2427
    ; DISABLED to reduce noise
    jmp .exec_block_now
    cmp r12d, 2424
    jb .exec_block_now
    cmp r12d, 2427
    ja .exec_block_now
    push rax                    ; Save code pointer
    ; Print B:XXXXX PC:XXXXXXXX
    sub rsp, 48
    mov byte [num_buffer], 'B'
    mov byte [num_buffer+1], ':'
    ; Print block number (5 hex digits)
    mov eax, r12d
    mov edi, 5
    lea rsi, [num_buffer+6]
.dbg_bn_hex:
    mov ecx, eax
    and ecx, 0xF
    add cl, '0'
    cmp cl, '9'
    jbe .dbg_bn_ok
    add cl, 'A' - '0' - 10
.dbg_bn_ok:
    mov [rsi], cl
    dec rsi
    shr eax, 4
    dec edi
    jnz .dbg_bn_hex
    mov byte [num_buffer+7], ' '
    mov byte [num_buffer+8], 'P'
    mov byte [num_buffer+9], 'C'
    mov byte [num_buffer+10], ':'
    mov rcx, [rbp-32]           ; Get PC pointer
    mov rax, [rcx]              ; Get current PC
    ; Print low 32 bits at offset 11-18
    mov edi, 8
    lea rsi, [num_buffer+18]
.gm_hex:
    mov ecx, eax
    and ecx, 0xF
    add cl, '0'
    cmp cl, '9'
    jbe .gm_ok
    add cl, 'A' - '0' - 10
.gm_ok:
    mov [rsi], cl
    dec rsi
    shr eax, 4
    dec edi
    jnz .gm_hex
    mov byte [num_buffer+19], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 20
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
.no_r14_debug:
    pop rax                     ; Restore code pointer
.exec_block_now:
    ; Debug: print "X" marker every time block 2425 is about to execute (DISABLED)
    jmp .skip_before_debug
    cmp r12, 2425
    jne .skip_before_debug
    push rax
    sub rsp, 48
    inc dword [block_2425_execcount]
    ; Just print "X" followed by newline for minimal trace
    mov byte [num_buffer], 'X'
    mov byte [num_buffer+1], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 2
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rax
    ; Skip x86 code print for now
    jmp .skip_before_debug
    ; Only print x86 code on first execution
    cmp dword [block_2425_execcount], 1
    jne .skip_before_debug
    push rax                    ; Save code pointer
    mov rdi, rax                ; RDI = code pointer for printing bytes
    sub rsp, 48
    mov byte [num_buffer], '>'
    ; Print first 100 bytes as hex
    mov ecx, 100
    lea rsi, [num_buffer+1]
.print_code_bytes:
    test ecx, ecx
    jz .done_code_bytes
    movzx eax, byte [rdi]
    push rcx
    push rdi
    ; Print high nibble
    mov edx, eax
    shr edx, 4
    cmp dl, 10
    jb .code_dig1
    add dl, 'A' - 10
    jmp .code_st1
.code_dig1:
    add dl, '0'
.code_st1:
    mov [rsi], dl
    inc rsi
    ; Print low nibble
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .code_dig2
    add dl, 'A' - 10
    jmp .code_st2
.code_dig2:
    add dl, '0'
.code_st2:
    mov [rsi], dl
    inc rsi
    pop rdi
    pop rcx
    inc rdi
    dec ecx
    jmp .print_code_bytes
.done_code_bytes:
    mov byte [rsi], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 202                ; 1 + 100*2 + 1
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    ; Also print s4 value before execution
    mov byte [num_buffer], 'S'
    mov byte [num_buffer+1], '4'
    mov byte [num_buffer+2], ':'
    mov rax, [rbx + 0xA0]       ; s4 = x20, offset = 160 = 0xA0
    mov ecx, 16
    lea rsi, [num_buffer+18]
.s4_before_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .s4b_dig
    add dl, 'A' - 10
    jmp .s4b_st
.s4b_dig:
    add dl, '0'
.s4b_st:
    mov [rsi], dl
    dec rsi
    shr rax, 4
    dec ecx
    jnz .s4_before_hex
    mov byte [num_buffer+19], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 20
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rax                     ; Restore code pointer
.skip_before_debug:
    ; Debug: print marker before block execution for blocks 9255-9258 (DISABLED)
    jmp .skip_pre_call
    cmp r12, 9255
    jb .skip_pre_call
    cmp r12, 9258
    ja .skip_pre_call
    push rax
    sub rsp, 48
    mov byte [num_buffer], '>'
    mov byte [num_buffer+1], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 2
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rax
.skip_pre_call:
    ; Debug: dump x86 code for blocks 9250-9256 before execution (DISABLED)
    jmp .skip_code_dump
    cmp r12, 9250
    jb .skip_code_dump
    cmp r12, 9256
    ja .skip_code_dump
    push rax
    push rdi
    push rcx
    sub rsp, 48
    ; Print "CP:" and code pointer value first
    mov byte [num_buffer], 'C'
    mov byte [num_buffer+1], 'P'
    mov byte [num_buffer+2], ':'
    mov rax, [rsp+64]           ; Get saved rax (code pointer)
    mov ecx, 16
    lea rsi, [num_buffer+18]
.cp_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .cp_dig
    add dl, 'A' - 10
    jmp .cp_st
.cp_dig:
    add dl, '0'
.cp_st:
    mov [rsi], dl
    dec rsi
    shr rax, 4
    dec ecx
    jnz .cp_hex
    mov byte [num_buffer+19], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 20
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    ; Dump first 64 bytes of code
    ; Stack: sub 48, then rcx at +48, rdi at +56, rax at +64
    mov rdi, [rsp+64]           ; Get saved rax (code pointer)
    mov ecx, 64
    lea rsi, [num_buffer]
.cd_loop:
    push rcx
    push rdi
    movzx edx, byte [rdi]
    push rdx
    shr edx, 4
    cmp dl, 10
    jb .cd_d1
    add dl, 'A' - 10
    jmp .cd_s1
.cd_d1:
    add dl, '0'
.cd_s1:
    mov [rsi], dl
    inc rsi
    pop rdx
    and edx, 0xF
    cmp dl, 10
    jb .cd_d2
    add dl, 'A' - 10
    jmp .cd_s2
.cd_d2:
    add dl, '0'
.cd_s2:
    mov [rsi], dl
    inc rsi
    pop rdi
    pop rcx
    inc rdi
    dec ecx
    jnz .cd_loop
    mov byte [rsi], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 129                ; 64*2 + 1
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    ; For block 9255, also print r14 and s4 values
    mov rax, [rsp+64]           ; Get saved rax (restore for comparison)
    cmp r12, 9255
    jne .skip_reg_dump
    ; Print "R14:" and r14 value
    mov byte [num_buffer], 'R'
    mov byte [num_buffer+1], '1'
    mov byte [num_buffer+2], '4'
    mov byte [num_buffer+3], ':'
    mov rax, r14
    mov ecx, 16
    lea rsi, [num_buffer+19]
.r14_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .r14_dig
    add dl, 'A' - 10
    jmp .r14_st
.r14_dig:
    add dl, '0'
.r14_st:
    mov [rsi], dl
    dec rsi
    shr rax, 4
    dec ecx
    jnz .r14_hex
    mov byte [num_buffer+20], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 21
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    ; Print "S4:" and s4 value (x20, offset 0xA0)
    mov byte [num_buffer], 'S'
    mov byte [num_buffer+1], '4'
    mov byte [num_buffer+2], ':'
    mov rax, [rbx + 0xA0]       ; x20 = s4
    mov ecx, 16
    lea rsi, [num_buffer+18]
.s4_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .s4_dig
    add dl, 'A' - 10
    jmp .s4_st
.s4_dig:
    add dl, '0'
.s4_st:
    mov [rsi], dl
    dec rsi
    shr rax, 4
    dec ecx
    jnz .s4_hex
    mov byte [num_buffer+19], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 20
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
.skip_reg_dump:
    ; For blocks 9253-9255, dump RISC-V instructions from guest memory
    cmp r12, 9253
    jb .skip_rv_dump
    cmp r12, 9255
    ja .skip_rv_dump
    ; Print "RV:" header
    mov byte [num_buffer], 'R'
    mov byte [num_buffer+1], 'V'
    mov byte [num_buffer+2], ':'
    ; Get block start PC - use known PCs for each block
    cmp r12, 9253
    jne .rv_not_9253
    mov rax, 0x1086E
    jmp .rv_got_pc
.rv_not_9253:
    cmp r12, 9254
    jne .rv_not_9254
    mov rax, 0x1084A
    jmp .rv_got_pc
.rv_not_9254:
    mov rax, 0x10852            ; block 9255
.rv_got_pc:
    add rax, r14                ; rax = guest_memory + PC
    ; Dump 48 bytes of RISC-V code
    mov ecx, 48
    lea rsi, [num_buffer+3]
.rv_loop:
    push rcx
    push rax
    movzx edx, byte [rax]
    push rdx
    shr edx, 4
    cmp dl, 10
    jb .rv_d1
    add dl, 'A' - 10
    jmp .rv_s1
.rv_d1:
    add dl, '0'
.rv_s1:
    mov [rsi], dl
    inc rsi
    pop rdx
    and edx, 0xF
    cmp dl, 10
    jb .rv_d2
    add dl, 'A' - 10
    jmp .rv_s2
.rv_d2:
    add dl, '0'
.rv_s2:
    mov [rsi], dl
    inc rsi
    pop rax
    pop rcx
    inc rax
    dec ecx
    jnz .rv_loop
    mov byte [rsi], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 100                ; 3 + 48*2 + 1
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
.skip_rv_dump:
    add rsp, 48
    pop rcx
    pop rdi
    pop rax
.skip_code_dump:

    ; Debug: print ra and r15 BEFORE block 95 or 150 (DISABLED for perf)
    jmp .skip_ra_before
    cmp r12, 150
    je .do_ra_before
    cmp r12, 95
    jne .skip_ra_before
.do_ra_before:
    push rax
    push rcx
    sub rsp, 48
    ; Print "BPC:XXXXXX ET:X SZ:XXX" (block start PC, exit type, code size)
    push rdi
    mov rdi, [rbp-56]           ; block pointer (was -48, moved to -56)
    mov byte [num_buffer], 'B'
    mov byte [num_buffer+1], 'P'
    mov byte [num_buffer+2], 'C'
    mov byte [num_buffer+3], ':'
    mov rax, [rdi + 8]          ; BLOCK_START_PC at offset 8
    mov ecx, 6
    lea rsi, [num_buffer+9]
.bpc_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .bpc_d
    add dl, 'A' - 10
    jmp .bpc_s
.bpc_d:
    add dl, '0'
.bpc_s:
    mov [rsi], dl
    shr rax, 4
    dec rsi
    dec ecx
    jnz .bpc_hex
    mov byte [num_buffer+10], ' '
    mov byte [num_buffer+11], 'E'
    mov byte [num_buffer+12], 'T'
    mov byte [num_buffer+13], ':'
    mov eax, [rdi + 28]         ; BLOCK_EXIT_TYPE at offset 28
    add al, '0'
    mov [num_buffer+14], al
    mov byte [num_buffer+15], ' '
    mov byte [num_buffer+16], 'S'
    mov byte [num_buffer+17], 'Z'
    mov byte [num_buffer+18], ':'
    mov eax, [rdi + 24]         ; BLOCK_CODE_SIZE at offset 24
    ; Print as decimal (3 digits)
    mov ecx, 100
    xor edx, edx
    div ecx
    add al, '0'
    mov [num_buffer+19], al
    mov eax, edx
    mov ecx, 10
    xor edx, edx
    div ecx
    add al, '0'
    mov [num_buffer+20], al
    add dl, '0'
    mov [num_buffer+21], dl
    mov byte [num_buffer+22], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 23
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    pop rdi
    ; Now print RB:
    mov byte [num_buffer], 'R'
    mov byte [num_buffer+1], 'B'
    mov byte [num_buffer+2], ':'
    mov rax, [rbx + 1*8]        ; ra = x1
    mov ecx, 8
    lea rsi, [num_buffer+10]
.rab_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .rab_d
    add dl, 'A' - 10
    jmp .rab_s
.rab_d:
    add dl, '0'
.rab_s:
    mov [rsi], dl
    shr rax, 4
    dec rsi
    dec ecx
    jnz .rab_hex
    ; Add " r15:" and r15 value
    mov byte [num_buffer+11], ' '
    mov byte [num_buffer+12], 'r'
    mov byte [num_buffer+13], '1'
    mov byte [num_buffer+14], '5'
    mov byte [num_buffer+15], ':'
    mov rax, r15
    mov ecx, 16
    lea rsi, [num_buffer+31]
.r15_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .r15_d
    add dl, 'A' - 10
    jmp .r15_s
.r15_d:
    add dl, '0'
.r15_s:
    mov [rsi], dl
    shr rax, 4
    dec rsi
    dec ecx
    jnz .r15_hex
    ; Add " pc:" and [r15] value
    mov byte [num_buffer+32], ' '
    mov byte [num_buffer+33], 'p'
    mov byte [num_buffer+34], 'c'
    mov byte [num_buffer+35], ':'
    mov rax, [r15]              ; Current PC
    mov ecx, 8
    lea rsi, [num_buffer+43]
.pc_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .pc_d
    add dl, 'A' - 10
    jmp .pc_s
.pc_d:
    add dl, '0'
.pc_s:
    mov [rsi], dl
    shr rax, 4
    dec rsi
    dec ecx
    jnz .pc_hex
    mov byte [num_buffer+44], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 45
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    ; Print "SP:XXXXXXXX STK8:XXXXXXXX" (sp value and [sp+8] in guest memory)
    mov byte [num_buffer], 'S'
    mov byte [num_buffer+1], 'P'
    mov byte [num_buffer+2], ':'
    mov rax, [rbx + 2*8]        ; sp = x2
    push rax                    ; Save sp for later
    mov ecx, 8
    lea rsi, [num_buffer+10]
.sp_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .sp_d
    add dl, 'A' - 10
    jmp .sp_s
.sp_d:
    add dl, '0'
.sp_s:
    mov [rsi], dl
    shr rax, 4
    dec rsi
    dec ecx
    jnz .sp_hex
    mov byte [num_buffer+11], ' '
    mov byte [num_buffer+12], 'S'
    mov byte [num_buffer+13], 'T'
    mov byte [num_buffer+14], 'K'
    mov byte [num_buffer+15], '8'
    mov byte [num_buffer+16], ':'
    pop rax                     ; Get sp back
    add rax, 8                  ; sp + 8
    add rax, r14                ; guest memory base
    mov rax, [rax]              ; Load [sp+8] from guest memory
    mov ecx, 8
    lea rsi, [num_buffer+24]
.stk8_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .stk8_d
    add dl, 'A' - 10
    jmp .stk8_s
.stk8_d:
    add dl, '0'
.stk8_s:
    mov [rsi], dl
    shr rax, 4
    dec rsi
    dec ecx
    jnz .stk8_hex
    mov byte [num_buffer+25], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 26
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    ; Also dump first 32 bytes of block code
    mov byte [num_buffer], 'C'
    mov byte [num_buffer+1], 'D'
    mov byte [num_buffer+2], ':'
    mov rdi, [rsp+56]           ; Get saved rax (block code ptr) from stack
    add rdi, 200                ; Start from byte 200
    mov rcx, 41                 ; Dump last 41 bytes (200-241)
    lea rsi, [num_buffer+3]
.blk_cd_loop:
    push rcx
    push rdi
    movzx eax, byte [rdi]
    mov edx, eax
    shr edx, 4
    cmp dl, 10
    jb .blk_cd_d1
    add dl, 'A' - 10
    jmp .blk_cd_s1
.blk_cd_d1:
    add dl, '0'
.blk_cd_s1:
    mov [rsi], dl
    inc rsi
    and eax, 0xF
    cmp al, 10
    jb .blk_cd_d2
    add al, 'A' - 10
    jmp .blk_cd_s2
.blk_cd_d2:
    add al, '0'
.blk_cd_s2:
    mov [rsi], al
    inc rsi
    pop rdi
    inc rdi
    pop rcx
    dec rcx
    jnz .blk_cd_loop
    mov byte [rsi], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 86                 ; 3 + 82 + 1
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rcx
    pop rax
.skip_ra_before:

    ; DEBUG: Print "R14:" (DISABLED)
    jmp .skip_r14_print
    cmp r12, 1
    jne .skip_r14_print
    push rax
    sub rsp, 48
    mov byte [num_buffer], 'R'
    mov byte [num_buffer+1], '1'
    mov byte [num_buffer+2], '4'
    mov byte [num_buffer+3], ':'
    ; Print r14 as 16 hex digits
    mov rax, r14
    mov ecx, 16
    lea rsi, [num_buffer+19]
.r14_hex2:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .r14_d2
    add dl, 'A' - 10
    jmp .r14_s2
.r14_d2:
    add dl, '0'
.r14_s2:
    mov [rsi], dl
    dec rsi
    shr rax, 4
    dec ecx
    jnz .r14_hex2
    mov byte [num_buffer+20], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 21
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rax
.skip_r14_print:

    ; DISABLED - first block debug
    jmp .skip_bx_full_debug
    cmp r12, 1
    jne .skip_bx_full_debug
    push rax
    push rdi
    sub rsp, 48
    mov rdi, rax                ; rdi = code pointer
    ; Print 128 bytes as hex (256 chars)
    mov ecx, 128
    lea rsi, [num_buffer]
.dump_first_bytes:
    movzx eax, byte [rdi]
    push rcx
    push rdi
    ; High nibble
    mov edx, eax
    shr edx, 4
    cmp dl, 10
    jb .dfb_d1
    add dl, 'A' - 10
    jmp .dfb_s1
.dfb_d1:
    add dl, '0'
.dfb_s1:
    mov [rsi], dl
    inc rsi
    ; Low nibble
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .dfb_d2
    add dl, 'A' - 10
    jmp .dfb_s2
.dfb_d2:
    add dl, '0'
.dfb_s2:
    mov [rsi], dl
    inc rsi
    pop rdi
    inc rdi
    pop rcx
    dec ecx
    jnz .dump_first_bytes
    mov byte [rsi], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 257                ; 256 + 1
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rdi
    pop rax
.skip_bx_full_debug:
    ; Debug: verify r14 is correct before first few blocks (DISABLED)
    jmp .skip_r14_check         ; DISABLED
    cmp r12d, 5
    jae .skip_r14_check
    ; Print "R14:XXXXXXXXXXXXXXXX\n"
    push rax
    sub rsp, 48
    mov byte [num_buffer], 'R'
    mov byte [num_buffer+1], '1'
    mov byte [num_buffer+2], '4'
    mov byte [num_buffer+3], ':'
    mov rax, r14                ; Get r14 value
    mov ecx, 16
    lea rsi, [num_buffer+19]
.r14chk_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .r14chk_d
    add dl, 'A' - 10
    jmp .r14chk_s
.r14chk_d:
    add dl, '0'
.r14chk_s:
    mov [rsi], dl
    dec rsi
    shr rax, 4
    dec ecx
    jnz .r14chk_hex
    mov byte [num_buffer+20], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 21
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rax
.skip_r14_check:

    jmp .real_call
    ; Old code dump debug - disabled
    push rax
    push rdi
    push rcx
    sub rsp, 48
    ; Print "X:" and code pointer as 16 hex digits
    mov byte [num_buffer], 'X'
    mov byte [num_buffer+1], ':'
    mov rax, [rsp+64]           ; Get saved rax (code pointer)
    mov rdi, rax                ; Save for byte dump
    mov ecx, 16
    lea rsi, [num_buffer+17]
.xcp_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .xcp_d
    add dl, 'A' - 10
    jmp .xcp_s
.xcp_d:
    add dl, '0'
.xcp_s:
    mov [rsi], dl
    dec rsi
    shr rax, 4
    dec ecx
    jnz .xcp_hex
    mov byte [num_buffer+18], ' '
    ; Now dump first 128 bytes of code
    lea rsi, [num_buffer+19]
    mov ecx, 128
.dump_bytes:
    movzx eax, byte [rdi]
    push rcx
    push rdi
    ; High nibble
    mov edx, eax
    shr edx, 4
    cmp dl, 10
    jb .db_d1
    add dl, 'A' - 10
    jmp .db_s1
.db_d1:
    add dl, '0'
.db_s1:
    mov [rsi], dl
    inc rsi
    ; Low nibble
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .db_d2
    add dl, 'A' - 10
    jmp .db_s2
.db_d2:
    add dl, '0'
.db_s2:
    mov [rsi], dl
    inc rsi
    pop rdi
    inc rdi
    pop rcx
    dec ecx
    jnz .dump_bytes
    mov byte [rsi], 10          ; newline
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 276                ; 2 + 16 + 1 + 256 + 1
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rcx
    pop rdi
    pop rax
.skip_bx_debug:
    ; END DEBUG

.real_call:
    call rax

    ; Debug: print "OK:" after EVERY block (DISABLED)
    jmp .skip_post_call
    push rax
    sub rsp, 48
    mov byte [num_buffer], 'O'
    mov byte [num_buffer+1], 'K'
    mov byte [num_buffer+2], ':'
    mov byte [num_buffer+3], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 4
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rax
.skip_post_call:

    ; Debug: track ra becoming 0 (DISABLED)
    jmp .skip_ra_done
    mov rax, [rbx + 1*8]        ; ra = x1
    test rax, rax
    jnz .skip_ra_done           ; ra not zero - skip
    ; ra is 0! Print "RA0:BBBBB P:XXXXXX S:XXXXXXXX\n" where BBBBB=block, P=PC, S=sp
    push rcx
    push rdi
    push rsi
    sub rsp, 48
    mov byte [num_buffer], 'R'
    mov byte [num_buffer+1], 'A'
    mov byte [num_buffer+2], '0'
    mov byte [num_buffer+3], ':'
    mov eax, r12d               ; Block number
    mov ecx, 5
    lea rsi, [num_buffer+8]
.ra0_dec:
    xor edx, edx
    mov edi, 10
    div edi
    add dl, '0'
    mov [rsi], dl
    dec rsi
    dec ecx
    jnz .ra0_dec
    ; Add " P:"
    mov byte [num_buffer+9], ' '
    mov byte [num_buffer+10], 'P'
    mov byte [num_buffer+11], ':'
    ; Print PC in hex (6 digits)
    mov rax, [r15]              ; Current PC
    mov ecx, 6
    lea rsi, [num_buffer+17]
.ra0_hex:
    mov edx, eax
    and edx, 0xF
    cmp edx, 10
    jb .ra0_digit
    add dl, 'A' - 10
    jmp .ra0_store
.ra0_digit:
    add dl, '0'
.ra0_store:
    mov [rsi], dl
    shr rax, 4
    dec rsi
    dec ecx
    jnz .ra0_hex
    ; Add " S:" for sp
    mov byte [num_buffer+18], ' '
    mov byte [num_buffer+19], 'S'
    mov byte [num_buffer+20], ':'
    ; Print sp in hex (8 digits)
    mov rax, [rbx + 2*8]        ; sp = x2
    mov ecx, 8
    lea rsi, [num_buffer+28]
.ra0_sp_hex:
    mov edx, eax
    and edx, 0xF
    cmp edx, 10
    jb .ra0_sp_digit
    add dl, 'A' - 10
    jmp .ra0_sp_store
.ra0_sp_digit:
    add dl, '0'
.ra0_sp_store:
    mov [rsi], dl
    shr rax, 4
    dec rsi
    dec ecx
    jnz .ra0_sp_hex
    mov byte [num_buffer+29], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 30
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rsi
    pop rdi
    pop rcx
.skip_ra_done:

    ; Debug: track a0 changes (DISABLED)
    jmp .skip_a0_track_done
    push rax
    push rcx
    mov rax, [rbx + 0x50]       ; a0 = x10, offset 0x50
    cmp rax, [last_a0_value]
    je .skip_a0_track           ; a0 unchanged
    mov [last_a0_value], rax
    ; Check if a0 == corrupt value
    mov rcx, 0x0000038800000034
    cmp rax, rcx
    jne .skip_a0_track          ; Not the corrupt value
    ; Print "A0C:BBBBB\n" where BBBBB is block number in decimal
    push rdi
    push rsi
    sub rsp, 48
    mov byte [num_buffer], 'A'
    mov byte [num_buffer+1], '0'
    mov byte [num_buffer+2], 'C'
    mov byte [num_buffer+3], ':'
    ; Print block number in decimal (5 digits)
    mov eax, r12d
    lea rsi, [num_buffer+8]
    mov ecx, 5
.a0c_dec:
    xor edx, edx
    mov edi, 10
    div edi
    add dl, '0'
    mov [rsi], dl
    dec rsi
    dec ecx
    jnz .a0c_dec
    mov byte [num_buffer+9], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 10
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rsi
    pop rdi
.skip_a0_track:
    pop rcx
    pop rax
.skip_a0_track_done:

    ; Debug: track s4 for blocks 9240-9260 (DISABLED)
    jmp .skip_s4_done
    push rax
    push rcx
    cmp r12, 9240
    jb .skip_s4_track
    cmp r12, 9260
    ja .skip_s4_track
    ; Print block# and s4 value: "sN:XXXXXXXXXXXXXXXX\n"
    push rdi
    push rsi
    sub rsp, 48
    mov byte [num_buffer], 's'
    ; Print last digit of block number
    mov eax, r12d
    mov ecx, 10
    xor edx, edx
    div ecx                     ; edx = r12 % 10
    add dl, '0'
    mov [num_buffer+1], dl
    mov byte [num_buffer+2], ':'
    ; Print s4 value (16 hex)
    mov rax, [rbx + 0xA0]
    mov ecx, 16
    lea rsi, [num_buffer+18]
.st_hex:
    mov edi, eax
    and edi, 0xF
    cmp edi, 10
    jb .st_dig
    add edi, 'A' - 10
    jmp .st_st
.st_dig:
    add edi, '0'
.st_st:
    mov [rsi], dil
    dec rsi
    shr rax, 4
    dec ecx
    jnz .st_hex
    mov byte [num_buffer+19], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 20
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rsi
    pop rdi
.skip_s4_track:
    mov rax, [rbx + 0xA0]       ; s4 = x20, offset 0xA0 = 160
    ; Check if s4 changed from last block
    cmp rax, [last_s4_value]
    je .skip_s4_after           ; s4 unchanged - skip
    mov [last_s4_value], rax    ; Save new s4 value
    ; Check if new s4 equals the corruption pattern
    mov rcx, 0x0000038800000034 ; The corrupted value
    cmp rax, rcx
    jne .skip_s4_after          ; Not the corruption pattern
    ; s4 just became corrupted! This block did it
    push rax                    ; Save corrupted s4 value
    sub rsp, 48
    mov byte [num_buffer], 'S'
    mov byte [num_buffer+1], '4'
    mov byte [num_buffer+2], 'B'
    mov byte [num_buffer+3], ':'
    ; Print block number (r12) as 8 hex digits
    mov eax, r12d
    mov ecx, 8
    lea rsi, [num_buffer+11]
.bad_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .bad_dig
    add dl, 'A' - 10
    jmp .bad_st
.bad_dig:
    add dl, '0'
.bad_st:
    mov [rsi], dl
    dec rsi
    shr eax, 4
    dec ecx
    jnz .bad_hex
    ; Add " S4:" label and corrupted value
    mov byte [num_buffer+12], ' '
    mov byte [num_buffer+13], 'S'
    mov byte [num_buffer+14], '4'
    mov byte [num_buffer+15], ':'
    ; Print s4 value (16 hex digits)
    mov rax, [rsp+48]           ; Get saved corrupted s4
    mov ecx, 16
    lea rsi, [num_buffer+31]
.bad_s4_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .bad_s4_dig
    add dl, 'A' - 10
    jmp .bad_s4_st
.bad_s4_dig:
    add dl, '0'
.bad_s4_st:
    mov [rsi], dl
    dec rsi
    shr rax, 4
    dec ecx
    jnz .bad_s4_hex
    mov byte [num_buffer+32], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 33
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    ; Print the PREVIOUS PC (before the block ran) - saved in block structure
    ; Actually we need to get the block's start PC, which would be in rbp-48
    ; For now, let's print guest memory at current PC-16 to PC+16
    mov byte [num_buffer], 'I'
    mov byte [num_buffer+1], 'N'
    mov byte [num_buffer+2], 'S'
    mov byte [num_buffer+3], ':'
    mov rax, [rbp-56]           ; Block pointer (was -48, moved to -56)
    mov rax, [rax + 8]          ; BLOCK_START_PC - start from beginning of block
    ; r14 points to guest_memory base (established earlier in function)
    push r14
    mov r14, [rbp-16]           ; guest_memory base from stack
    add rax, r14                ; guest_memory + PC
    ; Print 32 bytes of instruction data (to see more of the block)
    mov ecx, 32
    lea rsi, [num_buffer+4]
.ins_loop:
    push rcx
    push rax
    movzx edx, byte [rax]
    ; Print high nibble
    push rdx
    shr edx, 4
    cmp dl, 10
    jb .ins_d1
    add dl, 'A' - 10
    jmp .ins_s1
.ins_d1:
    add dl, '0'
.ins_s1:
    mov [rsi], dl
    inc rsi
    pop rdx
    and edx, 0xF
    cmp dl, 10
    jb .ins_d2
    add dl, 'A' - 10
    jmp .ins_s2
.ins_d2:
    add dl, '0'
.ins_s2:
    mov [rsi], dl
    inc rsi
    pop rax
    pop rcx
    inc rax
    dec ecx
    jnz .ins_loop
    pop r14
    mov byte [rsi], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 69                 ; 4 + 32*2 + 1
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    ; Also dump generated x86 code for this block
    mov byte [num_buffer], 'X'
    mov byte [num_buffer+1], '8'
    mov byte [num_buffer+2], '6'
    mov byte [num_buffer+3], ':'
    mov rax, [rbp-56]           ; Block pointer (was -48, moved to -56)
    mov rax, [rax + 16]         ; BLOCK_CODE_PTR
    ; Print first 64 bytes of x86 code
    mov ecx, 64
    lea rsi, [num_buffer+4]
.x86_loop:
    push rcx
    push rax
    movzx edx, byte [rax]
    push rdx
    shr edx, 4
    cmp dl, 10
    jb .x86_d1
    add dl, 'A' - 10
    jmp .x86_s1
.x86_d1:
    add dl, '0'
.x86_s1:
    mov [rsi], dl
    inc rsi
    pop rdx
    and edx, 0xF
    cmp dl, 10
    jb .x86_d2
    add dl, 'A' - 10
    jmp .x86_s2
.x86_d2:
    add dl, '0'
.x86_s2:
    mov [rsi], dl
    inc rsi
    pop rax
    pop rcx
    inc rax
    dec ecx
    jnz .x86_loop
    mov byte [rsi], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 133                ; 4 + 64*2 + 1
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    ; Print block's START PC (from block structure at rbp-56)
    mov byte [num_buffer], 'S'
    mov byte [num_buffer+1], 'P'
    mov byte [num_buffer+2], ':'
    mov rax, [rbp-56]           ; Block pointer (was -48, moved to -56)
    mov rax, [rax + 8]          ; BLOCK_START_PC = offset 8
    mov ecx, 16
    lea rsi, [num_buffer+18]
.bad_spc_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .bad_spc_dig
    add dl, 'A' - 10
    jmp .bad_spc_st
.bad_spc_dig:
    add dl, '0'
.bad_spc_st:
    mov [rsi], dl
    dec rsi
    shr rax, 4
    dec ecx
    jnz .bad_spc_hex
    mov byte [num_buffer+19], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 20
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    ; Print ending PC at BAD point
    mov byte [num_buffer], 'E'
    mov byte [num_buffer+1], 'P'
    mov byte [num_buffer+2], ':'
    mov rax, [r15]              ; r15 points to PC storage
    mov ecx, 16
    lea rsi, [num_buffer+18]
.bad_pc_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .bad_pc_dig
    add dl, 'A' - 10
    jmp .bad_pc_st
.bad_pc_dig:
    add dl, '0'
.bad_pc_st:
    mov [rsi], dl
    dec rsi
    shr rax, 4
    dec ecx
    jnz .bad_pc_hex
    mov byte [num_buffer+19], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 20
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    ; Print "gp:" (x3, offset 0x18) to see base address for LD
    mov byte [num_buffer], 'g'
    mov byte [num_buffer+1], 'p'
    mov byte [num_buffer+2], ':'
    mov rax, [rbx + 0x18]       ; x3 = gp
    mov ecx, 16
    lea rsi, [num_buffer+18]
.bad_a0_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .bad_a0_dig
    add dl, 'A' - 10
    jmp .bad_a0_st
.bad_a0_dig:
    add dl, '0'
.bad_a0_st:
    mov [rsi], dl
    dec rsi
    shr rax, 4
    dec ecx
    jnz .bad_a0_hex
    mov byte [num_buffer+19], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 20
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    ; Print more registers to find pattern
    ; Print all of a0-a7, s0-s11
    ; First, print register file from x8-x27 as hex dump
    mov byte [num_buffer], 'R'
    mov byte [num_buffer+1], 'F'
    mov byte [num_buffer+2], ':'
    mov byte [num_buffer+3], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 4
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    ; Print registers x8-x27 (s0-s11, a0-a7)
    xor r14d, r14d              ; r14 = register index (start at 8)
    add r14, 8
.reg_dump_loop:
    ; Print "xNN:"
    mov byte [num_buffer], 'x'
    mov eax, r14d
    ; Print 2 digit number
    mov edx, eax
    shr edx, 4
    add dl, '0'
    cmp dl, '9'
    jbe .rd_d1
    add dl, 7
.rd_d1:
    mov [num_buffer+1], dl
    mov edx, eax
    and edx, 0xF
    add dl, '0'
    cmp dl, '9'
    jbe .rd_d2
    add dl, 7
.rd_d2:
    mov [num_buffer+2], dl
    mov byte [num_buffer+3], ':'
    ; Load register value
    mov eax, r14d
    shl eax, 3                  ; offset = reg * 8
    mov rax, [rbx + rax]        ; load register value
    ; Print as 16 hex digits
    mov ecx, 16
    lea rsi, [num_buffer+19]
.rd_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .rd_hd
    add dl, 'A' - 10
    jmp .rd_hs
.rd_hd:
    add dl, '0'
.rd_hs:
    mov [rsi], dl
    dec rsi
    shr rax, 4
    dec ecx
    jnz .rd_hex
    mov byte [num_buffer+20], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 21
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    inc r14
    cmp r14, 28
    jb .reg_dump_loop
    ; Just print warning and continue (don't exit)
    add rsp, 48
    pop rax                     ; Restore stack balance
    jmp .skip_s4_after          ; Continue execution
.skip_s4_after:
    pop rcx
    pop rax
.skip_s4_done:

    ; Debug: print "<" after block 9256 executes (effectively disabled - compares to 999999999)
    cmp r12, 999999999
    jne .skip_after_call_debug
    push rax
    sub rsp, 48
    mov byte [num_buffer], '<'
    mov byte [num_buffer+1], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 2
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rax
.skip_after_call_debug:

    ; Debug: for blocks around 2425 (decimal), print block# and PC after execution
    ; DISABLED to reduce noise
    jmp .skip_pc_after
    cmp r12d, 2423
    jb .skip_pc_after
    cmp r12d, 2428
    ja .skip_pc_after
    ; Print "A[XXXX]:YYYYYYYY" (block number and after-PC)
    push rax
    sub rsp, 48
    mov byte [num_buffer], 'A'
    mov byte [num_buffer+1], '['
    ; Print block number (4 hex digits)
    mov eax, r12d
    mov ecx, 4
    lea rsi, [num_buffer+5]
.dbg_abn_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .dbg_abn_dig
    add dl, 'A' - 10
    jmp .dbg_abn_st
.dbg_abn_dig:
    add dl, '0'
.dbg_abn_st:
    mov [rsi], dl
    dec rsi
    shr eax, 4
    dec ecx
    jnz .dbg_abn_hex
    mov byte [num_buffer+6], ']'
    mov byte [num_buffer+7], ':'
    mov rax, [r15]              ; Current PC after block
    mov ecx, 8
    lea rsi, [num_buffer+15]
.dbg_after_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .dbg_after_dig
    add dl, 'A' - 10
    jmp .dbg_after_st
.dbg_after_dig:
    add dl, '0'
.dbg_after_st:
    mov [rsi], dl
    dec rsi
    shr eax, 4
    dec ecx
    jnz .dbg_after_hex
    mov byte [num_buffer+16], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 17
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rax
.skip_pc_after:

    ; Block executed, PC has been updated
    ; Check ecall_pending flag (set by ECALL blocks at runtime)
    cmp byte [ecall_pending], 0
    jne .handle_ecall

    ; Not an ECALL - try to link this block for future speedup
    ; Only link EXIT_JUMP (unconditional direct jumps like JAL)
    ; Branches have TWO exits and need special handling (not yet implemented)
    mov rax, [rbp-56]           ; Block pointer (was -48, moved to -56)
    mov ecx, [rax + BLOCK_EXIT_TYPE]
    cmp ecx, EXIT_JUMP
    jne .exec_loop              ; Only link unconditional jumps

    ; BUG FIX: Only link if current PC matches block's intended target
    ; This prevents re-linking when we follow a linked JMP through multiple blocks
    ; (linked blocks skip the trampoline, so [rbp-56] becomes stale)
    mov rdx, [rax + BLOCK_NEXT_PC]  ; Block's intended target from translation
    mov rcx, [rbp-32]
    mov rdi, [rcx]                  ; Current rv_pc value
    cmp rdx, rdi                    ; Do they match?
    jne .exec_loop                  ; No match = we're in a chain, don't re-link

    ; Look up target block by current PC
    call lookup_block
    test rax, rax
    jz .exec_loop               ; Target not cached yet - can't link

    ; Link source block to target block
    mov rdi, [rbp-56]           ; Source block (was -48, moved to -56)
    mov rsi, rax                ; Target block
    call link_block

    jmp .exec_loop

.handle_ecall:
    ; Debug: print EC: marker to confirm we reached ecall handler (DISABLED)
    jmp .skip_ec_debug
    push rax
    sub rsp, 48
    mov byte [num_buffer], 'E'
    mov byte [num_buffer+1], 'C'
    mov byte [num_buffer+2], ':'
    mov byte [num_buffer+3], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 4
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rax
.skip_ec_debug:
    ; ECALL - Linux RISC-V syscall ABI
    ; a7 (x17) = syscall number
    ; a0-a5 (x10-x15) = arguments
    ; a0 (x10) = return value (negative = -errno on error)
    mov rbx, [rbp-24]           ; rv_regs

    ; Get syscall number from a7 (x17)
    mov rax, [rbx + 17*8]

    ; Debug: Print all syscalls (ENABLED for debugging)
    push rax
    inc qword [syscall_count]
    ; Print first N syscalls (0 = disable, or set high to print all)
    ; jmp .skip_syscall_print  ; DISABLED - ENABLED FOR DEBUGGING
    ; Print all syscalls (no limit)
    mov rcx, [syscall_count]
    cmp rcx, 99999999
    ja .skip_syscall_print
    ; Print syscall number as hex digit
    push rax
    sub rsp, 48
    ; Convert syscall to single char: 0-9 = '0'-'9', 10+ = 'A'-...
    mov rax, [rsp+48]           ; Get syscall number back
    mov byte [num_buffer], '['
    ; Print low nibble as hex
    mov ecx, eax
    and ecx, 0xF
    cmp cl, 10
    jb .sc_digit1
    add cl, 'A' - 10
    jmp .sc_store1
.sc_digit1:
    add cl, '0'
.sc_store1:
    mov [num_buffer+2], cl
    ; Print second nibble
    shr eax, 4
    and eax, 0xF
    cmp al, 10
    jb .sc_digit2
    add al, 'A' - 10
    jmp .sc_store2
.sc_digit2:
    add al, '0'
.sc_store2:
    mov [num_buffer+1], al
    mov byte [num_buffer+3], ']'
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 4
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rax
.skip_syscall_print:
    pop rax

    ; Dispatch syscalls
    cmp rax, 29
    je .syscall_ioctl
    cmp rax, 56
    je .syscall_openat
    cmp rax, 57
    je .syscall_close
    cmp rax, 62
    je .syscall_lseek
    cmp rax, 63
    je .syscall_read
    cmp rax, 64
    je .syscall_write
    cmp rax, 80
    je .syscall_fstat
    cmp rax, 93
    je .syscall_exit
    cmp rax, 94
    je .syscall_exit            ; exit_group = exit for us
    cmp rax, 214
    je .syscall_brk
    cmp rax, 222
    je .syscall_mmap

    ; Conway/Doom-specific syscalls
    ; Common glibc startup syscalls
    cmp rax, 96                     ; set_tid_address
    je .syscall_set_tid_address
    cmp rax, 99                     ; set_robust_list
    je .syscall_stub_success
    cmp rax, 129                    ; kill
    je .syscall_signal_exit
    cmp rax, 130                    ; tkill
    je .syscall_signal_exit
    cmp rax, 131                    ; tgkill
    je .syscall_signal_exit
    cmp rax, 134                    ; rt_sigaction
    je .syscall_stub_success
    cmp rax, 135                    ; rt_sigprocmask
    je .syscall_stub_success
    cmp rax, 160                    ; uname
    je .syscall_uname
    cmp rax, 172                    ; getpid
    je .syscall_getpid
    cmp rax, 174                    ; getuid
    je .syscall_getuid
    cmp rax, 175                    ; geteuid
    je .syscall_getuid
    cmp rax, 176                    ; getgid
    je .syscall_getuid
    cmp rax, 177                    ; getegid
    je .syscall_getuid
    cmp rax, 178                    ; gettid
    je .syscall_getpid
    cmp rax, 261                    ; prlimit64
    je .syscall_prlimit64
    cmp rax, 278                    ; getrandom
    je .syscall_getrandom
    cmp rax, 98                     ; futex
    je .syscall_futex
    cmp rax, 48                     ; faccessat
    je .syscall_faccessat
    cmp rax, 17                     ; getcwd
    je .syscall_getcwd
    cmp rax, 78                     ; readlinkat
    je .syscall_stub_error          ; Return -ENOENT
    cmp rax, 79                     ; fstatat
    je .syscall_fstatat
    cmp rax, 66                     ; writev
    je .syscall_writev

    cmp rax, 1000
    je .syscall_drawframe
    cmp rax, 1001
    je .syscall_sleepms

    ; Unknown syscall - return -ENOSYS (38)
    mov qword [rbx + 10*8], -38
    jmp .exec_loop

;------------------------------------------------------------------------------
; exit(status) / exit_group(status) - syscall 93/94
; a0 = exit code
;------------------------------------------------------------------------------
.syscall_exit:
    mov edi, [rbx + 10*8]       ; a0 = exit code

    ; DEBUG: Print exit code (DISABLED)
    jmp .skip_exit_code_debug
    push rdi
    sub rsp, 48
    mov byte [num_buffer], 'X'
    mov byte [num_buffer+1], ':'
    mov eax, edi
    ; Print as 2-digit hex
    mov ecx, eax
    shr ecx, 4
    and ecx, 0xF
    cmp cl, 10
    jb .exit_d1
    add cl, 'A' - 10
    jmp .exit_s1
.exit_d1:
    add cl, '0'
.exit_s1:
    mov [num_buffer+2], cl
    mov ecx, eax
    and ecx, 0xF
    cmp cl, 10
    jb .exit_d2
    add cl, 'A' - 10
    jmp .exit_s2
.exit_d2:
    add cl, '0'
.exit_s2:
    mov [num_buffer+3], cl
    mov byte [num_buffer+4], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 5
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rdi
    ; END DEBUG

    ; Print load/store counts before exit
    push rdi
    sub rsp, 48
    ; Print "LB:XXXX " for LBU count
    mov byte [num_buffer], 'L'
    mov byte [num_buffer+1], 'B'
    mov byte [num_buffer+2], ':'
    mov rax, [lbu_count]
    mov ecx, 4
    lea rsi, [num_buffer+6]
.lbu_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .lbu_d
    add dl, 'A' - 10
    jmp .lbu_s
.lbu_d:
    add dl, '0'
.lbu_s:
    mov [rsi], dl
    dec rsi
    shr eax, 4
    dec ecx
    jnz .lbu_hex
    mov byte [num_buffer+7], ' '
    ; Print first LBU address (8 hex digits)
    mov byte [num_buffer+8], 'A'
    mov byte [num_buffer+9], ':'
    mov rax, [first_lbu_addr]
    mov ecx, 8
    lea rsi, [num_buffer+17]
.lbua_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .lbua_d
    add dl, 'A' - 10
    jmp .lbua_s
.lbua_d:
    add dl, '0'
.lbua_s:
    mov [rsi], dl
    dec rsi
    shr rax, 4
    dec ecx
    jnz .lbua_hex
    mov byte [num_buffer+18], ' '
    ; Print first LBU value (2 hex digits)
    mov byte [num_buffer+19], 'V'
    mov byte [num_buffer+20], ':'
    movzx eax, byte [first_lbu_val]
    mov edx, eax
    shr edx, 4
    cmp dl, 10
    jb .lbuv_d1
    add dl, 'A' - 10
    jmp .lbuv_s1
.lbuv_d1:
    add dl, '0'
.lbuv_s1:
    mov [num_buffer+21], dl
    and al, 0xF
    cmp al, 10
    jb .lbuv_d2
    add al, 'A' - 10
    jmp .lbuv_s2
.lbuv_d2:
    add al, '0'
.lbuv_s2:
    mov [num_buffer+22], al
    mov byte [num_buffer+23], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 24
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    ; Print "ST:SB=XXXX SH=XXXX SW=XXXX SD=XXXX\n"
    mov byte [num_buffer], 'S'
    mov byte [num_buffer+1], 'T'
    mov byte [num_buffer+2], ':'
    mov byte [num_buffer+3], 'B'
    mov byte [num_buffer+4], '='
    ; Print sb_count (4 hex digits)
    mov rax, [sb_count]
    mov ecx, 4
    lea rsi, [num_buffer+8]
.sb_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .sb_d
    add dl, 'A' - 10
    jmp .sb_s
.sb_d:
    add dl, '0'
.sb_s:
    mov [rsi], dl
    dec rsi
    shr eax, 4
    dec ecx
    jnz .sb_hex

    mov byte [num_buffer+9], ' '
    mov byte [num_buffer+10], 'H'
    mov byte [num_buffer+11], '='
    mov rax, [sh_count]
    mov ecx, 4
    lea rsi, [num_buffer+15]
.sh_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .sh_d
    add dl, 'A' - 10
    jmp .sh_s
.sh_d:
    add dl, '0'
.sh_s:
    mov [rsi], dl
    dec rsi
    shr eax, 4
    dec ecx
    jnz .sh_hex

    mov byte [num_buffer+16], ' '
    mov byte [num_buffer+17], 'W'
    mov byte [num_buffer+18], '='
    mov rax, [sw_count]
    mov ecx, 4
    lea rsi, [num_buffer+22]
.sw_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .sw_d
    add dl, 'A' - 10
    jmp .sw_s
.sw_d:
    add dl, '0'
.sw_s:
    mov [rsi], dl
    dec rsi
    shr eax, 4
    dec ecx
    jnz .sw_hex

    mov byte [num_buffer+23], ' '
    mov byte [num_buffer+24], 'D'
    mov byte [num_buffer+25], '='
    mov rax, [sd_count]
    mov ecx, 4
    lea rsi, [num_buffer+29]
.sd_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .sd_d
    add dl, 'A' - 10
    jmp .sd_s
.sd_d:
    add dl, '0'
.sd_s:
    mov [rsi], dl
    dec rsi
    shr eax, 4
    dec ecx
    jnz .sd_hex

    mov byte [num_buffer+30], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 31
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print compressed store counts
    mov byte [num_buffer], 'C'
    mov byte [num_buffer+1], 'S'
    mov byte [num_buffer+2], ':'
    mov byte [num_buffer+3], 'W'
    mov byte [num_buffer+4], '='
    mov rax, [c_sw_count]
    mov ecx, 4
    lea rsi, [num_buffer+8]
.csw_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .csw_d
    add dl, 'A' - 10
    jmp .csw_s
.csw_d:
    add dl, '0'
.csw_s:
    mov [rsi], dl
    dec rsi
    shr eax, 4
    dec ecx
    jnz .csw_hex

    mov byte [num_buffer+9], ' '
    mov byte [num_buffer+10], 'D'
    mov byte [num_buffer+11], '='
    mov rax, [c_sd_count]
    mov ecx, 4
    lea rsi, [num_buffer+15]
.csd_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .csd_d
    add dl, 'A' - 10
    jmp .csd_s
.csd_d:
    add dl, '0'
.csd_s:
    mov [rsi], dl
    dec rsi
    shr eax, 4
    dec ecx
    jnz .csd_hex

    mov byte [num_buffer+16], ' '
    mov byte [num_buffer+17], 'S'
    mov byte [num_buffer+18], 'W'
    mov byte [num_buffer+19], 'S'
    mov byte [num_buffer+20], 'P'
    mov byte [num_buffer+21], '='
    mov rax, [c_swsp_count]
    mov ecx, 4
    lea rsi, [num_buffer+25]
.cswsp_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .cswsp_d
    add dl, 'A' - 10
    jmp .cswsp_s
.cswsp_d:
    add dl, '0'
.cswsp_s:
    mov [rsi], dl
    dec rsi
    shr eax, 4
    dec ecx
    jnz .cswsp_hex

    mov byte [num_buffer+26], ' '
    mov byte [num_buffer+27], 'S'
    mov byte [num_buffer+28], 'D'
    mov byte [num_buffer+29], 'S'
    mov byte [num_buffer+30], 'P'
    mov byte [num_buffer+31], '='
    mov rax, [c_sdsp_count]
    mov ecx, 4
    lea rsi, [num_buffer+35]
.csdsp_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .csdsp_d
    add dl, 'A' - 10
    jmp .csdsp_s
.csdsp_d:
    add dl, '0'
.csdsp_s:
    mov [rsi], dl
    dec rsi
    shr eax, 4
    dec ecx
    jnz .csdsp_hex

    mov byte [num_buffer+36], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 37
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print SB runtime execution count
    mov byte [num_buffer], 'S'
    mov byte [num_buffer+1], 'B'
    mov byte [num_buffer+2], 'X'
    mov byte [num_buffer+3], '='
    mov rax, [sb_exec_count]
    mov ecx, 8
    lea rsi, [num_buffer+11]
.sbx_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .sbx_d
    add dl, 'A' - 10
    jmp .sbx_s
.sbx_d:
    add dl, '0'
.sbx_s:
    mov [rsi], dl
    dec rsi
    shr rax, 4
    dec ecx
    jnz .sbx_hex
    mov byte [num_buffer+12], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 13
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print first SB store debug info
    ; Format: "1SB:R14=XXXXXXXXXXXXXXXX A=XXXXXXXXXXXXXXXX\n"
    mov byte [num_buffer], '1'
    mov byte [num_buffer+1], 'S'
    mov byte [num_buffer+2], 'B'
    mov byte [num_buffer+3], ':'
    mov byte [num_buffer+4], 'R'
    mov byte [num_buffer+5], '='
    ; Print first_sb_r14
    mov rax, [first_sb_r14]
    mov ecx, 16
    lea rsi, [num_buffer+21]
.fsr_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .fsr_d
    add dl, 'A' - 10
    jmp .fsr_s
.fsr_d:
    add dl, '0'
.fsr_s:
    mov [rsi], dl
    dec rsi
    shr rax, 4
    dec ecx
    jnz .fsr_hex
    mov byte [num_buffer+22], ' '
    mov byte [num_buffer+23], 'A'
    mov byte [num_buffer+24], '='
    ; Print first_sb_addr
    mov rax, [first_sb_addr]
    mov ecx, 16
    lea rsi, [num_buffer+40]
.fsa_hex:
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .fsa_d
    add dl, 'A' - 10
    jmp .fsa_s
.fsa_d:
    add dl, '0'
.fsa_s:
    mov [rsi], dl
    dec rsi
    shr rax, 4
    dec ecx
    jnz .fsa_hex
    ; Also print what's actually at that address in memory
    ; First compute host address = [rbp-16] + first_sb_addr
    mov rax, [rbp-16]           ; guest_memory base
    add rax, [first_sb_addr]    ; + guest address = host address
    movzx edx, byte [rax]       ; read back what's there
    mov byte [num_buffer+41], ' '
    mov byte [num_buffer+42], 'V'
    mov byte [num_buffer+43], '='
    ; Print as 2 hex digits
    mov eax, edx
    shr eax, 4
    cmp al, 10
    jb .fsv_d1
    add al, 'A' - 10
    jmp .fsv_s1
.fsv_d1:
    add al, '0'
.fsv_s1:
    mov [num_buffer+44], al
    and dl, 0xF
    cmp dl, 10
    jb .fsv_d2
    add dl, 'A' - 10
    jmp .fsv_s2
.fsv_d2:
    add dl, '0'
.fsv_s2:
    mov [num_buffer+45], dl
    ; Add C= for captured cl value
    mov byte [num_buffer+46], ' '
    mov byte [num_buffer+47], 'C'
    mov byte [num_buffer+48], '='
    ; Print first_sb_val as 2 hex digits
    movzx eax, byte [first_sb_val]
    mov edx, eax
    shr eax, 4
    cmp al, 10
    jb .fsc_d1
    add al, 'A' - 10
    jmp .fsc_s1
.fsc_d1:
    add al, '0'
.fsc_s1:
    mov [num_buffer+49], al
    and dl, 0xF
    cmp dl, 10
    jb .fsc_d2
    add dl, 'A' - 10
    jmp .fsc_s2
.fsc_d2:
    add dl, '0'
.fsc_s2:
    mov [num_buffer+50], dl
    ; Add R= for readback value (immediately after store)
    mov byte [num_buffer+51], ' '
    mov byte [num_buffer+52], 'R'
    mov byte [num_buffer+53], '='
    ; Print first_sb_readback as 2 hex digits
    movzx eax, byte [first_sb_readback]
    mov edx, eax
    shr eax, 4
    cmp al, 10
    jb .fsr2_d1
    add al, 'A' - 10
    jmp .fsr2_s1
.fsr2_d1:
    add al, '0'
.fsr2_s1:
    mov [num_buffer+54], al
    and dl, 0xF
    cmp dl, 10
    jb .fsr2_d2
    add dl, 'A' - 10
    jmp .fsr2_s2
.fsr2_d2:
    add dl, '0'
.fsr2_s2:
    mov [num_buffer+55], dl
    mov byte [num_buffer+56], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 57
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print sb_target info: "ST@:XX\n" (what was stored at 0x6FFA4F)
    cmp byte [sb_target_captured], 0
    je .skip_target_print
    mov byte [num_buffer], 'S'
    mov byte [num_buffer+1], 'T'
    mov byte [num_buffer+2], '@'
    mov byte [num_buffer+3], ':'
    movzx eax, byte [sb_target_val]
    mov edx, eax
    shr eax, 4
    cmp al, 10
    jb .st_pr_d1
    add al, 'A' - 10
    jmp .st_pr_s1
.st_pr_d1:
    add al, '0'
.st_pr_s1:
    mov [num_buffer+4], al
    and dl, 0xF
    cmp dl, 10
    jb .st_pr_d2
    add dl, 'A' - 10
    jmp .st_pr_s2
.st_pr_d2:
    add dl, '0'
.st_pr_s2:
    mov [num_buffer+5], dl
    mov byte [num_buffer+6], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 7
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    jmp .after_target_print
.skip_target_print:
    mov byte [num_buffer], 'S'
    mov byte [num_buffer+1], 'T'
    mov byte [num_buffer+2], '@'
    mov byte [num_buffer+3], ':'
    mov byte [num_buffer+4], 'n'
    mov byte [num_buffer+5], 'o'
    mov byte [num_buffer+6], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 7
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
.after_target_print:

    ; Print SW corruption info: "SWC:ADDR/STORED/READBACK\n" or "SWC:no\n"
    cmp byte [sw_corrupt_captured], 0
    je .skip_swc_print
    mov byte [num_buffer], 'S'
    mov byte [num_buffer+1], 'W'
    mov byte [num_buffer+2], 'C'
    mov byte [num_buffer+3], ':'
    ; Print address (8 hex digits)
    mov eax, [sw_corrupt_addr]
    lea rdi, [num_buffer+4]
    mov ecx, 8
.swc_hex_addr:
    rol eax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .swc_digit_a
    add dl, 'A' - 10
    jmp .swc_store_a
.swc_digit_a:
    add dl, '0'
.swc_store_a:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .swc_hex_addr
    mov byte [rdi], '/'
    inc rdi
    ; Print stored value (8 hex digits)
    mov eax, [sw_corrupt_stored]
    mov ecx, 8
.swc_hex_stored:
    rol eax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .swc_digit_s
    add dl, 'A' - 10
    jmp .swc_store_s
.swc_digit_s:
    add dl, '0'
.swc_store_s:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .swc_hex_stored
    mov byte [rdi], '/'
    inc rdi
    ; Print readback value (8 hex digits)
    mov eax, [sw_corrupt_readback]
    mov ecx, 8
.swc_hex_readback:
    rol eax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .swc_digit_r
    add dl, 'A' - 10
    jmp .swc_store_r
.swc_digit_r:
    add dl, '0'
.swc_store_r:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .swc_hex_readback
    mov byte [rdi], 10
    inc rdi
    ; Write it all
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8, rdi
    sub r8, rdx
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    jmp .after_swc_print
.skip_swc_print:
    mov byte [num_buffer], 'S'
    mov byte [num_buffer+1], 'W'
    mov byte [num_buffer+2], 'C'
    mov byte [num_buffer+3], ':'
    mov byte [num_buffer+4], 'n'
    mov byte [num_buffer+5], 'o'
    mov byte [num_buffer+6], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 7
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
.after_swc_print:

    ; Print SD corruption info: "SDC:ADDR/STORED_LO/READBACK_LO\n" or "SDC:no\n"
    cmp byte [sd_corrupt_captured], 0
    je .skip_sdc_print
    mov byte [num_buffer], 'S'
    mov byte [num_buffer+1], 'D'
    mov byte [num_buffer+2], 'C'
    mov byte [num_buffer+3], ':'
    ; Print address (8 hex digits)
    mov eax, [sd_corrupt_addr]
    lea rdi, [num_buffer+4]
    mov ecx, 8
.sdc_hex_addr:
    rol eax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .sdc_digit_a
    add dl, 'A' - 10
    jmp .sdc_store_a
.sdc_digit_a:
    add dl, '0'
.sdc_store_a:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .sdc_hex_addr
    mov byte [rdi], '/'
    inc rdi
    ; Print stored value low 32 bits (8 hex digits)
    mov eax, [sd_corrupt_stored]
    mov ecx, 8
.sdc_hex_stored:
    rol eax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .sdc_digit_s
    add dl, 'A' - 10
    jmp .sdc_store_s
.sdc_digit_s:
    add dl, '0'
.sdc_store_s:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .sdc_hex_stored
    mov byte [rdi], '/'
    inc rdi
    ; Print readback value low 32 bits (8 hex digits)
    mov eax, [sd_corrupt_readback]
    mov ecx, 8
.sdc_hex_readback:
    rol eax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .sdc_digit_r
    add dl, 'A' - 10
    jmp .sdc_store_r
.sdc_digit_r:
    add dl, '0'
.sdc_store_r:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .sdc_hex_readback
    mov byte [rdi], 10
    inc rdi
    ; Write it all
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8, rdi
    sub r8, rdx
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    jmp .after_sdc_print
.skip_sdc_print:
    mov byte [num_buffer], 'S'
    mov byte [num_buffer+1], 'D'
    mov byte [num_buffer+2], 'C'
    mov byte [num_buffer+3], ':'
    mov byte [num_buffer+4], 'n'
    mov byte [num_buffer+5], 'o'
    mov byte [num_buffer+6], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 7
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
.after_sdc_print:

    ; Print C.SW corruption info: "CSW:ADDR/STORED/READBACK\n" or "CSW:no\n"
    cmp byte [csw_corrupt_captured], 0
    je .skip_csw_print
    mov byte [num_buffer], 'C'
    mov byte [num_buffer+1], 'S'
    mov byte [num_buffer+2], 'W'
    mov byte [num_buffer+3], ':'
    ; Print address (8 hex digits)
    mov eax, [csw_corrupt_addr]
    lea rdi, [num_buffer+4]
    mov ecx, 8
.csw_hex_addr:
    rol eax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .csw_digit_a
    add dl, 'A' - 10
    jmp .csw_store_a
.csw_digit_a:
    add dl, '0'
.csw_store_a:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .csw_hex_addr
    mov byte [rdi], '/'
    inc rdi
    ; Print stored value (8 hex digits)
    mov eax, [csw_corrupt_stored]
    mov ecx, 8
.csw_hex_stored:
    rol eax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .csw_digit_s
    add dl, 'A' - 10
    jmp .csw_store_s
.csw_digit_s:
    add dl, '0'
.csw_store_s:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .csw_hex_stored
    mov byte [rdi], '/'
    inc rdi
    ; Print readback value (8 hex digits)
    mov eax, [csw_corrupt_readback]
    mov ecx, 8
.csw_hex_readback:
    rol eax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .csw_digit_r
    add dl, 'A' - 10
    jmp .csw_store_r
.csw_digit_r:
    add dl, '0'
.csw_store_r:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .csw_hex_readback
    mov byte [rdi], 10
    inc rdi
    ; Write it all
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8, rdi
    sub r8, rdx
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    jmp .after_csw_print
.skip_csw_print:
    mov byte [num_buffer], 'C'
    mov byte [num_buffer+1], 'S'
    mov byte [num_buffer+2], 'W'
    mov byte [num_buffer+3], ':'
    mov byte [num_buffer+4], 'n'
    mov byte [num_buffer+5], 'o'
    mov byte [num_buffer+6], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 7
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
.after_csw_print:

    add rsp, 48
    pop rdi
.skip_exit_code_debug:
    ; END store count debug

    ; DEBUG: Print TP value and first 8 bytes of TLS data
    push rdi                        ; Save exit code
    sub rsp, 48
    mov byte [num_buffer], 'T'
    mov byte [num_buffer+1], 'P'
    mov byte [num_buffer+2], '='
    mov rax, [rbx + 4*8]            ; TP = x4
    push rax                        ; Save TP for later use
    mov ecx, 16
    lea rsi, [num_buffer+3]
.tp_exit_loop:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .tp_exit_digit
    add dl, 'A' - 10
    jmp .tp_exit_store
.tp_exit_digit:
    add dl, '0'
.tp_exit_store:
    mov [rsi], dl
    inc rsi
    dec ecx
    jnz .tp_exit_loop
    mov byte [num_buffer+19], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 20
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; DEBUG: Print first 8 bytes at TP address (TLS data)
    pop rax                         ; Get saved TP value
    mov rdi, [rbp-16]               ; guest memory base
    add rdi, rax                    ; TP in host memory
    mov rax, [rdi]                  ; First 8 bytes of TLS block
    mov byte [num_buffer], 'T'
    mov byte [num_buffer+1], 'D'
    mov byte [num_buffer+2], '='
    lea rsi, [num_buffer+3]
    mov ecx, 16
.td_exit_loop:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .td_exit_digit
    add dl, 'A' - 10
    jmp .td_exit_store
.td_exit_digit:
    add dl, '0'
.td_exit_store:
    mov [rsi], dl
    inc rsi
    dec ecx
    jnz .td_exit_loop
    mov byte [num_buffer+19], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 20
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile

    add rsp, 48
    pop rdi

    ; DEBUG: Print a0 (exit code) before exit
    push rdi
    sub rsp, 48
    mov byte [num_buffer], 'A'
    mov byte [num_buffer+1], '0'
    mov byte [num_buffer+2], '='
    mov rax, [rbx + 10*8]           ; a0 = x10
    shl rax, 32
    lea rsi, [num_buffer+3]
    mov ecx, 8
.a0_exit_loop:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .a0_exit_digit
    add dl, 'A' - 10
    jmp .a0_exit_store
.a0_exit_digit:
    add dl, '0'
.a0_exit_store:
    mov [rsi], dl
    inc rsi
    dec ecx
    jnz .a0_exit_loop
    mov byte [num_buffer+11], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 12
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rdi

%ifdef WINDOWS
    sub rsp, 40
    mov ecx, edi
    call ExitProcess
%else
    ; Linux: syscall exit(status)
    mov eax, 60                 ; SYS_exit
    syscall
%endif

;------------------------------------------------------------------------------
; read(fd, buf, count) - syscall 63
; a0 = fd, a1 = buf (guest addr), a2 = count
; Returns bytes read, or negative errno
;------------------------------------------------------------------------------
.syscall_read:
    mov rax, [rbx + 10*8]           ; a0 = fd

    ; stdin - return EOF for now
    test rax, rax
    jz .read_eof

    ; Check if it's a file fd
    cmp rax, FD_OFFSET
    jb .read_ebadf
    sub rax, FD_OFFSET
    cmp rax, MAX_OPEN_FILES
    jae .read_ebadf

    ; Get handle from file table
    lea rcx, [file_table]
    mov rcx, [rcx + rax*8]
    test rcx, rcx
    jz .read_ebadf

    ; Call ReadFile(handle, buffer, count, &bytes_read, NULL)
    push rbx
    sub rsp, 56                     ; Shadow space + overlapped

    mov rdi, [rbp-16]               ; guest memory base
    mov rax, [rbx + 11*8]           ; a1 = buffer (guest addr)
    add rdi, rax                    ; host buffer address

    ; RCX already has handle
    mov rdx, rdi                    ; lpBuffer
    mov r8, [rbx + 12*8]            ; nNumberOfBytesToRead
    lea r9, [bytes_read_tmp]        ; lpNumberOfBytesRead
    mov qword [rsp+32], 0           ; lpOverlapped = NULL
    call ReadFile

    add rsp, 56
    pop rbx

    test eax, eax               ; Check ReadFile return value
    jz .read_error

    ; Debug: print read fd, size, and first 8 bytes for large reads (>1000 bytes)
    mov rax, [bytes_read_tmp]
    cmp rax, 1000
    jb .skip_read_debug
    push rax
    push rdi
    sub rsp, 48
    mov byte [num_buffer], 'R'
    mov byte [num_buffer+1], 'D'
    mov byte [num_buffer+2], ':'
    ; Print fd (from saved regs)
    mov rax, [rbx + 10*8]
    sub eax, FD_OFFSET
    lea rdi, [num_buffer+3]
    mov ecx, 2
.rd_fd_loop:
    rol eax, 4
    mov edx, eax
    and edx, 0xF
    add dl, '0'
    cmp dl, '9'
    jbe .rd_fd_ok
    add dl, 7
.rd_fd_ok:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .rd_fd_loop
    mov byte [rdi], ' '
    inc rdi
    ; Print size
    mov rax, [bytes_read_tmp]
    mov ecx, 8
.rd_sz_loop:
    rol eax, 4
    mov edx, eax
    and edx, 0xF
    add dl, '0'
    cmp dl, '9'
    jbe .rd_sz_ok
    add dl, 7
.rd_sz_ok:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .rd_sz_loop
    mov byte [rdi], ' '
    inc rdi
    ; Print first 8 bytes of data
    mov rsi, [rbp-16]           ; guest memory
    mov rax, [rbx + 11*8]       ; buffer address
    add rsi, rax
    mov ecx, 8
.rd_dat_loop:
    movzx eax, byte [rsi]
    mov edx, eax
    shr edx, 4
    add dl, '0'
    cmp dl, '9'
    jbe .rd_dat_h
    add dl, 7
.rd_dat_h:
    mov [rdi], dl
    inc rdi
    and al, 0xF
    add al, '0'
    cmp al, '9'
    jbe .rd_dat_l
    add al, 7
.rd_dat_l:
    mov [rdi], al
    inc rdi
    inc rsi
    dec ecx
    jnz .rd_dat_loop
    mov byte [rdi], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 32
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rdi
    pop rax
.skip_read_debug:

    ; Return bytes read
    mov [rbx + 10*8], rax
    jmp .exec_loop

.read_eof:
    mov qword [rbx + 10*8], 0
    jmp .exec_loop

.read_error:
    mov qword [rbx + 10*8], -5      ; -EIO
    jmp .exec_loop

.read_ebadf:
    mov qword [rbx + 10*8], -9      ; -EBADF
    jmp .exec_loop

;------------------------------------------------------------------------------
; lseek(fd, offset, whence) - syscall 62
; a0 = fd, a1 = offset, a2 = whence (0=SEEK_SET, 1=SEEK_CUR, 2=SEEK_END)
; Returns new offset on success, negative errno on error
;------------------------------------------------------------------------------
.syscall_lseek:
    mov rax, [rbx + 10*8]           ; a0 = fd

    ; Check if it's a file fd
    cmp rax, FD_OFFSET
    jb .lseek_ebadf
    sub rax, FD_OFFSET
    cmp rax, MAX_OPEN_FILES
    jae .lseek_ebadf

    ; Get handle from file table
    lea rcx, [file_table]
    mov rcx, [rcx + rax*8]
    test rcx, rcx
    jz .lseek_ebadf

    ; Call SetFilePointer(handle, low_offset, NULL, whence)
    ; rcx already has handle
    ; Linux: SEEK_SET=0, SEEK_CUR=1, SEEK_END=2
    ; Windows: FILE_BEGIN=0, FILE_CURRENT=1, FILE_END=2 (they match!)
    push rbx
    sub rsp, 48

    mov rax, [rbx + 11*8]           ; a1 = offset (64-bit)
    mov edx, eax                    ; lDistanceToMove (low 32 bits)
    xor r8d, r8d                    ; lpDistanceToMoveHigh = NULL (32-bit seek)
    mov r9, [rbx + 12*8]            ; a2 = whence -> dwMoveMethod
    ; rcx already has handle
    call SetFilePointer

    ; Check for error (INVALID_SET_FILE_POINTER = -1)
    cmp eax, -1
    je .lseek_check_error

    ; For 32-bit seeks, rax just holds the new position
    add rsp, 48
    pop rbx
    mov [rbx + 10*8], rax
    jmp .exec_loop

.lseek_check_error:
    ; Return error
    add rsp, 48
    pop rbx
    mov qword [rbx + 10*8], -22     ; -EINVAL
    jmp .exec_loop

.lseek_ebadf:
    mov qword [rbx + 10*8], -9      ; -EBADF
    jmp .exec_loop

;------------------------------------------------------------------------------
; write(fd, buf, count) - syscall 64
; a0 = fd, a1 = buf (guest addr), a2 = count
; Returns bytes written, or negative errno
;------------------------------------------------------------------------------
.syscall_write:
    ; Get fd
    mov rax, [rbx + 10*8]       ; a0 = fd
    cmp rax, 1
    je .write_stdout
    cmp rax, 2
    je .write_stdout            ; stderr -> stdout for now

    ; Unsupported fd
    mov qword [rbx + 10*8], -9  ; -EBADF
    jmp .exec_loop

.write_stdout:
    ; Simple debug marker (DISABLED for perf)
    jmp .skip_write_marker
    push rax
    sub rsp, 48
    mov byte [num_buffer], 'W'
    mov byte [num_buffer+1], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 2
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rax

.skip_write_marker:
    ; Get buffer address (guest) and count
    mov rsi, [rbx + 11*8]       ; a1 = buf (guest offset)
    mov r8, [rbx + 12*8]        ; a2 = count (use r8 for Windows call)

    ; Debug: print buffer address for first 5 writes (DISABLED for perf)
    jmp .skip_buf_debug_no_pop
    push rax
    mov rax, [syscall_count]
    cmp rax, 5
    ja .skip_buf_debug
    ; Print "W:XXXXXXXX C:XXXX\n" (buffer address and count)
    push rsi
    push r8
    sub rsp, 48
    mov byte [num_buffer], 'W'
    mov byte [num_buffer+1], ':'
    ; Print guest buffer address as 8 hex digits (MSB first)
    mov eax, esi                ; Guest buffer address
    mov edi, 8
    lea rcx, [num_buffer+2]
.wbuf_hex:
    rol eax, 4                  ; Rotate MSB nibble to LSB
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .wbuf_digit
    add dl, 'A' - 10
    jmp .wbuf_store
.wbuf_digit:
    add dl, '0'
.wbuf_store:
    mov [rcx], dl
    inc rcx
    dec edi
    jnz .wbuf_hex
    mov byte [num_buffer+10], ' '
    mov byte [num_buffer+11], 'C'
    mov byte [num_buffer+12], ':'
    ; Also print count as 4 hex digits
    pop r8                      ; Restore count
    push r8                     ; Save again
    mov eax, r8d
    mov edi, 4
    lea rcx, [num_buffer+13]
.wcnt_hex:
    rol eax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .wcnt_digit
    add dl, 'A' - 10
    jmp .wcnt_store
.wcnt_digit:
    add dl, '0'
.wcnt_store:
    mov [rcx], dl
    inc rcx
    dec edi
    jnz .wcnt_hex
    mov byte [num_buffer+17], 10    ; newline
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 18
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop r8                      ; Restore count
    pop rsi                     ; Restore buffer address
.skip_buf_debug:
    pop rax
.skip_buf_debug_no_pop:

    ; Convert guest address to host address
    mov rdi, [rbp-16]           ; guest memory base
    add rsi, rdi                ; RSI = host address of buffer

    ; Reload r8 (for count)
    mov r8, [rbx + 12*8]

    ; Debug: skip if count is 0
    test r8, r8
    jz .write_zero

    ; DEBUG: Check if writing single byte 'C' (0x43) to trace the corruption
    cmp r8, 1                   ; Single byte write?
    jne .skip_c_debug
    cmp byte [rsi], 0x43        ; Writing 'C'?
    jne .skip_c_debug
    ; Print "!C:XXXXXXXX\n" showing guest address where 'C' came from
    push rax
    push rsi
    push r8
    sub rsp, 48
    mov byte [num_buffer], '!'
    mov byte [num_buffer+1], 'C'
    mov byte [num_buffer+2], ':'
    ; Guest address = rsi - rdi = [rbx + 11*8]
    mov eax, [rbx + 11*8]       ; Guest buffer address
    mov edi, 8
    lea rcx, [num_buffer+3]
.c_hex:
    rol eax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .c_digit
    add dl, 'A' - 10
    jmp .c_store
.c_digit:
    add dl, '0'
.c_store:
    mov [rcx], dl
    inc rcx
    dec edi
    jnz .c_hex
    mov byte [num_buffer+11], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 12
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop r8
    pop rsi
    pop rax
.skip_c_debug:

    ; Save rbx and count across Windows call
    push rbx
    push r8                     ; Save count
    push rsi                    ; Save buffer address

    ; Call Windows WriteFile(stdout_handle, buf, count, &written, NULL)
    ; RCX = handle, RDX = buffer, R8 = count, R9 = &written
    sub rsp, 48                 ; Shadow space + 5th arg
    mov rcx, [stdout_handle]
    mov rdx, rsi                ; buffer
    ; r8 already has count
    lea r9, [bytes_written]
    mov qword [rsp+32], 0       ; lpOverlapped = NULL
    call WriteFile

    add rsp, 48
    pop rsi                     ; Restore buffer address
    pop rax                     ; Get count
    pop rbx                     ; Restore rbx

    ; Return actual bytes written from WriteFile
    mov rax, [bytes_written]
    mov [rbx + 10*8], rax
    jmp .exec_loop

.write_zero:
    ; Zero-byte write - just return 0
    mov qword [rbx + 10*8], 0
    jmp .exec_loop

;------------------------------------------------------------------------------
; brk(addr) - syscall 214
; a0 = new break address (0 = query current)
; Returns current/new break address, or -1 on error
;------------------------------------------------------------------------------
.syscall_brk:
    ; DEBUG: Print brk request
    push rbx
    sub rsp, 48
    mov byte [num_buffer], 'B'
    mov byte [num_buffer+1], 'R'
    mov byte [num_buffer+2], 'K'
    mov byte [num_buffer+3], '='
    mov rax, [rbx + 10*8]       ; a0 = requested break
    shl rax, 32                 ; Move to upper 32 bits for rotation
    lea rsi, [num_buffer+4]
    mov ecx, 8
.brk_debug_loop:
    rol rax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .brk_debug_digit
    add dl, 'A' - 10
    jmp .brk_debug_store
.brk_debug_digit:
    add dl, '0'
.brk_debug_store:
    mov [rsi], dl
    inc rsi
    dec ecx
    jnz .brk_debug_loop
    mov byte [num_buffer+12], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 13
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rbx
    ; END DEBUG

    ; Simple brk implementation using a static heap pointer
    ; Heap starts at end of loaded segments (we'll use a fixed address for now)
    ;
    ; If a0 == 0: return current break
    ; If a0 > current: extend break (if within limits)
    ; If a0 < current: shrink break

    mov rax, [rbx + 10*8]       ; a0 = requested break

    ; Get current break from a reserved location
    ; We'll store it at guest_memory + 0xF000 (near end of 64KB)
    mov rdi, [rbp-16]           ; guest memory base
    mov rcx, [rdi + 0xF000]     ; current break

    ; If break not initialized, use elf_brk_base (end of loaded segments)
    test rcx, rcx
    jnz .brk_initialized
    mov rcx, [elf_brk_base]     ; Start heap at end of ELF segments
    test rcx, rcx
    jnz .brk_store_initial
    mov rcx, 0x10000            ; Fallback: 64KB if brk_base not set
.brk_store_initial:
    mov [rdi + 0xF000], rcx

.brk_initialized:
    ; If a0 == 0, just return current break
    test rax, rax
    jz .brk_return_current

    ; Check if new break is valid
    mov r8, [elf_brk_base]      ; Get minimum valid break
    test r8, r8
    jnz .brk_check_min
    mov r8, 0x10000             ; Fallback minimum
.brk_check_min:
    cmp rax, r8                 ; Must be >= elf_brk_base
    jb .brk_return_current      ; Too low, return current
    cmp rax, 0x6000000          ; Must be < 96MB (leave room for stack)
    ja .brk_return_current      ; Too high, return current

    ; Set new break
    mov [rdi + 0xF000], rax
    mov [rbx + 10*8], rax       ; Return new break
    jmp .exec_loop

.brk_return_current:
    mov [rbx + 10*8], rcx       ; Return current break
    jmp .exec_loop

;------------------------------------------------------------------------------
; mmap(addr, len, prot, flags, fd, offset) - syscall 222
; For anonymous mappings only (fd=-1, MAP_ANONYMOUS)
; Returns mapped address, or negative errno
;------------------------------------------------------------------------------
.syscall_mmap:
    ; Check if this is anonymous mapping (fd == -1 or 0xFFFFFFFF)
    mov rax, [rbx + 14*8]       ; a4 = fd
    cmp rax, -1
    jne .mmap_check_anon_flags
    jmp .mmap_do_anon

.mmap_check_anon_flags:
    ; Check if MAP_ANONYMOUS (0x20) is set in flags (a3)
    mov rax, [rbx + 13*8]       ; a3 = flags
    test rax, 0x20              ; MAP_ANONYMOUS
    jz .mmap_enodev             ; If not anonymous, reject
    ; Fall through to do anonymous mapping

.mmap_do_anon:
    ; For anonymous mappings, just bump the break
    ; This is a simplification - real mmap would be more complex
    mov rdi, [rbp-16]           ; guest memory base
    mov rcx, [rdi + 0xF000]     ; current break

    ; If not initialized, init it
    test rcx, rcx
    jnz .mmap_have_break
    mov rcx, 0x10000
    mov [rdi + 0xF000], rcx

.mmap_have_break:
    ; Allocate len bytes
    mov rax, [rbx + 11*8]       ; a1 = len

    ; Check if fits (within 96MB limit)
    mov rdx, rcx
    add rdx, rax
    cmp rdx, 0x6000000
    ja .mmap_enomem

    ; Return current break as mapped address
    mov [rbx + 10*8], rcx

    ; Update break
    mov [rdi + 0xF000], rdx
    jmp .exec_loop

.mmap_enodev:
    mov qword [rbx + 10*8], -19 ; -ENODEV (no file mappings)
    jmp .exec_loop

.mmap_enomem:
    mov qword [rbx + 10*8], -12 ; -ENOMEM
    jmp .exec_loop

;------------------------------------------------------------------------------
; ioctl(fd, request, ...) - syscall 29
; a0 = fd, a1 = request, a2 = arg
; Returns 0 on success, negative errno on error
;------------------------------------------------------------------------------
.syscall_ioctl:
    mov rax, [rbx + 10*8]       ; a0 = fd
    mov rcx, [rbx + 11*8]       ; a1 = request

    ; Only support stdin/stdout/stderr
    cmp rax, 2
    ja .ioctl_ebadf

    ; TIOCGWINSZ (0x5413) - get window size
    ; Return something sensible for terminals
    cmp rcx, 0x5413
    jne .ioctl_enotty

    ; Write a fake winsize struct to the buffer
    ; struct winsize { uint16_t ws_row, ws_col, ws_xpixel, ws_ypixel; }
    mov rdi, [rbp-16]           ; guest memory base
    mov rax, [rbx + 12*8]       ; a2 = arg (guest address)
    add rdi, rax                ; host address

    mov word [rdi], 24          ; ws_row = 24
    mov word [rdi+2], 80        ; ws_col = 80
    mov word [rdi+4], 0         ; ws_xpixel = 0
    mov word [rdi+6], 0         ; ws_ypixel = 0

    mov qword [rbx + 10*8], 0   ; success
    jmp .exec_loop

.ioctl_enotty:
    mov qword [rbx + 10*8], -25 ; -ENOTTY
    jmp .exec_loop

.ioctl_ebadf:
    mov qword [rbx + 10*8], -9  ; -EBADF
    jmp .exec_loop

;------------------------------------------------------------------------------
; Stub syscalls that just return success
;------------------------------------------------------------------------------
.syscall_stub_success:
    mov qword [rbx + 10*8], 0
    jmp .exec_loop

.syscall_stub_error:
    mov qword [rbx + 10*8], -2      ; -ENOENT
    jmp .exec_loop

;------------------------------------------------------------------------------
; faccessat - syscall 48
; Check file accessibility (simplified: always return success)
;------------------------------------------------------------------------------
.syscall_faccessat:
    mov qword [rbx + 10*8], 0       ; Return success
    jmp .exec_loop

;------------------------------------------------------------------------------
; getcwd - syscall 17
; Get current working directory
;------------------------------------------------------------------------------
.syscall_getcwd:
    ; Just return "/" as current directory
    mov rdi, [rbp-16]               ; guest memory base
    mov rax, [rbx + 10*8]           ; a0 = buffer (guest addr)
    add rdi, rax
    mov byte [rdi], '/'
    mov byte [rdi+1], 0
    mov qword [rbx + 10*8], 1       ; Return length
    jmp .exec_loop

;------------------------------------------------------------------------------
; fstatat - syscall 79
; Get file status
;------------------------------------------------------------------------------
.syscall_fstatat:
    ; For now, return error - file not found
    mov qword [rbx + 10*8], -2      ; -ENOENT
    jmp .exec_loop

;------------------------------------------------------------------------------
; writev - syscall 66
; Write from multiple buffers (iovec)
; a0 = fd, a1 = iov (guest addr), a2 = iovcnt
;------------------------------------------------------------------------------
.syscall_writev:
    push r12
    push r13
    push r14
    sub rsp, 56

    mov r12, [rbx + 11*8]           ; a1 = iov pointer (guest)
    add r12, [rbp-16]               ; Convert to host addr
    mov r13d, [rbx + 12*8]          ; a2 = iovcnt
    xor r14d, r14d                  ; Total bytes written

    ; Get appropriate handle (stdout=1, stderr=2)
    mov rax, [rbx + 10*8]           ; fd
    cmp rax, 1
    je .writev_stdout
    cmp rax, 2
    je .writev_stderr
    ; Unknown fd - return error
    mov qword [rbx + 10*8], -9      ; -EBADF
    jmp .writev_done

.writev_stdout:
    mov rcx, [stdout_handle]
    jmp .writev_loop

.writev_stderr:
    ; Suppress stderr output (glibc assertions) - just return fake success
    ; Calculate total bytes we "would have" written
    push rdi
    push rsi
    xor eax, eax                    ; total = 0
    mov edi, [rbx + 12*8]           ; iovcnt
    mov rsi, [rbx + 11*8]           ; iov base (guest)
    add rsi, [rbp-16]               ; + guest base for host addr
.writev_stderr_count:
    test edi, edi
    jz .writev_stderr_done
    add eax, [rsi + 8]              ; add iov_len (low 32 bits)
    add rsi, 16                     ; next iov
    dec edi
    jmp .writev_stderr_count
.writev_stderr_done:
    mov [rbx + 10*8], rax           ; Return fake bytes written
    pop rsi
    pop rdi
    jmp .writev_done

.writev_loop:
    test r13d, r13d
    jz .writev_success

    ; Get iov_base and iov_len
    mov rdi, [r12]                  ; iov_base (guest addr)
    add rdi, [rbp-16]               ; Convert to host
    mov rsi, [r12 + 8]              ; iov_len

    ; WriteFile(handle, buffer, count, &written, NULL)
    mov [rsp+48], rcx               ; Save handle
    mov rdx, rdi                    ; buffer
    mov r8, rsi                     ; count
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteFile
    mov rcx, [rsp+48]               ; Restore handle

    ; Add bytes written to total
    add r14d, [bytes_written]

    ; Next iovec (16 bytes each)
    add r12, 16
    dec r13d
    jmp .writev_loop

.writev_success:
    mov [rbx + 10*8], r14           ; Return total bytes written

.writev_done:
    add rsp, 56
    pop r14
    pop r13
    pop r12
    jmp .exec_loop

;------------------------------------------------------------------------------
; set_tid_address - syscall 96
;------------------------------------------------------------------------------
.syscall_set_tid_address:
    mov qword [rbx + 10*8], 1       ; Return fake TID
    jmp .exec_loop

;------------------------------------------------------------------------------
; kill/tkill/tgkill - signal syscalls
; Ignore signals and continue (glibc assertions call abort which raises SIGABRT)
;------------------------------------------------------------------------------
.syscall_signal_exit:
    ; Just return success and continue - ignore the signal
    mov qword [rbx + 10*8], 0       ; Return success
    jmp .exec_loop

.syscall_signal_exit_old:
    ; For tgkill: a0=tgid, a1=tid, a2=sig
    ; For kill: a0=pid, a1=sig
    ; For tkill: a0=tid, a1=sig
    ; Get signal number - try a2 first (tgkill), then a1
    mov rax, [rbx + 12*8]           ; a2 for tgkill
    test rax, rax
    jnz .signal_have_sig
    mov rax, [rbx + 11*8]           ; a1 for kill/tkill
.signal_have_sig:
    push rax                        ; Save signal
    ; Print "SIG XX PC=XXXXXXXX" debug message
    sub rsp, 48
    mov byte [num_buffer], 'S'
    mov byte [num_buffer+1], 'I'
    mov byte [num_buffer+2], 'G'
    ; Signal number (2 hex digits)
    mov ecx, eax
    shr ecx, 4
    and ecx, 0xF
    add cl, '0'
    cmp cl, '9'
    jbe .sig_d1
    add cl, 7
.sig_d1:
    mov [num_buffer+3], cl
    mov ecx, eax
    and ecx, 0xF
    add cl, '0'
    cmp cl, '9'
    jbe .sig_d2
    add cl, 7
.sig_d2:
    mov [num_buffer+4], cl
    mov byte [num_buffer+5], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 6
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rax
    ; Exit with code 128 + signal (Unix convention)
    add eax, 128
    mov ecx, eax
    sub rsp, 40
    call ExitProcess

;------------------------------------------------------------------------------
; getpid/gettid - syscall 172/178
;------------------------------------------------------------------------------
.syscall_getpid:
    mov qword [rbx + 10*8], 1       ; Fake PID
    jmp .exec_loop

;------------------------------------------------------------------------------
; getuid/geteuid/getgid/getegid - syscall 174-177
;------------------------------------------------------------------------------
.syscall_getuid:
    mov qword [rbx + 10*8], 1000    ; Fake UID
    jmp .exec_loop

;------------------------------------------------------------------------------
; uname - syscall 160
; a0 = struct utsname* (guest addr)
;------------------------------------------------------------------------------
.syscall_uname:
    mov rdi, [rbp-16]               ; guest memory base
    mov rax, [rbx + 10*8]           ; a0 = buf (guest addr)
    add rdi, rax                    ; host address

    ; struct utsname has 6 65-byte fields
    ; sysname, nodename, release, version, machine, domainname
    ; Just fill with minimal data
    mov byte [rdi], 'L'
    mov byte [rdi+1], 'i'
    mov byte [rdi+2], 'n'
    mov byte [rdi+3], 'u'
    mov byte [rdi+4], 'x'
    mov byte [rdi+5], 0

    ; nodename at +65
    mov byte [rdi+65], 'c'
    mov byte [rdi+66], 'o'
    mov byte [rdi+67], 'n'
    mov byte [rdi+68], 'w'
    mov byte [rdi+69], 'a'
    mov byte [rdi+70], 'y'
    mov byte [rdi+71], 0

    ; release at +130
    mov byte [rdi+130], '6'
    mov byte [rdi+131], '.'
    mov byte [rdi+132], '1'
    mov byte [rdi+133], '.'
    mov byte [rdi+134], '0'
    mov byte [rdi+135], 0

    ; version at +195
    mov byte [rdi+195], '#'
    mov byte [rdi+196], '1'
    mov byte [rdi+197], 0

    ; machine at +260
    mov byte [rdi+260], 'r'
    mov byte [rdi+261], 'i'
    mov byte [rdi+262], 's'
    mov byte [rdi+263], 'c'
    mov byte [rdi+264], 'v'
    mov byte [rdi+265], '6'
    mov byte [rdi+266], '4'
    mov byte [rdi+267], 0

    mov qword [rbx + 10*8], 0
    jmp .exec_loop

;------------------------------------------------------------------------------
; prlimit64 - syscall 261
; Just return success
;------------------------------------------------------------------------------
.syscall_prlimit64:
    mov qword [rbx + 10*8], 0
    jmp .exec_loop

;------------------------------------------------------------------------------
; getrandom - syscall 278
; a0 = buf, a1 = buflen, a2 = flags
; Fill with deterministic "random" data
;------------------------------------------------------------------------------
.syscall_getrandom:
    mov rdi, [rbp-16]               ; guest memory base
    mov rax, [rbx + 10*8]           ; a0 = buf (guest addr)
    add rdi, rax                    ; host address
    mov rcx, [rbx + 11*8]           ; a1 = buflen

    ; Fill with simple pattern
    xor eax, eax
.random_loop:
    test rcx, rcx
    jz .random_done
    mov byte [rdi], al
    inc al
    inc rdi
    dec rcx
    jmp .random_loop
.random_done:
    mov rax, [rbx + 11*8]           ; Return buflen
    mov [rbx + 10*8], rax
    jmp .exec_loop

;------------------------------------------------------------------------------
; futex - syscall 98
; Just return success (we're single-threaded)
;------------------------------------------------------------------------------
.syscall_futex:
    mov qword [rbx + 10*8], 0
    jmp .exec_loop

;------------------------------------------------------------------------------
; openat(dirfd, pathname, flags, mode) - syscall 56
; a0 = dirfd (-100 = AT_FDCWD), a1 = pathname, a2 = flags, a3 = mode
; Returns fd on success, negative errno on error
;------------------------------------------------------------------------------
.syscall_openat:
    push rbx
    push r12                        ; Save callee-saved registers we'll use
    push r13
    sub rsp, 80                     ; Shadow space + locals (80 for 16-byte alignment)

    ; Validate guest memory base
    mov rdi, [rbp-16]               ; Guest memory base
    test rdi, rdi
    jz .openat_enoent               ; Invalid guest memory

    ; Get pathname from guest memory
    mov rax, [rbx + 11*8]           ; a1 = pathname (guest addr)
    add rdi, rax                    ; RDI = host addr of pathname

    ; Copy pathname to path buffer with slash conversion
    mov rsi, [path_buffer_ptr]      ; Dest buffer
    mov ecx, 259                    ; Max path length

.copy_path:
    mov al, [rdi]
    cmp al, '/'             ; Convert Unix path separators
    jne .no_slash_convert
    mov al, '\'
.no_slash_convert:
    mov [rsi], al
    test al, al
    jz .path_done_clean
    inc rdi
    inc rsi
    dec ecx
    jnz .copy_path
    mov byte [rsi], 0

.path_done_clean:
    ; Skip leading ".\" if present (current directory prefix)
    mov rsi, [path_buffer_ptr]
    cmp byte [rsi], '.'
    jne .path_ready
    cmp byte [rsi+1], '\'
    jne .path_ready
    add rsi, 2              ; Skip ".\"
    mov rdi, [path_buffer_ptr]
.shift_path:
    mov al, [rsi]
    mov [rdi], al
    test al, al
    jz .path_ready
    inc rsi
    inc rdi
    jmp .shift_path
.path_ready:
    ; Find a free slot in file table
    xor eax, eax
    lea r10, [file_table]           ; R10 = file table base
.find_slot:
    cmp eax, MAX_OPEN_FILES
    jge .openat_emfile
    mov rcx, [r10 + rax*8]
    test rcx, rcx
    jz .found_slot
    inc eax
    jmp .find_slot

.found_slot:
    ; Save slot index and file table base in callee-saved registers
    ; (push/pop would put them where CreateFileA's shadow space would clobber them)
    mov r12d, eax                   ; Save slot index in r12
    mov r13, r10                    ; Save file table base in r13

    ; Check Linux flags from a2 (x12) to determine access mode
    mov rax, [rbx + 12*8]           ; Get flags from a2
    mov r11, rax                    ; Save flags for later

    ; Call CreateFileA
    ; RCX = lpFileName
    ; RDX = dwDesiredAccess
    ; R8 = dwShareMode
    ; R9 = lpSecurityAttributes
    ; [rsp+32] = dwCreationDisposition
    ; [rsp+40] = dwFlagsAndAttributes
    ; [rsp+48] = hTemplateFile
    mov rcx, [path_buffer_ptr]

    ; Determine access mode based on O_RDONLY(0), O_WRONLY(1), O_RDWR(2)
    mov edx, GENERIC_READ           ; Default: read
    test r11d, 3                    ; Check access bits
    jz .openat_access_done          ; O_RDONLY = 0
    test r11d, 1
    jz .openat_rdwr
    mov edx, GENERIC_WRITE          ; O_WRONLY = 1
    jmp .openat_access_done
.openat_rdwr:
    mov edx, GENERIC_READ
    or edx, GENERIC_WRITE           ; O_RDWR = 2

.openat_access_done:
    mov r8d, FILE_SHARE_READ
    or r8d, FILE_SHARE_WRITE        ; Allow sharing
    xor r9d, r9d

    ; Determine creation disposition based on O_CREAT (0x40), O_TRUNC (0x200)
    mov eax, OPEN_EXISTING          ; Default
    test r11d, 0x40                 ; O_CREAT?
    jz .openat_disp_done
    test r11d, 0x200                ; O_TRUNC?
    jz .openat_create_new
    mov eax, CREATE_ALWAYS          ; O_CREAT | O_TRUNC
    jmp .openat_disp_done
.openat_create_new:
    mov eax, OPEN_ALWAYS            ; O_CREAT without O_TRUNC
.openat_disp_done:
    mov qword [rsp+32], rax                     ; dwCreationDisposition
    mov qword [rsp+40], FILE_ATTRIBUTE_NORMAL   ; dwFlagsAndAttributes
    mov qword [rsp+48], 0                       ; hTemplateFile
    call CreateFileA

    ; Check if open succeeded
    mov r10, r13                    ; Restore file table base from r13
    mov ecx, r12d                   ; Restore slot index from r12
    cmp rax, INVALID_HANDLE_VALUE
    jne .openat_success

    ; First try failed - check if it's a WAD file and retry with known path
    mov rsi, [path_buffer_ptr]
    ; Find end of filename
.find_wad_ext:
    mov al, [rsi]
    test al, al
    jz .check_wad
    inc rsi
    jmp .find_wad_ext
.check_wad:
    ; Check if ends in ".wad" (case insensitive)
    cmp byte [rsi-4], '.'
    jne .openat_enoent
    mov al, [rsi-3]
    or al, 0x20                     ; lowercase
    cmp al, 'w'
    jne .openat_enoent
    mov al, [rsi-2]
    or al, 0x20
    cmp al, 'a'
    jne .openat_enoent
    mov al, [rsi-1]
    or al, 0x20
    cmp al, 'd'
    jne .openat_enoent

    ; It's a WAD - build path with "C:\dev\conway\test\" prefix
    lea rsi, [wad_search_path]      ; Source: "C:\dev\conway\test\"
    lea rdi, [wad_path_buffer]      ; Dest buffer
.copy_prefix:
    mov al, [rsi]
    test al, al
    jz .append_filename
    mov [rdi], al
    inc rsi
    inc rdi
    jmp .copy_prefix
.append_filename:
    mov rsi, [path_buffer_ptr]      ; Original filename
.copy_filename:
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    test al, al
    jnz .copy_filename

    ; Retry with full path
    lea rcx, [wad_path_buffer]
    mov edx, GENERIC_READ
    mov r8d, FILE_SHARE_READ
    or r8d, FILE_SHARE_WRITE
    xor r9d, r9d
    mov qword [rsp+32], OPEN_EXISTING
    mov qword [rsp+40], FILE_ATTRIBUTE_NORMAL
    mov qword [rsp+48], 0
    call CreateFileA

    ; Check retry result
    mov r10, r13
    mov ecx, r12d
    cmp rax, INVALID_HANDLE_VALUE
    je .openat_enoent

.openat_success:
    ; Store handle in file table
    mov [r10 + rcx*8], rax

    ; Return fd = slot + FD_OFFSET
    add ecx, FD_OFFSET
    add rsp, 80
    pop r13
    pop r12
    pop rbx
    mov [rbx + 10*8], rcx
    jmp .exec_loop

.openat_emfile:
    add rsp, 80
    pop r13
    pop r12
    pop rbx
    mov qword [rbx + 10*8], -24     ; -EMFILE (too many open files)
    jmp .exec_loop

.openat_enoent:
    add rsp, 80
    pop r13
    pop r12
    pop rbx
    mov qword [rbx + 10*8], -2      ; -ENOENT
    jmp .exec_loop

;------------------------------------------------------------------------------
; close(fd) - syscall 57
; a0 = fd
; Returns 0 on success, negative errno on error
;------------------------------------------------------------------------------
.syscall_close:
    mov rax, [rbx + 10*8]           ; a0 = fd

    ; Don't close stdin/stdout/stderr
    cmp rax, 2
    jbe .close_success

    ; Check if it's a valid fd
    sub rax, FD_OFFSET
    cmp rax, MAX_OPEN_FILES
    jae .close_success              ; Invalid fd, just return success

    ; Get handle from file table
    lea r10, [file_table]
    mov rcx, [r10 + rax*8]
    test rcx, rcx
    jz .close_success               ; Not open, return success

    ; Clear file table entry
    mov qword [r10 + rax*8], 0

    ; Call CloseHandle
    sub rsp, 40
    call CloseHandle
    add rsp, 40

.close_success:
    mov qword [rbx + 10*8], 0
    jmp .exec_loop

;------------------------------------------------------------------------------
; fstat(fd, statbuf) - syscall 80
; a0 = fd, a1 = statbuf (guest address)
; Returns 0 on success, negative errno on error
;------------------------------------------------------------------------------
.syscall_fstat:
    mov rax, [rbx + 10*8]       ; a0 = fd

    ; Only support stdin/stdout/stderr
    cmp rax, 2
    ja .fstat_ebadf

    ; Write a minimal stat struct for a character device (terminal)
    ; RISC-V Linux stat struct (LP64):
    ; struct stat {
    ;   uint64_t st_dev;          // 0
    ;   uint64_t st_ino;          // 8
    ;   uint32_t st_mode;         // 16
    ;   uint32_t st_nlink;        // 20
    ;   uint32_t st_uid;          // 24
    ;   uint32_t st_gid;          // 28
    ;   uint64_t st_rdev;         // 32
    ;   uint64_t __pad1;          // 40
    ;   int64_t  st_size;         // 48
    ;   int32_t  st_blksize;      // 56
    ;   int32_t  __pad2;          // 60
    ;   int64_t  st_blocks;       // 64
    ;   ... timespec fields ...   // 72+
    ; }

    mov rdi, [rbp-16]           ; guest memory base
    mov rcx, [rbx + 11*8]       ; a1 = statbuf (guest address)
    add rdi, rcx                ; host address

    ; Zero the struct first (128 bytes should cover it)
    push rdi
    xor eax, eax
    mov ecx, 16                 ; 16 qwords = 128 bytes
.fstat_zero:
    mov [rdi], rax
    add rdi, 8
    dec ecx
    jnz .fstat_zero
    pop rdi

    ; Fill in key fields
    mov qword [rdi], 0x0005     ; st_dev = 5 (tty)
    mov qword [rdi+8], 1        ; st_ino = 1
    mov dword [rdi+16], 0x2190  ; st_mode = S_IFCHR | 0600 (character device)
    mov dword [rdi+20], 1       ; st_nlink = 1
    mov qword [rdi+32], 0x0501  ; st_rdev = makedev(5, 1) for /dev/console
    mov dword [rdi+56], 1024    ; st_blksize = 1024

    mov qword [rbx + 10*8], 0   ; success
    jmp .exec_loop

.fstat_ebadf:
    mov qword [rbx + 10*8], -9  ; -EBADF
    jmp .exec_loop

;------------------------------------------------------------------------------
; Conway syscall 1000: DG_DrawFrame
; Flush framebuffer to host display
; Currently a stub - just returns 0
;------------------------------------------------------------------------------
.syscall_drawframe:
    ; Count frames and update ticks
    push rbx
    push r14
    sub rsp, 48

    ; Increment frame counter
    inc qword [frame_count]

    ; Debug: print "F" for first 10 frames
    mov rax, [frame_count]
    cmp rax, 10
    ja .df_no_debug
    mov rcx, [stdout_handle]
    lea rdx, [msg_frame]
    mov r8d, 1
    lea r9, [stdout_written]
    mov qword [rsp+32], 0
    call WriteFile
.df_no_debug:

    ; Update ticks in guest memory (at offset 0x7F0004)
    call GetTickCount
    mov r14, [rbp-16]           ; Guest memory base
    mov edx, [start_ticks]
    test edx, edx
    jnz .df_have_start
    mov [start_ticks], eax      ; First time - save start
    xor eax, eax
.df_have_start:
    sub eax, [start_ticks]      ; Relative ticks since start
    mov [r14 + 0x7F0004], eax   ; Store in guest memory

    add rsp, 48
    pop r14
    pop rbx

    mov qword [rbx + 10*8], 0   ; Return success
    jmp .exec_loop

;------------------------------------------------------------------------------
; Conway syscall 1001: DG_SleepMs(ms)
; a0 = milliseconds to sleep
;------------------------------------------------------------------------------
.syscall_sleepms:
    ; Get ms from a0
    mov rcx, [rbx + 10*8]       ; a0 = ms

    ; Save registers across Windows call
    push rbx
    sub rsp, 32                 ; Shadow space

    ; Call Windows Sleep(ms)
    ; RCX already has ms
    call Sleep

    add rsp, 32
    pop rbx

    ; Return 0 (success)
    mov qword [rbx + 10*8], 0
    jmp .exec_loop

.null_pc_error:
    ; PC became NULL - bad return address / function pointer
    ; Print last 4 PCs from history
    mov rbx, [rbp-24]               ; Get rv_regs pointer
    push rbx
    push r12
    push r13
    sub rsp, 48

    ; Print "NULL a0=XXXXXXXX ra=XXXXXXXX\n"
    mov byte [num_buffer], 'N'
    mov byte [num_buffer+1], 'U'
    mov byte [num_buffer+2], 'L'
    mov byte [num_buffer+3], 'L'
    mov byte [num_buffer+4], ' '
    mov byte [num_buffer+5], 'a'
    mov byte [num_buffer+6], '0'
    mov byte [num_buffer+7], '='

    ; Print a0 (x10) in hex (8 digits)
    mov rax, [rbx + 10*8]           ; a0
    lea rdi, [num_buffer+8]
    mov ecx, 8
.npc_a0_loop:
    rol eax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .npc_a0_dig
    add dl, 'A'-10
    jmp .npc_a0_str
.npc_a0_dig:
    add dl, '0'
.npc_a0_str:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .npc_a0_loop

    ; Also print ra (x1)
    mov byte [rdi], ' '
    mov byte [rdi+1], 'r'
    mov byte [rdi+2], 'a'
    mov byte [rdi+3], '='
    add rdi, 4

    mov rax, [rbx + 1*8]            ; ra = x1
    mov ecx, 8
.npc_ra_loop:
    rol eax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .npc_ra_dig
    add dl, 'A'-10
    jmp .npc_ra_str
.npc_ra_dig:
    add dl, '0'
.npc_ra_str:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .npc_ra_loop

    mov byte [rdi], 13
    mov byte [rdi+1], 10

    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 30                     ; "NULL a0=XXXXXXXX ra=XXXXXXXX\r\n"
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteFile

    ; Print last 4 PCs from history
    mov r12d, 4                     ; Print 4 PCs
    mov r13, [pc_history_idx]
    sub r13, 5                      ; Start from 4 entries back
.npc_hist_loop:
    mov rax, r13
    and rax, 7                      ; Keep in range
    lea rdx, [pc_history]
    mov rax, [rdx + rax*8]

    ; Print "PC: XXXXXXXX\n"
    mov byte [num_buffer], 'P'
    mov byte [num_buffer+1], 'C'
    mov byte [num_buffer+2], ':'
    lea rdi, [num_buffer+3]
    mov ecx, 8
.npc_pc_loop:
    rol eax, 4
    mov edx, eax
    and edx, 0xF
    cmp dl, 10
    jb .npc_pc_dig
    add dl, 'A'-10
    jmp .npc_pc_str
.npc_pc_dig:
    add dl, '0'
.npc_pc_str:
    mov [rdi], dl
    inc rdi
    dec ecx
    jnz .npc_pc_loop

    mov byte [rdi], 13
    mov byte [rdi+1], 10

    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 13
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteFile

    inc r13
    dec r12d
    jnz .npc_hist_loop

    add rsp, 48
    pop r13
    pop r12
    pop rbx
    jmp .done

.xlate_failed:
    ; Debug: print "X" to indicate translation failure
    push rax
    sub rsp, 48
    mov byte [num_buffer], 'X'
    mov byte [num_buffer+1], 13
    mov byte [num_buffer+2], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 3
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48
    pop rax

.done:
    ; Debug: just print "!"
    sub rsp, 48
    mov byte [num_buffer], '!'
    mov byte [num_buffer+1], 13
    mov byte [num_buffer+2], 10
    mov rcx, [stdout_handle]
    lea rdx, [num_buffer]
    mov r8d, 3
    lea r9, [bytes_written]
    mov qword [rsp+32], 0
    call WriteFile
    add rsp, 48

    ; Return final PC
    mov rcx, [rbp-32]
    mov rax, [rcx]

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    add rsp, 80
    pop rbp
    ret

