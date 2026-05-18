# ======================================================================
# XMSpeedAd — 喜马拉雅广告加速插件
#
# 编译方式:
#   方式 1: GitHub Actions (推荐, 无需本地环境)
#   方式 2: macOS 本地直接编译  →  make
#   方式 3: Theos 编译          →  make theos
# ======================================================================

ARCH   ?= arm64
MIN_IOS ?= 12.0

# 查找 iOS SDK (需要 Xcode)
SDK ?= $(shell xcrun --sdk iphoneos --show-sdk-path 2>/dev/null)

# ---- 直接编译 (macOS + Xcode 即可, 无需 Theos) ----

XMSpeedAd.dylib: Tweak.m
	clang -arch $(ARCH) \
	      -fobjc-arc \
	      -miphoneos-version-min=$(MIN_IOS) \
	      -isysroot $(SDK) \
	      -dynamiclib \
	      -framework Foundation \
	      -framework UIKit \
	      -framework AVFoundation \
	      -o $@ $< \
	      -Xlinker -install_name -Xlinker @rpath/$@

all: XMSpeedAd.dylib

# 编译并打包成 .deb
deb: XMSpeedAd.dylib
	mkdir -p _package/DEBIAN _package/Library/MobileSubstrate/DynamicLibraries
	cp XMSpeedAd.dylib   _package/Library/MobileSubstrate/DynamicLibraries/
	cp XMSpeedAd.plist   _package/Library/MobileSubstrate/DynamicLibraries/
	cp control           _package/DEBIAN/control
	dpkg-deb -b _package XMSpeedAd.deb
	rm -rf _package
	@echo "=== 打包完成: XMSpeedAd.deb ==="

# Theos 编译 (需要安装 THEOS)
theos:
	@echo "使用 Theos 编译: make clean && make package"

clean:
	rm -rf XMSpeedAd.dylib XMSpeedAd.deb _package

.PHONY: all deb theos clean
