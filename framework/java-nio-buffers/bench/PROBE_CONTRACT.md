# Heap buffer probe

Both programs allocate four bytes, write the argument count into the second byte and return its low seven bits plus the length of the three-byte view. The fixture uses the heap buffer cursor, mark, slice and read-only view. The control uses an equivalent D slice.
