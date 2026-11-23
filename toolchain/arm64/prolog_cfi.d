// The CFA rules of a function's prolog take effect after the instructions that
// establish them: after STP x29,x30 (4 bytes in, or after the SUB of a large frame)
// and after MOV x29,sp. The CIE's code alignment factor is 1.
// The test finds its own FDEs and checks the first two DW_CFA_advance_loc deltas.
struct DwarfEhBases { void* tbase, dbase, func; }
extern(C) void* _Unwind_Find_FDE(void* pc, DwarfEhBases* bases);

pragma(inline, false) int id(int* p) { return *p; }
// both call a function, so they have a frame record
pragma(inline, false) int small(int x) { int[4] a = x; return id(&a[1]) + 1; }
pragma(inline, false) int large(int x) { int[300] a = x; return id(&a[200]) + 1; }   // frame > 512 bytes

uint uleb(ref const(ubyte)* p)
{
    uint r, shift;
    ubyte b;
    do { b = *p++; r |= (b & 0x7F) << shift; shift += 7; } while (b & 0x80);
    return r;
}

// returns the deltas of the first two DW_CFA_advance_loc in the FDE of f, or 0
uint[2] advances(void* f)
{
    DwarfEhBases bases;
    auto fde = cast(const(ubyte)*) _Unwind_Find_FDE(f + 4, &bases);
    if (!fde) return [0, 0];
    const len = *cast(const(uint)*) fde;
    const end = fde + 4 + len;
    auto p = fde + 8 + 4 + 4;     // length, CIE pointer, pc_begin and pc_range (pcrel|sdata4)
    p += uleb(p);                 // augmentation data ('z')
    uint[2] r;
    size_t n;
    while (p < end && n < 2)
    {
        const op = *p++;
        if ((op & 0xC0) == 0x40) r[n++] = op & 0x3F;        // DW_CFA_advance_loc
        else if ((op & 0xC0) == 0x80) uleb(p);              // DW_CFA_offset
        else if (op == 0x0C) { uleb(p); uleb(p); }          // DW_CFA_def_cfa
        else if (op == 0x0D || op == 0x0E) uleb(p);         // DW_CFA_def_cfa_register, _offset
        else if (op == 0x05) { uleb(p); uleb(p); }          // DW_CFA_offset_extended
        else if (op == 0x02) p += 1;                        // DW_CFA_advance_loc1
        else if (op != 0) return [0, 0];
    }
    return r;
}

int main()
{
    if (small(3) != 4 || large(3) != 4) return 1;
    if (advances(&small) != [4, 4]) return 2;
    if (advances(&large) != [8, 4]) return 3;    // SUB sp,sp,#off; STP x29,x30,[sp]; MOV x29,sp
    return 0;
}
