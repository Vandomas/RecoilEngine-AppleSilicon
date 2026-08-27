// Minimal instanced-draw correctness test on EGL surfaceless + desktop GL.
// Draws 8 instanced quads into an FBO, one per column; prints which columns lit.
#include <EGL/egl.h>
#include <GL/gl.h>

// resolve every GL symbol dynamically: the stack has no libGL
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef void (*PFN)(void);
static PFN L(const char* n){ return eglGetProcAddress(n); }

typedef GLuint (*PFNCREATESHADER)(GLenum);
typedef void (*PFNSHADERSOURCE)(GLuint, GLsizei, const char* const*, const GLint*);
typedef void (*PFNCOMPILESHADER)(GLuint);
typedef GLuint (*PFNCREATEPROGRAM)(void);
typedef void (*PFNATTACH)(GLuint, GLuint);
typedef void (*PFNLINK)(GLuint);
typedef void (*PFNUSE)(GLuint);
typedef void (*PFNGENB)(GLsizei, GLuint*);
typedef void (*PFNBINDB)(GLenum, GLuint);
typedef void (*PFNBUFD)(GLenum, GLsizeiptr, const void*, GLenum);
typedef void (*PFNGENVA)(GLsizei, GLuint*);
typedef void (*PFNBINDVA)(GLuint);
typedef void (*PFNVAP)(GLuint, GLint, GLenum, GLboolean, GLsizei, const void*);
typedef void (*PFNEVA)(GLuint);
typedef void (*PFNDIV)(GLuint, GLuint);
typedef void (*PFNDEIBV)(GLenum, GLsizei, GLenum, const void*, GLsizei, GLint);
typedef void (*PFNDEI)(GLenum, GLsizei, GLenum, const void*, GLsizei);
typedef void (*PFNGENF)(GLsizei, GLuint*);
typedef void (*PFNBINDF)(GLenum, GLuint);
typedef void (*PFNFBT2)(GLenum, GLenum, GLenum, GLuint, GLint);
typedef void (*PFNGETSIV)(GLuint, GLenum, GLint*);
typedef void (*PFNGETSLOG)(GLuint, GLsizei, GLsizei*, char*);


typedef const GLubyte* (*PFNGETSTR)(GLenum);
typedef void (*PFNGENTEX)(GLsizei, GLuint*);
typedef void (*PFNBINDTEX)(GLenum, GLuint);
typedef void (*PFNTEXIMG)(GLenum, GLint, GLint, GLsizei, GLsizei, GLint, GLenum, GLenum, const void*);
typedef void (*PFNVIEWPORT)(GLint, GLint, GLsizei, GLsizei);
typedef void (*PFNCLEARCOL)(GLfloat, GLfloat, GLfloat, GLfloat);
typedef void (*PFNCLEAR)(GLbitfield);
typedef void (*PFNFINISH)(void);
typedef void (*PFNREADPX)(GLint, GLint, GLsizei, GLsizei, GLenum, GLenum, void*);
typedef GLenum (*PFNGETERR)(void);

int main(int argc, char** argv) {
   int use_base_vertex = argc > 1 && !strcmp(argv[1], "bv");
   EGLDisplay dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
   eglInitialize(dpy, NULL, NULL);
   eglBindAPI(EGL_OPENGL_API);
   EGLint cfga[] = { EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_BIT, EGL_NONE };
   EGLConfig cfg; EGLint n;
   eglChooseConfig(dpy, cfga, &cfg, 1, &n);
   EGLint pba[] = { EGL_WIDTH, 8, EGL_HEIGHT, 8, EGL_NONE };
   EGLSurface surf = eglCreatePbufferSurface(dpy, cfg, pba);
   EGLContext ctx = eglCreateContext(dpy, cfg, EGL_NO_CONTEXT, NULL);
   eglMakeCurrent(dpy, surf, surf, ctx);
   PFNGETSTR GetString = (PFNGETSTR)L("glGetString");
   PFNGENTEX GenTextures = (PFNGENTEX)L("glGenTextures");
   PFNBINDTEX BindTexture = (PFNBINDTEX)L("glBindTexture");
   PFNTEXIMG TexImage2D = (PFNTEXIMG)L("glTexImage2D");
   PFNVIEWPORT Viewport = (PFNVIEWPORT)L("glViewport");
   PFNCLEARCOL ClearColor = (PFNCLEARCOL)L("glClearColor");
   PFNCLEAR Clear = (PFNCLEAR)L("glClear");
   PFNFINISH Finish = (PFNFINISH)L("glFinish");
   PFNREADPX ReadPixels = (PFNREADPX)L("glReadPixels");
   PFNGETERR GetError = (PFNGETERR)L("glGetError");
   printf("GL: %s\n", (const char*)GetString(GL_RENDERER));

   PFNCREATESHADER CreateShader = (PFNCREATESHADER)L("glCreateShader");
   PFNSHADERSOURCE ShaderSource = (PFNSHADERSOURCE)L("glShaderSource");
   PFNCOMPILESHADER CompileShader = (PFNCOMPILESHADER)L("glCompileShader");
   PFNCREATEPROGRAM CreateProgram = (PFNCREATEPROGRAM)L("glCreateProgram");
   PFNATTACH AttachShader = (PFNATTACH)L("glAttachShader");
   PFNLINK LinkProgram = (PFNLINK)L("glLinkProgram");
   PFNUSE UseProgram = (PFNUSE)L("glUseProgram");
   PFNGENB GenBuffers = (PFNGENB)L("glGenBuffers");
   PFNBINDB BindBuffer = (PFNBINDB)L("glBindBuffer");
   PFNBUFD BufferData = (PFNBUFD)L("glBufferData");
   PFNGENVA GenVertexArrays = (PFNGENVA)L("glGenVertexArrays");
   PFNBINDVA BindVertexArray = (PFNBINDVA)L("glBindVertexArray");
   PFNVAP VertexAttribPointer = (PFNVAP)L("glVertexAttribPointer");
   PFNEVA EnableVertexAttribArray = (PFNEVA)L("glEnableVertexAttribArray");
   PFNDIV VertexAttribDivisor = (PFNDIV)L("glVertexAttribDivisor");
   PFNDEIBV DrawElementsInstancedBaseVertex = (PFNDEIBV)L("glDrawElementsInstancedBaseVertex");
   PFNDEI DrawElementsInstanced = (PFNDEI)L("glDrawElementsInstanced");
   PFNGENF GenFramebuffers = (PFNGENF)L("glGenFramebuffers");
   PFNBINDF BindFramebuffer = (PFNBINDF)L("glBindFramebuffer");
   PFNFBT2 FramebufferTexture2D = (PFNFBT2)L("glFramebufferTexture2D");
   PFNGETSIV GetShaderiv = (PFNGETSIV)L("glGetShaderiv");
   PFNGETSLOG GetShaderInfoLog = (PFNGETSLOG)L("glGetShaderInfoLog");

   const char* vs =
      "#version 330 core\n"
      "layout(location=0) in vec2 pos;\n"
      "layout(location=1) in vec2 offs;\n"
      "void main(){ gl_Position = vec4(pos.x*0.11 + offs.x, pos.y*0.85, 0.0, 1.0); }\n";
   const char* fs =
      "#version 330 core\nout vec4 c;\nvoid main(){ c = vec4(1.0); }\n";

   GLuint v = CreateShader(0x8B31), f = CreateShader(0x8B30);
   ShaderSource(v, 1, &vs, NULL); CompileShader(v);
   ShaderSource(f, 1, &fs, NULL); CompileShader(f);
   GLint ok; GetShaderiv(v, 0x8B81, &ok);
   if (!ok) { char log[512]; GetShaderInfoLog(v, 512, NULL, log); printf("VS: %s\n", log); return 1; }
   GLuint p = CreateProgram(); AttachShader(p, v); AttachShader(p, f); LinkProgram(p); UseProgram(p);

   // FBO 64x8
   GLuint tex; GenTextures(1, &tex); BindTexture(GL_TEXTURE_2D, tex);
   TexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 64, 8, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
   GLuint fbo; GenFramebuffers(1, &fbo); BindFramebuffer(0x8D40, fbo);
   FramebufferTexture2D(0x8D40, 0x8CE0, GL_TEXTURE_2D, tex, 0);
   Viewport(0, 0, 64, 8);
   ClearColor(0, 0, 0, 1); Clear(GL_COLOR_BUFFER_BIT);

   float quad[] = { -1,-1, 1,-1, 1,1, -1,1 };
   unsigned idx[] = { 0,1,2, 0,2,3 };
   float offs[16];
   for (int i = 0; i < 8; i++) { offs[i*2] = -0.875f + i * 0.25f; offs[i*2+1] = 0.f; }

   GLuint vao; GenVertexArrays(1, &vao); BindVertexArray(vao);
   GLuint vb, ib, ob;
   GenBuffers(1, &vb); BindBuffer(0x8892, vb); BufferData(0x8892, sizeof quad, quad, 0x88E4);
   VertexAttribPointer(0, 2, GL_FLOAT, 0, 0, 0); EnableVertexAttribArray(0);
   GenBuffers(1, &ob); BindBuffer(0x8892, ob); BufferData(0x8892, sizeof offs, offs, 0x88E4);
   VertexAttribPointer(1, 2, GL_FLOAT, 0, 0, 0); EnableVertexAttribArray(1); VertexAttribDivisor(1, 1);
   GenBuffers(1, &ib); BindBuffer(0x8893, ib); BufferData(0x8893, sizeof idx, idx, 0x88E4);

   for (int pass = 1; pass <= 8; pass *= 2) {
      Clear(GL_COLOR_BUFFER_BIT);
      if (use_base_vertex)
         DrawElementsInstancedBaseVertex(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0, pass, 0);
      else
         DrawElementsInstanced(GL_TRIANGLES, 6, GL_UNSIGNED_INT, 0, pass);
      Finish();
      unsigned char px[64*8*4];
      ReadPixels(0, 0, 64, 8, GL_RGBA, GL_UNSIGNED_BYTE, px);
      printf("inst=%d lit:", pass);
      for (int i = 0; i < 8; i++) {
         int x = i * 8 + 4;
         printf(" %c", px[(4*64 + x) * 4] > 128 ? '0' + i : '.');
      }
      printf("   (GLerr=0x%x)\n", GetError());
   }
   return 0;
}
