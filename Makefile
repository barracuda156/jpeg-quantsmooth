OS := $(shell uname)
ARCH := $(shell uname -m)

SRCDEPS := quantsmooth.h idct.h libjpegqs.h
SRCNAME ?= quantsmooth.c
ifeq ($(SRCNAME),jpegqs-mini.c)
APPNAME ?= jpegqs-mini
$(APPNAME): Makefile
else
ifeq ($(SRCNAME),example.c)
APPNAME ?= example
else
APPNAME ?= jpegqs
endif
$(APPNAME): Makefile $(SRCDEPS)
endif
SIMD := native
# machine flags
MFLAGS := 
SIMDFLG :=
SIMDOBJ :=
SIMD_AVX512 := -mavx512f -mavx512dq -mavx512bw -mfma
ifeq ($(SIMD),select)
SIMDOBJ := jpegqs_base.o jpegqs_sse2.o jpegqs_avx2.o jpegqs_avx512.o
else ifeq ($(SIMD),none)
SIMDFLG := -DNO_SIMD
else ifeq ($(SIMD),native)
ifneq (,$(filter arm% aarch64,$(ARCH)))
SIMDFLG := -mcpu=native
else ifneq (,$(filter powerpc,$(shell uname -p)))
SIMDFLG := -mtune=native
else
SIMDFLG := -march=native
endif
else ifeq ($(SIMD),avx512)
SIMDFLG := $(SIMD_AVX512)
else ifeq ($(SIMD),avx2)
SIMDFLG := -mavx2 -mfma
else ifeq ($(SIMD),sse2)
SIMDFLG := -msse2
endif
# multithreading options
ifeq ($(OS),Darwin)
MTOPTS := -Xpreprocessor -fopenmp
else
MTOPTS := -fopenmp
endif
# path to save "libgomp.a"
LIBMINIOMP :=
CFLAGS := -Wall -O2
ifneq (,$(filter e2k,$(ARCH)))
CFLAGS := $(filter-out -O2,$(CFLAGS)) -O3
endif
ifeq ($(OS),Darwin)
LDFLAGS := -Wl,-dead_strip
ifeq ($(LIBMINIOMP),)
LDFLAGS += -lomp
endif
else
LDFLAGS := -Wl,--gc-sections -s
endif

CFLAGS_LIB := $(CFLAGS) $(MFLAGS) $(SIMDFLG)
CFLAGS_APP := $(CFLAGS_LIB) -Wextra -pedantic $(MTOPTS)
ifeq ($(SIMD),select)
CFLAGS_APP += -DSIMD_SELECT
endif

.PHONY: clean all app lib

app: $(APPNAME)
all: app lib
lib: lib$(APPNAME).a

WGET_CMD = @echo "run make with WGET_CMD=wget to allow file downloads" ; echo "DISABLED:" wget

jpegsrc.v%.tar.gz: 
	$(WGET_CMD) -O $@ "https://www.ijg.org/files/$@"
	test -f $@
jpeg-%/jutils.c: jpegsrc.v%.tar.gz
	tar -xzf jpegsrc.v$(patsubst jpeg-%/jutils.c,%,$@).tar.gz
	touch $@
jpeg-%/Makefile: jpeg-%/jutils.c
	cd $(patsubst %/Makefile,%,$@) && ./configure
jpeg-%/libjpeg.a: jpeg-%/Makefile
	cd $(patsubst %/libjpeg.a,%,$@) && $(MAKE) all && test -d .libs && cp .libs/libjpeg.a . || true
.PRECIOUS: jpegsrc.v%.tar.gz jpeg-%/jutils.c jpeg-%/Makefile

libjpeg-turbo-%.tar.gz:
	$(WGET_CMD) -O $@ "https://sourceforge.net/projects/libjpeg-turbo/files/$(patsubst libjpeg-turbo-%.tar.gz,%,$@)/libjpeg-turbo-$(patsubst libjpeg-turbo-%.tar.gz,%,$@).tar.gz"
	test -f $@
libjpeg-turbo-%/jutils.c: libjpeg-turbo-%.tar.gz
	tar -xzf $(patsubst %/jutils.c,%,$@).tar.gz
	touch $@
.PRECIOUS: libjpeg-turbo-%.tar.gz libjpeg-turbo-%/jutils.c
libjpeg-turbo-1.%/Makefile: libjpeg-turbo-1.%/jutils.c
	cd $(patsubst %/Makefile,%,$@) && ./configure
libjpeg-turbo-1.%/libjpeg.a: libjpeg-turbo-1.%/Makefile
	cd $(patsubst %/libjpeg.a,%,$@) && $(MAKE) all && cp .libs/lib*jpeg.a .
.PRECIOUS: libjpeg-turbo-1.%/Makefile
libjpeg-turbo-2.%/.libs/Makefile: libjpeg-turbo-2.%/jutils.c
	mkdir -p $(patsubst %/Makefile,%,$@)
	cd $(patsubst %/Makefile,%,$@) && cmake -G"Unix Makefiles" ..
libjpeg-turbo-2.%/libjpeg.a: libjpeg-turbo-2.%/.libs/Makefile
	cd $(patsubst %/Makefile,%,$<) && $(MAKE) all && cp jconfig*.h lib*jpeg.a ..
.PRECIOUS: libjpeg-turbo-2.%/.libs/Makefile

ifeq ($(JPEGSRC),)
JPEGLIB ?= -ljpeg
JPEGLIB2 := $(JPEGLIB)
CFLAGS_APP += $(filter -I%,$(JPEGLIB))
OBJLIST :=
else
OBJDIR ?= $(JPEGSRC)
ALLSRC := $(patsubst $(JPEGSRC)/%.c,%,$(wildcard $(JPEGSRC)/*.c))
SOURCES := jutils jmemmgr jmemnobs jcomapi jerror \
  jdapimin jdcoefct jdmarker jdhuff jdinput jdtrans \
  jcapimin jcmaster jcmarker jchuff jcparam jctrans \
	rdswitch cdjpeg transupp jdatasrc jdatadst
ifeq ($(SRCNAME),jpegqs-mini.c)
SOURCES += jidctint jfdctint
else ifeq ($(SRCNAME),example.c)
SOURCES += jidctint jidctfst jidctflt jquant1 jquant2 \
	jdapistd jdmaster jdcolor jdpostct jddctmgr jdsample jdmerge jdmainct
SOURCES += $(filter jidctred,$(ALLSRC))
endif
# version specific sources
SOURCES += $(filter jdphuff jcphuff jaricom jdarith jcarith,$(ALLSRC))

OBJLIST := $(patsubst %,$(OBJDIR)/%.o,$(SOURCES))
CFLAGS_APP += -DWITH_JPEGSRC -I$(JPEGSRC) -I.

$(OBJDIR)/%.o: $(JPEGSRC)/%.c
	$(CC) $(CFLAGS_LIB) -I$(JPEGSRC) -I. -c -o $@ $<

JPEGLIB2 := $(OBJLIST)
$(APPNAME): $(OBJLIST)
endif

clean:
	rm -f $(APPNAME) $(OBJLIST) jpegqs_*.o libjpegqs*.o lib$(APPNAME).a miniomp.o $(LIBMINIOMP)

ifneq ($(LIBMINIOMP),)
JPEGLIB2 += -L$(dir $(LIBMINIOMP))
$(APPNAME): $(LIBMINIOMP)
endif

$(APPNAME): $(SRCNAME) $(SIMDOBJ)
	$(CC) $(CFLAGS_APP) -DAPPNAME=$(APPNAME) -o $@ $< $(JPEGLIB2) $(SIMDOBJ) $(LDFLAGS) -lm

ifeq ($(SRCNAME),example.c)
SIMDSEL_FLAGS ?=
else
SIMDSEL_FLAGS ?= -DTRANSCODE_ONLY -DWITH_LOG
endif

jpegqs_avx512.o: libjpegqs.c $(SRCDEPS)
	$(CC) $(SIMDSEL_FLAGS) -DSIMD_NAME=avx512 $(SIMD_AVX512) $(CFLAGS_APP) -DSIMD_AVX512 -c -o $@ $<
jpegqs_avx2.o: libjpegqs.c $(SRCDEPS)
	$(CC) $(SIMDSEL_FLAGS) -DSIMD_NAME=avx2 -mavx2 -mfma $(CFLAGS_APP) -DSIMD_AVX2 -c -o $@ $<
jpegqs_sse2.o: libjpegqs.c $(SRCDEPS)
	$(CC) $(SIMDSEL_FLAGS) -DSIMD_NAME=sse2 -msse2 $(CFLAGS_APP) -DSIMD_SSE2 -c -o $@ $<
jpegqs_base.o: libjpegqs.c $(SRCDEPS)
	$(CC) $(SIMDSEL_FLAGS) -DSIMD_NAME=base $(CFLAGS_APP) -DSIMD_BASE -c -o $@ $<

ifeq ($(SIMD),select)
lib$(APPNAME).a: libjpegqs_base.o libjpegqs_sse2.o libjpegqs_avx2.o libjpegqs_avx512.o
endif
lib$(APPNAME).a: libjpegqs.o
	$(AR) -rsc $@ $^

libjpegqs.o: libjpegqs.c $(SRCDEPS)
	$(CC) $(CFLAGS_APP) -c -o $@ $<
libjpegqs_avx512.o: libjpegqs.c $(SRCDEPS)
	$(CC) -DSIMD_NAME=avx512 $(SIMD_AVX512) $(CFLAGS_APP) -DSIMD_AVX512 -c -o $@ $<
libjpegqs_avx2.o: libjpegqs.c $(SRCDEPS)
	$(CC) -DSIMD_NAME=avx2 -mavx2 -mfma $(CFLAGS_APP) -DSIMD_AVX2 -c -o $@ $<
libjpegqs_sse2.o: libjpegqs.c $(SRCDEPS)
	$(CC) -DSIMD_NAME=sse2 -msse2 $(CFLAGS_APP) -DSIMD_SSE2 -c -o $@ $<
libjpegqs_base.o: libjpegqs.c $(SRCDEPS)
	$(CC) -DSIMD_NAME=base $(CFLAGS_APP) -DSIMD_BASE -c -o $@ $<

$(LIBMINIOMP): miniomp.o
	$(AR) -rsc $@ $^
miniomp.o: miniomp.c
	$(CC) -DOVERFLOW_CHECKS=0 -O2 -Wall -Wextra -c -o $@ $< -ffunction-sections -fdata-sections

