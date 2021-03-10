#include <X11/Xlib.h>

int ext_defaultscreen(const Display *disp);
Window ext_rootwindow(const Display *disp, int screen);
Visual *ext_defaultvisual(const Display *disp, int screen);
Colormap ext_defaultcolormap(const Display *disp, int screen);
unsigned int ext_defaultdepth(const Display *disp, int screen);
