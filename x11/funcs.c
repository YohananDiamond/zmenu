#include <X11/Xlib.h>

int x11_defaultscreen(const Display *disp) {
	return DefaultScreen(disp);
}

Window x11_rootwindow(const Display *disp, int screen) {
	return RootWindow(disp, screen);
}

Visual *x11_defaultvisual(const Display *disp, int screen) {
	return ScreenOfDisplay(disp, screen)->root_visual;
}

Colormap x11_defaultcolormap(const Display *disp, int screen) {
	return ScreenOfDisplay(disp, screen)->cmap;
}

int x11_defaultdepth(const Display *disp, int screen) {
	return (unsigned int) ScreenOfDisplay(disp, screen)->root_depth;
}
