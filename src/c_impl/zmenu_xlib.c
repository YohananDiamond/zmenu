#include <X11/Xlib.h>

int zmenu_defaultscreen(const Display *disp) {
	return DefaultScreen(disp);
}

Window zmenu_rootwindow(const Display *disp, int screen) {
	return RootWindow(disp, screen);
}

Visual *zmenu_defaultvisual(const Display *disp, int screen) {
	return ScreenOfDisplay(disp, screen)->root_visual;
}

Colormap zmenu_defaultcolormap(const Display *disp, int screen) {
	return ScreenOfDisplay(disp, screen)->cmap;
}

int zmenu_defaultdepth(const Display *disp, int screen) {
	return (unsigned int) ScreenOfDisplay(disp, screen)->root_depth;
}
