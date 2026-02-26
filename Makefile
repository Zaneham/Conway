# Conway - RISC-V to x86-64 Binary Translator
# Makefile for Linux (NASM + GCC)
# For Windows, use build-mingw.bat instead

ASM = nasm
ASMFLAGS = -f elf64 -g -DLINUX
CC = gcc
CFLAGS = -Wall -Wextra -O2

# Directories
SRCDIR = src
INCDIR = include
OBJDIR = obj
BINDIR = bin

# ASM sources (translator + elf_loader + platform, no old main.asm)
ASMSOURCES = translator.asm elf_loader.asm platform_linux.asm
ASMOBJECTS = $(ASMSOURCES:%.asm=$(OBJDIR)/%.o)

# C sources
CSOURCES = main.c
COBJECTS = $(CSOURCES:%.c=$(OBJDIR)/%.o)

TARGET = $(BINDIR)/conway

# Default target
all: dirs $(TARGET)

# Create directories
dirs:
	@mkdir -p $(OBJDIR)
	@mkdir -p $(BINDIR)

# Link with GCC (not raw ld) so we get libc
$(TARGET): $(COBJECTS) $(ASMOBJECTS)
	$(CC) -o $@ $^

# C compilation
$(OBJDIR)/%.o: $(SRCDIR)/%.c
	$(CC) $(CFLAGS) -I$(INCDIR) -c -o $@ $<

# Assemble
$(OBJDIR)/%.o: $(SRCDIR)/%.asm
	$(ASM) $(ASMFLAGS) -I$(INCDIR)/ -o $@ $<

# Clean
clean:
	rm -rf $(OBJDIR) $(BINDIR)

.PHONY: all dirs clean
