// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.net.datagrampacket : DatagramPacket;

@safe:

int main(string[] args)
{
    auto packet = new DatagramPacket(new byte[16], cast(int) args.length);
    packet.setLength(cast(int) args.length + 1);
    return packet.getLength() & 127;
}
