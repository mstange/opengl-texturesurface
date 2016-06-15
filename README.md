This is just an experiment I did some time ago for implementing filters in OpenGL.

It has a few example shaders; the interesting ones are the turbulence and the blur shader. The turbulence shader produces a noise output in the same way as the SVG feTurbulence element. The blur shader uses a fixed number of samples in the fragment shader and does multiple passes for larger blur radii.

This program only runs on OS X. Compile and run using:

    $ clang++ main.mm -Wall -O3 -framework Cocoa -framework OpenGL -framework QuartzCore -o test && ./test
 
Use trackpad scrolling to adjust the blur radius and the turbulence offset.
