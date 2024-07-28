/*
 * vim: set et ts=4 sw=4
 *------------------------------------------------------------
 *                                  ___ ___ _
 *  ___ ___ ___ ___ ___       _____|  _| . | |_
 * |  _| . |_ -|  _| . |     |     | . | . | '_|
 * |_| |___|___|___|___|_____|_|_|_|___|___|_,_|
 *                     |_____|
 * ------------------------------------------------------------
 * Copyright (c) 2024 Xark
 * MIT License
 *
 * Test and example for Xosera filled rectangle
 * ------------------------------------------------------------
 */

#include <assert.h>
#include <ctype.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <basicio.h>
#include <machine.h>

#include "xosera_m68k_api.h"

// rosco_m68k support

static void dputc(char c)
{
    __asm__ __volatile__(
        "move.w %[chr],%%d0\n"
        "move.l #2,%%d1\n"        // SENDCHAR
        "trap   #14\n"
        :
        : [chr] "d"(c)
        : "d0", "d1");
}

static void dprint(const char * str)
{
    register char c;
    while ((c = *str++) != '\0')
    {
        if (c == '\n')
        {
            dputc('\r');
        }
        dputc(c);
    }
}

static char dprint_buff[4096];
static void dprintf(const char * fmt, ...) __attribute__((__format__(__printf__, 1, 2)));
static void dprintf(const char * fmt, ...)
{
    va_list args;
    va_start(args, fmt);
    vsnprintf(dprint_buff, sizeof(dprint_buff), fmt, args);
    dprint(dprint_buff);
    va_end(args);
}

// xosera support

xosera_info_t initinfo;

static void reset_vid(void)
{
    xv_prep();

    xwait_not_vblank();
    xwait_vblank();

    xreg_setw(VID_CTRL, 0x0008);
    xreg_setw(COPP_CTRL, 0x0000);
    xreg_setw(AUD_CTRL, 0x0000);
    xreg_setw(VID_LEFT, 0);
    xreg_setw(VID_RIGHT, xosera_vid_width());
    xreg_setw(POINTER_H, 0x0000);
    xreg_setw(POINTER_V, 0x0000);

    xreg_setw(PA_GFX_CTRL, MAKE_GFX_CTRL(0x00, 0, GFX_1_BPP, 0, 0, 0));
    xreg_setw(PA_TILE_CTRL, MAKE_TILE_CTRL(XR_TILE_ADDR, 0, 0, 16));
    xreg_setw(PA_DISP_ADDR, 0x0000);
    xreg_setw(PA_LINE_LEN, xosera_vid_width() / 8);
    xreg_setw(PA_HV_FSCALE, MAKE_HV_FSCALE(0, 0));
    xreg_setw(PA_H_SCROLL, MAKE_H_SCROLL(0));
    xreg_setw(PA_V_SCROLL, MAKE_V_SCROLL(0, 0));

    xreg_setw(PB_GFX_CTRL, MAKE_GFX_CTRL(0x00, 1, GFX_1_BPP, 0, 0, 0));
    xreg_setw(PB_TILE_CTRL, MAKE_TILE_CTRL(XR_TILE_ADDR, 0, 0, 16));
    xreg_setw(PB_DISP_ADDR, 0x0000);
    xreg_setw(PB_LINE_LEN, xosera_vid_width() / 8);
    xreg_setw(PB_HV_FSCALE, MAKE_HV_FSCALE(0, 0));
    xreg_setw(PB_H_SCROLL, MAKE_H_SCROLL(0));
    xreg_setw(PB_V_SCROLL, MAKE_V_SCROLL(0, 0));

    printf("\033c");        // reset XANSI

    while (checkinput())
    {
        readchar();
    }
}

_NOINLINE bool delay_check(int ms)
{
    xv_prep();

    do
    {
        if (checkinput())
        {
            return true;
        }
        if (ms)
        {
            uint16_t tms = 10;
            do
            {
                uint16_t tv = xm_getw(TIMER);
                while (tv == xm_getw(TIMER))
                    ;
            } while (--tms);
        }
    } while (--ms);

    return false;
}

// Xosera rectangle test code

#define SCREEN_ADDR    0x0000        // VRAM address of start of bitmap
#define SCREEN_WIDTH   320           // pixel width of bitmap
#define SCREEN_HEIGHT  240           // pixel height of bitmap
#define PIXEL_PER_WORD 2             // pixels per word (4=4-bpp, 2=8-bpp)

static const uint16_t fw_mask[2] = {0xF0, 0x30};        // first word 8-bit pixel mask: XX .X
static const uint16_t lw_mask[2] = {0x0F, 0x0C};        // last word 8-bit pixel mask : X. ..

void fill_rect_8bpp(int x, int y, int w, int h, uint8_t c)
{
    // zero w or h ignored
    if (w < 1 || h < 1)
        return;

    uint16_t va    = SCREEN_ADDR + (y * (SCREEN_WIDTH / PIXEL_PER_WORD)) + (x / PIXEL_PER_WORD);        // vram address
    uint16_t ww    = ((w + 1) + ((x + w) & 1)) / PIXEL_PER_WORD;          // width in words
    uint16_t mod   = (SCREEN_WIDTH / PIXEL_PER_WORD) - ww;                // destination modulo
    uint16_t shift = (fw_mask[x & 1] | lw_mask[(x + w) & 1]) << 8;        // fw mask | lw mask

    dprintf("fw=0x%02x lw=0x%02x\n", fw_mask[x & 1], lw_mask[(x + w) & 1]);
    dprintf("x=%d y=%d w=%d va=0x%04x ww=0x%04x mod=0x%04x, shift=0x%04x\n", x, y, w, va, ww, mod, shift);

    xv_prep();
    xreg_setw(BLIT_CTRL, MAKE_BLIT_CTRL(0, 0, 0, 1));        // tr_val=NA, tr_8bit=NA, tr_enable=FALSE, const_S=TRUE
    xreg_setw(BLIT_ANDC, 0x0000);                            // ANDC constant (0=NA)
    xreg_setw(BLIT_XOR, 0x0000);                             // XOR constant (0=NA)
    xreg_setw(BLIT_MOD_S, 0x0000);                           // no modulo S (constant)
    xreg_setw(BLIT_SRC_S, c << 8 | c);                       // A = fill pattern (color)
    xreg_setw(BLIT_MOD_D, mod);           // dest modulo (screen width in words - blit width in words)
    xreg_setw(BLIT_DST_D, va);            // VRAM display address
    xreg_setw(BLIT_SHIFT, shift);         // no edge masking or shifting
    xreg_setw(BLIT_LINES, h - 1);         // lines = height-1
    xreg_setw(BLIT_WORDS, ww - 1);        // width = ww -1 (and go!)
    xwait_blit_done();
}

void xosera_rectangle()
{
    xv_prep();

    dprintf("Xosera_rectangle_m68k\n");

    dprintf("Checking for Xosera XANSI firmware...");
    if (xosera_xansi_detect(true))        // check for XANSI (and disable input cursor if present)
    {
        dprintf("detected.\n");
    }
    else
    {
        dprintf(
            "\n\nXosera XANSI firmware was not detected!\n"
            "This program will likely trap without Xosera hardware.\n");
    }

    dprintf("Calling xosera_init(XINIT_CONFIG_640x480)...");
    bool success = xosera_init(XINIT_CONFIG_640x480);
    dprintf("%s (%dx%d)\n\n", success ? "succeeded" : "FAILED", xosera_vid_width(), xosera_vid_height());

    if (!success)
    {
        dprintf("Exiting without Xosera init.\n");
        exit(1);
    }

    xosera_get_info(&initinfo);

    xreg_setw(PA_GFX_CTRL, MAKE_GFX_CTRL(0x00, GFX_VISIBLE, GFX_8_BPP, GFX_BITMAP, GFX_2X, GFX_2X));
    xreg_setw(PA_TILE_CTRL, MAKE_TILE_CTRL(0x0C00, 0, 0, 8));
    xreg_setw(PA_DISP_ADDR, 0x0000);
    xreg_setw(PA_LINE_LEN, SCREEN_WIDTH / PIXEL_PER_WORD);        // line len
    xreg_setw(PA_H_SCROLL, MAKE_H_SCROLL(0));
    xreg_setw(PA_V_SCROLL, MAKE_V_SCROLL(0, 0));
    xreg_setw(PA_HV_FSCALE, MAKE_HV_FSCALE(HV_FSCALE_OFF, HV_FSCALE_OFF));

    xreg_setw(PB_GFX_CTRL, MAKE_GFX_CTRL(0x00, GFX_BLANKED, GFX_1_BPP, GFX_TILEMAP, GFX_1X, GFX_1X));


    int c = 0;
    for (int y = 0; y < 240; y++)
    {
        int w = (y >> 1) + 1;
        int x = y;
        c     = (c + 1) & 0xf;
        if (c == 0)
            c = 1;

        dprintf("> fill_rect_8bpp(%d, %d, %d, %d, %04x)\n", x, y, w, 1, c);
        fill_rect_8bpp(x, y, w, 1, c);
        readchar();
    }

    dprintf("(Done, Press a key)\n");
    readchar();

    dprintf("Exiting normally.\n");

    // exit test
    reset_vid();
}
