#include "flint_abi_probe.h"
int main(void) {
    flint_abi_info info;
    if (flint_abi_probe(&info, sizeof(info))) return 1;
    if (info.abi_version != 1 || info.struct_bytes != 48) return 2;
    if (info.pointer_bytes != sizeof(void*) || info.size_t_bytes != sizeof(size_t)) return 3;
    if (flint_abi_probe(0, sizeof(info)) != -1) return 4;
    if (flint_abi_probe(&info, sizeof(info)-1) != -1) return 5;
    return 0;
}
