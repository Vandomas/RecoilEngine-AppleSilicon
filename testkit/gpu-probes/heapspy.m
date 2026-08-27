#import <Metal/Metal.h>
#import <objc/runtime.h>
#include <execinfo.h>
#include <stdatomic.h>
#include <stdio.h>

static FILE *out;
static atomic_ullong c_heap, c_devbuf, c_devtex, c_heapbuf, c_heaptex, c_cmdbuf, c_nocopy;
static atomic_ullong b_devbuf, b_heapbuf;

static void trace(const char *tag, unsigned long long n, size_t bytes)
{
   fprintf(out, "\n[%s] #%llu size=%zuK\n", tag, n, bytes / 1024);
   void *cb[32];
   int f = backtrace(cb, 32);
   char **syms = backtrace_symbols(cb, f);
   for (int i = 1; i < f && i < 16; i++)
      fprintf(out, "    %s\n", syms[i]);
   free(syms);
   fflush(out);
}

static void tick(void)
{
   static atomic_ullong last;
   unsigned long long total = atomic_load(&c_devbuf) + atomic_load(&c_heapbuf) +
                              atomic_load(&c_devtex) + atomic_load(&c_heaptex) +
                              atomic_load(&c_cmdbuf) + atomic_load(&c_nocopy);
   if (total - atomic_load(&last) < 5000)
      return;
   atomic_store(&last, total);
   fprintf(out, "[COUNTS] heap=%llu devbuf=%llu(%.0fMB) heapbuf=%llu(%.0fMB) devtex=%llu heaptex=%llu cmdbuf=%llu nocopy=%llu\n",
           atomic_load(&c_heap), atomic_load(&c_devbuf), atomic_load(&b_devbuf) / 1048576.0,
           atomic_load(&c_heapbuf), atomic_load(&b_heapbuf) / 1048576.0,
           atomic_load(&c_devtex), atomic_load(&c_heaptex), atomic_load(&c_cmdbuf), atomic_load(&c_nocopy));
   fflush(out);
}

#define HOOK(name, ret, args, body)                                                                \
   static IMP orig_##name;                                                                         \
   static ret spy_##name args body

HOOK(devbuf, id, (id self, SEL _cmd, NSUInteger len, MTLResourceOptions o), {
   unsigned long long n = atomic_fetch_add(&c_devbuf, 1) + 1;
   atomic_fetch_add(&b_devbuf, len);
   if (n <= 2 || (n % 20000) == 0) trace("DEVBUF", n, len);
   tick();
   return ((id (*)(id, SEL, NSUInteger, MTLResourceOptions))orig_devbuf)(self, _cmd, len, o);
})

HOOK(heapbuf, id, (id self, SEL _cmd, NSUInteger len, MTLResourceOptions o, NSUInteger off), {
   unsigned long long n = atomic_fetch_add(&c_heapbuf, 1) + 1;
   atomic_fetch_add(&b_heapbuf, len);
   if (n <= 2 || (n % 20000) == 0) trace("HEAPBUF", n, len);
   tick();
   return ((id (*)(id, SEL, NSUInteger, MTLResourceOptions, NSUInteger))orig_heapbuf)(self, _cmd, len, o, off);
})

HOOK(devtex, id, (id self, SEL _cmd, MTLTextureDescriptor *d), {
   unsigned long long n = atomic_fetch_add(&c_devtex, 1) + 1;
   if (n <= 2 || (n % 20000) == 0) trace("DEVTEX", n, (size_t)d.width * d.height * 4);
   tick();
   return ((id (*)(id, SEL, MTLTextureDescriptor *))orig_devtex)(self, _cmd, d);
})

HOOK(heaptex, id, (id self, SEL _cmd, MTLTextureDescriptor *d, NSUInteger off), {
   unsigned long long n = atomic_fetch_add(&c_heaptex, 1) + 1;
   if (n <= 2 || (n % 20000) == 0) trace("HEAPTEX", n, (size_t)d.width * d.height * 4);
   tick();
   return ((id (*)(id, SEL, MTLTextureDescriptor *, NSUInteger))orig_heaptex)(self, _cmd, d, off);
})

HOOK(cmdbuf, id, (id self, SEL _cmd), {
   unsigned long long n = atomic_fetch_add(&c_cmdbuf, 1) + 1;
   if (n <= 2 || (n % 20000) == 0) trace("CMDBUF", n, 0);
   tick();
   return ((id (*)(id, SEL))orig_cmdbuf)(self, _cmd);
})

HOOK(heapmk, id, (id self, SEL _cmd, MTLHeapDescriptor *d), {
   atomic_fetch_add(&c_heap, 1);
   return ((id (*)(id, SEL, MTLHeapDescriptor *))orig_heapmk)(self, _cmd, d);
})

static void swiz(Class c, SEL sel, IMP newimp, IMP *saved, const char *what)
{
   Method m = class_getInstanceMethod(c, sel);
   if (!m) { fprintf(out, "[HEAPSPY] miss %s on %s\n", what, class_getName(c)); return; }
   *saved = method_getImplementation(m);
   method_setImplementation(m, newimp);
   fprintf(out, "[HEAPSPY] hooked %s on %s\n", what, class_getName(c));
}

__attribute__((constructor)) static void heapspy_init(void)
{
   const char *p = getenv("HEAPSPY_OUT");
   out = p ? fopen(p, "w") : stderr;
   if (!out) out = stderr;

   id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
   Class dc = object_getClass(dev);
   swiz(dc, @selector(newBufferWithLength:options:), (IMP)spy_devbuf, &orig_devbuf, "dev.newBuffer");
   swiz(dc, @selector(newTextureWithDescriptor:), (IMP)spy_devtex, &orig_devtex, "dev.newTexture");
   swiz(dc, @selector(newHeapWithDescriptor:), (IMP)spy_heapmk, &orig_heapmk, "dev.newHeap");

   MTLHeapDescriptor *hd = [MTLHeapDescriptor new];
   hd.type = MTLHeapTypePlacement;
   hd.resourceOptions = MTLResourceStorageModeShared;
   hd.size = 1 << 20;
   id<MTLHeap> h = [dev newHeapWithDescriptor:hd];
   if (h) {
      Class hc = object_getClass(h);
      swiz(hc, @selector(newBufferWithLength:options:offset:), (IMP)spy_heapbuf, &orig_heapbuf, "heap.newBuffer");
      swiz(hc, @selector(newTextureWithDescriptor:offset:), (IMP)spy_heaptex, &orig_heaptex, "heap.newTexture");
   }

   id<MTLCommandQueue> q = [dev newCommandQueue];
   if (q)
      swiz(object_getClass(q), @selector(commandBuffer), (IMP)spy_cmdbuf, &orig_cmdbuf, "queue.commandBuffer");
   fflush(out);
}
