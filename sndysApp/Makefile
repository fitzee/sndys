APP_NAME = sndysApp
BUILD_DIR = build
BRIDGE_DIR = Bridge
SOURCES_DIR = Sources
LIB = $(BRIDGE_DIR)/libsndys.a
HEADER = $(BRIDGE_DIR)/sndys_bridge.h

SWIFT_FILES = $(wildcard $(SOURCES_DIR)/*.swift)
SWIFT_FLAGS = -O -import-objc-header $(HEADER) -L$(BRIDGE_DIR) -lsndys \
              -L/opt/homebrew/lib -lSDL2 -lm \
              -Xlinker -framework -Xlinker AVFoundation \
              -Xlinker -framework -Xlinker AppKit \
              -Xlinker -framework -Xlinker SwiftUI \
              -Xlinker -framework -Xlinker UniformTypeIdentifiers

.PHONY: all clean lib run

all: $(BUILD_DIR)/$(APP_NAME)

lib: $(LIB)

$(LIB):
	cd $(BRIDGE_DIR) && bash build_lib.sh

$(BUILD_DIR)/$(APP_NAME): $(LIB) $(SWIFT_FILES)
	@mkdir -p $(BUILD_DIR)
	swiftc $(SWIFT_FILES) $(SWIFT_FLAGS) -o $(BUILD_DIR)/$(APP_NAME)
	@echo "Built: $(BUILD_DIR)/$(APP_NAME)"

clean:
	rm -rf $(BUILD_DIR)
	rm -f $(BRIDGE_DIR)/libsndys.a $(BRIDGE_DIR)/*.o
	rm -f $(BRIDGE_DIR)/bridge_all.c $(BRIDGE_DIR)/sndys_combined.c

run: $(BUILD_DIR)/$(APP_NAME)
	./$(BUILD_DIR)/$(APP_NAME)
