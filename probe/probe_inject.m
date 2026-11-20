#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <dlfcn.h>
#import <stdio.h>
#import <unistd.h>

int main(int argc, char **argv) {
    @autoreleasepool {
        printf("=== %s pid=%d uid=%d\n", argv[0], getpid(), getuid());
        const char *ins = getenv("DYLD_INSERT_LIBRARIES");
        printf("DYLD_INSERT_LIBRARIES=%s\n", ins ? ins : "(null)");
        uint32_t n = _dyld_image_count();
        int hits = 0;
        for (uint32_t i = 0; i < n; i++) {
            const char *name = _dyld_get_image_name(i);
            if (!name) continue;
            if (strstr(name, "ellekit") || strstr(name, "TweakInject") ||
                strstr(name, "TweakLoader") || strstr(name, "libsubstrate") ||
                strstr(name, "libhooker") || strstr(name, "Choicy") ||
                strstr(name, "MobileSafety") || strstr(name, "systemhook")) {
                printf("  [INJ] %s\n", name);
                hits++;
            }
        }
        printf("total_images=%u injection_like=%d\n", n, hits);
    }
    return 0;
}
