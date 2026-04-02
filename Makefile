# ============================================================================
# WEG_jb - Makefile ajustado
# - Detecta automaticamente se as fontes estão em ./src ou no diretório atual
# - Compila módulos opcionais como mod_vtk_out.f90 e mod_journal_center_io.f90
# - Mantém dependências explícitas para uso seguro com make -j
# ============================================================================

PROJECT   := WEG_jb
OBJDIR    := obj
BINDIR    := bin
TARGET    := $(BINDIR)/weg_jb.x

# Detecta layout do projeto
DEFAULT_SRCDIR := src
ifeq ($(wildcard $(DEFAULT_SRCDIR)/main.f90),)
  SRCDIR := .
else
  SRCDIR := $(DEFAULT_SRCDIR)
endif

FC        := gfortran
MODE      := release
OPENMP    := 1
VECREPORT ?= 0
PROFILE   ?= 0

STDLIB_INC ?=
STDLIB_LIB ?=

WARNFLAGS := -Wall -Wextra -Wimplicit-interface -Wunderflow -Wcharacter-truncation \
             -Wno-unused-dummy-argument -Wno-unused-parameter
BASEFLAGS := -std=f2008 -fimplicit-none -ffree-line-length-none -J$(OBJDIR) -I$(OBJDIR)
DBGFLAGS  := -g -O0 -fcheck=all -fbacktrace -ffpe-trap=invalid,zero,overflow
OMPFLAGS  :=
OPTFLAGS  :=
VECFLAGS  :=
PROFFLAGS :=

ifeq ($(OPENMP),1)
  OMPFLAGS += -fopenmp
else
  OMPFLAGS += -fopenmp-simd
endif

ifeq ($(FC),gfortran)
  OPTFLAGS += -O3 -march=native -mtune=native -funroll-loops -fbacktrace
  ifeq ($(MODE),release)
    OPTFLAGS += -flto
  endif
  ifeq ($(VECREPORT),1)
    VECFLAGS += -fopt-info-vec-optimized -fopt-info-vec-missed
  endif
  ifeq ($(PROFILE),1)
    PROFFLAGS += -pg
  endif
else ifeq ($(FC),ifx)
  OPTFLAGS += -O3 -xHost -ipo -qopenmp -fp-model=precise -traceback
  OMPFLAGS :=
  ifeq ($(VECREPORT),1)
    VECFLAGS += -qopt-report=5 -qopt-report-phase=vec
  endif
  ifeq ($(PROFILE),1)
    PROFFLAGS += -pg
  endif
else ifeq ($(FC),ifort)
  OPTFLAGS += -O3 -xHost -ipo -qopenmp -fp-model=precise -traceback
  OMPFLAGS :=
  ifeq ($(VECREPORT),1)
    VECFLAGS += -qopt-report=5 -qopt-report-phase=vec
  endif
  ifeq ($(PROFILE),1)
    PROFFLAGS += -pg
  endif
endif

ifeq ($(MODE),debug)
  FFLAGS := $(BASEFLAGS) $(DBGFLAGS) $(WARNFLAGS) $(OMPFLAGS) $(VECFLAGS) $(PROFFLAGS) $(STDLIB_INC)
  LDFLAGS := $(DBGFLAGS) $(OMPFLAGS) $(PROFFLAGS) $(STDLIB_LIB)
else
  FFLAGS := $(BASEFLAGS) $(OPTFLAGS) $(WARNFLAGS) $(OMPFLAGS) $(VECFLAGS) $(PROFFLAGS) $(STDLIB_INC)
  LDFLAGS := $(OPTFLAGS) $(OMPFLAGS) $(PROFFLAGS) $(STDLIB_LIB)
endif

# ---------------------------------------------------------------------------
# Módulos opcionais: entram apenas se o arquivo existir no layout detectado
# ---------------------------------------------------------------------------
OPTIONAL_SOURCE_FILES := $(wildcard $(SRCDIR)/mod_vtk_out.f90) \
                         $(wildcard $(SRCDIR)/mod_journal_center_io.f90)
OPTIONAL_OBJECTS := $(patsubst $(SRCDIR)/%.f90,$(OBJDIR)/%.o,$(OPTIONAL_SOURCE_FILES))

# ---------------------------------------------------------------------------
# Ordem principal das fontes
# ---------------------------------------------------------------------------
CORE_SOURCES := \
  $(SRCDIR)/mod_kinds.f90 \
  $(SRCDIR)/mod_constants.f90 \
  $(SRCDIR)/mod_stdlib_utils.f90 \
  $(SRCDIR)/mod_types.f90 \
  $(SRCDIR)/mod_catalog.f90 \
  $(SRCDIR)/mod_solid_thermal.f90 \
  $(SRCDIR)/mod_geometry.f90 \
  $(SRCDIR)/mod_mesh.f90 \
  $(SRCDIR)/mod_oil_props.f90 \
  $(SRCDIR)/mod_scaling.f90 \
  $(SRCDIR)/mod_reynolds.f90 \
  $(SRCDIR)/mod_energy.f90 \
  $(SRCDIR)/mod_integrals.f90 \
  $(OPTIONAL_SOURCE_FILES) \
  $(SRCDIR)/mod_solver.f90 \
  $(SRCDIR)/mod_equilibrium.f90 \
  $(SRCDIR)/mod_dynamics.f90 \
  $(SRCDIR)/mod_report.f90 \
  $(SRCDIR)/mod_namelist_io.f90 \
  $(SRCDIR)/main.f90

EXTRA_SOURCES := $(filter-out $(CORE_SOURCES),$(sort $(wildcard $(SRCDIR)/*.f90)))
SOURCES       := $(CORE_SOURCES) $(EXTRA_SOURCES)
OBJECTS       := $(patsubst $(SRCDIR)/%.f90,$(OBJDIR)/%.o,$(SOURCES))

.PHONY: all release debug vecreport profile dirs clean run info

all: release

release: dirs $(TARGET)

debug:
	@$(MAKE) MODE=debug OPENMP=$(OPENMP) FC="$(FC)" STDLIB_INC="$(STDLIB_INC)" STDLIB_LIB="$(STDLIB_LIB)" release

vecreport:
	@$(MAKE) MODE=release VECREPORT=1 OPENMP=$(OPENMP) FC="$(FC)" STDLIB_INC="$(STDLIB_INC)" STDLIB_LIB="$(STDLIB_LIB)" release

profile:
	@$(MAKE) MODE=release PROFILE=1 OPENMP=$(OPENMP) FC="$(FC)" STDLIB_INC="$(STDLIB_INC)" STDLIB_LIB="$(STDLIB_LIB)" release

dirs:
	@mkdir -p $(OBJDIR) $(BINDIR)

$(TARGET): $(OBJECTS) | dirs
	$(FC) $(OBJECTS) -o $@ $(LDFLAGS)

$(OBJDIR)/%.o: $(SRCDIR)/%.f90 | dirs
	$(FC) $(FFLAGS) -c $< -o $@

run: $(TARGET)
	./$(TARGET)

info:
	@echo "PROJECT   = $(PROJECT)"
	@echo "SRCDIR    = $(SRCDIR)"
	@echo "FC        = $(FC)"
	@echo "MODE      = $(MODE)"
	@echo "OPENMP    = $(OPENMP)"
	@echo "FFLAGS    = $(FFLAGS)"
	@echo "LDFLAGS   = $(LDFLAGS)"
	@echo "SOURCES   = $(SOURCES)"

clean:
	@rm -rf $(OBJDIR) $(BINDIR)

# ============================================================================
# DEPENDÊNCIAS DE MÓDULOS
# ============================================================================

# Nível 1: Base
$(OBJDIR)/mod_constants.o:      $(OBJDIR)/mod_kinds.o
$(OBJDIR)/mod_stdlib_utils.o:   $(OBJDIR)/mod_kinds.o

# Nível 2: Tipos
$(OBJDIR)/mod_types.o:          $(OBJDIR)/mod_kinds.o $(OBJDIR)/mod_constants.o

# Nível 3: Geometria, propriedades e catálogo
$(OBJDIR)/mod_geometry.o:       $(OBJDIR)/mod_kinds.o $(OBJDIR)/mod_types.o
$(OBJDIR)/mod_mesh.o:           $(OBJDIR)/mod_types.o $(OBJDIR)/mod_geometry.o
$(OBJDIR)/mod_catalog.o:        $(OBJDIR)/mod_kinds.o $(OBJDIR)/mod_types.o
$(OBJDIR)/mod_solid_thermal.o:  $(OBJDIR)/mod_types.o $(OBJDIR)/mod_geometry.o
$(OBJDIR)/mod_oil_props.o:      $(OBJDIR)/mod_kinds.o $(OBJDIR)/mod_types.o
$(OBJDIR)/mod_scaling.o:        $(OBJDIR)/mod_kinds.o $(OBJDIR)/mod_types.o $(OBJDIR)/mod_constants.o

# Nível 4: Equações e integrais
$(OBJDIR)/mod_reynolds.o:       $(OBJDIR)/mod_mesh.o $(OBJDIR)/mod_oil_props.o $(OBJDIR)/mod_scaling.o $(OBJDIR)/mod_types.o
$(OBJDIR)/mod_energy.o:         $(OBJDIR)/mod_mesh.o $(OBJDIR)/mod_solid_thermal.o $(OBJDIR)/mod_oil_props.o $(OBJDIR)/mod_scaling.o $(OBJDIR)/mod_types.o
$(OBJDIR)/mod_integrals.o:      $(OBJDIR)/mod_kinds.o $(OBJDIR)/mod_constants.o $(OBJDIR)/mod_types.o

# Módulos opcionais
$(OBJDIR)/mod_vtk_out.o:        $(OBJDIR)/mod_kinds.o $(OBJDIR)/mod_types.o
$(OBJDIR)/mod_journal_center_io.o: $(OBJDIR)/mod_kinds.o

# Nível 5: Solver e pós-processamento
$(OBJDIR)/mod_solver.o:         $(OBJDIR)/mod_reynolds.o $(OBJDIR)/mod_energy.o $(OBJDIR)/mod_integrals.o $(OBJDIR)/mod_scaling.o $(OBJDIR)/mod_types.o
$(OBJDIR)/mod_namelist_io.o:    $(OBJDIR)/mod_types.o $(OBJDIR)/mod_catalog.o
$(OBJDIR)/mod_report.o:         $(OBJDIR)/mod_kinds.o $(OBJDIR)/mod_types.o
$(OBJDIR)/mod_equilibrium.o:    $(OBJDIR)/mod_kinds.o $(OBJDIR)/mod_types.o $(OBJDIR)/mod_solver.o $(OBJDIR)/mod_integrals.o
$(OBJDIR)/mod_dynamics.o:       $(OBJDIR)/mod_kinds.o $(OBJDIR)/mod_types.o $(OBJDIR)/mod_solver.o $(OBJDIR)/mod_integrals.o

# Main: acrescenta automaticamente objetos opcionais presentes
$(OBJDIR)/main.o: $(OBJDIR)/mod_solver.o \
                  $(OBJDIR)/mod_report.o \
                  $(OBJDIR)/mod_namelist_io.o \
                  $(OBJDIR)/mod_dynamics.o \
                  $(OBJDIR)/mod_equilibrium.o \
                  $(OPTIONAL_OBJECTS)
