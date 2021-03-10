#include <X11/Xlib.h>

int ext_defaultscreen(const Display *disp) {
	return DefaultScreen(disp);
}

Window ext_rootwindow(const Display *disp, int screen) {
	return RootWindow(disp, screen);
}

Visual *ext_defaultvisual(const Display *disp, int screen) {
	return ScreenOfDisplay(disp, screen)->root_visual;
}

Colormap ext_defaultcolormap(const Display *disp, int screen) {
	return ScreenOfDisplay(disp, screen)->cmap;
}

int ext_defaultdepth(const Display *disp, int screen) {
	return (unsigned int) ScreenOfDisplay(disp, screen)->root_depth;
}
