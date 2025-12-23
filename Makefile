# Conway - RISC-V to x86-64 Binary Translator
# Makefile for Windows (NASM + GoLink) and Linux (NASM + ld)

ASM = nasm
ASMFLAGS = -f win64 -g
LD = golink
LDFLAGS = /console /entry:main kernel32.dll

# Source files
SRCDIR = src
INCDIR = include
OBJDIR = obj
BINDIR = bin

SOURCES = main.asm decode.asm emit.asm dispatch.asm runtime.asm
OBJECTS = $(SOURCES:%.asm=$(OBJDIR)/%.obj)

TARGET = $(BINDIR)/conway.exe

# Default target
all: dirs $(TARGET)

# Create directories
dirs:
	@if not exist $(OBJDIR) mkdir $(OBJDIR)
	@if not exist $(BINDIR) mkdir $(BINDIR)

# Link
$(TARGET): $(OBJECTS)
	$(LD) $(LDFLAGS) /out:$@ $(OBJECTS)

# Assemble
$(OBJDIR)/%.obj: $(SRCDIR)/%.asm
	$(ASM) $(ASMFLAGS) -I$(INCDIR)/ -o $@ $<

# Clean
clean:
	@if exist $(OBJDIR) rmdir /s /q $(OBJDIR)
	@if exist $(BINDIR) rmdir /s /q $(BINDIR)

# Linux target
linux: ASMFLAGS = -f elf64 -g
linux: LD = ld
linux: LDFLAGS = -o
linux: TARGET = $(BINDIR)/conway
linux: OBJECTS = $(SOURCES:%.asm=$(OBJDIR)/%.o)
linux: dirs $(TARGET)

$(OBJDIR)/%.o: $(SRCDIR)/%.asm
	$(ASM) $(ASMFLAGS) -I$(INCDIR)/ -o $@ $<

.PHONY: all dirs clean linux
