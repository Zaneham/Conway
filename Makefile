# Conway - RISC-V to x86-64 Binary Translator
# Makefile for Linux (NASM + ld)
# For Windows, use build.bat instead

ASM = nasm
ASMFLAGS = -f elf64 -g -DLINUX
LD = ld

# Source files
SRCDIR = src
INCDIR = include
OBJDIR = obj
BINDIR = bin

SOURCES = translator.asm elf_loader.asm platform_linux.asm
OBJECTS = $(SOURCES:%.asm=$(OBJDIR)/%.o)

TARGET = $(BINDIR)/conway

# Default target
all: dirs $(TARGET)

# Create directories (Linux/Unix)
dirs:
	@mkdir -p $(OBJDIR)
	@mkdir -p $(BINDIR)

# Link
$(TARGET): $(OBJECTS)
	$(LD) -o $@ $(OBJECTS)

# Assemble
$(OBJDIR)/%.o: $(SRCDIR)/%.asm
	$(ASM) $(ASMFLAGS) -I$(INCDIR)/ -o $@ $<

# Clean
clean:
	rm -rf $(OBJDIR) $(BINDIR)

.PHONY: all dirs clean
