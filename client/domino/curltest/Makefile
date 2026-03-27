# curltest — Domino servertask Makefile
#
# Builds against libnotes.so (Linux) or nnotes.lib (Windows).
# No curl headers needed — declarations are inlined in curltest.c.
#
# Environment variables (set by build container):
#   DOMINO_API     — path to Domino C-API root
#   DOMINO_LIB     — path to libnotes.so / nnotes.lib

CC      = gcc
BOOTOBJS = $(LOTUS)/notesapi/lib/linux64/notes0.o $(LOTUS)/notesapi/lib/linux64/notesai0.o
CFLAGS  = -c -m64 -DUNIX -DLINUX -DLINUX64 -DDND_ALLOW_INET_SOCKETS \
          -I$(INCLUDE)

LDFLAGS = -m64
LIBS    = -L$(LD_LIBRARY_PATH) -lnotes $(BOOTOBJS)

TARGET  = curltest
OBJS    = curltest.o

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(OBJS)
	$(CC) $(LDFLAGS) -o $@ $^ $(LIBS)

%.o: %.c
	$(CC) $(CFLAGS) -o $@ $<

clean:
	rm -f $(OBJS) $(TARGET)
