# Java ZIP checksum probe

Both programs feed each input byte to CRC32, CRC32C and Adler32 and print the
three unsigned values in hexadecimal. The candidate calls each implementation
through Checksum. The control calls pinned zlib directly for CRC32 and Adler32
and uses the bitwise Castagnoli recurrence for CRC32C. The default input is
`123456789`, with output `cbf43926 e3069283 091e01de`.

The initial package cap uses this candidate's O3/Oz retained loadable bytes
against the JDK no-leaf control. That measurement includes pinned zlib code and
tables. The provider-equivalent package measurement compares the two programs
above. The JDK closure probes measure the four public leaves separately.
