// SPDX-License-Identifier: GPL-2.0-only WITH Classpath-exception-2.0
module app;

import flint.java.nio.file.path : Path;

@safe:

int main(string[] args)
{
    auto input = args.length > 1 ? args[1] : "";
    auto more = args.length > 2 ? args[2] : "";
    auto path = Path.of(input, more, "leaf");
    auto parent = path.getParent();
    auto parentCount = parent is null ? 0 : parent.getNameCount();
    return cast(int)((path.toString().length + path.getFileName().toString().length + parentCount) & 127);
}
