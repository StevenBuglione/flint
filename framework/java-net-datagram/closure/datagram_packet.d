// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module datagram_packet_probe;

import flint.java.net.datagrampacket : DatagramPacket;

@safe:

// The address types, named through the packet so the probe imports only the packet leaf.
private alias InetAddress = typeof(DatagramPacket.init.getAddress());
private alias SocketAddress = typeof(DatagramPacket.init.getSocketAddress());

int main(string[] args)
{
    byte[] buf = new byte[16];
    buf[0] = cast(byte) args.length;
    InetAddress addr = null;
    auto packet = new DatagramPacket(buf, 1, 8, addr, 5353);
    packet.setLength(4);
    SocketAddress endpoint = packet.getSocketAddress();
    auto copy = new DatagramPacket(buf, 2, endpoint);
    copy.setPort(cast(int) args.length);
    return endpoint !is null && packet.getOffset() == 1 && packet.getLength() == 4
        && copy.getAddress() !is null && packet.getData()[0] == buf[0] ? 0 : 1;
}
