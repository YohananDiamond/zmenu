#include <X11/Xlib.h>

int x11_defaultscreen(const Display *disp);
Window x11_rootwindow(const Display *disp, int screen);
Visual *x11_defaultvisual(const Display *disp, int screen);
Colormap x11_defaultcolormap(const Display *disp, int screen);
unsigned int x11_defaultdepth(const Display *disp, int screen);
