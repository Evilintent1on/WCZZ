ARCHS = arm64 arm64e
TARGET = iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = wczz
wczz_FILES = Tweak.xm MessageMenuConfig.m MessageMenuBackup.m MessageMenuSettingsController.m GroupHelperConfig.m GroupHelperSessionPickerController.m
wczz_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -DPACKAGE_VERSION=@\"$(shell grep '^Version:' control | cut -d' ' -f2)\"
wczz_FRAMEWORKS = UIKit Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
