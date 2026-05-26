THEOS_PACKAGE_SCHEME = rootless
TARGET = iphone:clang:latest:14.0
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AudioMix

AudioMix_FILES = Tweak.x
AudioMix_CFLAGS = -fobjc-arc
AudioMix_FRAMEWORKS = AVFoundation
AudioMix_LDFLAGS = -Wl,-segalign,4000

include $(THEOS_MAKE_PATH)/tweak.mk
