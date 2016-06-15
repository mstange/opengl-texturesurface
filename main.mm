/**
 * clang++ main.mm -Wall -O3 -framework Cocoa -framework OpenGL -framework QuartzCore -o test && ./test
 **/

#import <Cocoa/Cocoa.h>
#include <OpenGL/gl.h>
#include <OpenGL/glu.h>
#include <algorithm>

#define DISPLAY_GL_TO_WINDOW

class TextureSurface
{
public:
  TextureSurface(int aWidth, int aHeight);
  virtual ~TextureSurface();

  GLuint TextureID() { return mTextureID; }

  void DrawInto(void (^drawCallback)());
  void DrawIntoCleared(void (^drawCallback)());

  CGImageRef Snapshot();

  CGSize Size() { return CGSizeMake(mWidth, mHeight); }

private:
  int mWidth;
  int mHeight;
  GLuint mTextureID;
  GLuint mFBO;
};

#define checkError() \
  do { \
    GLuint lastError = glGetError(); \
    if (lastError) { \
      const GLubyte* s = gluErrorString(lastError); \
      NSLog(@"gl error: %s in line %d", s, __LINE__); \
    } \
  } while (0);


TextureSurface::TextureSurface(int aWidth, int aHeight)
 : mWidth(aWidth)
 , mHeight(aHeight)
{
  glGenFramebuffers(1, &mFBO);
  glBindFramebuffer(GL_FRAMEBUFFER, mFBO);
  checkError();

  glGenTextures(1, &mTextureID);
  glBindTexture(GL_TEXTURE_2D, mTextureID);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, mWidth, mHeight, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
  checkError();

  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  checkError();

  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, mTextureID, 0);
  checkError();
  GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);

  if (status != GL_FRAMEBUFFER_COMPLETE) {
    NSLog(@"framebuffer incomplete :(");
  }
}

TextureSurface::~TextureSurface()
{
  checkError();
  glDeleteTextures(1, &mTextureID);
  checkError();
  glDeleteFramebuffers(1, &mFBO);
  checkError();
}

void
TextureSurface::DrawInto(void (^drawCallback)())
{
  glEnable(GL_TEXTURE_2D);
  checkError();
  glEnable(GL_BLEND);
  checkError();

  glBindFramebuffer(GL_FRAMEBUFFER, mFBO);
  checkError();
  glPushAttrib(GL_VIEWPORT_BIT);
  glViewport(0, 0, mWidth, mHeight);
  checkError();

  drawCallback();

  glPopAttrib();
  checkError();
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  checkError();
  glBindTexture(GL_TEXTURE_2D, 0);
  checkError();
  glDisable(GL_TEXTURE_2D);
  checkError();
}

void
TextureSurface::DrawIntoCleared(void (^drawCallback)())
{
  DrawInto(^{
    glClearColor(0, 0, 0, 0);
    glClear(GL_COLOR_BUFFER_BIT);
    checkError();

    drawCallback();
  });
}

CGImageRef
TextureSurface::Snapshot()
{
  CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
  CGContextRef imgCtx = CGBitmapContextCreate(NULL, mWidth, mHeight, 8, mWidth * 4,
                                              rgb, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
  CGColorSpaceRelease(rgb);

  glBindFramebuffer(GL_FRAMEBUFFER, mFBO);
  checkError();
  glReadPixels(0, 0, mWidth, mHeight, GL_BGRA, GL_UNSIGNED_BYTE, CGBitmapContextGetData(imgCtx));
  checkError();
  glBindFramebuffer(GL_FRAMEBUFFER, 0);
  checkError();

  CGImageRef image = CGBitmapContextCreateImage(imgCtx);
  CGContextRelease(imgCtx);

  return image;
}

class ShaderProgram
{
public:
  ShaderProgram(const char* vertexShader, const char* fragmentShader);

  virtual ~ShaderProgram() {}

  virtual void Use() { glUseProgram(mProgramID); }
  virtual void DrawQuad(GLuint aQuad);

protected:
  GLuint mProgramID;
  GLuint mPosAttribute;
};

static GLuint
CompileShaders(const char* vertexShader, const char* fragmentShader)
{
  // Create the shaders
  GLuint vertexShaderID = glCreateShader(GL_VERTEX_SHADER);
  GLuint fragmentShaderID = glCreateShader(GL_FRAGMENT_SHADER);

  GLint result = GL_FALSE;
  int infoLogLength;

  // Compile Vertex Shader
  glShaderSource(vertexShaderID, 1, &vertexShader , NULL);
  glCompileShader(vertexShaderID);

  // Check Vertex Shader
  glGetShaderiv(vertexShaderID, GL_COMPILE_STATUS, &result);
  glGetShaderiv(vertexShaderID, GL_INFO_LOG_LENGTH, &infoLogLength);
  if (infoLogLength > 0) {
    char* vertexShaderErrorMessage = new char[infoLogLength+1];
    glGetShaderInfoLog(vertexShaderID, infoLogLength, NULL, vertexShaderErrorMessage);
    printf("%s\n", vertexShaderErrorMessage);
    delete[] vertexShaderErrorMessage;
  }

  // Compile Fragment Shader
  glShaderSource(fragmentShaderID, 1, &fragmentShader , NULL);
  glCompileShader(fragmentShaderID);

  // Check Fragment Shader
  glGetShaderiv(fragmentShaderID, GL_COMPILE_STATUS, &result);
  glGetShaderiv(fragmentShaderID, GL_INFO_LOG_LENGTH, &infoLogLength);
  if (infoLogLength > 0) {
    char* fragmentShaderErrorMessage = new char[infoLogLength+1];
    glGetShaderInfoLog(fragmentShaderID, infoLogLength, NULL, fragmentShaderErrorMessage);
    printf("%s\n", fragmentShaderErrorMessage);
    delete[] fragmentShaderErrorMessage;
  }

  // Link the program
  GLuint programID = glCreateProgram();
  glAttachShader(programID, vertexShaderID);
  glAttachShader(programID, fragmentShaderID);
  glLinkProgram(programID);

  // Check the program
  glGetProgramiv(programID, GL_LINK_STATUS, &result);
  glGetProgramiv(programID, GL_INFO_LOG_LENGTH, &infoLogLength);
  if (infoLogLength > 0) {
    char* programErrorMessage = new char[infoLogLength+1];
    glGetProgramInfoLog(programID, infoLogLength, NULL, programErrorMessage);
    printf("%s\n", programErrorMessage);
    delete[] programErrorMessage;
  }

  glDeleteShader(vertexShaderID);
  glDeleteShader(fragmentShaderID);

  return programID;
}

ShaderProgram::ShaderProgram(const char* vertexShader, const char* fragmentShader)
{
  mProgramID = CompileShaders(vertexShader, fragmentShader);
  mPosAttribute = glGetAttribLocation(mProgramID, "aPos");
}

void
ShaderProgram::DrawQuad(GLuint aQuad)
{
  glEnableVertexAttribArray(mPosAttribute);
  checkError();
  glBindBuffer(GL_ARRAY_BUFFER, aQuad);
  checkError();
  glVertexAttribPointer(
    mPosAttribute, // The attribute we want to configure
    2,             // size
    GL_FLOAT,      // type
    GL_FALSE,      // normalized?
    0,             // stride
    (void*)0       // array buffer offset
  );
  checkError();

  glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
  checkError();

  glDisableVertexAttribArray(mPosAttribute);
  checkError();
}

class OneSamplerProgram : public ShaderProgram
{
public:
  OneSamplerProgram(const char* vertexShader, const char* fragmentShader);

  virtual void SetTexture(GLuint aTexture);

protected:
  GLuint mSamplerUniform;
};

OneSamplerProgram::OneSamplerProgram(const char* vertexShader, const char* fragmentShader)
 : ShaderProgram(vertexShader, fragmentShader)
{
  mSamplerUniform = glGetUniformLocation(mProgramID, "uSampler");
}

void
OneSamplerProgram::SetTexture(GLuint aTexture)
{
  glActiveTexture(GL_TEXTURE0);
  checkError();
  glBindTexture(GL_TEXTURE_2D, aTexture);
  checkError();
  glUniform1i(mSamplerUniform, 0);
  checkError();
}

class DilateProgram : public OneSamplerProgram
{
public:
  DilateProgram();

  void SetSourcePixelSize(CGSize aSize);
  void SetDilateRadius(int aRadius);
  void SetSampleDirection(CGSize aDireciton);

protected:
  GLuint mPixelSizeUniform;
  GLuint mSampleDirectionUniform;
  GLuint mDilateRadiusUniform;
};

static const char* sCoverBufferWith01aPosVertexShader =
  "#version 120\n"
  "// Input vertex data, different for all executions of this shader.\n"
  "attribute vec2 aPos;\n"
  "varying vec2 vPos;\n"
  "void main(){\n"
  "  vPos = aPos;\n"
  "  gl_Position = vec4(aPos * 2.0 - vec2(1.0), 0.0, 1.0);\n"
  "}\n";

static const char* sDilateVertexShader =
  "#version 120\n"
  "// Input vertex data, different for all executions of this shader.\n"
  "uniform vec2 uSourcePixelSize;\n"
  "uniform float uDilateRadius;\n"
  "uniform vec2 uSampleDirection;\n"
  "attribute vec2 aPos;\n"
  "varying vec2 vPos;\n"
  "varying vec2 vReadTexCoords[14];\n"
  "void main(){\n"
  "  vPos = aPos;\n"
  "  vReadTexCoords[0] = aPos + 1.0 / 7 * uDilateRadius * uSourcePixelSize * uSampleDirection;\n"
  "  vReadTexCoords[1] = aPos - 1.0 / 7 * uDilateRadius * uSourcePixelSize * uSampleDirection;\n"
  "  vReadTexCoords[2] = aPos + 2.0 / 7 * uDilateRadius * uSourcePixelSize * uSampleDirection;\n"
  "  vReadTexCoords[3] = aPos - 2.0 / 7 * uDilateRadius * uSourcePixelSize * uSampleDirection;\n"
  "  vReadTexCoords[4] = aPos + 3.0 / 7 * uDilateRadius * uSourcePixelSize * uSampleDirection;\n"
  "  vReadTexCoords[5] = aPos - 3.0 / 7 * uDilateRadius * uSourcePixelSize * uSampleDirection;\n"
  "  vReadTexCoords[6] = aPos + 4.0 / 7 * uDilateRadius * uSourcePixelSize * uSampleDirection;\n"
  "  vReadTexCoords[7] = aPos - 4.0 / 7 * uDilateRadius * uSourcePixelSize * uSampleDirection;\n"
  "  vReadTexCoords[8] = aPos + 5.0 / 7 * uDilateRadius * uSourcePixelSize * uSampleDirection;\n"
  "  vReadTexCoords[9] = aPos - 5.0 / 7 * uDilateRadius * uSourcePixelSize * uSampleDirection;\n"
  "  vReadTexCoords[10] = aPos + 6.0 / 7 * uDilateRadius * uSourcePixelSize * uSampleDirection;\n"
  "  vReadTexCoords[11] = aPos - 6.0 / 7 * uDilateRadius * uSourcePixelSize * uSampleDirection;\n"
  "  vReadTexCoords[12] = aPos + 7.0 / 7 * uDilateRadius * uSourcePixelSize * uSampleDirection;\n"
  "  vReadTexCoords[13] = aPos - 7.0 / 7 * uDilateRadius * uSourcePixelSize * uSampleDirection;\n"
  "  gl_Position = vec4(aPos * 2.0 - vec2(1.0), 0.0, 1.0);\n"
  "}\n";

static const char* sDilateFragmentShader =
  "#version 120\n"
  "varying vec2 vPos;\n"
  "uniform sampler2D uSampler;\n"
  "varying vec2 vReadTexCoords[14];\n"
  "void main()\n"
  "{\n"/*
  "  vec4 pixel = texture2D(uSampler, vPos);\n"
  "  vec4 maximum01 = max(texture2D(uSampler, vReadTexCoords[0]), texture2D(uSampler, vReadTexCoords[1]));\n"
  "  vec4 maximum23 = max(texture2D(uSampler, vReadTexCoords[2]), texture2D(uSampler, vReadTexCoords[3]));\n"
  "  vec4 maximum45 = max(texture2D(uSampler, vReadTexCoords[4]), texture2D(uSampler, vReadTexCoords[5]));\n"
  "  vec4 maximum67 = max(texture2D(uSampler, vReadTexCoords[6]), texture2D(uSampler, vReadTexCoords[7]));\n"
  "  vec4 maximum89 = max(texture2D(uSampler, vReadTexCoords[8]), texture2D(uSampler, vReadTexCoords[9]));\n"
  "  vec4 maximum1011 = max(texture2D(uSampler, vReadTexCoords[10]), texture2D(uSampler, vReadTexCoords[11]));\n"
  "  vec4 maximum1213 = max(texture2D(uSampler, vReadTexCoords[12]), texture2D(uSampler, vReadTexCoords[13]));\n"
  "  vec4 maximum0123 = max(maximum01, maximum23);\n"
  "  vec4 maximum4567 = max(maximum45, maximum67);\n"
  "  vec4 maximum891011 = max(maximum89, maximum1011);\n"
  "  vec4 maximum1213p = max(maximum1213, pixel);\n"
  "  vec4 maximum01234567 = max(maximum0123, maximum4567);\n"
  "  vec4 maximum8top = max(maximum891011, maximum1213p);\n"
  "  gl_FragColor = max(maximum01234567, maximum8top);\n"*/
  "  vec4 maximum = texture2D(uSampler, vPos);\n"
  "  maximum = max(maximum, texture2D(uSampler, vReadTexCoords[2]));\n"
  "  maximum = max(maximum, texture2D(uSampler, vReadTexCoords[3]));\n"
  "  maximum = max(maximum, texture2D(uSampler, vReadTexCoords[4]));\n"
  "  maximum = max(maximum, texture2D(uSampler, vReadTexCoords[5]));\n"
  "  maximum = max(maximum, texture2D(uSampler, vReadTexCoords[6]));\n"
  "  maximum = max(maximum, texture2D(uSampler, vReadTexCoords[7]));\n"
  "  maximum = max(maximum, texture2D(uSampler, vReadTexCoords[8]));\n"
  "  maximum = max(maximum, texture2D(uSampler, vReadTexCoords[9]));\n"
  "  maximum = max(maximum, texture2D(uSampler, vReadTexCoords[10]));\n"
  "  maximum = max(maximum, texture2D(uSampler, vReadTexCoords[11]));\n"
  "  maximum = max(maximum, texture2D(uSampler, vReadTexCoords[12]));\n"
  "  maximum = max(maximum, texture2D(uSampler, vReadTexCoords[13]));\n"
  "  gl_FragColor = maximum;\n"
  "}\n";

DilateProgram::DilateProgram()
 : OneSamplerProgram(sDilateVertexShader, sDilateFragmentShader)
{
  mPixelSizeUniform = glGetUniformLocation(mProgramID, "uSourcePixelSize");
  mDilateRadiusUniform = glGetUniformLocation(mProgramID, "uDilateRadius");
  mSampleDirectionUniform = glGetUniformLocation(mProgramID, "uSampleDirection");
}

void
DilateProgram::SetSourcePixelSize(CGSize aSize)
{
  glUniform2f(mPixelSizeUniform, aSize.width, aSize.height);
  checkError();
}

void
DilateProgram::SetDilateRadius(int aRadius)
{
  glUniform1f(mDilateRadiusUniform, aRadius);
  checkError();
}

void
DilateProgram::SetSampleDirection(CGSize aRadius)
{
  glUniform2f(mSampleDirectionUniform, aRadius.width, aRadius.height);
  checkError();
}

class UnpremultiplyProgram : public OneSamplerProgram
{
public:
  UnpremultiplyProgram();
};

static const char* sUnpremultiplyFragmentShader =
  "#version 120\n"
  "varying vec2 vPos;\n"
  "uniform sampler2D uSampler;\n"
  "void main()\n"
  "{\n"
  "  vec4 premul = texture2D(uSampler, vPos);\n"
  "  gl_FragColor = vec4(premul.rgb / premul.a, premul.a);\n"
  "}\n";

UnpremultiplyProgram::UnpremultiplyProgram()
 : OneSamplerProgram(sCoverBufferWith01aPosVertexShader, sUnpremultiplyFragmentShader)
{}

class PassThruProgram : public OneSamplerProgram
{
public:
  PassThruProgram();
};

static const char* sPassThruFragmentShader =
  "#version 120\n"
  "varying vec2 vPos;\n"
  "uniform sampler2D uSampler;\n"
  "void main()\n"
  "{\n"
  "  gl_FragColor = texture2D(uSampler, vPos);\n"
  "}\n";

PassThruProgram::PassThruProgram()
 : OneSamplerProgram(sCoverBufferWith01aPosVertexShader, sPassThruFragmentShader)
{}

class AlphaProgram : public OneSamplerProgram
{
public:
  AlphaProgram();
  void SetAlpha(float aAlpha);

private:
  GLuint mAlphaUniform;
};

static const char* sAlphaFragmentShader =
  "#version 120\n"
  "varying vec2 vPos;\n"
  "uniform sampler2D uSampler;\n"
  "uniform float uAlpha;\n"
  "void main()\n"
  "{\n"
  "  gl_FragColor = texture2D(uSampler, vPos) * uAlpha;\n"
  "}\n";

AlphaProgram::AlphaProgram()
 : OneSamplerProgram(sCoverBufferWith01aPosVertexShader, sAlphaFragmentShader)
{
  mAlphaUniform = glGetUniformLocation(mProgramID, "uAlpha");
}

void
AlphaProgram::SetAlpha(float aAlpha)
{
  glUniform1f(mAlphaUniform, aAlpha);
}

class TurbulenceProgram : public ShaderProgram
{
public:
  TurbulenceProgram();
  virtual ~TurbulenceProgram();
  void SetSeed(int32_t aSeed);
  void SetBaseFrequency(CGSize aBaseFreq);
  void SetOffset(CGPoint aOffset);

protected:
  GLuint mLatticeSelectorTexture;
  GLuint mLatticeSelectorUniform;
  GLuint mGradientTexture;
  GLuint mGradientUniform;
  GLuint mBaseFrequencyUniform;
  GLuint mOffsetUniform;
  int32_t mSeed;
};

static const char* sTurbulenceFragmentShader =
  "#version 120\n"
  "varying vec2 vPos;\n"
  "uniform sampler1D uLatticeSelector;\n"
  "uniform sampler1D uGradient;\n"
  "uniform vec2 uBaseFrequency;\n"
  "uniform vec2 uOffset;\n"
  "vec2 SCurve(vec2 t)\n"
  "{\n"
  "  return t * t * (3 - 2 * t);\n"
  "}\n"
  "\n"
  "vec4 BiLerp(vec2 t, vec4 aa, vec4 ab, vec4 ba, vec4 bb)\n"
  "{\n"
  "  return mix(mix(aa, ab, t.x), mix(ba, bb, t.x), t.y);\n"
  "}\n"
  "\n"
  "\n"
  "vec4 Interpolate(vec2 r, vec4 qua0, vec4 qua1, vec4 qub0, vec4 qub1, vec4 qva0, vec4 qva1, vec4 qvb0, vec4 qvb1)\n"
  "{\n"
  "  return BiLerp(SCurve(r),\n"
  "                qua0 * r.x + qua1 * r.y,\n"
  "                qva0 * (r.x - 1) + qva1 * r.y,\n"
  "                qub0 * r.x + qub1 * (r.y - 1),\n"
  "                qvb0 * (r.x - 1) + qvb1 * (r.y - 1));\n"
  "}\n"
  "\n"
  "vec4 Noise2(vec2 pos)\n"
  "{\n"
  "  vec2 nearestLatticePoint = floor(pos);\n"
  "  vec2 fractionalOffset = pos - nearestLatticePoint;\n"
  "  vec2 b0 = nearestLatticePoint; // + 4096\n;"
  "  vec2 b1 = b0 + 1;\n"
  "  float i = texture1D(uLatticeSelector, b0.x / 256.0).b * 255;\n"
  "  float j = texture1D(uLatticeSelector, b1.x / 256.0).b * 255;\n"
  "  vec4 qua0 = texture1D(uGradient, (i + b0.y) / 256);\n"
  "  vec4 qua1 = texture1D(uGradient, (i + b0.y) / 256 + 1.0 / 512);\n"
  "  vec4 qub0 = texture1D(uGradient, (i + b1.y) / 256);\n"
  "  vec4 qub1 = texture1D(uGradient, (i + b1.y) / 256 + 1.0 / 512);\n"
  "  vec4 qva0 = texture1D(uGradient, (j + b0.y) / 256);\n"
  "  vec4 qva1 = texture1D(uGradient, (j + b0.y) / 256 + 1.0 / 512);\n"
  "  vec4 qvb0 = texture1D(uGradient, (j + b1.y) / 256);\n"
  "  vec4 qvb1 = texture1D(uGradient, (j + b1.y) / 256 + 1.0 / 512);\n"
  "  return Interpolate(fractionalOffset, qua0, qua1, qub0, qub1, qva0, qva1, qvb0, qvb1);\n"
  "}\n"
  "\n"
  "void main()\n"
  "{\n"
  "  int numOctaves = 6;\n"
  "  vec2 pos = (vec2(vPos.x, 1 - vPos.y) - uOffset) * uBaseFrequency;\n"
  "  float ratio = 1.0;\n"
  "  vec4 result = vec4(0, 0, 0, 0);\n"
  "  for (int i = 0; i < numOctaves; i++) {\n"
  "    result += Noise2(pos) / ratio;\n"
  "    pos *= 2;\n"
  "    ratio *= 2;\n"
  "  }\n"
  "  gl_FragColor = (result + vec4(1)) / 2;\n"
  "}\n";

TurbulenceProgram::TurbulenceProgram()
 : ShaderProgram(sCoverBufferWith01aPosVertexShader, sTurbulenceFragmentShader)
 , mLatticeSelectorTexture(0)
 , mGradientTexture(0)
 , mSeed(0)
{
  mLatticeSelectorUniform = glGetUniformLocation(mProgramID, "uLatticeSelector");
  mGradientUniform = glGetUniformLocation(mProgramID, "uGradient");
  mBaseFrequencyUniform = glGetUniformLocation(mProgramID, "uBaseFrequency");
  mOffsetUniform = glGetUniformLocation(mProgramID, "uOffset");
  checkError();
}

TurbulenceProgram::~TurbulenceProgram()
{
  glDeleteTextures(1, &mLatticeSelectorTexture);
  glDeleteTextures(1, &mGradientTexture);
  checkError();
}

namespace {

struct RandomNumberSource
{
  RandomNumberSource(int32_t aSeed) : mLast(SetupSeed(aSeed)) {}
  int32_t Next() { mLast = Random(mLast); return mLast; }

private:
  static const int32_t RAND_M = 2147483647; /* 2**31 - 1 */
  static const int32_t RAND_A = 16807;      /* 7**5; primitive root of m */
  static const int32_t RAND_Q = 127773;     /* m / a */
  static const int32_t RAND_R = 2836;       /* m % a */

  /* Produces results in the range [1, 2**31 - 2].
     Algorithm is: r = (a * r) mod m
     where a = 16807 and m = 2**31 - 1 = 2147483647
     See [Park & Miller], CACM vol. 31 no. 10 p. 1195, Oct. 1988
     To test: the algorithm should produce the result 1043618065
     as the 10,000th generated number if the original seed is 1.
  */

  static int32_t
  SetupSeed(int32_t aSeed) {
    if (aSeed <= 0)
      aSeed = -(aSeed % (RAND_M - 1)) + 1;
    if (aSeed > RAND_M - 1)
      aSeed = RAND_M - 1;
    return aSeed;
  }

  static int32_t
  Random(int32_t aSeed)
  {
    int32_t result = RAND_A * (aSeed % RAND_Q) - RAND_R * (aSeed / RAND_Q);
    if (result <= 0)
      result += RAND_M;
    return result;
  }

  int32_t mLast;
};

} // unnamed namespace

const static int sBSize = 0x100;
const static int sPerlinN = 0x1000;

template<typename T>
static void
Swap(T& a, T& b) {
  T c = a;
  a = b;
  b = c;
}

void
TurbulenceProgram::SetSeed(int32_t aSeed)
{
  if (aSeed != mSeed || !mLatticeSelectorTexture || !mGradientTexture) {
    RandomNumberSource rand(aSeed);
    uint32_t mLatticeSelector[sBSize];
    float mGradient[sBSize][2][4];

    float gradient[4][sBSize][2];
    for (int32_t k = 0; k < 4; k++) {
      for (int32_t i = 0; i < sBSize; i++) {
        float a = float((rand.Next() % (sBSize + sBSize)) - sBSize) / sBSize;
        float b = float((rand.Next() % (sBSize + sBSize)) - sBSize) / sBSize;
        float s = sqrt(a * a + b * b);
        gradient[k][i][0] = a / s;
        gradient[k][i][1] = b / s;
      }
    }

    for (int32_t i = 0; i < sBSize; i++) {
      mLatticeSelector[i] = i;
    }
    for (int32_t i1 = sBSize - 1; i1 > 0; i1--) {
      int32_t i2 = rand.Next() % sBSize;
      Swap(mLatticeSelector[i1], mLatticeSelector[i2]);
    }

    for (int32_t i = 0; i < sBSize; i++) {
      uint8_t j = mLatticeSelector[i];
      mGradient[i][0][0] = gradient[0][j][0];
      mGradient[i][0][1] = gradient[1][j][0];
      mGradient[i][0][2] = gradient[2][j][0];
      mGradient[i][0][3] = gradient[3][j][0];
      mGradient[i][1][0] = gradient[0][j][1];
      mGradient[i][1][1] = gradient[1][j][1];
      mGradient[i][1][2] = gradient[2][j][1];
      mGradient[i][1][3] = gradient[3][j][1];
    }

    glActiveTexture(GL_TEXTURE0);
    if (!mLatticeSelectorTexture) {
      glGenTextures(1, &mLatticeSelectorTexture);
    }
    glBindTexture(GL_TEXTURE_1D, mLatticeSelectorTexture);
    glTexImage1D(GL_TEXTURE_1D, 0, GL_RGBA, 256, 0, GL_BGRA, GL_UNSIGNED_BYTE, mLatticeSelector);
    glTexParameteri(GL_TEXTURE_1D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_1D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    checkError();

    glActiveTexture(GL_TEXTURE1);
    if (!mGradientTexture) {
      glGenTextures(1, &mGradientTexture);
    }
    glBindTexture(GL_TEXTURE_1D, mGradientTexture);
    glTexImage1D(GL_TEXTURE_1D, 0, GL_RGBA32F_ARB, 512, 0, GL_RGBA, GL_FLOAT, mGradient);
    glTexParameteri(GL_TEXTURE_1D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_1D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    checkError();
  }

  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_1D, mLatticeSelectorTexture);
  glUniform1i(mLatticeSelectorUniform, 0);
  checkError();

  glActiveTexture(GL_TEXTURE1);
  glBindTexture(GL_TEXTURE_1D, mGradientTexture);
  glUniform1i(mGradientUniform, 1);
  checkError();
}

void
TurbulenceProgram::SetBaseFrequency(CGSize aBaseFreq)
{
  glUniform2f(mBaseFrequencyUniform, aBaseFreq.width, aBaseFreq.height);
}

void
TurbulenceProgram::SetOffset(CGPoint aOffset)
{
  glUniform2f(mOffsetUniform, aOffset.x, aOffset.y);
}

#define GAUSSIAN_KERNEL_HALF_WIDTH 11
#define GAUSSIAN_KERNEL_STEP 0.2

static const char* sBlurVertexShader =
  "#version 120\n"
  "// Input vertex data, different for all executions of this shader.\n"
  "attribute vec2 aPos;\n"
  "varying vec2 vPos;\n"
  "void main(){\n"
  "  vPos = aPos;\n"
  "  gl_Position = vec4(aPos * 2.0 - vec2(1.0), 0.0, 1.0);\n"
  "}\n";

static const char* sBlurFragmentShader =
  "#version 120\n"
  "varying vec2 vPos;\n"
  "#define GAUSSIAN_KERNEL_HALF_WIDTH 11\n"
  "#define GAUSSIAN_KERNEL_STEP 0.2\n"
  "uniform float uBlurGaussianKernel[GAUSSIAN_KERNEL_HALF_WIDTH];\n"
  "uniform vec2 uBlurRadius;\n"
  "uniform sampler2D uSampler;\n"
  "uniform float uMipmapLevel;\n"
  "vec4 sampleAtRadius(vec2 coord, float radius) {\n"
  "  return texture2D(uSampler, coord + radius * uBlurRadius);\n"
  "}\n"
  "\n"
  "vec4 blur(vec2 coord) {\n"
  "  vec4 total = sampleAtRadius(coord, 0) * uBlurGaussianKernel[0];\n"
  "  for (int i = 1; i < GAUSSIAN_KERNEL_HALF_WIDTH; ++i) {\n"
  "    float r = float(i) * GAUSSIAN_KERNEL_STEP; /* XXX textureGather(Offsets) */\n"
  "    float k = uBlurGaussianKernel[i];\n"
  "    total += sampleAtRadius(coord, r) * k;\n"
  "    total += sampleAtRadius(coord, -r) * k;\n"
  "  }\n"
  "  return total;\n"
  "}\n"
  "void main()\n"
  "{\n"
  "  gl_FragColor = blur(vPos);\n"
  "}\n";

class BlurProgram : public OneSamplerProgram
{
public:
  BlurProgram();
  virtual ~BlurProgram() {}
  virtual void Use();
  virtual void SetTexture(GLuint aTexture);
  virtual void SetBlurRadius(CGSize aRadius);

protected:
  GLuint mBlurRadiusUniform;
  GLuint mBlurGaussianKernelUniform;
  GLuint mMipmapLevelUniform;
};

BlurProgram::BlurProgram()
 : OneSamplerProgram(sBlurVertexShader, sBlurFragmentShader)
 , mBlurGaussianKernelUniform(0)
{
  mBlurRadiusUniform = glGetUniformLocation(mProgramID, "uBlurRadius");
  mMipmapLevelUniform = glGetUniformLocation(mProgramID, "uMipmapLevel");
  checkError();
}

void
BlurProgram::Use()
{
  OneSamplerProgram::Use();
  if (!mBlurGaussianKernelUniform) {
    mBlurGaussianKernelUniform = glGetUniformLocation(mProgramID, "uBlurGaussianKernel");
    float gaussianKernel[GAUSSIAN_KERNEL_HALF_WIDTH];
    float sum = 0.0f;
    for (int i = 0; i < GAUSSIAN_KERNEL_HALF_WIDTH; i++) {
      float x = i * GAUSSIAN_KERNEL_STEP;
      float sigma = 1.0f;
      gaussianKernel[i] = exp(-x * x / (2 * sigma * sigma)) / sqrt(2 * M_PI * sigma * sigma);
      sum += gaussianKernel[i] * (i == 0 ? 1 : 2);
    }
    for (int i = 0; i < GAUSSIAN_KERNEL_HALF_WIDTH; i++) {
      gaussianKernel[i] /= sum;
    }
    glUniform1fv(mBlurGaussianKernelUniform, GAUSSIAN_KERNEL_HALF_WIDTH, gaussianKernel);
    checkError();
  }
}

void
BlurProgram::SetTexture(GLuint aTexture)
{
  OneSamplerProgram::SetTexture(aTexture);
  checkError();
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  checkError();
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  checkError();
  // glHint(GL_GENERATE_MIPMAP_HINT, GL_FASTEST);
  // glGenerateMipmap(GL_TEXTURE_2D);
  // checkError();
}

void
BlurProgram::SetBlurRadius(CGSize aRadius)
{
  glUniform2f(mBlurRadiusUniform, aRadius.width, aRadius.height);
  checkError();

  // if (aRadius.width == 0 && aRadius.height == 0) {
  //   glUniform1f(mMipmapLevelUniform, 0);
  // } else {
  //   CGSize textureSize = { 1600, 1000 };
  //   CGSize samplePointDistance = {
  //     textureSize.width * aRadius.width * GAUSSIAN_KERNEL_STEP,
  //     textureSize.height * aRadius.height * GAUSSIAN_KERNEL_STEP
  //   };
  //   CGSize log2 = { log(samplePointDistance.width) / log(2), log(samplePointDistance.height) / log(2) };
  //   printf("%f, %f\n", log2.width, log2.height);
  //   glUniform1f(mMipmapLevelUniform, ceil(std::max(log2.width, log2.height) * 1.2));
  // }
}

@interface TestView: NSView
{
  NSOpenGLContext* mContext;
  DilateProgram* mDilateProgram;
  UnpremultiplyProgram* mUnpremultiplyProgram;
  PassThruProgram* mPassThruProgram;
  TurbulenceProgram* mTurbulenceProgram;
  BlurProgram* mBlurProgram;
  GLuint mTexture;
  GLuint mQuad;
  CVDisplayLinkRef mDisplayLink;
  NSOpenGLPixelFormat* mPixelFormat;
}

- (void)displayGL;

@end 

// This is the renderer output callback function

static CVReturn
MyDisplayLinkCallback(CVDisplayLinkRef displayLink, const CVTimeStamp* now,
                      const CVTimeStamp* outputTime, CVOptionFlags flagsIn,
                      CVOptionFlags* flagsOut, void* aClosure)
{
  [(TestView*)aClosure displayGL];
  return kCVReturnSuccess;
}

static CGPoint sScrollOffset = { 0, 0 };

static const CGEventType kCGEventGesture = 29;
static const CGEventField kCGGestureType = 110;
static const CGEventField kCGMagnifyEventMagnification = 113; // or 114 or 116 or 118
static const CGEventField kCGRotateEventRotation = 113; // or 114 or 116 or 118
static const int64_t kCGGestureTypeRotate = 5;
static const int64_t kCGGestureTypeMagnify = 8;
static const int64_t kCGGestureTypeBeginGesture = 61;
static const int64_t kCGGestureTypeEndGesture = 62;

// Called on scroll thread
static CGEventRef
ScrollEventCallback(CGEventTapProxy proxy, CGEventType type,
                    CGEventRef cgEvent, void *refcon)
{
  if (type == kCGEventScrollWheel) {
    NSEvent* event = [NSEvent eventWithCGEvent:cgEvent];
    if ([event window]) {
      sScrollOffset.x += [event scrollingDeltaX];
      sScrollOffset.y += [event scrollingDeltaY];
    }
  }
  return cgEvent;
}

@implementation TestView

- (id)initWithFrame:(NSRect)aFrame
{
  if (self = [super initWithFrame:aFrame]) {

    [NSThread detachNewThreadSelector:@selector(runScrollThread) toTarget:self withObject:nil];

    NSOpenGLPixelFormatAttribute attribs[] = {
        NSOpenGLPFAAccelerated,
#ifdef DISPLAY_GL_TO_WINDOW
        //NSOpenGLPFADoubleBuffer,
#else
        NSOpenGLPFAAllowOfflineRenderers,
#endif
        (NSOpenGLPixelFormatAttribute)nil 
    };
    mPixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attribs];
    mContext = [[NSOpenGLContext alloc] initWithFormat:mPixelFormat shareContext:nil];
#ifdef DISPLAY_GL_TO_WINDOW
    GLint swapInt = 1;
    [mContext setValues:&swapInt forParameter:NSOpenGLCPSwapInterval];
    GLint opaque = 0;
    [mContext setValues:&opaque forParameter:NSOpenGLCPSurfaceOpacity];
#endif
    mDisplayLink = NULL;

    [mContext makeCurrentContext];
    [self _initGL];
#ifdef DISPLAY_GL_TO_WINDOW
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(_surfaceNeedsUpdate:)
                                                 name:NSViewGlobalFrameDidChangeNotification
                                               object:self];
#endif
  }
  return self;
}

- (void)dealloc
{
  [self _cleanupGL];
#ifdef DISPLAY_GL_TO_WINDOW
  CVDisplayLinkRelease(mDisplayLink);
#endif
  [mPixelFormat release];
  [mContext release];
  [super dealloc];
}

static GLuint
CreateTexture(NSSize size, void (^drawCallback)(CGContextRef ctx))
{
  int width = size.width;
  int height = size.height;
  CGColorSpaceRef rgb = CGColorSpaceCreateDeviceRGB();
  CGContextRef imgCtx = CGBitmapContextCreate(NULL, width, height, 8, width * 4,
                                              rgb, kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host);
  CGColorSpaceRelease(rgb);
  drawCallback(imgCtx);

  GLuint texture = 0;
  glActiveTexture(GL_TEXTURE0);
  glGenTextures(1, &texture);
  glBindTexture(GL_TEXTURE_2D, texture);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, width, height, 0, GL_BGRA, GL_UNSIGNED_BYTE, CGBitmapContextGetData(imgCtx));
  CGContextRelease(imgCtx);
  checkError();
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  checkError();
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  checkError();
  return texture;
}

- (void)_initGL
{
  mDilateProgram = new DilateProgram();
  mUnpremultiplyProgram = new UnpremultiplyProgram();
  mPassThruProgram = new PassThruProgram();
  mTurbulenceProgram = new TurbulenceProgram();
  mBlurProgram = new BlurProgram();
  checkError();

  if (false) {
    mTexture = CreateTexture(NSMakeSize(300, 200), ^(CGContextRef ctx) {
      // CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
      // CGContextFillRect(ctx, CGRectMake(0, 0, 300, 200));
      CGContextSetRGBFillColor(ctx, 0, 0, 1, 1);
      CGContextFillEllipseInRect(ctx, CGRectMake(100, 50, 100, 100));
      CGContextFillRect(ctx, CGRectMake(100, 140, 100, 20));
      CGContextSetRGBFillColor(ctx, 0.8, 0.1, 0.2, 0.6);
      CGContextFillRect(ctx, CGRectMake(50, 60, 80, 40));
      CGContextSetRGBFillColor(ctx, 0.1, 0.8, 0.2, 0.5);
      CGContextFillEllipseInRect(ctx, CGRectMake(170, 100, 60, 80));
    });
  } else {
    NSImage* image = [NSImage imageNamed:@"firefox_logo-only_RGB.png"];
    NSSize textureSize = { 1600, 1000 };
    mTexture = CreateTexture(textureSize, ^(CGContextRef ctx) {
      CGContextTranslateCTM(ctx, 0, textureSize.height);
      CGContextScaleCTM(ctx, 1, -1);
      CGContextTranslateCTM(ctx, textureSize.width / 2, textureSize.height / 2);
      CGContextScaleCTM(ctx, 0.25, 0.25);
      CGContextTranslateCTM(ctx, -[image size].width / 2, -[image size].height / 2);
      NSGraphicsContext* oldContext = [NSGraphicsContext currentContext];
      NSGraphicsContext* gctx = [NSGraphicsContext graphicsContextWithGraphicsPort:ctx flipped:YES];
      [NSGraphicsContext setCurrentContext:gctx];
      [image drawAtPoint:NSZeroPoint fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
      [NSGraphicsContext setCurrentContext:oldContext];
      [gctx release];
    });
    [image release];
  }
  checkError();

  mQuad = [self _createQuad];
}

- (BOOL)isFlipped
{
  return YES;
}

- (GLuint)_createQuad
{
  static const GLfloat data[] = { 
    0.0f, 0.0f,
    1.0f, 0.0f,
    0.0f, 1.0f,
    1.0f, 1.0f
  };

  GLuint quad;
  glGenBuffers(1, &quad);
  glBindBuffer(GL_ARRAY_BUFFER, quad);
  glBufferData(GL_ARRAY_BUFFER, sizeof(data), data, GL_STATIC_DRAW);
  checkError();
  return quad;
}

- (void)_cleanupGL
{
  glDeleteTextures(1, &mTexture);
  glDeleteBuffers(1, &mQuad);
  delete mDilateProgram;
  delete mUnpremultiplyProgram;
  delete mPassThruProgram;
  delete mTurbulenceProgram;
  delete mBlurProgram;
}

#ifdef DISPLAY_GL_TO_WINDOW
- (void)_surfaceNeedsUpdate:(NSNotification*)notification
{
  [mContext update];
}
#endif

- (void)drawRect:(NSRect)aRect
{
  [[NSColor clearColor] set];
  NSRectFill(aRect);
  [self displayGL];
}

- (void)displayGL
{
  if (![[self window] isVisible] && ![NSView focusView]) {
    return;
  }

  CGLLockContext((CGLContextObj)[mContext CGLContextObj]);

  GLdouble pointWidth = [self bounds].size.width;
  GLdouble pointHeight = [self bounds].size.height;
  NSSize backingSize = [self convertSizeToBacking:[self bounds].size];
  GLdouble width = backingSize.width;
  GLdouble height = backingSize.height;

#ifdef DISPLAY_GL_TO_WINDOW
  if (!mDisplayLink) {
    // Create a display link capable of being used with all active displays
    CVDisplayLinkCreateWithActiveCGDisplays(&mDisplayLink);

    // Set the renderer output callback function
    CVDisplayLinkSetOutputCallback(mDisplayLink, &MyDisplayLinkCallback, self);

    // Set the display link for the current renderer
    CGLContextObj cglContext = (CGLContextObj)[mContext CGLContextObj];
    CGLPixelFormatObj cglPixelFormat = (CGLPixelFormatObj)[mPixelFormat CGLPixelFormatObj];
    CVDisplayLinkSetCurrentCGDisplayFromOpenGLContext(mDisplayLink, cglContext, cglPixelFormat);

    // Activate the display link
    CVDisplayLinkStart(mDisplayLink);
  }

  [mContext setView:self];
#endif

  [mContext makeCurrentContext];
  checkError();

#ifdef DISPLAY_GL_TO_WINDOW
  glViewport(0, 0, width, height);
  checkError();

  glClearColor(1.0, 1.0, 1.0, 1.0);
  glClear(GL_COLOR_BUFFER_BIT);
  checkError();
#else
  CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
  CGContextSetInterpolationQuality(ctx, kCGInterpolationNone);
#endif

  // Turbulence
  checkError();
  TextureSurface* turbulenced = new TextureSurface(width, height);
  turbulenced->DrawInto(^{
    glBlendFuncSeparate(GL_SRC_ALPHA, GL_ZERO,
                        GL_ONE,       GL_ZERO); // premultiply at the same time
    mTurbulenceProgram->Use();
    mTurbulenceProgram->SetSeed(0);
    mTurbulenceProgram->SetBaseFrequency(CGSizeMake(pointWidth / 100, pointHeight / 100));
    mTurbulenceProgram->SetOffset(CGPointMake(sScrollOffset.x / pointWidth, sScrollOffset.y / pointHeight));
    mTurbulenceProgram->DrawQuad(mQuad);
  });
/*

  // Unpremultiply
  TextureSurface* surf2 = new TextureSurface(width, height);
  surf2->DrawInto(^{
    glBlendFunc(GL_ONE, GL_ZERO);  // op source
    mUnpremultiplyProgram->Use();
    mUnpremultiplyProgram->SetTexture(surf4->TextureID());
    mUnpremultiplyProgram->DrawQuad(mQuad);
  });

  // Premultiply
  TextureSurface* surf3 = new TextureSurface(width, height);
  surf3->DrawInto(^{
    glBlendFuncSeparate(GL_SRC_ALPHA, GL_ZERO,
                        GL_ONE,       GL_ZERO);
    mPassThruProgram->Use();
    mPassThruProgram->SetTexture(surf2->TextureID());
    mPassThruProgram->DrawQuad(mQuad);
  });
*/

  CGSize blurRadius = {
    (-cos(sScrollOffset.x / 600) + 1) / 2 * 100,
    (-cos(sScrollOffset.y / 600) + 1) / 2 * 100
  };
  CGSize textureSize = { 1600, 1000 };
  CGSize samplePointDistance = {
    blurRadius.width * GAUSSIAN_KERNEL_STEP,
    blurRadius.height * GAUSSIAN_KERNEL_STEP
  };
  CGSize numHalvingSteps = {
    log(std::max(1.0, samplePointDistance.width)) / log(2),
    log(std::max(1.0, samplePointDistance.height)) / log(2),
  };

  GLuint reducedSource = mTexture;
  TextureSurface* sourceStorage = 0;
  CGSize sourceSize = textureSize;

  for (int i = 0; i < std::max(numHalvingSteps.width, numHalvingSteps.height); i++) {
    CGSize nextLevelSize = {
      sourceSize.width / (i < numHalvingSteps.width ? 2 : 1),
      sourceSize.height / (i < numHalvingSteps.height ? 2 : 1)
    };
    TextureSurface* nextLevel = new TextureSurface(nextLevelSize.width, nextLevelSize.height);
    nextLevel->DrawInto(^{
      glBlendFuncSeparate(GL_ONE, GL_ZERO,
                          GL_ONE, GL_ZERO);
      mPassThruProgram->Use();
      mPassThruProgram->SetTexture(reducedSource);
      mPassThruProgram->DrawQuad(mQuad);
    });
    if (sourceStorage) {
      delete sourceStorage;
    }
    sourceStorage = nextLevel;
    sourceSize = nextLevelSize;
    reducedSource = nextLevel->TextureID();
  }

  // blurRadius = CGSizeMake(0, 0);

  TextureSurface* blurredHoriz = new TextureSurface(sourceSize.width, height);
  blurredHoriz->DrawInto(^{
    glBlendFuncSeparate(GL_ONE, GL_ZERO,
                        GL_ONE, GL_ZERO);
    mBlurProgram->Use();
    // mBlurProgram->SetBlurRadius(CGSizeMake(blurRadius.width / width, 0));
    mBlurProgram->SetBlurRadius(CGSizeMake(0, blurRadius.height / height));
    mBlurProgram->SetTexture(reducedSource);
    mBlurProgram->DrawQuad(mQuad);
  });

  TextureSurface* blurredBoth = new TextureSurface(width, height);
  blurredBoth->DrawInto(^{
    glBlendFuncSeparate(GL_ONE, GL_ZERO,
                        GL_ONE, GL_ZERO);
    mBlurProgram->Use();
    mBlurProgram->SetBlurRadius(CGSizeMake(blurRadius.width / width, 0));
    // mBlurProgram->SetBlurRadius(CGSizeMake(0, blurRadius.height / height));
    mBlurProgram->SetTexture(blurredHoriz->TextureID());
    mBlurProgram->DrawQuad(mQuad);
  });
/*
  // Dilate
  TextureSurface* dilatedH = new TextureSurface(width, height);
  dilatedH->DrawInto(^{
    glBlendFunc(GL_ONE, GL_ZERO); // op source
    mDilateProgram->Use();
    mDilateProgram->SetTexture(blurredBoth->TextureID());
    mDilateProgram->SetSourcePixelSize(CGSizeMake(1.0 / blurredBoth->Size().width, 1.0 / blurredBoth->Size().height));
    mDilateProgram->SetDilateRadius(10);
    mDilateProgram->SetSampleDirection(CGSizeMake(1, 0));
    mDilateProgram->DrawQuad(mQuad);
  });
  TextureSurface* dilatedV = new TextureSurface(width, height);
  dilatedV->DrawInto(^{
    glBlendFunc(GL_ONE, GL_ZERO); // op source
    mDilateProgram->Use();
    mDilateProgram->SetTexture(dilatedH->TextureID());
    mDilateProgram->SetSourcePixelSize(CGSizeMake(1.0 / blurredBoth->Size().width, 1.0 / blurredBoth->Size().height));
    mDilateProgram->SetDilateRadius(10);
    mDilateProgram->SetSampleDirection(CGSizeMake(0, 1));
    mDilateProgram->DrawQuad(mQuad);
  });
  dilatedH->DrawInto(^{
    glBlendFunc(GL_ONE, GL_ZERO); // op source
    mDilateProgram->Use();
    mDilateProgram->SetTexture(dilatedV->TextureID());
    mDilateProgram->SetSourcePixelSize(CGSizeMake(1.0 / blurredBoth->Size().width, 1.0 / blurredBoth->Size().height));
    mDilateProgram->SetDilateRadius(10);
    mDilateProgram->SetSampleDirection(CGSizeMake(1, 0));
    mDilateProgram->DrawQuad(mQuad);
  });
  dilatedV->DrawInto(^{
    glBlendFunc(GL_ONE, GL_ZERO); // op source
    mDilateProgram->Use();
    mDilateProgram->SetTexture(dilatedH->TextureID());
    mDilateProgram->SetSourcePixelSize(CGSizeMake(1.0 / blurredBoth->Size().width, 1.0 / blurredBoth->Size().height));
    mDilateProgram->SetDilateRadius(10);
    mDilateProgram->SetSampleDirection(CGSizeMake(0, 1));
    mDilateProgram->DrawQuad(mQuad);
  });
*/
#ifdef DISPLAY_GL_TO_WINDOW
  glBlendFuncSeparate(GL_ONE, GL_ONE_MINUS_SRC_ALPHA,
                      GL_ONE, GL_ONE_MINUS_SRC_ALPHA);
  mPassThruProgram->Use();
  mPassThruProgram->SetTexture(turbulenced->TextureID());
  mPassThruProgram->DrawQuad(mQuad);
  mPassThruProgram->SetTexture(blurredBoth->TextureID());
  mPassThruProgram->DrawQuad(mQuad);

  //[mContext flushBuffer];
  glFlush();
#else
  CGImageRef img = surf3->Snapshot();
  CGRect drawRect = { { 0, 0 }, { surf3->Size().width / 2, surf3->Size().height / 2 } };
  CGContextSetRGBFillColor(ctx, 1, 1, 1, 1);
  CGContextFillRect(ctx, drawRect);
  CGContextDrawImage(ctx, drawRect, img);
  CGImageRelease(img);
#endif
  // delete dilatedH;
  // delete dilatedV;
/*
  delete surf3;
  delete surf2;*/
  delete turbulenced;
  delete blurredHoriz;
  delete blurredBoth;
  if (sourceStorage) {
    delete sourceStorage;
  }
  CGLUnlockContext((CGLContextObj)[mContext CGLContextObj]);
}

- (BOOL)wantsBestResolutionOpenGLSurface
{
  return YES;
}

- (void)runScrollThread
{
  ProcessSerialNumber currentProcess;
  GetCurrentProcess(&currentProcess);
  CFMachPortRef eventPort =
    CGEventTapCreateForPSN(&currentProcess,
                           kCGHeadInsertEventTap,
                           kCGEventTapOptionListenOnly,
                           kCGEventMaskForAllEvents,
                           ScrollEventCallback,
                           self);
  CFRunLoopSourceRef eventPortSource =
    CFMachPortCreateRunLoopSource(kCFAllocatorSystemDefault, eventPort, 0);
  CFRunLoopAddSource(CFRunLoopGetCurrent(), eventPortSource, kCFRunLoopCommonModes);
  CFRunLoopRun();
}

@end

@interface TerminateOnClose : NSObject<NSWindowDelegate>
@end

@implementation TerminateOnClose
- (void)windowWillClose:(NSNotification*)notification
{
  [NSApp terminate:self];
}
@end

@interface TestWindow : NSWindow
@end

@implementation TestWindow

- (BOOL)_shouldRoundCornersForSurface
{
  return NO;
}

@end

int
main (int argc, char **argv)
{
  NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];

  [NSApplication sharedApplication];
  [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];

  int style = 
    NSTitledWindowMask | NSClosableWindowMask | NSResizableWindowMask | NSMiniaturizableWindowMask;
  NSRect contentRect = NSMakeRect(200, 200, 1000, 625);
  NSWindow* window = [[TestWindow alloc] initWithContentRect:contentRect
                                       styleMask:style
                                         backing:NSBackingStoreBuffered
                                           defer:NO];

  NSView* view = [[TestView alloc] initWithFrame:NSMakeRect(0, 0, contentRect.size.width, contentRect.size.height)];
    
  [window setContentView:view];
  [window setDelegate:[[TerminateOnClose alloc] autorelease]];
  [window setCollectionBehavior:[window collectionBehavior] | NSWindowCollectionBehaviorFullScreenPrimary];
  [NSApp activateIgnoringOtherApps:YES];
  [window makeKeyAndOrderFront:window];

  [NSApp run];

  [pool release];
  
  return 0;
}
