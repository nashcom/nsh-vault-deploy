# Makefile — vault_push + example
# Targets: Linux and Windows (MinGW)
#
# nlohmann/json:
#   Linux:   apt install nlohmann-json3-dev   (or copy json.hpp to ./include/nlohmann/)
#   Windows: copy json.hpp to ./include/nlohmann/
#            or: winget install nlohmann-json
#
# libcurl:
#   Linux:   apt install libcurl4-openssl-dev
#   Windows: download curl for Windows, set CURL_DIR below

# ── platform detection ────────────────────────────────────────────────────────
ifeq ($(OS),Windows_NT)
    PLATFORM   := windows
    EXE        := vault_example.exe
    RM         := del /Q
    PATHSEP    := \\
    # MinGW curl — adjust if installed elsewhere
    CURL_DIR   ?= C:/curl
    CURL_INC   := -I$(CURL_DIR)/include
    CURL_LIB   := -L$(CURL_DIR)/lib -lcurl
    # nlohmann/json — adjust if installed elsewhere
    JSON_INC   ?= -I./include
    EXTRA_LIBS := -lws2_32 -lwldap32 -lcrypt32
else
    PLATFORM   := linux
    EXE        := vault_example
    RM         := rm -f
    PATHSEP    := /
    CURL_INC   :=
    CURL_LIB   := -lcurl
    JSON_INC   ?= -I./include
    EXTRA_LIBS :=
endif

# ── compiler ──────────────────────────────────────────────────────────────────
CXX      := g++
CXXFLAGS := -std=c++17 -Wall -Wextra -pedantic \
            $(CURL_INC) $(JSON_INC)
LDFLAGS  := $(CURL_LIB) $(EXTRA_LIBS)

# Debug build: make DEBUG=1
ifdef DEBUG
    CXXFLAGS += -g -O0 -DDEBUG
else
    CXXFLAGS += -O2 -DNDEBUG
endif

# ── sources ───────────────────────────────────────────────────────────────────
OBJS := vault_push.o example.o

# ── targets ───────────────────────────────────────────────────────────────────
.PHONY: all clean run

all: $(EXE)

$(EXE): $(OBJS)
	$(CXX) $(OBJS) $(LDFLAGS) -o $@
	@echo "Built: $@ ($(PLATFORM))"

vault_push.o: vault_push.cpp vault_push.hpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

example.o: example.cpp vault_push.hpp
	$(CXX) $(CXXFLAGS) -c $< -o $@

clean:
	$(RM) $(OBJS) $(EXE)

# ── run with local Vault (docker compose up -d in server/) ────────────────────
run: $(EXE)
	@echo "Starting Vault docker stack first if needed..."
	VAULT_ADDR=http://127.0.0.1:8200 \
	VAULT_ROLE_ID=$$(cat ../../server/init/../../../server/init/../../client/nginx/credentials/nginx01.example.com/role_id) \
	VAULT_SECRET_ID=$$(cat ../../server/init/../../../server/init/../../client/nginx/credentials/nginx01.example.com/secret_id) \
	VAULT_SERVER=nginx01.example.com \
	./$(EXE)

# ── install nlohmann/json header locally (Linux) ──────────────────────────────
include/nlohmann/json.hpp:
	@mkdir -p include/nlohmann
	curl -sL https://github.com/nlohmann/json/releases/latest/download/json.hpp \
	    -o include/nlohmann/json.hpp
	@echo "Downloaded nlohmann/json to include/nlohmann/json.hpp"

fetch-json: include/nlohmann/json.hpp
