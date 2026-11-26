# Heap character buffer probe

Both programs allocate four zeroed UTF-16 code units, write the argument count into the second unit, and return its low seven bits plus the length of the three-unit view. The fixture exercises the heap character cursor, mark and read-only slice. The control uses the equivalent D slice.
