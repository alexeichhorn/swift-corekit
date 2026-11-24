#include "CCoreKitRoutes.h"
#include <stddef.h>

#if defined(__ELF__)
// Weak, so binaries without routes still link.
extern const char __start_corekit_routes[] __attribute__((weak, visibility("hidden")));
extern const char __stop_corekit_routes[] __attribute__((weak, visibility("hidden")));

const void *corekit_routes_start(void) { return __start_corekit_routes; }
const void *corekit_routes_end(void) { return __stop_corekit_routes; }
#else
const void *corekit_routes_start(void) { return NULL; }
const void *corekit_routes_end(void) { return NULL; }
#endif
