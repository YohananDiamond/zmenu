#include <X11/Xlib.h>

int zmenu_defaultscreen(const Display *disp);
Window zmenu_rootwindow(const Display *disp, int screen);
Visual *zmenu_defaultvisual(const Display *disp, int screen);
Colormap zmenu_defaultcolormap(const Display *disp, int screen);
unsigned int zmenu_defaultdepth(const Display *disp, int screen);
