## configurable variables

ARCH           ?= x86_64
API_VERSION    ?= 26
ANDROID_SDK    ?= ${HOME}/Android/Sdk
RELEASE        ?= 2019.07.1
DBG_CFLAGS     ?= -g -O0

PROJ_JAVA_PATH ?= com/example/myapplication

## end of configurable variables

ARCHS           = x86_64 aarch64

ifeq ($(ARCH),x86_64)
SDK_ARCH        = arch-x86_64
JNI_ARCH        = $(ARCH)
else ifeq ($(ARCH),aarch64)
SDK_ARCH        = arch-arm64
JNI_ARCH        = arm64-v8a
else
$(error ARCH=$(ARCH) unknown, must be one of: $(ARCHS))
endif

RAKUDO          = rakudo-$(RELEASE)
MOAR_BRANCH     = release-$(RELEASE)
RAKUDO_DL       = https://github.com/rakudo/rakudo/releases/download/$(RELEASE)/$(RAKUDO).tar.gz

BUILD_ARCH      = x86_64-pc-linux-gnu
TARGET_ARCH     = $(ARCH)-linux-android$(API_VERSION)

ANDROID_NDK     = $(lastword $(sort $(wildcard $(ANDROID_SDK)/ndk/*)))
ANDROID_NDK_BIN = $(ANDROID_NDK)/toolchains/llvm/prebuilt/linux-x86_64/bin
ANDROID_SDK_PLT = $(ANDROID_SDK)/platform-tools
CC              = $(ANDROID_NDK_BIN)/$(ARCH)-linux-android$(API_VERSION)-clang
ADB             = $(ANDROID_SDK)/platform-tools/adb
MOAR_TARGET     = MoarVM-$(ARCH)-linux-android$(API_VERSION)

PREFIX_MOAR     = $(MOAR_TARGET)/install

CFLAGS_COM      = $(DBG_CFLAGS) -fPIC -mstackrealign
CFLAGS_COM     += -I$(PREFIX_MOAR)/include/moar
CFLAGS_COM     += -I$(PREFIX_MOAR)/include/libuv
CFLAGS_COM     += -I$(PREFIX_MOAR)/include/libatomic_ops
CFLAGS_COM     += -I$(PREFIX_MOAR)/include/dyncall
CFLAGS_COM     += -I$(PREFIX_MOAR)/include/libtommath

P6_OPS_SO_DIR   = $(DROID_PREFIX)/assets/rakudroid/share/perl6/lib/dynext
P6_OPS_SO       = $(P6_OPS_SO_DIR)/libperl6_ops_moar.so
P6_OPS_SRCS     = $(RAKUDO)/src/vm/moar/ops/perl6_ops.c $(RAKUDO)/src/vm/moar/ops/container.c
P6_OPS_CFLAGS   = $(CFLAGS_COM)
#P6_OPS_LDFLAGS  = -shared -L$(PREFIX_MOAR)/lib -Wl,-rpath-link=$(PREFIX_MOAR)/lib -Wl,-rpath='$$ORIGIN'/../../../../lib
P6_OPS_LDFLAGS  = -shared -L$(PREFIX_MOAR)/lib -Wl,-rpath-link=$(PREFIX_MOAR)/lib
P6_OPS_LIBS     = -lmoar -lm -ldl

DROID_PREFIX    = app/src/main

DROID_SRCS      = src/librakudroid/rakudroid.c

DROID_HDRS      = src/librakudroid/rakudroid.h

DROID_SO_DIR    = $(DROID_PREFIX)/jniLibs/$(JNI_ARCH)
DROID_SO_NAME   = librakudroid.so
DROID_SO        = $(DROID_SO_DIR)/$(DROID_SO_NAME)
MOAR_SO         = $(DROID_SO_DIR)/libmoar.so

HELPER_DIR      = $(DROID_PREFIX)/assets/rakudroid/lib

DROID_DEFINES   = -DSTATIC_NQP_HOME="/rakudroid/share/nqp"
DROID_DEFINES  += -DSTATIC_PERL6_HOME="/rakudroid/share/perl6"
DROID_DEFINES  += -DSTATIC_HELPER_FILE="/rakudroid/lib/RakuDroid.pm6"
DROID_DEFINES  += -DLIBFILENAME="$(DROID_SO_NAME)"

DROID_CFLAGS    = $(CFLAGS_COM)
DROID_LDFLAGS   = -shared -Wl,-e,start

DROID_LIBS      = -L$(PREFIX_MOAR)/lib -lmoar -L$(ANDROID_NDK)/platforms/android-$(API_VERSION)/$(SDK_ARCH)/usr/lib -llog

TO_CLEAN        = app $(RAKUDO)* MoarVM*

export PATH    := $(ANDROID_NDK_BIN):$(ANDROID_SDK_PLT):${PATH}
SHELL           = /bin/bash

.PHONY: all backup $(PREFIX_MOAR)/lib/libmoar.so

none:
	@echo Hmmm… I don\'t know what to make, and you neither… try \"make help\" or read README.md \(same thing\)

help:
	@cat README.md

check:
	@echo supported architectures: $(ARCHS)
	@echo ARCH=$(ARCH)
	@echo API_VERSION=$(API_VERSION)
	@echo ANDROID_SDK=$(ANDROID_SDK)
	@echo RELEASE=$(RELEASE)
	@echo DBG_CFLAGS=$(DBG_CFLAGS)
	@echo PROJ_JAVA_PATH=$(PROJ_JAVA_PATH)
	@echo
	@adb=`which adb 2>/dev/null`; \
	if [[ $$adb == "" ]]; then \
		echo \'adb\' not found in PATH && false; \
	else \
		echo adb found here: $$adb; \
		arch=`adb shell uname -m`; \
		if [[ $$arch != $(ARCH) ]]; then \
			echo target device is $$arch, not $(ARCH) && false; \
		else \
			echo device\'s arch matches; \
		fi; \
	fi
	@if [[ -r $(CC) ]]; then \
		echo cross-compiler found in $(CC); \
	else \
		echo cross-compiler not found in $(CC) && false; \
	fi
	@if [[ `which wget >/dev/null 2>&1` ]]; then \
		echo \'wget\' not found in PATH && false; \
	fi
	@if [[ `which git >/dev/null 2>&1` ]]; then \
		echo \'git\' not found in PATH && false; \
	fi


all: $(DROID_SO) $(MOAR_SO) $(P6_OPS_SO) $(HELPER_DIR)/RakuDroid.pm6

$(MOAR_TARGET).touch:
	rm -rf $(MOAR_TARGET)
	git clone -b $(MOAR_BRANCH) https://github.com/MoarVM/MoarVM.git $(MOAR_TARGET)
	cd $(MOAR_TARGET) && \
		git submodule sync --quiet && git submodule --quiet update --init && \
		git am ../src/librakudroid/0001-Make-MoarVM-cross-compile-nicely-for-Android.patch && \
		MAKEFLAGS="-j" perl Configure.pl --build=$(BUILD_ARCH) --host=$(TARGET_ARCH) --no-jit --relocatable && \
		MAKEFLAGS="-j" make install
	touch $(MOAR_TARGET).touch

$(PREFIX_MOAR)/lib/libmoar.so: $(MOAR_TARGET).touch

$(MOAR_SO): $(PREFIX_MOAR)/lib/libmoar.so
	mkdir -p $(DROID_SO_DIR)
	cp -a $(PREFIX_MOAR)/lib/libmoar.so $(MOAR_SO)

$(RAKUDO).touch: $(RAKUDO)
	cd $(RAKUDO) && \
		MAKEFLAGS="-j" perl Configure.pl --gen-nqp --gen-moar --backends=moar --make-install --relocatable
	touch $(RAKUDO).touch

$(RAKUDO).tar.gz:
	wget $(RAKUDO_DL)

$(RAKUDO): $(RAKUDO).tar.gz
	tar -xzf $(RAKUDO).tar.gz

$(HELPER_DIR)/RakuDroid.pm6:
	mkdir -p $(HELPER_DIR)
	cp -a src/librakudroid/RakuDroid.pm6 $(HELPER_DIR)/

$(DROID_SO): $(DROID_SRCS) $(DROID_HDRS) $(RAKUDO).touch $(MOAR_TARGET).touch
	mkdir -p $(DROID_SO_DIR)
	$(CC) $(DROID_CFLAGS) $(DROID_LDFLAGS) -o $(DROID_SO) $(DROID_DEFINES) $(DROID_SRCS) $(DROID_LIBS)

$(P6_OPS_SRCS): $(RAKUDO).touch

$(P6_OPS_SO): $(P6_OPS_SRCS) $(RAKUDO).touch
	mkdir -p $(P6_OPS_SO_DIR)
	$(CC) $(P6_OPS_CFLAGS) $(P6_OPS_LDFLAGS) -o $(P6_OPS_SO) $(P6_OPS_SRCS) $(P6_OPS_LIBS)

clean:
	rm -rf app

clean-all: clean
	rm -rf $(TO_CLEAN)

install: all
	mkdir -p app
	sed -e s/%%ARCH_JNI%%/$(JNI_ARCH)/ src/AndroidStudio/build.gradle.in >app/build.gradle
	mkdir -p $(DROID_PREFIX)/java/$(PROJ_JAVA_PATH)
	cp -a src/AndroidStudio/MainActivity.kt $(DROID_PREFIX)/java/$(PROJ_JAVA_PATH)/
	mkdir -p $(DROID_PREFIX)/cpp
	cp -a src/AndroidStudio/CMakeLists.txt src/librakudroid/rakudroid.h src/AndroidStudio/native-lib.cpp $(DROID_PREFIX)/cpp/
	tar -czf MyApplication.tgz app
	@echo
	@echo Ok, now go to your Android project\'s root directory \(where the directory \'app\' resides\) and do \'tar -xzvf `pwd`/MyApplication.tgz\'
