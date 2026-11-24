#ifndef CCOREKITROUTES_H
#define CCOREKITROUTES_H

/// Bounds of the ELF `corekit_routes` section, from the linker's `__start_`/`__stop_` symbols. Both are NULL when the
/// binary has no routes, and always on other object formats.
const void *corekit_routes_start(void);
const void *corekit_routes_end(void);

#endif
